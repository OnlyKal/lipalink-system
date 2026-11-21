import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/func/export.dart';

void print(data) => debugPrint(data.toString());

Future<T?> goTox<T>(BuildContext context, Widget page) {
  return Navigator.push<T>(
    context,
    MaterialPageRoute(builder: (context) => page),
  );
}

void back(context) => Navigator.pop(context);

String capitalizeString(String input) {
  List<String> words = input.split(' ');
  List<String> capitalizedWords = words.map((word) {
    if (word.isNotEmpty) {
      return word[0].toUpperCase() + word.substring(1);
    } else {
      return word;
    }
  }).toList();
  String result = capitalizedWords.join(' ');
  return result;
}

/// Date en français : "27, novembre 2027".
/// Accepte une chaîne ISO ou un DateTime ; retourne "—" si la date est illisible.
/// Met seulement la première lettre en majuscule ("3 sacs de riz" -> "3 sacs de riz").
String sentenceCase(String input) {
  final t = input.trim();
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

String convertDate(Object? date) {
  final DateTime? parsed = date is DateTime
      ? date
      : DateTime.tryParse(date?.toString() ?? '');
  if (parsed == null) return '—';
  return DateFormat('d, MMMM yyyy', 'fr').format(parsed);
}

/// Jours calendaires avant une échéance (négatif = en retard).
int daysUntil(Object? date) {
  final due = DateTime.tryParse(date?.toString() ?? '');
  if (due == null) return 0;
  final now = DateTime.now();
  return DateTime(
    due.year,
    due.month,
    due.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
}

/// Libellé court d'une échéance : "Dans 3 jours", "Aujourd'hui", "Retard 2 j"…
String dueLabel(int days) {
  if (days > 1) return 'Dans $days jours';
  if (days == 1) return 'Demain';
  if (days == 0) return "Aujourd'hui";
  if (days == -1) return 'En retard d\'1 jour';
  return 'En retard de ${-days} jours';
}

void shareString(dateToshare) {
  Share.share(dateToshare);
}

/// Masque ou affiche les dettes réglées, et mémorise le choix.
Future<void> setOperationMasked(bool value) async {
  operationIsMasked = value;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool("operationState", value);
}

/// Charge le réglage au démarrage. Par défaut (jamais modifié) : masquer.
Future<void> chechIfOperationIsmaskef() async {
  final prefs = await SharedPreferences.getInstance();
  operationIsMasked = prefs.getBool("operationState") ?? true;
}

/// Partage le relevé d'une dette sous forme de texte (WhatsApp, SMS...).
Future<void> sendReleve(DatabaseHelper dbHelper, customerId, id) async {
  final releve = await dbHelper.getDEBTDetails(customerId, id);
  if (releve == null || releve.isEmpty) return;

  final first = releve.first;
  final devise = first['debtDevise'].toString();
  final amount = toAmount(first['borrowedAmount']);
  final iOwe = first['own'].toString() == kIOweThem;

  final buffer = StringBuffer();
  buffer.writeln("*RELEVÉ DE DETTE*");
  buffer.writeln("*CLIENT :* ${first['customerName']}");
  buffer.writeln("*SENS :* ${iOwe ? 'Nous vous devons' : 'Vous nous devez'}");
  buffer.writeln("*MOTIF :* ${first['motif']}");
  buffer.writeln("*MONTANT :* ${formatMoney(amount, devise)}");
  buffer.writeln("*ÉCHÉANCE :* ${convertDate(first['dueDate'].toString())}");
  buffer.writeln("-------------------------");

  double paid = 0;
  for (final entry in releve) {
    if (entry['advanceAmount'] == null) continue;
    final value = toAmount(entry['advanceAmount']);
    paid += value;
    buffer.writeln(
      "${convertDate(entry['paidDate'].toString())} : ${formatMoney(value, devise)}",
    );
  }
  final rest = amount - paid;

  buffer.writeln("-------------------------");
  buffer.writeln("*TOTAL PAYÉ :* ${formatMoney(paid, devise)}");
  buffer.writeln(
    rest <= kMoneyEpsilon
        ? "*SOLDE :* Dette entièrement réglée"
        : "*RESTE À PAYER :* ${formatMoney(rest, devise)}",
  );

  shareString(buffer.toString());
}

Future<void> updateCompanyInfos(
  String? rccm,
  String? phone,
  String? email,
  String? idnat,
  String? adresse,
  String? website,
) async {
  final prefs = await SharedPreferences.getInstance();

  if (rccm != null) await prefs.setString('rccm', rccm);
  if (phone != null) await prefs.setString('phone', phone);
  if (email != null) await prefs.setString('email', email);
  if (idnat != null) await prefs.setString('idnat', idnat);
  if (adresse != null) await prefs.setString('adresse', adresse);
  if (website != null) await prefs.setString('website', website);
}

Future<Map<String, String>> getCompanyInfos() async {
  final prefs = await SharedPreferences.getInstance();

  // valeurs initiales
  // Vides par défaut : l'utilisateur renseigne ses propres coordonnées.
  final defaults = {
    'rccm': '',
    'phone': '',
    'email': '',
    'idnat': '',
    'adresse': '',
    'website': '',
  };

  // si c'est la première fois → on enregistre les valeurs par défaut
  for (final entry in defaults.entries) {
    if (!prefs.containsKey(entry.key)) {
      await prefs.setString(entry.key, entry.value);
    }
  }

  // on retourne les valeurs actuelles (mises à jour ou par défaut)
  return {
    'rccm': prefs.getString('rccm') ?? defaults['rccm']!,
    'phone': prefs.getString('phone') ?? defaults['phone']!,
    'email': prefs.getString('email') ?? defaults['email']!,
    'idnat': prefs.getString('idnat') ?? defaults['idnat']!,
    'adresse': prefs.getString('adresse') ?? defaults['adresse']!,
    'website': prefs.getString('website') ?? defaults['website']!,
  };
}

Future<String?> getCompanyLogo() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  return prefs.getString('company_logo');
}
