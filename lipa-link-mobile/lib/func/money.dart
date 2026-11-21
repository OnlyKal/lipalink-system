// Outils de lecture et d'affichage des montants.

/// En dessous de cette valeur, un solde est considéré comme nul
/// (évite les erreurs d'arrondi des nombres à virgule : 0.1 + 0.2 != 0.3).
const double kMoneyEpsilon = 0.005;

/// Lit un montant saisi par l'utilisateur.
/// Accepte la virgule ou le point ("10,5" ou "10.5") et ignore les espaces.
/// Retourne null si la saisie n'est pas un nombre valide.
double? parseAmount(String? input) {
  if (input == null) return null;
  final cleaned = input.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null || value.isNaN || value.isInfinite) return null;
  return value;
}

/// Arrondit au centime.
double roundMoney(num value) => (value * 100).roundToDouble() / 100;

/// Convertit une valeur venant de la base (int, double, String, null) en double.
double toAmount(Object? value) {
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();
  return parseAmount(value.toString()) ?? 0.0;
}

/// Affiche un montant : "1 250.5" -> "1 250.50".
String formatAmount(num value) {
  final rounded = roundMoney(value);
  final negative = rounded < 0;
  final parts = rounded.abs().toStringAsFixed(2).split('.');
  final intPart = parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(intPart[i]);
  }
  return '${negative ? '-' : ''}$buffer.${parts[1]}';
}

/// Affiche un montant suivi de sa devise : "1 250.50 USD".
String formatMoney(num value, String devise) =>
    '${formatAmount(value)} $devise';
