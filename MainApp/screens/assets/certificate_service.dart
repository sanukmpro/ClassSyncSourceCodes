import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle; // Required for loading assets
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

class CertificateService {
  static Future<Uint8List> generateCertificateBytes({
    required String name,
    required int rank,
    required String dept,
    required String semester, // 1. ADDED: Semester parameter
    required int score,
  }) async {
    final pdf = pw.Document();

    // 2. ADDED: Load the logo from assets
    // Change this line in your CertificateService class:
    final ByteData logoData = await rootBundle.load('assets/icon/app_icon.png');
    final pw.MemoryImage logoImage = pw.MemoryImage(logoData.buffer.asUint8List());

    // Determine colors based on rank
    final PdfColor primaryColor = rank == 1
        ? PdfColor.fromHex("#D4AF37") // Gold
        : (rank == 2 ? PdfColor.fromHex("#C0C0C0") : PdfColor.fromHex("#CD7F32")); // Silver, Bronze

    final String rankLabel = rank == 1 ? "Gold" : (rank == 2 ? "Silver" : "Platinum");
    final String dateStr = DateFormat('MMMM d, yyyy').format(DateTime.now());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: primaryColor, width: 12),
            ),
            child: pw.Container(
              margin: const pw.EdgeInsets.all(5),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: primaryColor, width: 2),
              ),
              child: pw.Center(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text("CERTIFICATE OF HONOR",
                        style: pw.TextStyle(
                          fontSize: 40,
                          fontWeight: pw.FontWeight.bold,
                        )),
                    pw.SizedBox(height: 10),
                    pw.Text("ClassSync Academic Excellence Award",
                        style: const pw.TextStyle(fontSize: 18, color: PdfColors.grey700)),
                    pw.SizedBox(height: 35),
                    pw.Text("This recognition is proudly presented to",
                        style: const pw.TextStyle(fontSize: 16, fontStyle: pw.FontStyle.italic)),
                    pw.SizedBox(height: 15),
                    pw.Text(name.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 45,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        )),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 100),
                      child: pw.Divider(thickness: 1, color: PdfColors.grey300),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Text(
                      "For achieving Rank #$rank Contributor in the $dept Department",
                      style: const pw.TextStyle(fontSize: 16),
                      textAlign: pw.TextAlign.center,
                    ),
                    // 3. UPDATED: Text now includes the semester
                    pw.Text(
                      "during Semester $semester with a total Honor Score of $score.",
                      style: const pw.TextStyle(fontSize: 16),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 50),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        _buildSignColumn("ClassSync Admin", "Official Verification"),
                        // 4. REPLACED: The old seal is now the logo
                        pw.SizedBox(
                          width: 80,
                          height: 80,
                          child: pw.Image(logoImage),
                        ),
                        _buildSignColumn(dateStr, "Date of Issue"),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Helper function for signature lines, no changes needed here.
  static pw.Widget _buildSignColumn(String topText, String bottomText) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          width: 150,
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(width: 1, color: PdfColors.black)),
          ),
          padding: const pw.EdgeInsets.only(top: 5),
          child: pw.Text(
            topText,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(bottomText, style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }
}
