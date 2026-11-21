import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'export.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void generateReleveDettes(
  ctx,
  DatabaseHelper dbHelper,
  String customerId,
  String id,
) {
  dbHelper.getDEBTDetails(customerId, id).then((releve) async {
    var companydb = await dbHelper.getCompany();
    String company = companydb!.first['nom'].toString();
    Map<String, String> informationCompany = await getCompanyInfos();
    String dateNow = convertDate(DateTime.now().toIso8601String());

    final fontRegular = pw.Font.ttf(
      await rootBundle.load("assets/fonts/Roboto-Regular.ttf"),
    );
    final fontBold = pw.Font.ttf(
      await rootBundle.load("assets/fonts/Roboto-Bold.ttf"),
    );

    // Get company logo
    String? logoBase64 = await getCompanyLogo();
    pw.ImageProvider? logoImage;
    if (logoBase64 != null) {
      try {
        final logoBytes = base64Decode(logoBase64);
        logoImage = pw.MemoryImage(logoBytes);
      } catch (e) {
        logoImage = null;
      }
    }

    if (releve != null) {
      List<Map<String, dynamic>> data = releve.toList();
      String customerName = data[0]['customerName'];
      double borrowedAmount = toAmount(data[0]['borrowedAmount']);
      final bool iOwe = data[0]['own'].toString() == kIOweThem;
      String debtDevise = data[0]['debtDevise'];
      String dueDate = convertDate(data[0]['dueDate']);
      String motif = data[0]['motif'];

      var total = 0.0;
      for (var i = 0; i < data.length; i++) {
        total += toAmount(data[i]['advanceAmount']);
      }
      final double rest = borrowedAmount - total;

      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header with company info and logo
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            company,
                            style: pw.TextStyle(font: fontBold, fontSize: 16),
                          ),
                          pw.SizedBox(height: 4),
                          if ((informationCompany['rccm'] ?? '').isNotEmpty)
                            pw.Text(
                              "RCCM: ${informationCompany['rccm']}",
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: 10,
                              ),
                            ),
                          if ((informationCompany['idnat'] ?? '').isNotEmpty)
                            pw.Text(
                              "IDNAT: ${informationCompany['idnat']}",
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: 10,
                              ),
                            ),
                          if ((informationCompany['website'] ?? '').isNotEmpty)
                            pw.Text(
                              "Site Web: ${informationCompany['website']}",
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: 10,
                              ),
                            ),
                          if ((informationCompany['phone'] ?? '').isNotEmpty)
                            pw.Text(
                              "Téléphone: ${informationCompany['phone']}",
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: 10,
                              ),
                            ),
                          if ((informationCompany['email'] ?? '').isNotEmpty)
                            pw.Text(
                              "Email: ${informationCompany['email']}",
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (logoImage != null)
                      pw.Container(
                        width: 80,
                        height: 80,
                        child: pw.Image(logoImage),
                      ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  "Date: $dateNow",
                  style: pw.TextStyle(font: fontRegular, fontSize: 10),
                ),
                pw.Divider(thickness: 1),
                pw.SizedBox(height: 10),
                pw.Text(
                  'RELEVÉ DE DETTES',
                  style: const pw.TextStyle(fontSize: 24),
                ),
                pw.SizedBox(height: 20),
                pw.Text('Nom du Client : $customerName'),
                pw.Text(
                  iOwe
                      ? 'Sens : dette envers le client'
                      : 'Sens : le client nous doit',
                ),
                pw.Text(
                  'Montant de la dette : ${formatMoney(borrowedAmount, debtDevise)}',
                ),
                pw.Text('Date d\'échéance : $dueDate'),
                pw.Text('Motif : $motif'),
                pw.SizedBox(height: 20),
                pw.Text('Paiements:'),
                pw.ListView.builder(
                  itemCount: data.length,
                  itemBuilder: (context, index) {
                    if (data[index]['paidDate'] != null) {
                      return pw.Text(
                        'Date: ${convertDate(data[index]['paidDate'])} - Montant: ${formatMoney(toAmount(data[index]['advanceAmount']), debtDevise)}',
                      );
                    }
                    return pw.SizedBox.shrink();
                  },
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Total des avances : ${formatMoney(total, debtDevise)}',
                ),
                pw.Text(
                  rest <= kMoneyEpsilon
                      ? 'Solde : dette entièrement réglée'
                      : 'Reste à payer : ${formatMoney(rest, debtDevise)}',
                ),
              ],
            );
          },
        ),
      );
      savePDFPermanently(ctx, pdf, company, "DETTE");
    }
  });
}

