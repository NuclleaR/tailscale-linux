import 'package:flutter/material.dart';

import '../platform/autostart.dart';
import '../tailscale/tailscale_controller.dart';
import 'about_page.dart';
import 'accounts_page.dart';
import 'app_settings.dart';
import 'settings_page.dart';

enum SettingsTab {
  accounts('Accounts', Icons.account_circle_outlined),
  settings('Settings', Icons.tune),
  about('About', Icons.info_outline);

  const SettingsTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The settings window: Accounts, Settings and About, switched by a row of
/// tabs at the top, as in the macOS app.
class SettingsWindow extends StatefulWidget {
  const SettingsWindow({
    super.key,
    required this.tailscale,
    required this.appSettings,
    required this.autostart,
    required this.onBack,
  });

  final TailscaleController tailscale;
  final AppSettings appSettings;
  final Autostart autostart;

  /// Goes back to the main window.
  final VoidCallback onBack;

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow> {
  SettingsTab _tab = SettingsTab.accounts;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Stack(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final tab in SettingsTab.values)
                      _TabButton(
                        tab: tab,
                        selected: tab == _tab,
                        onPressed: () => setState(() => _tab = tab),
                      ),
                  ],
                ),
                Positioned(
                  left: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: widget.onBack,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: switch (_tab) {
              SettingsTab.accounts => AccountsPage(tailscale: widget.tailscale),
              SettingsTab.settings => SettingsPage(
                tailscale: widget.tailscale,
                appSettings: widget.appSettings,
                autostart: widget.autostart,
              ),
              SettingsTab.about => AboutPage(tailscale: widget.tailscale),
            },
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.onPressed,
  });

  final SettingsTab tab;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: selected ? colors.primary : colors.onSurfaceVariant,
          backgroundColor: selected
              ? colors.primary.withValues(alpha: 0.12)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tab.icon, size: 28),
            const SizedBox(height: 4),
            Text(tab.label),
          ],
        ),
      ),
    );
  }
}
