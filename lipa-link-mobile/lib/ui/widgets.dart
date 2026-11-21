import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../func/money.dart';
import 'theme.dart';

// ---------------------------------------------------------------- Fond

/// Fond « immersif » : deux halos lumineux flous qui dérivent lentement.
class AmbientBackground extends StatefulWidget {
  final Widget child;
  const AmbientBackground({super.key, required this.child});

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final opacity = context.isDark ? 0.35 : 0.22;
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: context.colors.surface)),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_controller.value);
            final size = MediaQuery.sizeOf(context);
            return Stack(
              children: [
                _glow(
                  app.glowA.withValues(alpha: opacity),
                  left: -size.width * 0.35 + t * 60,
                  top: -size.width * 0.3 + t * 40,
                  diameter: size.width * 1.1,
                ),
                _glow(
                  app.glowB.withValues(alpha: opacity * 0.8),
                  left: size.width * 0.45 - t * 50,
                  top: size.height * 0.25 + t * 70,
                  diameter: size.width * 0.9,
                ),
              ],
            );
          },
        ),
        widget.child,
      ],
    );
  }

  Widget _glow(
    Color color, {
    required double left,
    required double top,
    required double diameter,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- Cartes

/// Carte en verre dépoli, avec retour visuel au toucher.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? tint;
  final double radius;
  final Border? border;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.onLongPress,
    this.tint,
    this.radius = AppTheme.radius,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final shape = BorderRadius.circular(radius);
    final content = Container(
      decoration: BoxDecoration(
        color: tint != null
            ? Color.alphaBlend(tint!.withValues(alpha: 0.10), app.glass)
            : app.glass,
        borderRadius: shape,
        border: border ?? Border.all(color: app.glassBorder),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: shape,
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          onLongPress: onLongPress == null
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  onLongPress!();
                },
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: shape,
      child: context.isDark
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: content,
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: shape,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1E293B).withValues(alpha: 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: content,
            ),
    );
  }
}

// ------------------------------------------------------------ Animations

/// Apparition en fondu + glissement. `index` décale l'animation
/// pour créer un effet de cascade dans les listes.
class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final int index;
  final Offset offset;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = const Offset(0, 24),
  });

  @override
  Widget build(BuildContext context) {
    final delay = (index.clamp(0, 10)) * 0.06;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 450 + (delay * 1000).round()),
      curve: Interval(delay / (0.45 + delay), 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: offset * (1 - t), child: child),
      ),
      child: child,
    );
  }
}

/// Montant qui « compte » jusqu'à sa valeur.
class AnimatedAmount extends StatelessWidget {
  final double value;
  final String devise;
  final TextStyle? style;
  final TextStyle? deviseStyle;

  const AnimatedAmount({
    super.key,
    required this.value,
    required this.devise,
    this.style,
    this.deviseStyle,
  });

