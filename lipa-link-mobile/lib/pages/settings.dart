import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../func/export.dart';
import '../cloud/cloud_service.dart';
import 'cloud_page.dart';
import 'home_shell.dart';

/// Masquer les dettes réglées par défaut dans la liste des dettes.
bool operationIsMasked = true;

class Settings extends StatefulWidget {
  /// Onglet de l'accueil (pas de bouton retour).
  final bool embedded;

  /// Premier lancement : la page sert d'accueil de configuration.
  final bool firstRun;

  const Settings({super.key, this.embedded = false, this.firstRun = false});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  final DatabaseHelper dbHelper = DatabaseHelper();

  Map<String, dynamic>? company;
  Map<String, String> infos = {};
  String? companyLogo;
  double? rate;

  static const _infoFields = <(String, String, IconData, TextInputType)>[
    ('phone', 'Téléphone', CupertinoIcons.phone, TextInputType.phone),
    ('email', 'E-mail', CupertinoIcons.mail, TextInputType.emailAddress),
    (
      'adresse',
      'Adresse',
      CupertinoIcons.location,
      TextInputType.streetAddress,
    ),
    ('rccm', 'RCCM', CupertinoIcons.doc_text, TextInputType.text),
    ('idnat', 'N° ID NAT', CupertinoIcons.number, TextInputType.text),
    ('website', 'Site web', CupertinoIcons.globe, TextInputType.url),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object?>([
      dbHelper.getCompany(),
      getCompanyInfos(),
      dbHelper.getRateValue(),
      SharedPreferences.getInstance(),
    ]);
    if (!mounted) return;
    final rows = results[0] as List<Map<String, dynamic>>?;
    setState(() {
      company = (rows != null && rows.isNotEmpty) ? rows.first : null;
      infos = results[1] as Map<String, String>;
      rate = results[2] as double?;
      companyLogo = (results[3] as SharedPreferences).getString('company_logo');
    });
  }

  String get companyName => (company?['nom'] ?? 'LIPALINK').toString();

  Future<void> _finishSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('params-checked', true);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = widget.embedded
        ? MediaQuery.paddingOf(context).bottom + 96
        : MediaQuery.paddingOf(context).bottom + 24;

