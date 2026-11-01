import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tailscale/status.dart';
import '../tailscale/tailscale_controller.dart';
import 'pinger.dart';

/// "Test connection reliability": pings the device once a second, while it
/// stays selected or until Stop, and graphs the latency.
class PingSection extends StatefulWidget {
  const PingSection({super.key, required this.tailscale, required this.ip});

  final TailscaleController tailscale;
  final String ip;

  @override
  State<PingSection> createState() => _PingSectionState();
}

class _PingSectionState extends State<PingSection> {
  late final Pinger _pinger = Pinger(() => widget.tailscale.ping(widget.ip));

  /// Closing the window only hides it; pinging stops then, as with Stop.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () {
        if (_pinger.running) _pinger.stop();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _pinger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: _pinger,
        builder: (context, _) {
          final samples = _pinger.samples;
          final last = samples.lastOrNull;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Test connection reliability',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const Divider(height: 1),
              SizedBox(
                height: 150,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: CustomPaint(
                          painter: _LatencyGraph(
                            samples: samples,
                            maxSamples: _pinger.maxSamples,
                            line: theme.colorScheme.primary,
                            grid: theme.colorScheme.outlineVariant,
                            label: theme.colorScheme.onSurfaceVariant,
                            failure: theme.colorScheme.error,
                            labelStyle: theme.textTheme.labelSmall!,
                          ),
                        ),
                      ),
                    ),
                    if (!_pinger.running)
                      Center(
                        child: FilledButton.tonal(
                          onPressed: _pinger.start,
                          child: const Text('Ping device'),
                        ),
                      ),
                  ],
                ),
              ),
              if (_pinger.running || last != null) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          switch (last) {
                            null => 'Pinging…',
                            PingResult(ok: false, :final error) => error,
                            final r =>
                              '${r.latency.inMilliseconds} ms · ${r.path}',
                          },
                          style: TextStyle(
                            color: last?.ok == false
                                ? theme.colorScheme.error
                                : null,
                          ),
                        ),
                      ),
                      if (_pinger.running)
                        TextButton(
                          onPressed: _pinger.stop,
                          child: const Text('Stop'),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Latency over time, newest on the right. The scale starts at 600 ms and
/// grows in steps of 300 ms to fit the slowest reply. A failed ping shows as
/// a gap in the line and a dot at the bottom.
class _LatencyGraph extends CustomPainter {
  _LatencyGraph({
    required this.samples,
    required this.maxSamples,
    required this.line,
    required this.grid,
    required this.label,
    required this.failure,
    required this.labelStyle,
  });

  final List<PingResult> samples;
  final int maxSamples;
  final Color line;
  final Color grid;
  final Color label;
  final Color failure;
  final TextStyle labelStyle;

  static const _step = 300;
  static const _labelWidth = 48.0;

  @override
  void paint(Canvas canvas, Size size) {
    final slowest = samples
        .where((s) => s.ok)
        .fold(0, (m, s) => math.max(m, s.latency.inMilliseconds));
    final top = math.max(2 * _step, (slowest / _step).ceil() * _step);
    final plot = Size(size.width - _labelWidth, size.height);

    double y(num ms) => plot.height * (1 - ms / top);

    // Grid lines and their labels: 0, the middle and the top of the scale.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final ms in [0, top ~/ 2, top]) {
      canvas.drawLine(Offset(0, y(ms)), Offset(plot.width, y(ms)), gridPaint);
      final text = TextPainter(
        text: TextSpan(
          text: '$ms ms',
          style: labelStyle.copyWith(color: label),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(
        canvas,
        Offset(
          plot.width + 6,
          (y(ms) - text.height / 2).clamp(0, size.height - text.height),
        ),
      );
    }

    if (samples.isEmpty) return;
    final dx = plot.width / math.max(1, maxSamples - 1);
    double x(int i) => plot.width - (samples.length - 1 - i) * dx;

    final linePaint = Paint()
      ..color = line
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    var drawing = false;
    for (final (i, s) in samples.indexed) {
      if (!s.ok) {
        drawing = false;
        canvas.drawCircle(Offset(x(i), y(0)), 3, Paint()..color = failure);
        continue;
      }
      final point = Offset(x(i), y(s.latency.inMilliseconds));
      if (drawing) {
        path.lineTo(point.dx, point.dy);
      } else {
        path.moveTo(point.dx, point.dy);
        drawing = true;
      }
    }
    canvas.drawPath(path, linePaint);

    final last = samples.last;
    if (last.ok) {
      canvas.drawCircle(
        Offset(x(samples.length - 1), y(last.latency.inMilliseconds)),
        3.5,
        Paint()..color = line,
      );
    }
  }

  @override
  bool shouldRepaint(_LatencyGraph old) => true;
}