  @override
  Widget build(BuildContext context) {
    final base = (style ?? context.text.headlineSmall)!.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text.rich(
        TextSpan(
          children: [
            TextSpan(text: formatAmount(v), style: base),
            TextSpan(
              text: ' $devise',
              style:
                  deviseStyle ??
                  base.copyWith(
                    fontSize: (base.fontSize ?? 20) * 0.55,
                    fontWeight: FontWeight.w600,
                    color: context.colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// -------------------------------------------------------------- Éléments

/// Petite pastille colorée (statut, sens de la dette…).
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Titre de section.
class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionTitle(
    this.title, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 24, 4, 12),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: context.text.labelMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Avatar à initiales, avec un dégradé stable par personne.
class InitialsAvatar extends StatelessWidget {
  final String name;
  final double size;

  const InitialsAvatar(this.name, {super.key, this.size = 48});

  static const _palettes = [
    [Color(0xFF6366F1), Color(0xFF22D3EE)],
    [Color(0xFF14B8A6), Color(0xFF84CC16)],
    [Color(0xFF8B5CF6), Color(0xFFEC4899)],
    [Color(0xFFF59E0B), Color(0xFFEF4444)],
    [Color(0xFF0EA5E9), Color(0xFF6366F1)],
    [Color(0xFF10B981), Color(0xFF0EA5E9)],
  ];

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return letters;
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palettes[name.hashCode.abs() % _palettes.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.34),
        gradient: LinearGradient(
          colors: palette,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.first.withValues(alpha: 0.30),
            blurRadius: 16,
            spreadRadius: -6,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}

/// Icône dans un carré coloré arrondi.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const IconBadge(this.icon, {super.key, required this.color, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// Barre de progression arrondie et animée.
class ProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;

  const ProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(
        children: [
          Container(
            height: height,
            color: context.colors.onSurface.withValues(alpha: 0.08),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0, 1)),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => FractionallySizedBox(
              widthFactor: v,
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height),
                  gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.7), color],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// État vide avec animation Lottie.
class EmptyState extends StatelessWidget {
  final String title;
  final String? message;
  final Widget? action;

  const EmptyState({super.key, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: FadeSlideIn(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Lottie.asset(
                'assets/anime/empty-customer.json',
                width: 140,
                height: 140,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: context.text.titleMedium,
              ),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------- Feuilles & dialogues

/// Ouvre une feuille modale arrondie qui suit le clavier.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: builder(sheetContext),
      ),
    ),
  );
}

/// Titre standard d'une feuille modale.
class SheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const SheetHeader(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.text.headlineSmall),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Une ligne d'action dans une feuille modale.
class SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? color;
  final VoidCallback onTap;

  const SheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: IconBadge(icon, color: c, size: 42),
      title: Text(
        label,
        style: context.text.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      onTap: onTap,
    );
  }
}

/// Demande de confirmation. Retourne true si l'utilisateur confirme.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmer',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final danger = dialogContext.app.danger;
      return AlertDialog(
        icon: Icon(
          destructive ? Icons.warning_amber_rounded : Icons.help_outline,
          color: destructive ? danger : dialogContext.colors.primary,
          size: 32,
        ),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: destructive
                      ? FilledButton.styleFrom(backgroundColor: danger)
                      : null,
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(confirmLabel),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Message bref en bas de l'écran.
void showAppSnack(BuildContext context, String message, {bool error = false}) {
  final app = context.app;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  HapticFeedback.lightImpact();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: error ? app.danger : context.colors.inverseSurface,
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              color: error ? Colors.white : app.success,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: error ? Colors.white : context.colors.onInverseSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
}

/// Bouton qui fait défiler le thème : Système → Clair → Sombre.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeController.instance;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: controller,
      builder: (context, mode, _) {
        final icon = switch (mode) {
          ThemeMode.light => Icons.light_mode_rounded,
          ThemeMode.dark => Icons.dark_mode_rounded,
          ThemeMode.system => Icons.brightness_auto_rounded,
        };
        return Tooltip(
          message: switch (mode) {
            ThemeMode.light => 'Thème clair',
            ThemeMode.dark => 'Thème sombre',
            ThemeMode.system => 'Thème du système',
          },
          child: GlassCard(
            radius: 16,
            padding: const EdgeInsets.all(12),
            onTap: () => controller.set(switch (mode) {
              ThemeMode.system => ThemeMode.light,
              ThemeMode.light => ThemeMode.dark,
              ThemeMode.dark => ThemeMode.system,
            }),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, a) => RotationTransition(
                turns: Tween(begin: 0.6, end: 1.0).animate(a),
                child: FadeTransition(opacity: a, child: child),
              ),
              child: Icon(icon, key: ValueKey(mode), size: 22),
            ),
          ),
        );
      },
    );
  }
}

/// Champ de saisie d'un montant : gros chiffres, devise, équivalent en aide.
class AmountField extends StatelessWidget {
  final TextEditingController controller;
  final String devise;
  final bool autofocus;
  final String helper;
  final String label;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;

  const AmountField({
    super.key,
    required this.controller,
    required this.devise,
    this.autofocus = false,
    this.helper = '',
    this.label = 'Montant',
    this.validator,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: context.text.headlineSmall?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      decoration: InputDecoration(
        labelText: label,
        suffixText: devise,
        helperText: helper.isEmpty ? null : helper,
        prefixIcon: const Icon(Icons.payments_outlined),
      ),
      onChanged: onChanged,
      validator: validator,
    );
  }
}
