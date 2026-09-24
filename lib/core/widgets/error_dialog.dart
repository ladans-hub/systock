import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/l10n/localized_text.dart';

enum AppAlertKind { success, info, error }

Future<void> showAppError(
  BuildContext context,
  String message, {
  Object? details,
}) => showAppAlert(
  context,
  details == null ? message : '$message\n\n$details',
  title: 'Operação não concluída',
  kind: AppAlertKind.error,
  dismissible: false,
);

Future<void> showAppFailure(BuildContext context, AppFailure failure) =>
    showAppError(context, failure.userMessage, details: failure.cause);

Future<void> showAppInfo(
  BuildContext context,
  String message, {
  String title = 'Informação',
}) => showAppAlert(context, message, title: title, kind: AppAlertKind.info);

Future<void> showAppAlert(
  BuildContext context,
  String message, {
  String? title,
  AppAlertKind kind = AppAlertKind.success,
  IconData? icon,
  bool dismissible = false,
}) async {
  if (!context.mounted) return;
  final resolvedTitle =
      title ??
      switch (kind) {
        AppAlertKind.success => 'Operação concluída',
        AppAlertKind.info => 'Informação',
        AppAlertKind.error => 'Operação não concluída',
      };
  await showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: dismissible,
    barrierLabel: 'Fechar',
    barrierColor: Colors.black.withValues(alpha: .48),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => _PremiumFeedbackDialog(
      kind: kind,
      title: resolvedTitle.localized(context),
      message: message.localized(context),
      icon: icon,
    ),
    transitionBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: .92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _PremiumFeedbackDialog extends StatefulWidget {
  const _PremiumFeedbackDialog({
    required this.kind,
    required this.title,
    required this.message,
    this.icon,
  });

  final AppAlertKind kind;
  final String title, message;
  final IconData? icon;

  @override
  State<_PremiumFeedbackDialog> createState() => _PremiumFeedbackDialogState();
}

class _PremiumFeedbackDialogState extends State<_PremiumFeedbackDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 680),
    reverseDuration: const Duration(milliseconds: 360),
  );

  @override
  void initState() {
    super.initState();
    controller.forward();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> close() async {
    await controller.reverse();
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final accent = switch (widget.kind) {
      AppAlertKind.success => const Color(0xFF159F68),
      AppAlertKind.info => scheme.secondary,
      AppAlertKind.error => scheme.error,
    };
    final icon =
        widget.icon ??
        switch (widget.kind) {
          AppAlertKind.success => Icons.check_rounded,
          AppAlertKind.info => Icons.info_outline_rounded,
          AppAlertKind.error => Icons.close_rounded,
        };
    final panel = dark ? const Color(0xFF121F29) : Colors.white;
    final text = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 380,
          maxHeight: MediaQuery.sizeOf(context).height * .82,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: panel,
            gradient: LinearGradient(
              colors: dark
                  ? [
                      Color.alphaBlend(
                        scheme.primary.withValues(alpha: .18),
                        panel,
                      ),
                      Color.alphaBlend(
                        scheme.secondary.withValues(alpha: .14),
                        const Color(0xFF09131B),
                      ),
                    ]
                  : [
                      Color.alphaBlend(
                        scheme.primary.withValues(alpha: .07),
                        Colors.white,
                      ),
                      Color.alphaBlend(
                        scheme.secondary.withValues(alpha: .06),
                        Colors.white,
                      ),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.primary.withValues(alpha: dark ? .48 : .30),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? .42 : .18),
                blurRadius: 38,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 30, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: controller,
                  builder: (_, child) => Transform.rotate(
                    angle: math.sin(controller.value * math.pi * 2.4) * .055,
                    child: Transform.scale(
                      scale: Curves.elasticOut.transform(
                        controller.value.clamp(0, 1),
                      ),
                      child: child,
                    ),
                  ),
                  child: _FeedbackIcon(icon: icon, accent: accent),
                ),
                const SizedBox(height: 17),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: text,
                    fontSize: 21,
                    height: 1.12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.7,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: muted,
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 17),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onPressed: close,
                    child: const LocalizedText('Fechar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackIcon extends StatelessWidget {
  const _FeedbackIcon({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    width: 77,
    height: 77,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: accent,
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: .28),
          blurRadius: 16,
          spreadRadius: 5,
        ),
        BoxShadow(
          color: accent.withValues(alpha: .18),
          blurRadius: 0,
          spreadRadius: 9,
        ),
      ],
      border: Border.all(color: Colors.white.withValues(alpha: .18), width: 2),
    ),
    child: Icon(icon, color: Colors.white, size: 49),
  );
}
