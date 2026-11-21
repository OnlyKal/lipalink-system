import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../func/export.dart';

/// Coquille principale : Accueil, Clients, Réglages.
class HomeShell extends StatefulWidget {
  final int initialIndex;
  const HomeShell({super.key, this.initialIndex = 0});

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  late int index = widget.initialIndex;

  /// Change d'onglet depuis une page enfant (ex. le tableau de bord).
  void goToTab(int value) => setState(() => index = value);

  @override
  Widget build(BuildContext context) {
    // Chaque onglet est reconstruit quand on y revient : les données
    // sont toujours à jour, sans bouton « actualiser ».
    final Widget page = switch (index) {
      0 => DashboardScreen(key: const ValueKey('home'), onNavigate: goToTab),
      1 => const Clients(key: ValueKey('clients'), embedded: true),
      _ => const Settings(key: ValueKey('settings'), embedded: true),
    };

    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => index = 0);
      },
      child: Scaffold(
        extendBody: true,
        body: AmbientBackground(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween(begin: 0.98, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            child: page,
          ),
        ),
        bottomNavigationBar: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.surface.withValues(alpha: 0.72),
                border: Border(top: BorderSide(color: context.app.glassBorder)),
              ),
              child: NavigationBar(
                selectedIndex: index,
                onDestinationSelected: goToTab,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(CupertinoIcons.square_grid_2x2),
                    selectedIcon: Icon(CupertinoIcons.square_grid_2x2_fill),
                    label: 'Accueil',
                  ),
                  NavigationDestination(
                    icon: Icon(CupertinoIcons.person_2),
                    selectedIcon: Icon(CupertinoIcons.person_2_fill),
                    label: 'Clients',
                  ),
                  NavigationDestination(
                    icon: Icon(CupertinoIcons.gear),
                    selectedIcon: Icon(CupertinoIcons.gear_solid),
                    label: 'Réglages',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
