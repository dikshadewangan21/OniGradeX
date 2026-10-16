import 'package:flutter/material.dart';

import '../ml/postprocess.dart';

class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ]),
        ),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) =>
      Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(message, textAlign: TextAlign.center)));
}

void toast(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

/// Loads async data once, shows loading / error+retry / content.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, VoidCallback reload) builder;
  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  late Future<T> _f = widget.load();
  void _reload() => setState(() => _f = widget.load());
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _f,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (s.hasError) return ErrorView(message: s.error.toString(), onRetry: _reload);
          return widget.builder(c, s.data as T, _reload);
        },
      );
}

/// Draws detection boxes over the captured image (the app's visual proof; not a Grad-CAM heatmap).
class DetectionBoxPainter extends CustomPainter {
  DetectionBoxPainter(this.detections, this.defectIds);
  final List<Detection> detections;
  final Set<int> defectIds;
  @override
  void paint(Canvas canvas, Size size) {
    for (final d in detections) {
      final b = d.box;
      if (b == null) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = defectIds.contains(d.classId) ? Colors.red : Colors.green;
      canvas.drawRect(Rect.fromLTRB(b[0] * size.width, b[1] * size.height, b[2] * size.width, b[3] * size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant DetectionBoxPainter old) => old.detections != detections;
}

class LanguageSwitcherAction extends StatelessWidget {
  const LanguageSwitcherAction({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.language),
      tooltip: 'Language / भाषा',
      onSelected: (code) {
        try {
          (context as dynamic).read<dynamic>().setLocale(Locale(code));
        } catch (_) {}
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'en', child: Text('English')),
        PopupMenuItem(value: 'hi', child: Text('हिंदी (Hindi)')),
        PopupMenuItem(value: 'mr', child: Text('मराठी (Marathi)')),
      ],
    );
  }
}
