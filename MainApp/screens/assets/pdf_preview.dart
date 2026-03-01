import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'certificate_service.dart'; // Adjust path if needed

class CertificatePreviewPage extends StatelessWidget {
  final String name;
  final int rank;
  final String dept;
  final int score;
  final String semester;

  const CertificatePreviewPage({
    super.key,
    required this.name,
    required this.rank,
    required this.dept,
    required this.score,
    required this.semester,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("$name's Certificate"),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: PdfPreview(
        // Calls the service to get the raw PDF data
        build: (format) => CertificateService.generateCertificateBytes(
          name: name,
          rank: rank,
          dept: dept,
          score: score,
          semester: semester,
        ),
        allowPrinting: true,
        allowSharing: true,
        canChangePageFormat: false,
        pdfFileName: "Certificate_${name.replaceAll(' ', '_')}.pdf",
      ),
    );
  }
}