import 'package:flutter/material.dart';

import 'access_controller.dart';

const operatorCommand = r'sudo tailscale set --operator=$USER';

class AccessPage extends StatelessWidget {
  const AccessPage({super.key, required this.controller});

  final AccessController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => switch (controller.status) {
                AccessStatus.checking => const _Checking(),
                AccessStatus.granted => const _Message(
                  icon: Icons.check_circle_outline,
                  title: 'Access granted',
                  body: [Text('This user can manage Tailscale.')],
                ),
                AccessStatus.denied => _Message(
                  icon: Icons.lock_outline,
                  title: 'Tailscale needs operator access',
                  body: [
                    const Text(
                      'Run this command in a terminal, then press Recheck:',
                    ),
                    const SizedBox(height: 12),
                    const _Command(operatorCommand),
                  ],
                  onRecheck: controller.check,
                ),
                AccessStatus.error => _Message(
                  icon: Icons.error_outline,
                  title: "Can't reach tailscaled",
                  body: [SelectableText(controller.error ?? '')],
                  onRecheck: controller.check,
                ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Checking extends StatelessWidget {
  const _Checking();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Checking access to tailscaled…'),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.onRecheck,
  });

  final IconData icon;
  final String title;
  final List<Widget> body;
  final VoidCallback? onRecheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        ...body,
        if (onRecheck != null) ...[
          const SizedBox(height: 24),
          FilledButton(onPressed: onRecheck, child: const Text('Recheck')),
        ],
      ],
    );
  }
}

class _Command extends StatelessWidget {
  const _Command(this.command);

  final String command;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        command,
        style: const TextStyle(fontFamily: 'monospace'),
      ),
    );
  }
}