Future<void> savePDFPermanently(
  context,
  pw.Document pdf,
  String company,
  String type,
) async {
  Directory? reportsDirectory;
  var companyAsPath = company.toString().replaceAll(" ", "_");
  if (Platform.isAndroid) {
    reportsDirectory = await getExternalStorageDirectory();
    String newPath = "";
    List<String> folders = reportsDirectory!.path.split("/");
    for (int i = 1; i < folders.length; i++) {
      String folder = folders[i];
      if (folder != "Android") {
        newPath += "/$folder";
      } else {
        break;
      }
    }

    newPath += "/Download/$companyAsPath";
    reportsDirectory = Directory(newPath);
  } else if (Platform.isIOS) {
    reportsDirectory = await getApplicationDocumentsDirectory();
    reportsDirectory = Directory("${reportsDirectory.path}/$companyAsPath");
  }

  // Créer le dossier si non existant
  if (reportsDirectory?.exists() != null) {
    await reportsDirectory?.create(recursive: true);
  }

  // Nom de fichier unique
  String formattedDate = DateFormat('dd-MM-yyyy').format(DateTime.now());
  int number = math.Random().nextInt(3000) + 1;
  String fileName = "$type-$formattedDate-$number.pdf";
  final filePath = "${reportsDirectory?.path}/$fileName";

  final file = File(filePath);
  await file.writeAsBytes(await pdf.save());
  final xFile = XFile(filePath);

  // --- Afficher un dialog pour choisir ---
  if (context.mounted) {
    showAppSheet(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader('Relevé prêt', subtitle: fileName),
          SheetAction(
            icon: Icons.open_in_new_rounded,
            label: 'Ouvrir',
            subtitle: 'Avec votre lecteur PDF',
            onTap: () {
              Navigator.pop(ctx);
              OpenFile.open(filePath);
            },
          ),
          SheetAction(
            icon: Icons.ios_share_rounded,
            label: 'Partager',
            subtitle: 'WhatsApp, e-mail, Bluetooth…',
            onTap: () async {
              Navigator.pop(ctx);
              await Share.shareXFiles(
                [xFile],
                text:
                    "Bonjour, veuillez trouver ci-joint le relevé pour votre consultation. Merci et bonne journée.",
                subject: "Relevé $type - $company",
              );
            },
          ),
        ],
      ),
    );
  }
}

Future<bool> requestStoragePermission() async {
  if (Platform.isAndroid) {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    return status.isGranted;
  }
  return true; // iOS n'a pas besoin ici
}

