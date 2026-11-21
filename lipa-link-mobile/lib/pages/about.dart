import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../func/export.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _features = <(IconData, String, String)>[
    (
      CupertinoIcons.arrow_right_arrow_left,
      'Dettes dans les deux sens',
      'Ce que vos clients vous doivent et ce que vous leur devez, séparément.',
    ),
    (
      CupertinoIcons.chart_bar_alt_fill,
      'Remboursements suivis',
      'Paiements partiels, reste à payer et clôture automatique.',
    ),
    (
      CupertinoIcons.bell,
      'Rappels d\'échéance',
      'Une notification quand une dette dépasse son échéance.',
    ),
    (
      CupertinoIcons.doc_richtext,
      'Relevés PDF',
      'À imprimer ou à partager en un geste.',
    ),
    (
      CupertinoIcons.wifi_slash,
      '100 % hors ligne',
      'Vos données restent sur votre téléphone. Aucune inscription.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(CupertinoIcons.back),
                ),
              ),
              const SizedBox(height: 16),
              FadeSlideIn(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: context.app.glass,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: context.app.glassBorder),
                        boxShadow: [
                          BoxShadow(
                            color: context.colors.primary.withValues(
                              alpha: 0.3,
                            ),
                            blurRadius: 40,
                          ),
                        ],
                      ),
                      child: Image.asset('assets/eden.png', width: 64),
                    ),
                    const SizedBox(height: 18),
                    Text('LipaLink', style: context.text.headlineMedium),
                    const SizedBox(height: 6),
                    Text(
                      'La gestion de dettes simple, rapide et locale, pensée pour les commerçants.',
                      textAlign: TextAlign.center,
                      style: context.text.bodyLarge?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SectionTitle('Fonctionnalités'),
              for (var i = 0; i < _features.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FadeSlideIn(
                    index: i + 1,
                    child: GlassCard(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          IconBadge(
                            _features[i].$1,
                            color: [
                              context.colors.primary,
                              context.app.receivable,
                              context.app.warning,
                              context.app.payable,
                              context.app.success,
                            ][i % 5],
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _features[i].$2,
                                  style: context.text.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _features[i].$3,
                                  style: context.text.bodySmall?.copyWith(
                                    color: context.colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SectionTitle('Contact'),
              FadeSlideIn(
                index: 6,
                child: GlassCard(
                  child: Column(
                    children: [
                      Image.asset('assets/ltech.png', height: 56),
                      const SizedBox(height: 12),
                      Text('+243 838 249 020', style: context.text.titleSmall),
                      Text(
                        'jb@liviatech.store',
                        style: context.text.bodyMedium?.copyWith(
                          color: context.colors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
