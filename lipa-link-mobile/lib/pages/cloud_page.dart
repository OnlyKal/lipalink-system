import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../cloud/cloud_service.dart';
import '../func/export.dart';

/// Sauvegarde en ligne : activation, connexion, synchro et sauvegardes.
class CloudPage extends StatefulWidget {
  const CloudPage({super.key});

  @override
  State<CloudPage> createState() => _CloudPageState();
}

class _CloudPageState extends State<CloudPage> {
  final cloud = CloudService.instance;
  List<CloudBackup>? backups;
  bool backupsError = false;

  @override
  void initState() {
    super.initState();
    cloud.addListener(_changed);
    _init();
  }

  @override
  void dispose() {
    cloud.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    await cloud.load();
    await cloud.refreshLocalState();
    if (cloud.activated) {
      await cloud.autoRun(force: true);
      await _loadBackups();
    }
  }

  Future<void> _loadBackups() async {
    if (!cloud.activated || cloud.state == CloudState.expired) return;
    try {
      final list = await cloud.listBackups();
      if (mounted) {
        setState(() {
          backups = list;
          backupsError = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => backupsError = true);
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    try {
      await action();
      if (mounted) showAppSnack(context, success);
    } on CloudException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showAppSnack(context, 'Opération impossible', error: true);
    }
  }

  // ================================================================ Build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: RefreshIndicator(
          onRefresh: () async {
            await cloud.autoRun(force: true);
            await _loadBackups();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverSafeArea(
                bottom: false,
                sliver: SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  sliver: SliverToBoxAdapter(child: _header()),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  MediaQuery.paddingOf(context).bottom + 32,
                ),
                sliver: SliverList.list(
                  children: cloud.activated ? _activated() : _notActivated(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(CupertinoIcons.back),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sauvegarde en ligne', style: context.text.headlineSmall),
              Text(
                'Sauvegarde, synchronisation et connexion',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------ Pas encore activé

  List<Widget> _notActivated() {
    final busy = cloud.busy != null;
    return [
      FadeSlideIn(
        child: GlassCard(
          tint: context.colors.primary,
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                CupertinoIcons.cloud_upload_fill,
                color: context.colors.primary,
                size: 56,
              ),
              const SizedBox(height: 16),
              Text('Protégez vos données', style: context.text.titleLarge),
              const SizedBox(height: 6),
              Text(
                'En cas de perte ou de changement de téléphone, retrouvez '
                'tous vos clients, dettes et paiements.',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              for (final (icon, text) in [
                (CupertinoIcons.number, 'Un identifiant unique ·LIVIA vous est attribué'),
                (CupertinoIcons.arrow_2_circlepath, 'Synchronisation automatique ou manuelle'),
                (CupertinoIcons.lock_shield, 'Une clé de récupération pour vous reconnecter'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(icon, size: 18, color: context.app.receivable),
                      const SizedBox(width: 10),
                      Expanded(child: Text(text, style: context.text.bodyMedium)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      const SectionTitle('Mode de fonctionnement'),
      FadeSlideIn(index: 1, child: _automationGroup()),
      const SectionTitle('Serveur'),
      FadeSlideIn(index: 2, child: _group([_serverTile()])),
      const SizedBox(height: 24),
      FadeSlideIn(
        index: 3,
        child: FilledButton.icon(
          onPressed: busy ? null : _activate,
          icon: cloud.busy == 'activate'
              ? const _Spinner()
              : const Icon(CupertinoIcons.cloud_upload),
          label: Text(
            cloud.busy == 'activate'
                ? 'Activation…'
                : 'Activer la sauvegarde en ligne',
          ),
        ),
      ),
      const SizedBox(height: 10),
      FadeSlideIn(
        index: 4,
        child: OutlinedButton.icon(
          onPressed: busy ? null : _loginSheet,
          icon: const Icon(CupertinoIcons.person_crop_circle_badge_checkmark),
          label: const Text('J\'ai déjà un identifiant'),
        ),
      ),
    ];
  }

  Future<void> _activate() async {
    try {
      await cloud.activate();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      await _loadBackups();
      if (mounted) _showCredentials(firstTime: true);
    } on CloudException catch (e) {
      if (mounted) showAppSnack(context, e.message, error: true);
    }
  }

  // ------------------------------------------------------------- Activé

  List<Widget> _activated() {
    return [
      FadeSlideIn(child: _statusCard()),
      if (cloud.state == CloudState.expired) ...[
        const SizedBox(height: 12),
        FadeSlideIn(
          index: 1,
          child: _alert(
            CupertinoIcons.lock,
            context.app.warning,
            'Session expirée',
            'Reconnectez-vous avec votre clé de récupération.',
            action: TextButton(
              onPressed: () => _loginSheet(prefillId: cloud.id),
              child: const Text('Se reconnecter'),
            ),
          ),
        ),
      ],
      if (cloud.state == CloudState.suspended) ...[
        const SizedBox(height: 12),
        _alert(
          CupertinoIcons.nosign,
          context.app.danger,
          'Compte suspendu',
          cloud.lastError ?? 'Contactez l\'administrateur LipaLink.',
        ),
      ],
      const SizedBox(height: 16),
      FadeSlideIn(index: 1, child: _actions()),
      const SectionTitle('Automatisation'),
      FadeSlideIn(index: 2, child: _automationGroup()),
      SectionTitle(
        'Sauvegardes en ligne',
        trailing: backups == null
            ? null
            : Text(
                '${backups!.length}',
                style: context.text.labelMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
      FadeSlideIn(index: 3, child: _backupList()),
      const SectionTitle('Connexion'),
      FadeSlideIn(
        index: 4,
        child: _group([
          _tile(
            icon: CupertinoIcons.lock_shield,
            color: context.app.receivable,
            title: 'Identifiant et clé de récupération',
            subtitle: 'Pour vous reconnecter sur un autre téléphone',
            onTap: () => _showCredentials(),
          ),
          _serverTile(),
          _tile(
            icon: CupertinoIcons.square_arrow_right,
            color: context.app.danger,
            title: 'Déconnecter ce téléphone',
            subtitle: 'Vos données en ligne sont conservées',
            onTap: _disconnect,
          ),
        ]),
      ),
    ];
  }

  Widget _statusCard() {
    final (label, color, icon) = switch (cloud.state) {
      CloudState.connected => ('Connecté', context.app.success, CupertinoIcons.checkmark_circle_fill),
      CloudState.offline => ('Hors ligne', context.app.warning, CupertinoIcons.wifi_slash),
      CloudState.expired => ('Session expirée', context.app.warning, CupertinoIcons.lock),
      CloudState.suspended => ('Suspendu', context.app.danger, CupertinoIcons.nosign),
      CloudState.off => ('Désactivé', context.colors.onSurfaceVariant, CupertinoIcons.cloud),
    };
    final pending = cloud.hasPendingChanges;
    final id = cloud.id!;

    return GlassCard(
      tint: context.colors.primary,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(CupertinoIcons.cloud_fill, color: context.colors.primary, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VOTRE IDENTIFIANT',
                      style: context.text.labelSmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _copy(id, 'Identifiant copié'),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: id.substring(0, id.length - 5)),
                            TextSpan(
                              text: '·LIVIA',
                              style: TextStyle(color: context.colors.primary),
                            ),
                          ],
                        ),
                        style: context.text.headlineSmall?.copyWith(
                          letterSpacing: 1.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(label: label, color: color, icon: icon),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _stat(
                  'Dernière synchro',
                  _ago(cloud.lastSync),
                  CupertinoIcons.arrow_2_circlepath,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _stat(
                  'Dernière sauvegarde',
                  _ago(cloud.lastBackup),
                  CupertinoIcons.cloud_upload,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Row(
              key: ValueKey(pending),
              children: [
                Icon(
                  pending
                      ? CupertinoIcons.exclamationmark_circle
                      : CupertinoIcons.checkmark_seal,
                  size: 18,
                  color: pending ? context.app.warning : context.app.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pending
                        ? 'Modifications non synchronisées'
                        : 'Vos données en ligne sont à jour',
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: pending ? context.app.warning : context.app.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: context.colors.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: context.text.titleSmall),
        ],
      ),
    );
  }

  Widget _actions() {
    final usable = cloud.state != CloudState.expired &&
        cloud.state != CloudState.suspended &&
        cloud.busy == null;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: usable
                ? () => _run(cloud.syncNow, 'Données synchronisées')
                : null,
            icon: cloud.busy == 'sync'
                ? const _Spinner()
                : const Icon(CupertinoIcons.arrow_2_circlepath, size: 20),
            label: const Text('Synchroniser'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: usable
                ? () => _run(() async {
                    await cloud.backupNow();
                    await _loadBackups();
                  }, 'Sauvegarde envoyée')
                : null,
            icon: cloud.busy == 'backup'
                ? const _Spinner()
                : const Icon(CupertinoIcons.cloud_upload, size: 20),
            label: const Text('Sauvegarder'),
          ),
        ),
      ],
    );
  }

  Widget _automationGroup() {
    return _group([
      _tile(
        icon: CupertinoIcons.arrow_2_circlepath,
        color: context.app.receivable,
        title: 'Synchronisation automatique',
        subtitle: cloud.autoSync
            ? 'Dès que vous quittez l\'application'
            : 'Manuelle : seulement quand vous le demandez',
        trailing: Switch(value: cloud.autoSync, onChanged: cloud.setAutoSync),
        onTap: () => cloud.setAutoSync(!cloud.autoSync),
      ),
      _tile(
        icon: CupertinoIcons.cloud_upload,
        color: context.colors.primary,
        title: 'Sauvegarde automatique',
        subtitle: cloud.autoBackup
            ? 'Une fois par jour si vos données ont changé'
            : 'Manuelle : seulement quand vous le demandez',
        trailing: Switch(
          value: cloud.autoBackup,
          onChanged: cloud.setAutoBackup,
        ),
        onTap: () => cloud.setAutoBackup(!cloud.autoBackup),
      ),
    ]);
  }

  Widget _backupList() {
    if (backups == null) {
      return GlassCard(
        child: backupsError
            ? Text(
                'Impossible de charger les sauvegardes (hors ligne ?).',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              )
            : const Center(child: _Spinner(size: 22)),
      );
    }
    if (backups!.isEmpty) {
      return GlassCard(
        child: Text(
          'Aucune sauvegarde pour le moment.',
          style: context.text.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      );
    }
    final fmt = DateFormat('d MMM yyyy · HH:mm', 'fr');
    return _group([
      for (final (i, b) in backups!.take(10).indexed)
        _tile(
          icon: b.kind == 'auto'
              ? CupertinoIcons.time
              : CupertinoIcons.hand_point_right,
          color: b.kind == 'auto' ? context.app.receivable : context.colors.primary,
          title: fmt.format(b.createdAt),
          subtitle:
              '${b.kind == 'auto' ? 'Auto' : 'Manuelle'} · ${b.customers} clients · ${b.debts} dettes${i == 0 ? ' · la plus récente' : ''}',
          trailing: Icon(
            CupertinoIcons.arrow_counterclockwise,
            size: 18,
            color: context.colors.onSurfaceVariant,
          ),
          onTap: () => _restore(b),
        ),
    ]);
  }

  // ------------------------------------------------------------ Actions

  Future<void> _restore(CloudBackup b) async {
    final ok = await confirmAction(
      context,
      title: 'Restaurer cette sauvegarde ?',
      message:
          'Les données actuelles du téléphone seront remplacées par celles du '
          '${DateFormat('d MMMM yyyy à HH:mm', 'fr').format(b.createdAt)} '
          '(${b.customers} clients, ${b.debts} dettes).',
      confirmLabel: 'Restaurer',
      destructive: true,
    );
    if (!ok) return;
    await _run(() => cloud.restore(b.id), 'Données restaurées');
  }

  Future<void> _disconnect() async {
    final ok = await confirmAction(
      context,
      title: 'Déconnecter ce téléphone ?',
      message:
          'La sauvegarde en ligne s\'arrête sur ce téléphone. Notez votre '
          'identifiant ${cloud.id} et votre clé de récupération pour vous '
          'reconnecter plus tard.',
      confirmLabel: 'Déconnecter',
      destructive: true,
    );
    if (!ok) return;
    await cloud.disconnect();
    if (mounted) {
      setState(() => backups = null);
      showAppSnack(context, 'Téléphone déconnecté');
    }
  }

  void _copy(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    showAppSnack(context, message);
  }

  void _showCredentials({bool firstTime = false}) {
    final id = cloud.id!;
    final key = cloud.recoveryKey;
    showAppSheet(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            firstTime ? 'C\'est activé 🎉' : 'Vos identifiants',
            subtitle:
                'Conservez-les précieusement : ils permettent de retrouver '
                'vos données sur un autre téléphone.',
          ),
          _credential('Identifiant', id, CupertinoIcons.number),
          const SizedBox(height: 10),
          _credential(
            'Clé de récupération',
            key ?? 'Indisponible sur ce téléphone',
            CupertinoIcons.lock_shield,
            copyable: key != null,
          ),
          const SizedBox(height: 20),
          if (key != null)
            OutlinedButton.icon(
              onPressed: () => shareString(
                'Mes identifiants LipaLink\nIdentifiant : $id\nClé de récupération : $key',
              ),
              icon: const Icon(CupertinoIcons.share),
              label: const Text('Partager / enregistrer'),
            ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () => Navigator.pop(sheetContext),
            child: const Text('C\'est noté'),
          ),
        ],
      ),
    );
  }

  Widget _credential(String label, String value, IconData icon, {bool copyable = true}) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: copyable ? () => _copy(value, '$label copié') : null,
      child: Row(
        children: [
          Icon(icon, color: context.colors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: context.text.labelMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                SelectableText(
                  value,
                  style: context.text.titleLarge?.copyWith(letterSpacing: 1.4),
                ),
              ],
            ),
          ),
          if (copyable)
            Icon(
              CupertinoIcons.doc_on_doc,
              size: 18,
              color: context.colors.onSurfaceVariant,
            ),
        ],
      ),
    );
  }

  void _loginSheet({String? prefillId}) {
    final idCtrl = TextEditingController(text: prefillId ?? '');
    final keyCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var loading = false;
    showAppSheet(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          return Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHeader(
                  'Se connecter',
                  subtitle:
                      'Saisissez l\'identifiant ·LIVIA et la clé de récupération '
                      'reçus lors de l\'activation.',
                ),
                TextFormField(
                  controller: idCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Identifiant',
                    hintText: 'Ex. 7KQ2MLIVIA',
                    prefixIcon: Icon(CupertinoIcons.number),
                  ),
                  validator: (v) {
                    final clean = (v ?? '').toUpperCase().replaceAll(
                      RegExp(r'[^A-Z0-9]'),
                      '',
                    );
                    return RegExp(r'^[A-Z0-9]{5}LIVIA$').hasMatch(clean)
                        ? null
                        : 'Format attendu : 5 caractères suivis de LIVIA';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: keyCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Clé de récupération',
                    hintText: 'XXXX-XXXX',
                    prefixIcon: Icon(CupertinoIcons.lock_shield),
                  ),
                  validator: (v) =>
                      (v ?? '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length == 8
                      ? null
                      : 'La clé contient 8 caractères',
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: loading ? null : () async {
                    if (!formKey.currentState!.validate()) return;
                    setSheet(() => loading = true);
                    try {
                      final lastBackupId = await cloud.login(
                        idCtrl.text,
                        keyCtrl.text,
                      );
                      if (!sheetContext.mounted) return;
                      Navigator.pop(sheetContext);
                      await _loadBackups();
                      if (mounted) showAppSnack(context, 'Connecté à ${cloud.id}');
                      if (lastBackupId != null && mounted) {
                        _offerRestore();
                      } else {
                        await cloud.autoRun(force: true);
                      }
                    } on CloudException catch (e) {
                      if (mounted) showAppSnack(context, e.message, error: true);
                    } finally {
                      if (sheetContext.mounted) setSheet(() => loading = false);
                    }
                  },
                  child: loading
                      ? const _Spinner()
                      : const Text('Se connecter'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Après reconnexion : proposer de récupérer la dernière sauvegarde.
  Future<void> _offerRestore() async {
    final latest = backups?.isNotEmpty == true ? backups!.first : null;
    if (latest == null) return;
    await _restore(latest);
  }

  void _serverDialog() {
    final ctrl = TextEditingController(text: cloud.serverUrl);
    showAppSheet(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(
            'Adresse du serveur',
            subtitle: 'Fournie par l\'administrateur LipaLink.',
          ),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Adresse',
              hintText: 'https://lipalink.liviatech.store',
              prefixIcon: Icon(CupertinoIcons.globe),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              Navigator.pop(sheetContext);
              await cloud.setServerUrl(ctrl.text);
              final ok = await cloud.ping();
              if (!mounted) return;
              showAppSnack(
                context,
                ok ? 'Serveur joignable ✓' : 'Serveur injoignable à cette adresse',
                error: !ok,
              );
              if (ok && cloud.activated) {
                await cloud.autoRun(force: true);
                await _loadBackups();
              }
            },
            child: const Text('Enregistrer et tester'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ Éléments

  Widget _serverTile() => _tile(
    icon: CupertinoIcons.globe,
    color: context.app.warning,
    title: 'Serveur',
    subtitle: cloud.serverUrl,
    onTap: _serverDialog,
  );

  Widget _alert(
    IconData icon,
    Color color,
    String title,
    String message, {
    Widget? action,
  }) {
    return GlassCard(
      tint: color,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        children: [
          IconBadge(icon, color: color, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall),
                Text(
                  message,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }

  Widget _group(List<Widget> tiles) => GlassCard(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(children: tiles),
  );

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: IconBadge(icon, color: color, size: 42),
      title: Text(
        title,
        style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing:
          trailing ??
          Icon(
            CupertinoIcons.chevron_right,
            size: 18,
            color: context.colors.onSurfaceVariant,
          ),
    );
  }

  String _ago(DateTime? date) {
    if (date == null) return 'Jamais';
    final d = DateTime.now().difference(date);
    if (d.inMinutes < 1) return 'À l\'instant';
    if (d.inMinutes < 60) return 'Il y a ${d.inMinutes} min';
    if (d.inHours < 24) return 'Il y a ${d.inHours} h';
    if (d.inDays < 7) return 'Il y a ${d.inDays} j';
    return DateFormat('d MMM yyyy', 'fr').format(date);
  }
}

class _Spinner extends StatelessWidget {
  final double size;
  const _Spinner({this.size = 18});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: const CircularProgressIndicator(strokeWidth: 2.2),
  );
}