void generateMultipleReleveDettes(
  ctx,
  DatabaseHelper dbHelper,
  String customerId,
  List<int> debtIds,
) {
  dbHelper.getMultipleDEBTDetails(customerId, debtIds).then((releves) async {
    var companydb = await dbHelper.getCompany();
    String company = companydb!.first['nom'].toString();
    Map<String, String> informationCompany = await getCompanyInfos();
    String dateNow = convertDate(DateTime.now().toIso8601String());

    final fontRegular = pw.Font.ttf(
      await rootBundle.load("assets/fonts/Roboto-Regular.ttf"),
    );
    final fontBold = pw.Font.ttf(
      await rootBundle.load("assets/fonts/Roboto-Bold.ttf"),
    );

    // Get company logo
    String? logoBase64 = await getCompanyLogo();
    pw.ImageProvider? logoImage;
    if (logoBase64 != null) {
      try {
        final logoBytes = base64Decode(logoBase64);
        logoImage = pw.MemoryImage(logoBytes);
      } catch (e) {
        logoImage = null;
      }
    }

    if (releves != null && releves.isNotEmpty) {
      final pdf = pw.Document();

      // Group debts by debt ID
      Map<int, List<Map<String, dynamic>>> groupedReleves = {};

      for (var releve in releves) {
        int debtId = (releve['debtId'] as int?) ?? 0;
        if (!groupedReleves.containsKey(debtId)) {
          groupedReleves[debtId] = [];
        }
        groupedReleves[debtId]!.add(releve);
      }

      String customerName = (releves[0]['customerName'] as String?) ?? '';

      pdf.addPage(
        pw.MultiPage(
          build: (pw.Context context) {
            List<pw.Widget> widgets = [];

            // Header with company info and logo
            widgets.add(
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          company,
                          style: pw.TextStyle(font: fontBold, fontSize: 16),
                        ),
                        pw.SizedBox(height: 4),
                        if ((informationCompany['rccm'] ?? '').isNotEmpty)
                          pw.Text(
                            "RCCM: ${informationCompany['rccm']}",
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 10,
                            ),
                          ),
                        if ((informationCompany['idnat'] ?? '').isNotEmpty)
                          pw.Text(
                            "IDNAT: ${informationCompany['idnat']}",
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 10,
                            ),
                          ),
                        if ((informationCompany['website'] ?? '').isNotEmpty)
                          pw.Text(
                            "Site Web: ${informationCompany['website']}",
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 10,
                            ),
                          ),
                        if ((informationCompany['phone'] ?? '').isNotEmpty)
                          pw.Text(
                            "Téléphone: ${informationCompany['phone']}",
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 10,
                            ),
                          ),
                        if ((informationCompany['email'] ?? '').isNotEmpty)
                          pw.Text(
                            "Email: ${informationCompany['email']}",
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (logoImage != null)
                    pw.Container(
                      width: 80,
                      height: 80,
                      child: pw.Image(logoImage),
                    ),
                ],
              ),
            );

            widgets.addAll([
              pw.SizedBox(height: 8),
              pw.Text(
                "Date: $dateNow",
                style: pw.TextStyle(font: fontRegular, fontSize: 10),
              ),
              pw.Divider(thickness: 1),
              pw.SizedBox(height: 10),
              pw.Text(
                'RELEVÉ DE DETTES GROUPÉES',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 20,
                  color: PdfColors.blue800,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Nom du Client : $customerName',
                style: pw.TextStyle(font: fontRegular, fontSize: 14),
              ),
              pw.SizedBox(height: 20),
            ]);

            // Process each debt
            groupedReleves.forEach((debtId, debtData) {
              if (debtData.isNotEmpty) {
                var firstDebt = debtData.first;
                double borrowedAmount = toAmount(firstDebt['borrowedAmount']);
                String debtDevise = (firstDebt['debtDevise'] as String?) ?? '';
                final bool iOwe = firstDebt['own'].toString() == kIOweThem;
                String dueDate = convertDate(
                  (firstDebt['dueDate'] as String?) ?? '',
                );
                String motif = (firstDebt['motif'] as String?) ?? '';

                var total = 0.0;
                for (var debt in debtData) {
                  total += toAmount(debt['advanceAmount']);
                }
                final double rest = borrowedAmount - total;

                widgets.addAll([
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400),
                      borderRadius: pw.BorderRadius.circular(0),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Motif : $motif',
                          style: pw.TextStyle(font: fontBold, fontSize: 14),
                        ),
                        pw.Text(
                          iOwe
                              ? 'Sens : dette envers le client'
                              : 'Sens : le client nous doit',
                          style: pw.TextStyle(font: fontRegular, fontSize: 12),
                        ),
                        pw.Text(
                          'Montant de la dette : ${formatMoney(borrowedAmount, debtDevise)}',
                          style: pw.TextStyle(font: fontRegular, fontSize: 12),
                        ),
                        pw.Text(
                          'Date d\'échéance : $dueDate',
                          style: pw.TextStyle(font: fontRegular, fontSize: 12),
                        ),
                        pw.SizedBox(height: 8),

                        // Payments table for this debt
                        if (debtData.any((d) => d['paidDate'] != null)) ...[
                          pw.Text(
                            'Paiements:',
                            style: pw.TextStyle(font: fontBold, fontSize: 12),
                          ),
                          pw.SizedBox(height: 4),
                          pw.TableHelper.fromTextArray(
                            headers: ['Date', 'Montant'],
                            data: debtData
                                .where((d) => d['paidDate'] != null)
                                .map(
                                  (d) => [
                                    convertDate(
                                      (d['paidDate'] as String?) ?? '',
                                    ),
                                    formatMoney(
                                      toAmount(d['advanceAmount']),
                                      debtDevise,
                                    ),
                                  ],
                                )
                                .toList(),
                            headerStyle: pw.TextStyle(
                              font: fontBold,
                              fontSize: 10,
                            ),
                            cellStyle: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 10,
                            ),
                            headerDecoration: pw.BoxDecoration(
                              color: PdfColors.grey300,
                            ),
                            cellAlignment: pw.Alignment.centerLeft,
                          ),
                          pw.SizedBox(height: 8),
                        ],

                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'Total des avances : ${formatMoney(total, debtDevise)}',
                              style: pw.TextStyle(font: fontBold, fontSize: 12),
                            ),
                            pw.Text(
                              rest <= kMoneyEpsilon
                                  ? 'Dette réglée'
                                  : 'Reste à payer : ${formatMoney(rest, debtDevise)}',
                              style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 12,
                                color: PdfColors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 15),
                ]);
              }
            });

            // Résumé : un total par sens ET par devise (jamais mélangés).
            // clé : "devise|own" -> [montant, payé]
            final Map<String, List<double>> totals = {};
            groupedReleves.forEach((debtId, debtData) {
              if (debtData.isEmpty) return;
              final firstDebt = debtData.first;
              final key =
                  "${firstDebt['debtDevise']}|${firstDebt['own'] == kIOweThem ? kIOweThem : kTheyOweMe}";
              final paid = debtData.fold<double>(
                0,
                (sum, d) => sum + toAmount(d['advanceAmount']),
              );
              final entry = totals.putIfAbsent(key, () => [0, 0]);
              entry[0] += toAmount(firstDebt['borrowedAmount']);
              entry[1] += paid;
            });

            final summaryRows = <List<String>>[];
            for (final own in [kTheyOweMe, kIOweThem]) {
              for (final devise in ['USD', 'CDF']) {
                final entry = totals["$devise|$own"];
                if (entry == null) continue;
                summaryRows.add([
                  own == kIOweThem ? 'Nous devons' : 'Le client doit',
                  devise,
                  formatAmount(entry[0]),
                  formatAmount(entry[1]),
                  formatAmount(math.max(0, entry[0] - entry[1])),
                ]);
              }
            }

            widgets.addAll([
              pw.Divider(thickness: 2),
              pw.Text(
                'RÉSUMÉ GÉNÉRAL',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 16,
                  color: PdfColors.blue800,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                headers: ['Sens', 'Devise', 'Montant', 'Payé', 'Reste'],
                data: summaryRows,
                headerStyle: pw.TextStyle(font: fontBold, fontSize: 11),
                cellStyle: pw.TextStyle(font: fontRegular, fontSize: 10),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
                cellAlignment: pw.Alignment.center,
              ),
            ]);

            return widgets;
          },
        ),
      );

      savePDFPermanently(ctx, pdf, company, "DETTES_GROUPEES");
    }
  });
}
