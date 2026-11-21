import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../DataBaseHelper.dart';
import '../func/size.dart' show getCompanyInfos, updateCompanyInfos;

/// Adresse du serveur LipaLink Cloud par défaut (production).
/// Pour tester avec un serveur local, la changer dans l'écran
/// « Sauvegarde en ligne → Serveur » : http://10.0.2.2:4100 (émulateur
/// Android) ou http://localhost:4100 (simulateur iOS).
const String kDefaultCloudUrl = 'https://lipalink.liviatech.store';
const String kAppVersion = '1.0.0';

/// État de la connexion au serveur.
enum CloudState {
  /// Sauvegarde en ligne jamais activée sur ce téléphone.
  off,
  connected,

  /// Serveur injoignable (pas d'internet, serveur arrêté…).
  offline,

  /// Le jeton n'est plus valide : se reconnecter avec la clé de récupération.
  expired,

  /// Compte suspendu par l'administrateur.
  suspended,
}

class CloudException implements Exception {
  final String message;
  final int? status;
  const CloudException(this.message, [this.status]);
  @override
  String toString() => message;
}

class CloudBackup {
  final int id;
  final String kind;
  final int size;
  final DateTime createdAt;
  final int customers;
  final int debts;

  CloudBackup.fromJson(Map<String, dynamic> j)
    : id = j['id'] as int,
      kind = j['kind'] as String,
      size = j['size'] as int,
      createdAt = DateTime.parse(j['createdAt'] as String).toLocal(),
      customers = (j['counts']?['customers'] ?? 0) as int,
      debts = (j['counts']?['debts'] ?? 0) as int;
}

/// Sauvegarde, synchronisation et connexion au serveur LipaLink Cloud.
///
/// - Synchronisation : le serveur garde une copie à jour des données
///   (consultable par l'administration).
/// - Sauvegarde : instantané daté, restaurable sur ce téléphone ou un autre.
/// Chacune peut être automatique ou manuelle.
class CloudService extends ChangeNotifier {
  CloudService._();
  static final CloudService instance = CloudService._();

  static const _kUrl = 'cloud_url';
  static const _kId = 'cloud_id';
  static const _kToken = 'cloud_token';
  static const _kRecovery = 'cloud_recovery';
  static const _kAutoBackup = 'cloud_auto_backup';
  static const _kAutoSync = 'cloud_auto_sync';
  static const _kLastSync = 'cloud_last_sync';
  static const _kLastBackup = 'cloud_last_backup';
  static const _kSyncedFp = 'cloud_synced_fp';
  static const _kBackupFp = 'cloud_backup_fp';
  static const _kSettingsDirty = 'cloud_settings_dirty';
  static const _kLastContact = 'cloud_last_contact';
  static const _kLastContactFp = 'cloud_last_contact_fp';

  String serverUrl = kDefaultCloudUrl;
  String? id;
  String? recoveryKey;
  String? _token;
  bool autoBackup = true;
  bool autoSync = true;
  DateTime? lastSync;
  DateTime? lastBackup;
  CloudState state = CloudState.off;
  String? lastError;

  /// Opération en cours ('sync', 'backup', 'restore', 'activate'…), ou null.
  String? busy;

  /// Empreinte des données locales au dernier calcul.
  String? _localFp;
  String? _syncedFp;
  bool _loaded = false;

  bool get activated => id != null;
  bool get hasPendingChanges =>
      activated && _localFp != null && _localFp != _syncedFp;

