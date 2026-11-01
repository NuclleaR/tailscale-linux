import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../platform/file_picker.dart';
import '../tailscale/local_api.dart';
import '../tailscale/tailscale_controller.dart';

/// Sends files to a device with Taildrop: picked with the desktop's file
/// dialog or dropped on the section.
class TaildropSection extends StatefulWidget {
  const TaildropSection({
    super.key,
    required this.tailscale,
    required this.nodeId,
  });

  final TailscaleController tailscale;

  /// The device's stable ID.
  final String nodeId;

  @override
  State<TaildropSection> createState() => _TaildropSectionState();
}

class _TaildropSectionState extends State<TaildropSection> {
  bool _hovering = false;
  bool _sending = false;

  /// What is being sent, or what happened last.
  String? _message;
  bool _failed = false;

  /// 0 to 1 while sending.
  double? _progress;

  Future<void> _pick() async {
    final List<String> paths;
    try {
      paths = await pickFiles(title: 'Send with Taildrop');
    } on FilePickerUnavailable catch (e) {
      _show('$e', failed: true);
      return;
    }
    await _send(paths);
  }

  Future<void> _send(List<String> paths) async {
    if (_sending || paths.isEmpty) return;
    setState(() => _sending = true);
    try {
      for (final (i, path) in paths.indexed) {
        final file = File(path);
        final name = file.uri.pathSegments.last;
        final count = paths.length == 1 ? '' : ' (${i + 1} of ${paths.length})';
        _show('Sending $name$count…', progress: 0);
        try {
          await widget.tailscale.sendFile(
            widget.nodeId,
            file,
            onProgress: (sent, total) => _show(
              'Sending $name$count…',
              progress: total == 0 ? 1 : sent / total,
            ),
          );
        } on Exception catch (e) {
          final reason = e is LocalApiException ? e.message : '$e';
          _show('Could not send $name: $reason', failed: true);
          return;
        }
      }
      _show(
        paths.length == 1
            ? 'Sent ${File(paths.single).uri.pathSegments.last}'
            : 'Sent ${paths.length} files',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _show(String message, {bool failed = false, double? progress}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _failed = failed;
      _progress = progress;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DropTarget(
      acceptedKinds: const {DropItemKind.file},
      enabled: !_sending,
      onEnter: (_) => setState(() => _hovering = true),
      onLeave: () => setState(() => _hovering = false),
      onDrop: (details) {
        setState(() => _hovering = false);
        _send([
          for (final item in details.items.whereType<DropFileItem>())
            ?item.localPath,
        ]);
      },
      child: CustomPaint(
        painter: _DashedBorder(
          color: _hovering ? colors.primary : colors.outline,
          fill: _hovering ? colors.primary.withValues(alpha: 0.08) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.send_and_archive_outlined, color: colors.primary),
              const SizedBox(height: 8),
              const Text(
                'Select or drag and drop a file to send it to this device…',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _sending ? null : _pick,
                child: const Text('Select a File…'),
              ),
              if (_message case final message?) ...[
                const SizedBox(height: 12),
                if (_sending && _progress != null)
                  LinearProgressIndicator(value: _progress),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _failed ? colors.error : null),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A dashed rounded rectangle around the drop zone.
class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, this.fill});

  final Color color;
  final Color? fill;

  static const _radius = 12.0;
  static const _dash = 6.0;
  static const _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(_radius),
    );
    if (fill case final fill?) {
      canvas.drawRRect(rect, Paint()..color = fill);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += _dash + _gap) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + _dash, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.fill != fill;
}