    final content = CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverSafeArea(
          bottom: false,
          sliver: SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            sliver: SliverToBoxAdapter(child: _header()),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, bottom),
          sliver: SliverList.list(
            children: [
              FadeSlideIn(child: _companyCard()),
              const SectionTitle('Apparence'),
              FadeSlideIn(index: 1, child: _themeSelector()),
              const SectionTitle('Finances'),
              FadeSlideIn(
                index: 2,
                child: _group([
                  _tile(
                    icon: CupertinoIcons.arrow_2_squarepath,
                    color: context.app.warning,
                    title: 'Taux du jour',
                    subtitle: rate == null
                        ? 'Non défini'
                        : '1 USD = ${formatMoney(rate!, 'CDF')}',
                    onTap: _editRate,
                  ),
                ]),
              ),
              const SectionTitle('Affichage'),
              FadeSlideIn(
                index: 3,
                child: _group([
                  _tile(
                    icon: CupertinoIcons.eye_slash,
                    color: context.colors.primary,
                    title: 'Masquer les dettes réglées',
                    subtitle:
                        'Afficher seulement les dettes en cours par défaut',
                    trailing: Switch(
                      value: operationIsMasked,
                      onChanged: (value) async {
                        await setOperationMasked(value);
                        setState(() {});
                      },
                    ),
                    onTap: () async {
                      await setOperationMasked(!operationIsMasked);
                      setState(() {});
                    },
                  ),
                ]),
              ),
              const SectionTitle('Sauvegarde en ligne'),
              FadeSlideIn(
                index: 4,
                child: _group([
                  ListenableBuilder(
                    listenable: CloudService.instance,
                    builder: (context, _) {
                      final cloud = CloudService.instance;
                      return _tile(
                        icon: CupertinoIcons.cloud_upload,
                        color: context.colors.primary,
                        title: 'Sauvegarde & synchronisation',
                        subtitle: cloud.activated
                            ? '${cloud.id} · ${cloud.autoSync ? 'synchro auto' : 'synchro manuelle'}'
                            : 'Désactivée · protégez vos données',
                        onTap: () => goTox(context, const CloudPage()),
                      );
                    },
                  ),
                ]),
              ),
              const SectionTitle('Application'),
              FadeSlideIn(
                index: 5,
                child: _group([
                  _tile(
                    icon: CupertinoIcons.info,
                    color: context.app.receivable,
                    title: 'À propos',
                    subtitle: 'LipaLink · Livia Tech',
                    onTap: () => goTox(context, const AboutPage()),
                  ),
                ]),
              ),
              if (widget.firstRun) ...[
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _finishSetup,
                  icon: const Icon(CupertinoIcons.arrow_right),
                  label: const Text('Commencer'),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return Scaffold(backgroundColor: Colors.transparent, body: content);
    }
    return PopScope(
      canPop: !widget.firstRun,
      child: Scaffold(body: AmbientBackground(child: content)),
    );
  }

  // ------------------------------------------------------------- Blocs

  Widget _header() {
    return Row(
      children: [
        if (!widget.embedded && !widget.firstRun) ...[
          IconButton.filledTonal(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(CupertinoIcons.back),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.firstRun ? 'Bienvenue 👋' : 'Réglages',
                style: context.text.headlineMedium,
              ),
              Text(
                widget.firstRun
                    ? 'Personnalisez votre entreprise, puis commencez.'
                    : 'Entreprise, taux et apparence',
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

  Widget _companyCard() {
    final filled = _infoFields.where((f) => (infos[f.$1] ?? '').isNotEmpty);
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _logoOptions,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainer,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: context.app.glassBorder),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: companyLogo == null
                      ? Icon(
                          CupertinoIcons.camera,
                          color: context.colors.onSurfaceVariant,
                        )
                      : Image.memory(
                          base64Decode(companyLogo!),
                          fit: BoxFit.cover,
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      companyName,
                      style: context.text.titleLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Apparaît sur vos relevés PDF',
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (filled.isNotEmpty) ...[
            for (final f in filled.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      f.$3,
                      size: 16,
                      color: context.colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        infos[f.$1]!,
                        style: context.text.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: _editCompanyName,
                  icon: const Icon(CupertinoIcons.pencil, size: 18),
                  label: const Text('Nom'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: _editInfos,
                  icon: const Icon(CupertinoIcons.doc_text, size: 18),
                  label: const Text('Infos'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _themeSelector() {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) => SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto_rounded),
            label: Text('Auto'),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_rounded),
            label: Text('Clair'),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_rounded),
            label: Text('Sombre'),
          ),
        ],
        selected: {mode},
        showSelectedIcon: false,
        onSelectionChanged: (v) => ThemeController.instance.set(v.first),
      ),
    );
  }

  Widget _group(List<Widget> tiles) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: tiles),
    );
  }

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
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing:
          trailing ??
          Icon(
            CupertinoIcons.chevron_right,
            size: 18,
            color: context.colors.onSurfaceVariant,
          ),
    );
  }

  // ------------------------------------------------------------ Actions

  void _editCompanyName() {
    final controller = TextEditingController(text: companyName);
    final formKey = GlobalKey<FormState>();
    showAppSheet(
      context,
      builder: (sheetContext) => Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader(
              'Nom de l\'entreprise',
              subtitle: 'Affiché sur l\'accueil et les relevés.',
            ),
            TextFormField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Nom',
                prefixIcon: Icon(CupertinoIcons.building_2_fill),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Veuillez entrer un nom'
                  : null,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(sheetContext);
                await dbHelper.updateCompany(
                  company?['id'] as int? ?? 1,
                  controller.text.trim(),
                );
                await _load();
                if (mounted) messageInfo(context, 'Nom enregistré', false);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  void _editInfos() {
    final controllers = {
      for (final f in _infoFields)
        f.$1: TextEditingController(text: infos[f.$1] ?? ''),
    };
    showAppSheet(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(
            'Coordonnées',
            subtitle: 'Tous les champs sont facultatifs.',
          ),
          for (final f in _infoFields) ...[
            TextField(
              controller: controllers[f.$1],
              keyboardType: f.$4,
              decoration: InputDecoration(
                labelText: f.$2,
                prefixIcon: Icon(f.$3),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              Navigator.pop(sheetContext);
              await updateCompanyInfos(
                controllers['rccm']!.text.trim(),
                controllers['phone']!.text.trim(),
                controllers['email']!.text.trim(),
                controllers['idnat']!.text.trim(),
                controllers['adresse']!.text.trim(),
                controllers['website']!.text.trim(),
              );
              await _load();
              if (mounted) {
                messageInfo(context, 'Coordonnées enregistrées', false);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  void _editRate() {
    final controller = TextEditingController(
      text: rate == null ? '' : roundMoney(rate!).toString(),
    );
    final formKey = GlobalKey<FormState>();
    showAppSheet(
      context,
      builder: (sheetContext) => Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader(
              'Taux du jour',
              subtitle:
                  'Nombre de CDF pour 1 USD. Sert à afficher les équivalents entre devises.',
            ),
            AmountField(
              controller: controller,
              devise: 'CDF',
              label: '1 USD =',
              autofocus: true,
              validator: (value) {
                final parsed = parseAmount(value);
                if (parsed == null) return 'Veuillez entrer un taux valide';
                if (parsed <= 0) return 'Le taux doit être positif';
                return null;
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(sheetContext);
                await dbHelper.updateRate(
                  parseAmount(controller.text)!.toString(),
                );
                await _load();
                if (mounted) messageInfo(context, 'Taux mis à jour', false);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  void _logoOptions() {
    showAppSheet(
      context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(
            'Logo de l\'entreprise',
            subtitle: 'Affiché en haut de vos relevés PDF.',
          ),
          SheetAction(
            icon: CupertinoIcons.photo,
            label: 'Choisir dans la galerie',
            onTap: () {
              Navigator.pop(sheetContext);
              _pickLogo(ImageSource.gallery);
            },
          ),
          SheetAction(
            icon: CupertinoIcons.camera,
            label: 'Prendre une photo',
            onTap: () {
              Navigator.pop(sheetContext);
              _pickLogo(ImageSource.camera);
            },
          ),
          if (companyLogo != null)
            SheetAction(
              icon: CupertinoIcons.trash,
              label: 'Supprimer le logo',
              color: context.app.danger,
              onTap: () {
                Navigator.pop(sheetContext);
                _deleteLogo();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickLogo(ImageSource source) async {
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        maxWidth: 300,
        maxHeight: 300,
        imageQuality: 80,
      );
      if (image == null) return;
      final base64String = base64Encode(await File(image.path).readAsBytes());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('company_logo', base64String);
      if (!mounted) return;
      setState(() => companyLogo = base64String);
      messageInfo(context, 'Logo enregistré', false);
    } catch (e) {
      if (mounted) {
        messageInfo(context, 'Impossible d\'enregistrer le logo', true);
      }
    }
  }

  Future<void> _deleteLogo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('company_logo');
    if (!mounted) return;
    setState(() => companyLogo = null);
    messageInfo(context, 'Logo supprimé', false);
  }
}