  // ------------------------------------------------------------ État local

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    serverUrl = p.getString(_kUrl) ?? kDefaultCloudUrl;
    id = p.getString(_kId);
    _token = p.getString(_kToken);
    recoveryKey = p.getString(_kRecovery);
    autoBackup = p.getBool(_kAutoBackup) ?? true;
    autoSync = p.getBool(_kAutoSync) ?? true;
    lastSync = DateTime.tryParse(p.getString(_kLastSync) ?? '');
    lastBackup = DateTime.tryParse(p.getString(_kLastBackup) ?? '');
    _syncedFp = p.getString(_kSyncedFp);
    if (id == null) {
      state = CloudState.off;
    } else if (_token == null) {
      state = CloudState.expired;
    } else if (state == CloudState.off) {
      state = CloudState.connected;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded) await load();
  }

  Future<void> setServerUrl(String url) async {
    var clean = url.trim();
    if (!clean.startsWith('http')) clean = 'http://$clean';
    clean = clean.replaceAll(RegExp(r'/+$'), '');
    serverUrl = clean;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUrl, clean);
    notifyListeners();
  }

  /// Vérifie que le serveur répond.
  Future<bool> ping([String? url]) async {
    try {
      final res = await http
          .get(Uri.parse('${url ?? serverUrl}/api/health'))
          .timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // --------------------------------------------------------------- Réseau

  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Object? body,
    bool auth = true,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final uri = Uri.parse('$serverUrl/api/device$path');
    final headers = {
      'Content-Type': 'application/json',
      if (auth && _token != null) 'Authorization': 'Bearer $_token',
    };
    http.Response res;
    try {
      final encoded = body == null ? null : jsonEncode(body);
      res = await switch (method) {
        'GET' => http.get(uri, headers: headers),
        'PUT' => http.put(uri, headers: headers, body: encoded),
        _ => http.post(uri, headers: headers, body: encoded),
      }.timeout(timeout);
    } on TimeoutException {
      _setState(CloudState.offline, 'Le serveur ne répond pas');
      throw CloudException(
        'Le serveur ne répond pas ($serverUrl). Vérifiez l\'adresse du serveur.',
      );
    } catch (_) {
      _setState(CloudState.offline, 'Serveur injoignable');
      throw CloudException(
        'Serveur injoignable ($serverUrl). Vérifiez l\'adresse du serveur '
        'et votre connexion internet.',
      );
    }

    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      json = decoded is Map<String, dynamic>
          ? decoded
          : {'items': decoded};
    } catch (_) {
      json = {};
    }

    if (res.statusCode == 401 && auth) {
      await _dropToken();
      _setState(CloudState.expired, json['error'] as String?);
    } else if (res.statusCode == 403) {
      _setState(CloudState.suspended, json['error'] as String?);
    } else if (res.statusCode < 400 && activated) {
      _setState(CloudState.connected, null);
    }
    if (res.statusCode >= 400) {
      throw CloudException(
        (json['error'] as String?) ?? 'Erreur du serveur (${res.statusCode})',
        res.statusCode,
      );
    }
    return json;
  }

  void _setState(CloudState s, String? error) {
    if (!activated) return;
    state = s;
    lastError = error;
    notifyListeners();
  }

  Future<void> _dropToken() async {
    _token = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
  }

  Map<String, Object?> get _deviceInfo {
    final model = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    return {
      'platform': Platform.operatingSystem,
      'model': model.length > 80 ? model.substring(0, 80) : model,
      'appVersion': kAppVersion,
    };
  }

  // ------------------------------------------------------------ Données

  /// Instantané des données + empreinte (pour savoir si quelque chose a changé).
  Future<({Map<String, Object?> data, String fingerprint})> _snapshot({
    bool withLogo = false,
  }) async {
    final raw = await DatabaseHelper().exportSnapshot();
    final infos = await getCompanyInfos();
    final data = <String, Object?>{
      'version': 1,
      'customers': raw['customers'],
      'debts': raw['debts'],
      'avance': raw['avance'],
      'rate': raw['rate'],
      'company': {'name': raw['companyName'], 'infos': infos},
    };
    final fingerprint = _fnv1a(jsonEncode(data));
    if (withLogo) {
      final p = await SharedPreferences.getInstance();
      data['logo'] = p.getString('company_logo');
    }
    data['exportedAt'] = DateTime.now().toUtc().toIso8601String();
    _localFp = fingerprint;
    return (data: data, fingerprint: fingerprint);
  }

  /// Empreinte FNV-1a 32 bits (suffisante pour détecter un changement).
  static String _fnv1a(String input) {
    var hash = 0x811c9dc5;
    for (final b in utf8.encode(input)) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return '${hash.toRadixString(16).padLeft(8, '0')}-${input.length}';
  }

  Map<String, int> _counts(Map<String, Object?> data) => {
    for (final t in DatabaseHelper.cloudTables) t: (data[t] as List).length,
  };

  /// Recalcule l'empreinte locale (pour afficher « modifications en attente »).
  Future<void> refreshLocalState() async {
    await _ensureLoaded();
    if (!activated) return;
    await _snapshot();
    notifyListeners();
  }

  // ------------------------------------------------- Activation / connexion

  /// Première activation : le serveur attribue l'identifiant XXXXXLIVIA.
  Future<void> activate() async {
    await _ensureLoaded();
    busy = 'activate';
    notifyListeners();
    try {
      final snap = await _snapshot();
      final json = await _call(
        'POST',
        '/activate',
        auth: false,
        body: {
          'device': _deviceInfo,
          'company': snap.data['company'],
          'settings': {'autoBackup': autoBackup, 'autoSync': autoSync},
        },
      );
      await _saveSession(json);
      recoveryKey = json['recoveryKey'] as String;
      final p = await SharedPreferences.getInstance();
      await p.setString(_kRecovery, recoveryKey!);
      state = CloudState.connected;
      notifyListeners();
      // Premier envoi : synchro + sauvegarde initiale.
      await _sync(snap.data, snap.fingerprint);
      await _backup(auto: true);
    } finally {
      busy = null;
      notifyListeners();
    }
  }

  /// Reconnexion avec un identifiant existant (nouveau téléphone…).
  /// Retourne l'id de la dernière sauvegarde disponible, s'il y en a une.
  Future<int?> login(String cloudId, String key) async {
    await _ensureLoaded();
    busy = 'login';
    notifyListeners();
    try {
      final json = await _call(
        'POST',
        '/login',
        auth: false,
        body: {'id': cloudId, 'recoveryKey': key, 'device': _deviceInfo},
      );
      await _saveSession(json);
      recoveryKey = key.trim().toUpperCase();
      final p = await SharedPreferences.getInstance();
      await p.setString(_kRecovery, recoveryKey!);
      final settings = json['settings'] as Map<String, dynamic>?;
      if (settings != null) {
        autoBackup = settings['autoBackup'] as bool? ?? autoBackup;
        autoSync = settings['autoSync'] as bool? ?? autoSync;
        await p.setBool(_kAutoBackup, autoBackup);
        await p.setBool(_kAutoSync, autoSync);
      }
      state = CloudState.connected;
      lastError = null;
      return (json['lastBackup'] as Map<String, dynamic>?)?['id'] as int?;
    } finally {
      busy = null;
      notifyListeners();
    }
  }

  Future<void> _saveSession(Map<String, dynamic> json) async {
    id = json['id'] as String;
    _token = json['token'] as String;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kId, id!);
    await p.setString(_kToken, _token!);
  }

  /// Déconnecte ce téléphone. Les données en ligne restent sur le serveur et
  /// peuvent être récupérées avec l'identifiant et la clé de récupération.
  Future<void> disconnect() async {
    try {
      if (_token != null) await _call('POST', '/disconnect');
    } catch (_) {
      // Hors ligne : on déconnecte quand même localement.
    }
    final p = await SharedPreferences.getInstance();
    for (final k in [
      _kId, _kToken, _kRecovery, _kLastSync, _kLastBackup, _kSyncedFp,
      _kBackupFp, _kSettingsDirty, _kLastContact, _kLastContactFp,
    ]) {
      await p.remove(k);
    }
    id = null;
    _token = null;
    recoveryKey = null;
    lastSync = null;
    lastBackup = null;
    _syncedFp = null;
    state = CloudState.off;
    lastError = null;
    notifyListeners();
  }

  // ------------------------------------------------------------ Réglages

  Future<void> setAutoBackup(bool value) => _setSettings(backup: value);
  Future<void> setAutoSync(bool value) => _setSettings(sync: value);

  Future<void> _setSettings({bool? backup, bool? sync}) async {
    final p = await SharedPreferences.getInstance();
    if (backup != null) {
      autoBackup = backup;
      await p.setBool(_kAutoBackup, backup);
    }
    if (sync != null) {
      autoSync = sync;
      await p.setBool(_kAutoSync, sync);
    }
    notifyListeners();
    if (!activated) return;
    try {
      await _pushSettings();
    } catch (_) {
      // Sera envoyé au prochain contact avec le serveur.
      await p.setBool(_kSettingsDirty, true);
    }
  }

  Future<void> _pushSettings() async {
    await _call(
      'PUT',
      '/settings',
      body: {'autoBackup': autoBackup, 'autoSync': autoSync},
    );
    final p = await SharedPreferences.getInstance();
    await p.remove(_kSettingsDirty);
  }

  // ----------------------------------------------- Synchro & sauvegarde

  Future<void> syncNow() => _guard('sync', () async {
    final snap = await _snapshot();
    await _sync(snap.data, snap.fingerprint);
  });

  Future<void> backupNow() => _guard('backup', () => _backup(auto: false));

  Future<void> _guard(String op, Future<void> Function() run) async {
    await _ensureLoaded();
    if (!activated) throw const CloudException('Sauvegarde en ligne désactivée');
    if (_token == null) {
      throw const CloudException('Session expirée : reconnectez-vous');
    }
    busy = op;
    notifyListeners();
    try {
      await run();
    } finally {
      busy = null;
      notifyListeners();
    }
  }

  Future<void> _sync(Map<String, Object?> data, String fingerprint) async {
    final json = await _call(
      'POST',
      '/sync',
      body: {'data': data, 'fingerprint': fingerprint, 'device': _deviceInfo},
      timeout: const Duration(seconds: 60),
    );
    lastSync =
        DateTime.tryParse(json['syncedAt'] as String? ?? '')?.toLocal() ??
        DateTime.now();
    _syncedFp = fingerprint;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLastSync, lastSync!.toIso8601String());
    await p.setString(_kSyncedFp, fingerprint);
    await p.setString(_kLastContactFp, fingerprint);
    await p.setString(_kLastContact, DateTime.now().toIso8601String());
  }

  Future<void> _backup({required bool auto}) async {
    // La sauvegarde inclut aussi le logo de l'entreprise.
    final snap = await _snapshot(withLogo: true);
    final json = await _call(
      'POST',
      '/backups',
      body: {
        'data': snap.data,
        'fingerprint': snap.fingerprint,
        'kind': auto ? 'auto' : 'manual',
        'device': _deviceInfo,
      },
      timeout: const Duration(seconds: 90),
    );
    lastBackup =
        DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
        DateTime.now();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLastBackup, lastBackup!.toIso8601String());
    await p.setString(_kBackupFp, snap.fingerprint);
  }

  Future<List<CloudBackup>> listBackups() async {
    final json = await _call('GET', '/backups');
    return (json['items'] as List? ?? const [])
        .map((e) => CloudBackup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Remplace les données du téléphone par celles d'une sauvegarde.
  Future<void> restore(int backupId) => _guard('restore', () async {
    final json = await _call(
      'GET',
      '/backups/$backupId',
      timeout: const Duration(seconds: 90),
    );
    final data = json['data'] as Map<String, dynamic>;
    await DatabaseHelper().restoreSnapshot(data);

    final infos = (data['company']?['infos'] as Map?) ?? const {};
    await updateCompanyInfos(
      infos['rccm'] as String?,
      infos['phone'] as String?,
      infos['email'] as String?,
      infos['idnat'] as String?,
      infos['adresse'] as String?,
      infos['website'] as String?,
    );
    final logo = data['logo'] as String?;
    if (logo != null) {
      final p = await SharedPreferences.getInstance();
      await p.setString('company_logo', logo);
    }
    // Le serveur doit refléter les données restaurées.
    final snap = await _snapshot();
    await _sync(snap.data, snap.fingerprint);
  });

  // ------------------------------------------------------ Automatique

  bool _running = false;

  /// Contact avec le serveur + synchro/sauvegarde automatiques si besoin.
  /// Appelé au démarrage, à la mise en arrière-plan et en tâche de fond.
  Future<void> autoRun({bool force = false}) async {
    await _ensureLoaded();
    if (!activated || _token == null || _running || busy != null) return;
    _running = true;
    try {
      final p = await SharedPreferences.getInstance();
      final snap = await _snapshot();
      final fp = snap.fingerprint;

      if (p.getBool(_kSettingsDirty) ?? false) await _pushSettings();

      // Pas de changement et contact récent : inutile de déranger le serveur.
      final lastContact = DateTime.tryParse(p.getString(_kLastContact) ?? '');
      final quiet =
          !force &&
          p.getString(_kLastContactFp) == fp &&
          lastContact != null &&
          DateTime.now().difference(lastContact) < const Duration(minutes: 30);

      if (!quiet) {
        final hb = await _call(
          'POST',
          '/heartbeat',
          body: {
            'fingerprint': fp,
            'counts': _counts(snap.data),
            'device': _deviceInfo,
            'company': snap.data['company'],
            'rate': snap.data['rate'],
          },
        );
        await p.setString(_kLastContact, DateTime.now().toIso8601String());
        await p.setString(_kLastContactFp, fp);
        final s = hb['settings'] as Map<String, dynamic>?;
        if (s != null && !(p.getBool(_kSettingsDirty) ?? false)) {
          autoBackup = s['autoBackup'] as bool? ?? autoBackup;
          autoSync = s['autoSync'] as bool? ?? autoSync;
          await p.setBool(_kAutoBackup, autoBackup);
          await p.setBool(_kAutoSync, autoSync);
        }
      }

      if (autoSync && fp != _syncedFp) {
        await _sync(snap.data, fp);
      }

      // Sauvegarde automatique : au plus une par jour, seulement si les
      // données ont changé depuis la précédente.
      final backupDue =
          lastBackup == null ||
          DateTime.now().difference(lastBackup!) > const Duration(hours: 24);
      if (autoBackup && backupDue && p.getString(_kBackupFp) != fp) {
        await _backup(auto: true);
      }
    } catch (_) {
      // L'état (hors ligne, expiré…) est déjà mis à jour par _call.
    } finally {
      _running = false;
      notifyListeners();
    }
  }
}

/// Déclenche la synchro automatique quand l'app passe en arrière-plan
/// (moment où l'utilisateur a fini sa saisie) et quand elle revient.
class CloudLifecycleObserver with WidgetsBindingObserver {
  DateTime _lastResume = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      CloudService.instance.autoRun(force: true);
    } else if (state == AppLifecycleState.resumed &&
        DateTime.now().difference(_lastResume) > const Duration(minutes: 2)) {
      _lastResume = DateTime.now();
      CloudService.instance.autoRun();
    }
  }
}
