import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tailscale_linux/main_window/pinger.dart';
import 'package:tailscale_linux/tailscale/status.dart';

PingResult ms(int n) => PingResult(
  latency: Duration(milliseconds: n),
  endpoint: '1.2.3.4:41641',
);

void main() {
  test('keeps the last maxSamples results, failures included', () async {
    final replies = <FutureOr<PingResult> Function()>[
      () => ms(10),
      () => throw TimeoutException('no reply'),
      () => const PingResult(error: "peer's node key has expired"),
      () => ms(40),
    ];
    var calls = 0;
    late Pinger pinger;
    pinger = Pinger(
      () async {
        final reply = replies[calls++];
        if (calls == replies.length) pinger.stop();
        return reply();
      },
      interval: Duration.zero,
      maxSamples: 2,
    );
    addTearDown(pinger.dispose);

    pinger.start();
    expect(pinger.running, isTrue);
    await pumpEventQueue();

    expect(calls, 4);
    expect(pinger.running, isFalse);
    // The 10 ms reply fell off the end; the reply that arrived after stop
    // was dropped.
    expect(
      pinger.samples.map((s) => s.ok ? s.latency.inMilliseconds : s.error),
      ['no reply', "peer's node key has expired"],
    );
  });

  test('start drops the previous series', () async {
    var n = 0;
    late Pinger pinger;
    pinger = Pinger(() async {
      n++;
      pinger.stop();
      return ms(n);
    }, interval: Duration.zero);
    addTearDown(pinger.dispose);

    pinger.start();
    await pumpEventQueue();
    pinger.start();
    await pumpEventQueue();

    expect(n, 2);
    expect(pinger.samples, isEmpty);
  });

  test('a ping result tells the path', () {
    expect(
      PingResult.fromJson({
        'LatencySeconds': 0.237055598,
        'Endpoint': '15.235.84.242:41641',
      }),
      isA<PingResult>()
          .having((r) => r.latency.inMilliseconds, 'ms', 237)
          .having((r) => r.path, 'path', 'direct'),
    );
    expect(
      PingResult.fromJson({'DERPRegionCode': 'waw', 'LatencySeconds': 0.1})
          .path,
      'relay: waw',
    );
    expect(
      PingResult.fromJson({'Err': "peer's node key has expired"}).ok,
      isFalse,
    );
  });
}
