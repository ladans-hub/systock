import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';

class AsyncLoadingPane extends StatelessWidget {
  const AsyncLoadingPane({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox.square(
      dimension: 24,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

class AsyncErrorPane extends StatelessWidget {
  const AsyncErrorPane({required this.onRetry, this.message, super.key});
  final VoidCallback onRetry;
  final String? message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 42,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 14),
          Text(
            message ?? 'Não foi possível carregar os dados.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const LocalizedText('Os dados locais continuam seguros.'),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const LocalizedText('Tentar novamente'),
          ),
        ],
      ),
    ),
  );
}

class EmptyStatePane extends StatelessWidget {
  const EmptyStatePane({
    required this.title,
    required this.message,
    this.action,
    super.key,
  });
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 44),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    ),
  );
}
