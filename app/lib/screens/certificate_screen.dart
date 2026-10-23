import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/api_client.dart';
import '../domain/certificate_builder.dart';
import '../state/app_state.dart';
import '../widgets/gov_ui.dart';

/// Shows one certificate. `local` is a record from the on-device DB: {body, image_path, synced, ...}.
class CertificateScreen extends StatefulWidget {
  const CertificateScreen({super.key, required this.local});
  final Map<String, dynamic> local;
  @override
  State<CertificateScreen> createState() => _CertificateScreenState();
}

class _CertificateScreenState extends State<CertificateScreen> {
  String? _verifyText;
  bool? _verifyOk;
  bool _busy = false;

  Map<String, dynamic> get _b => Map<String, dynamic>.from(widget.local['body'] as Map);
  bool get _synced => widget.local['synced'] as bool;

  String get _qr => 'onigrader:verify:${_b['id']}:${_b['device_hash']}';

  Future<void> _verify() async {
    setState(() => _busy = true);
    try {
      final r = await context.read<AppState>().api.verify(_b['id'] as String);
      setState(() {
        _verifyOk = r['valid'] as bool;
        _verifyText = r['reason'] as String;
      });
    } on ApiException catch (e) {
      setState(() {
        _verifyOk = null;
        _verifyText = e.message;
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _pdf() async {
    final b = _b;
    final doc = pw.Document();
    doc.addPage(pw.Page(
      build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('National Mandi Produce Quality Certificate', style: const pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text('Government of India Mandi Quality Standards Compliance', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 12),
        pw.Text('Certificate ID: ${b['id']}'),
        pw.Text('Issued: ${b['captured_at']}'),
        pw.Text('Location Coordinates: ${b['latitude']}, ${b['longitude']}'),
        pw.SizedBox(height: 8),
        pw.Text('Grade: ${b['grade']}', style: const pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Text('Sample Count: ${b['onion_count']} onions'),
        pw.Text('Fresh: ${b['fresh_pct']}%   Defective: ${b['defective_pct']}%'),
        for (final e in (b['details'] as Map).entries) pw.Text('${e.key}: ${e.value}%'),
        if (b['scale_weight_kg'] != null) pw.Text('Scale weight: ${b['scale_weight_kg']} kg'),
        if (b['rate_per_kg'] != null)
          pw.Text('Rate: ₹${b['rate_per_kg']}/kg (${b['rate_source']})  Payout/kg: ₹${((b['rate_per_kg'] as num) * (b['fresh_pct'] as num) / 100).toStringAsFixed(2)}'),
        pw.Text('Model Version: ${b['model_version']}   Rule Version: ${b['rule_version']}'),
        pw.SizedBox(height: 12),
        pw.Text('SHA-256 Device Hash: ${b['device_hash']}', style: const pw.TextStyle(fontSize: 8)),
        pw.Text(_synced ? 'Server-signed record exists. Verify by certificate ID.' : 'NOT YET SYNCED: not server-signed.',
            style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 12),
        pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: _qr, width: 100, height: 100),
      ]),
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'certificate_${b['id']}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final b = _b;
    final localOk = localHashValid(b);
    final img = widget.local['image_path'] as String?;
    final grade = '${b['grade']}';
    final isGradeA = grade.toUpperCase().contains('A');
    final isDesktop = GovBreakpoints.isTablet(context) || GovBreakpoints.isDesktop(context);

    final certCard = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (img != null && File(img).existsSync())
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: GovColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Image.file(File(img), height: 220, width: double.infinity, fit: BoxFit.cover),
            ),
          ),
        GovCard(
          title: 'Official Mandi Grading Certificate',
          subtitle: 'Issued under NAFED produce specifications & e-NAM standards',
          icon: Icons.verified,
          badge: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isGradeA ? GovColors.greenLight : GovColors.saffronLight,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: isGradeA ? GovColors.green : GovColors.saffron),
            ),
            child: Text(
              'GRADE $grade',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: isGradeA ? GovColors.greenDark : GovColors.saffronDark,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Grade $grade',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: isGradeA ? GovColors.greenDark : GovColors.navy),
              ),
              const SizedBox(height: 4),
              Text(
                '${b['onion_count']} sample onions · ${b['fresh_pct']}% fresh · ${b['defective_pct']}% defective',
                style: const TextStyle(fontSize: 13, color: GovColors.textSecondary),
              ),
              const Divider(height: 20),
              const Text('Defect Breakdown:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: GovColors.navy)),
              const SizedBox(height: 6),
              for (final e in (b['details'] as Map).entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${e.key}:', style: const TextStyle(fontSize: 12, color: GovColors.textSecondary)),
                      Text('${e.value}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: GovColors.navy)),
                    ],
                  ),
                ),
              if (b['rate_per_kg'] != null) ...[
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Estimated Rate:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: GovColors.textMuted)),
                    Text(
                      'Payout/kg: ₹${((b['rate_per_kg'] as num) * (b['fresh_pct'] as num) / 100).toStringAsFixed(2)} (${b['rate_source']})',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: GovColors.greenDark),
                    ),
                  ],
                ),
              ],
              const Divider(height: 20),
              Text('ID: ${b['id']}', style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: GovColors.textMuted)),
              const SizedBox(height: 2),
              Text('Captured: ${b['captured_at']}  @ ${b['latitude']}, ${b['longitude']}',
                  style: const TextStyle(fontSize: 11, color: GovColors.textMuted)),
              const SizedBox(height: 2),
              Text('Model ${b['model_version']} · rules v${b['rule_version']}',
                  style: const TextStyle(fontSize: 11, color: GovColors.textMuted)),
            ],
          ),
        ),
      ],
    );

    final securityCard = GovCard(
      title: 'Cryptographic Security & Verification',
      subtitle: 'Tamper-evident verification status',
      icon: Icons.security,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(localOk ? Icons.verified_outlined : Icons.dangerous, color: localOk ? GovColors.green : GovColors.error),
            title: Text(
              localOk ? 'Stored record matches its SHA-256' : 'STORED RECORD WAS ALTERED',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: localOk ? GovColors.navy : GovColors.error),
            ),
            subtitle: const Text(
              'Local check only. A rooted device could recompute the hash; the server signature after sync is the real proof.',
              style: TextStyle(fontSize: 11),
            ),
          ),
          const Divider(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_synced ? Icons.cloud_done : Icons.cloud_off, color: _synced ? GovColors.green : GovColors.textMuted),
            title: Text(
              _synced ? 'Synced and server-signed' : 'Not synced yet',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _synced ? GovColors.greenDark : GovColors.navy),
            ),
            subtitle: widget.local['last_error'] != null
                ? Text('Server said: ${widget.local['last_error']}', style: const TextStyle(fontSize: 11, color: GovColors.error))
                : null,
          ),
          if (_synced) ...[
            const SizedBox(height: 10),
            GovButton(label: 'Verify with server', busy: _busy, onPressed: _verify),
            if (_verifyText != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _verifyOk == null ? _verifyText! : (_verifyOk! ? '✔ $_verifyText' : '✘ $_verifyText'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: _verifyOk == false ? GovColors.error : GovColors.greenDark,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                QrImageView(data: _qr, size: 140),
                const SizedBox(height: 4),
                const Text(
                  'Scan QR at Mandi Terminal for Public Verification',
                  style: TextStyle(fontSize: 10.5, color: GovColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: GovColors.background,
      appBar: AppBar(
        title: const Text('Produce Certificate', style: TextStyle(fontWeight: FontWeight.w700, color: GovColors.navy)),
        actions: [
          IconButton(tooltip: 'Export Official PDF', icon: const Icon(Icons.picture_as_pdf, color: GovColors.navy), onPressed: _pdf),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(3),
          child: GovTricolorBar(height: 3),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: GovResponsiveContainer(
                      maxWidth: 1040,
                      child: isDesktop
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 3, child: certCard),
                                const SizedBox(width: 16),
                                Expanded(flex: 2, child: securityCard),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                certCard,
                                securityCard,
                              ],
                            ),
                    ),
                  ),
                  const GovPortalFooter(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
