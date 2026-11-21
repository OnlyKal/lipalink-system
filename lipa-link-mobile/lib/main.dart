import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import '/func/export.dart';
import 'cloud/cloud_service.dart';

// flutter build apk --release --split-per-abi

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Noms des mois et des jours en français pour toutes les dates affichées.
  await initializeDateFormatting('fr');

  // La base doit être prête (tables, taux par défaut, statuts recalculés)
  // avant d'afficher le moindre écran.
  await DatabaseHelper().ensureInitialData();
  await chechIfOperationIsmaskef();
  await ThemeController.instance.load();

  runApp(const LipaLinkApp());

  // Services non bloquants : notifications, tâche de fond, permissions.
  initServices();
}

Future<void> initServices() async {
  try {
    // Sauvegarde en ligne : contact au démarrage puis à chaque mise en
    // arrière-plan de l'application.
    await CloudService.instance.load();
    WidgetsBinding.instance.addObserver(CloudLifecycleObserver());
    CloudService.instance.autoRun(force: true);
    NotificationClass.initializeNotif();
    await initBackgroundFetch();
    await permissionContact();
    await requestStoragePermission();
  } catch (e) {
    print("Initialisation des services : $e");
  }
}

class LipaLinkApp extends StatelessWidget {
  const LipaLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) => MaterialApp(
        title: 'LipaLink',
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('fr', 'FR')],
        locale: const Locale('fr', 'FR'),
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        themeAnimationDuration: const Duration(milliseconds: 400),
        // Icônes de la barre d'état et de navigation adaptées au thème.
        builder: (context, child) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value:
                (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                    .copyWith(
                      statusBarColor: Colors.transparent,
                      systemNavigationBarColor: Theme.of(
                        context,
                      ).colorScheme.surface,
                      systemNavigationBarIconBrightness: dark
                          ? Brightness.light
                          : Brightness.dark,
                    ),
            child: child!,
          );
        },
        home: const SplashScreen(),
      ),
    );
  }
}
