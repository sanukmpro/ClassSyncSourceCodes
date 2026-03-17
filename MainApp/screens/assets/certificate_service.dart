import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

class CertificateService {
  static Future<Uint8List> generateCertificateBytes({
    required String name,
    required int rank,
    required String dept,
    required String semester,
    required int score,
    required String certId, // The Firestore Document ID
  }) async {
    final pdf = pw.Document();

    // 1. Load the Official Branding
    // Ensure this path exists in your pubspec.yaml
    final ByteData logoData = await rootBundle.load('assets/icon/app_icon.png');
    final pw.MemoryImage logoImage = pw.MemoryImage(logoData.buffer.asUint8List());

    // 2. Dynamic Theming based on Achievement Level
    final PdfColor primaryColor = rank == 1
        ? PdfColor.fromHex("#D4AF37") // Gold
        : (rank == 2 ? PdfColor.fromHex("#C0C0C0") : PdfColor.fromHex("#CD7F32")); // Silver/Bronze

    final String dateStr = DateFormat('MMMM d, yyyy').format(DateTime.now());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(15),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: primaryColor, width: 10),
            ),
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: primaryColor, width: 2),
              ),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  // --- HEADER: Official Branding ---
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.SizedBox(width: 45, height: 45, child: pw.Image(logoImage)),
                      pw.SizedBox(width: 15),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text("CLASSSYNC ACADEMIC NETWORK",
                              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                          pw.Text("Official Digital Credential",
                              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 15),
                  pw.Text("CERTIFICATE OF HONOR",
                      style: pw.TextStyle(fontSize: 40, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                  pw.SizedBox(height: 25),

                  // --- RECIPIENT DATA ---
                  pw.Text("This recognition is proudly presented to",
                      style: const pw.TextStyle(fontSize: 16, fontStyle: pw.FontStyle.italic)),
                  pw.SizedBox(height: 10),
                  pw.Text(name.toUpperCase(),
                      style: pw.TextStyle(fontSize: 44, fontWeight: pw.FontWeight.bold, color: primaryColor)),

                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 140),
                    child: pw.Divider(thickness: 1.5, color: PdfColors.grey400),
                  ),
                  pw.SizedBox(height: 20),

                  // --- ACHIEVEMENT DESCRIPTION ---
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 50),
                    child: pw.Text(
                      "In recognition of outstanding academic performance and contribution, achieving Rank #$rank in the $dept Department during Semester $semester, with a verified Honor Score of $score.",
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 14, lineSpacing: 1.4),
                    ),
                  ),

                  pw.SizedBox(height: 35),

                  // --- VERIFICATION FOOTER ---
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      _buildSignColumn("College Administration", "ClassSync Authority"),

                      // --- SECURE QR VERIFICATION ---
                      pw.Column(
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.all(5),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.white,
                              border: pw.Border.all(color: PdfColors.grey300),
                            ),
                            child: pw.BarcodeWidget(
                              barcode: pw.Barcode.qrCode(),
                              // Using a clear data format for Admin Scanning
                              data: certId,
                              width: 70,
                              height: 70,
                            ),
                          ),
                          pw.SizedBox(height: 5),
                          pw.Text("ID: $certId",
                              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                          pw.Text("SCAN TO VERIFY",
                              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                        ],
                      ),

                      _buildSignColumn(dateStr, "Date of Issuance"),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildSignColumn(String topText, String bottomText) {
    return pw.Column(
      children: [
        pw.Text(topText, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        pw.Container(
          width: 150,
          margin: const pw.EdgeInsets.symmetric(vertical: 4),
          decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(width: 1, color: PdfColors.black))
          ),
        ),
        pw.Text(bottomText, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
      ],
    );
  }
}
