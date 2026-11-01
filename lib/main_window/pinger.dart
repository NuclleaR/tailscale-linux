import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tailscale/status.dart';

/// Pings one device once per [interval] until stopped, keeping the last
/// [maxSamples] results for the graph.
class Pinger extends ChangeNotifier {
  Pinger(
    this._ping, {
    this.interval = const Duration(seconds: 1),
    this.maxSamples = 60,
  });

  final Future<PingResult> Function() _ping;
  final Duration interval;
  final int maxSamples;

  /// Oldest first. A ping that failed or timed out has a non-empty error.
  List<PingResult> get samples => List.unmodifiable(_samples);
  final List<PingResult> _samples = [];

  bool get running => _running;
  bool _running = false;

  /// Bumped on every start and stop, so a loop from an earlier run ends.
  int _run = 0;
  bool _disposed = false;

  /// Starts a new series, dropping the previous one.
  void start() {
    _samples.clear();
    _running = true;
    notifyListeners();
    _loop(++_run);
  }

  void stop() {
    _run++;
    _running = false;
    notifyListeners();
  }

  Future<void> _loop(int run) async {
    bool current() => run == _run && !_disposed;
    while (current()) {
      final watch = Stopwatch()..start();
      PingResult result;
      try {
        result = await _ping();
      } on Exception catch (e) {
        result = PingResult(error: e is TimeoutException ? 'no reply' : '$e');
      }
      if (!current()) return;
      _samples.add(result);
      if (_samples.length > maxSamples) _samples.removeAt(0);
      notifyListeners();
      final wait = interval - watch.elapsed;
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
