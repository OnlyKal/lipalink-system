import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../func/export.dart';
import 'home_shell.dart';

/// Écran de démarrage.
///
/// Sa première image est identique à l'écran natif (Android/iOS) : même fond,
/// logo de 96 au centre. L'animation part donc de là, sans saut ni flash.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  SplashScreenState createState() => SplashScreenState();
}

class SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _logoSize = 96.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
    // On prépare la suite pendant l'animation.
    final next = _nextScreen();
    Future.delayed(const Duration(milliseconds: 1250), () async {
      _open(await next);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Premier lancement : configuration ; ensuite : l'application.
  Future<Widget> _nextScreen() async {
    final session = await SharedPreferences.getInstance();
    return session.getBool('params-checked') == true
        ? const HomeShell()
        : const Settings(firstRun: true);
  }

  void _open(Widget next) {
    if (!mounted) return;
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => next,
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween(begin: 1.03, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Animation<double> step(double a, double b, [Curve c = Curves.easeOut]) =>
        CurvedAnimation(
          parent: _controller,
          curve: Interval(a, b, curve: c),
        );

    final background = step(0, 0.6);
    final glow = step(0.1, 0.7);
    final lift = step(0.25, 0.75, Curves.easeOutCubic);
    final pulse = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.08), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 1),
    ]).animate(step(0, 0.5, Curves.easeInOut));
    final title = step(0.4, 0.9, Curves.easeOutCubic);
    final footer = step(0.6, 1);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: context.colors.surface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Halos lumineux qui apparaissent en fondu.
            FadeTransition(
              opacity: background,
              child: const AmbientBackground(child: SizedBox.expand()),
            ),
            Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final up = -36 * lift.value;
                  return Transform.translate(
                    offset: Offset(0, up),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Le logo : même taille et même place que l'écran natif.
                        Transform.scale(
                          scale: pulse.value,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: context.colors.primary.withValues(
                                    alpha: 0.45 * glow.value,
                                  ),
                                  blurRadius: 70,
                                  spreadRadius: 6,
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/eden.png',
                              width: _logoSize,
                              height: _logoSize,
                            ),
                          ),
                        ),
                        // Le titre est placé sous le logo sans le décaler.
                        SizedBox(
                          height: 0,
                          child: OverflowBox(
                            maxHeight: 200,
                            alignment: Alignment.topCenter,
                            child: Opacity(
                              opacity: title.value,
                              child: Transform.translate(
                                offset: Offset(0, 24 + 16 * (1 - title.value)),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'LipaLink',
                                      style: context.text.headlineMedium,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Vos dettes, sous contrôle.',
                                      style: context.text.bodyLarge?.copyWith(
                                        color: context.colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: FadeTransition(
                  opacity: footer,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Text(
                      'Powered by Livia Tech © ${DateTime.now().year}',
                      style: context.text.labelMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
