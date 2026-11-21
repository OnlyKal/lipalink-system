import 'dart:io';

import 'package:edenmanager/DataBaseHelper.dart';
import 'package:edenmanager/classes/Customer.dart';
import 'package:edenmanager/classes/Debt.dart';
import 'package:edenmanager/func/size.dart';
import 'package:edenmanager/pages/dettes.dart';
import 'package:edenmanager/pages/settings.dart';
import 'package:edenmanager/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Widget app(Widget home) => MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('fr', 'FR')],
      locale: const Locale('fr', 'FR'),
      theme: AppTheme.light(),
      home: home,
    );

void main() {
  late int clientId;

  setUpAll(() async {
    await initializeDateFormatting('fr');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final f = File(p.join(await getDatabasesPath(), 'debt_.db'));
    if (f.existsSync()) f.deleteSync();
    final db = DatabaseHelper();
    await db.ensureInitialData();
    await db.createCustomer(Customer(fullname: 'Aline', phone: '1', email: ''));
    clientId = (await db.getCustomersWithBalances()).first['id'] as int;
    Future<int> debt(String motif, double amount) async => (await db.insertDebt(Debt(
          todayDate: DateTime.now(),
          dueDate: DateTime.now().add(const Duration(days: 5)),
          borrowedAmount: amount,
          devise: 'USD',
          status: 'false',
          motif: motif,
          customerId: clientId,
          own: kTheyOweMe,
        )))!;
    await debt('Dette en cours A', 100);
    await debt('Dette en cours B', 50);
    final settled = await debt('Dette reglee C', 30);
    await db.addAvance(settled, 30); // entièrement payée -> réglée
  });

  Future<void> openList(WidgetTester t) async {
    t.view.physicalSize = const Size(1080, 4000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const SizedBox()); // nouvel écran, comme dans l'appli
    await t.runAsync(() async {
      await t.pumpWidget(app(DebtList(customerId: clientId, customer: 'Aline')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    for (var i = 0; i < 15; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapChip(WidgetTester t, String label) async {
    await t.tap(find.textContaining(label).first);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  void expectVisible({required bool a, required bool b, required bool c}) {
    expect(find.text('Dette en cours A'), a ? findsOneWidget : findsNothing);
    expect(find.text('Dette en cours B'), b ? findsOneWidget : findsNothing);
    expect(find.text('Dette reglee C'), c ? findsOneWidget : findsNothing);
  }

  testWidgets('1. Nouvelle installation : réglées masquées par défaut', (t) async {
    SharedPreferences.setMockInitialValues({});
    await chechIfOperationIsmaskef();
    expect(operationIsMasked, isTrue);
    await openList(t);
    expectVisible(a: true, b: true, c: false);
  });

  testWidgets('2. Filtres : Réglées puis Toutes puis En cours', (t) async {
    SharedPreferences.setMockInitialValues({});
    await chechIfOperationIsmaskef();
    await openList(t);
    await tapChip(t, 'Réglées');
    expectVisible(a: false, b: false, c: true);
    await tapChip(t, 'Toutes');
    expectVisible(a: true, b: true, c: true);
    await tapChip(t, 'En cours');
    expectVisible(a: true, b: true, c: false);
  });

  testWidgets('3. Réglage désactivé : toutes les dettes affichées', (t) async {
    SharedPreferences.setMockInitialValues({'operationState': false});
    await chechIfOperationIsmaskef();
    expect(operationIsMasked, isFalse);
    await openList(t);
    expectVisible(a: true, b: true, c: true);
  });

  testWidgets('4. Interrupteur des Réglages : enregistré et appliqué', (t) async {
    SharedPreferences.setMockInitialValues({});
    await chechIfOperationIsmaskef();
    await t.runAsync(() async {
      await t.pumpWidget(app(const Settings()));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    for (var i = 0; i < 15; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final sw = find.byType(Switch);
    expect(t.widget<Switch>(sw).value, isTrue);
    await t.runAsync(() async {
      await t.tap(sw);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await t.pump();
    expect(t.widget<Switch>(sw).value, isFalse);
    expect(operationIsMasked, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('operationState'), isFalse);
    // Redémarrage simulé : la valeur est relue.
    operationIsMasked = true;
    await chechIfOperationIsmaskef();
    expect(operationIsMasked, isFalse);
    await openList(t);
    expectVisible(a: true, b: true, c: true);
  });

  testWidgets('5. Dette soldée : disparaît de « En cours »', (t) async {
    SharedPreferences.setMockInitialValues({});
    await chechIfOperationIsmaskef();
    final db = DatabaseHelper();
    final rows = await t.runAsync(() => db.getDebtsOptimized(clientId, 0, -1));
    final b = rows!.firstWhere((d) => d['motif'] == 'Dette en cours B')['id'] as int;
    final result = await t.runAsync(() => db.addAvance(b, 50));
    expect(result!.closed, isTrue);
    await openList(t);
    expectVisible(a: true, b: false, c: false);
    await tapChip(t, 'Réglées');
    expectVisible(a: false, b: true, c: true);
    // Suppression du paiement : la dette est rouverte et revient « En cours ».
    final avances = await t.runAsync(() => db.getAvance(b));
    await t.runAsync(() => db.deleteAvance(avances!.first.id!));
    await openList(t);
    expectVisible(a: true, b: true, c: false);
  });
}
