import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/api_client.dart';
import '../domain/certificate_builder.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

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
        pw.Text('Onion Quality Certificate', style: const pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        pw.Text('Certificate ID: ${b['id']}'),
        pw.Text('Issued: ${b['captured_at']}'),
        pw.Text('Location: ${b['latitude']}, ${b['longitude']}'),
        pw.SizedBox(height: 8),
        pw.Text('Grade: ${b['grade']}', style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.Text('Onions detected: ${b['onion_count']}'),
        pw.Text('Fresh: ${b['fresh_pct']}%   Defective: ${b['defective_pct']}%'),
        for (final e in (b['details'] as Map).entries) pw.Text('${e.key}: ${e.value}%'),
        if (b['scale_weight_kg'] != null) pw.Text('Scale weight: ${b['scale_weight_kg']} kg'),
        if (b['rate_per_kg'] != null)
          pw.Text('Rate: ₹${b['rate_per_kg']}/kg (${b['rate_source']})  Payout/kg: ₹${((b['rate_per_kg'] as num) * (b['fresh_pct'] as num) / 100).toStringAsFixed(2)}'),
        pw.Text('Model: ${b['model_version']}   Rule version: ${b['rule_version']}'),
        pw.SizedBox(height: 12),
        pw.Text('SHA-256: ${b['device_hash']}', style: const pw.TextStyle(fontSize: 8)),
        pw.Text(_synced ? 'Server-signed record exists. Verify by certificate ID.' : 'NOT YET SYNCED: not server-signed.',
            style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 12),
        pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: _qr, width: 110, height: 110),
      ]),
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'certificate_${b['id']}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final b = _b;
    final localOk = localHashValid(b);
    final img = widget.local['image_path'] as String?;
    return Scaffold(
      appBar: AppBar(title: const Text('Certificate'), actions: [
        IconButton(tooltip: 'Export PDF', icon: const Icon(Icons.picture_as_pdf), onPressed: _pdf),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (img != null && File(img).existsSync()) ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(img), height: 200, fit: BoxFit.cover)),
        const SizedBox(height: 12),
        Text('Grade ${b['grade']}', style: Theme.of(context).textTheme.headlineMedium),
        Text('${b['onion_count']} onions · ${b['fresh_pct']}% fresh · ${b['defective_pct']}% defective'),
        for (final e in (b['details'] as Map).entries) Text('${e.key}: ${e.value}%'),
        if (b['rate_per_kg'] != null)
          Text('Payout/kg: ₹${((b['rate_per_kg'] as num) * (b['fresh_pct'] as num) / 100).toStringAsFixed(2)} (${b['rate_source']})'),
        const Divider(height: 32),
        Text('ID: ${b['id']}', style: const TextStyle(fontSize: 12)),
        Text('Captured: ${b['captured_at']}  @ ${b['latitude']}, ${b['longitude']}', style: const TextStyle(fontSize: 12)),
        Text('Model ${b['model_version']} · rules v${b['rule_version']}', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        ListTile(
          leading: Icon(localOk ? Icons.verified_outlined : Icons.dangerous, color: localOk ? null : Colors.red),
          title: Text(localOk ? 'Stored record matches its SHA-256' : 'STORED RECORD WAS ALTERED'),
          subtitle: const Text('Local check only. A rooted device could recompute the hash; the server signature after sync is the real proof.'),
        ),
        ListTile(
          leading: Icon(_synced ? Icons.cloud_done : Icons.cloud_off),
          title: Text(_synced ? 'Synced and server-signed' : 'Not synced yet'),
          subtitle: widget.local['last_error'] != null ? Text('Server said: ${widget.local['last_error']}') : null,
        ),
        if (_synced) ...[
          BusyButton(label: 'Verify with server', busy: _busy, onPressed: _verify),
          if (_verifyText != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_verifyOk == null ? _verifyText! : (_verifyOk! ? '✔ $_verifyText' : '✘ $_verifyText'),
                  style: TextStyle(color: _verifyOk == false ? Colors.red : null)),
            ),
        ],
        const SizedBox(height: 16),
        Center(child: QrImageView(data: _qr, size: 160)),
      ]),
    );
  }
}
