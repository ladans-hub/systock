import 'package:flutter/material.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/l10n/localized_text.dart';

Future<void> showAppError(
  BuildContext context,
  String message, {
  Object? details,
}) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel_outlined, size: 56, color: Colors.red.shade700),
            const SizedBox(height: 12),
            const LocalizedText('Erro'),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            '${message.localized(dialogContext)}'
            '${details == null ? "" : "\n\n$details"}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const LocalizedText('Fechar'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showAppFailure(BuildContext context, AppFailure failure) =>
    showAppError(context, failure.userMessage, details: failure.cause);
