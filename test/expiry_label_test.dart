import 'package:flutter_test/flutter_test.dart';
import 'package:tailscale_linux/settings/widgets.dart';

void main() {
  final now = DateTime.utc(2026, 11, 4, 12);

  test('the largest whole unit left, like the macOS app', () {
    String label(Duration left) => expiryLabel(now.add(left), now);

    expect(label(const Duration(days: 90, hours: 5)), 'Expires in 90 days');
    expect(label(const Duration(days: 1)), 'Expires in 1 day');
    expect(
      label(const Duration(hours: 18, minutes: 40)),
      'Expires in 18 hours',
    );
    expect(label(const Duration(hours: 1)), 'Expires in 1 hour');
    expect(label(const Duration(minutes: 5)), 'Expires in 5 minutes');
    expect(label(const Duration(seconds: 20)), 'Expires in 1 minute');
  });

  test('a key past its expiry has expired', () {
    expect(expiryLabel(now, now), 'Expired');
    expect(expiryLabel(now.subtract(const Duration(hours: 3)), now), 'Expired');
  });

  test('how long ago a key expired, in the largest whole unit', () {
    String? label(Duration ago) => expiredLabel(now.subtract(ago), now);

    expect(label(const Duration(days: 1, hours: 23)), 'Expired 1 day ago');
    expect(label(const Duration(days: 3)), 'Expired 3 days ago');
    expect(label(const Duration(hours: 5, minutes: 59)), 'Expired 5 hours ago');
    expect(label(const Duration(minutes: 1)), 'Expired 1 minute ago');
    expect(label(Duration.zero), 'Expired 1 minute ago');
  });

  test('a key that has not expired has no expired label', () {
    expect(expiredLabel(now.add(const Duration(seconds: 1)), now), isNull);
  });
}
