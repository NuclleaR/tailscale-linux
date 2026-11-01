import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/desktop.dart';
import '../tailscale/status.dart';
import '../tailscale/tailscale_controller.dart';

const _privacyPolicyUrl = 'https://tailscale.com/privacy-policy';
const _termsUrl = 'https://tailscale.com/terms';
const _issuesUrl = 'https://github.com/NuclleaR/tailscale-linux/issues';

/// The About pane: versions and links.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key, required this.tailscale});

  final TailscaleController tailscale;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final Future<String> _appVersion = _readAppVersion();
  late final Future<ClientVersion> _update = widget.tailscale.checkForUpdate();

  /// Flutter writes the pubspec version into the bundle's `version.json`.
  static Future<String> _readAppVersion() async {
    final json = jsonDecode(await rootBundle.loadString('version.json'));
    return json is Map<String, Object?> ? json['version'] as String? ?? '' : '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _AppIcon(size: 128),
              const SizedBox(width: 32),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tailscale for Linux',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FutureBuilder(
                    future: _appVersion,
                    builder: (context, snapshot) =>
                        Text('Version ${snapshot.data ?? '…'}'),
                  ),
                  ListenableBuilder(
                    listenable: widget.tailscale,
                    builder: (context, _) =>
                        Text(switch (widget.tailscale.status?.version) {
                          null || '' => 'tailscaled is not running',
                          final v => 'tailscaled ${v.split('-').first}',
                        }),
                  ),
                  FutureBuilder(
                    future: _update,
                    builder: (context, snapshot) => switch (snapshot.data) {
                      ClientVersion(
                        updateAvailable: true,
                        :final latestVersion,
                      ) =>
                        Text(
                          'Update available: $latestVersion',
                          style: TextStyle(color: theme.colorScheme.primary),
                        ),
                      _ => const SizedBox.shrink(),
                    },
                  ),
                  const SizedBox(height: 12),
                  const _Link('Privacy Policy', _privacyPolicyUrl),
                  const _Link('Terms of Service', _termsUrl),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => openUrl(_issuesUrl),
                    child: const Text('Report an Issue…'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            'An unofficial client, not affiliated with Tailscale Inc.\n'
            'Tailscale is a trademark of Tailscale Inc.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.url);

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () => openUrl(url),
      child: Text(label),
    );
  }
}

/// The 3×3 dots of the tray icon on a white tile.
class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.size});

  final double size;

  /// The dots drawn solid, as (row, column); the rest are faint.
  static const _solid = {(1, 0), (1, 1), (1, 2), (2, 1)};

  @override
  Widget build(BuildContext context) {
    final dot = size * 0.16;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var row = 0; row < 3; row++)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var column = 0; column < 3; column++)
                  Container(
                    width: dot,
                    height: dot,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _solid.contains((row, column))
                          ? const Color(0xFF242424)
                          : const Color(0xFFC4C4C4),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
