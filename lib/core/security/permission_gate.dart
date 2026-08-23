import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/security/authorization_service.dart';

final activePermissionsProvider = FutureProvider<Set<String>>((ref) async {
  final db = ref.watch(databaseProvider);
  final user =
      await (db.select(db.users)
            ..where((u) => u.active.equals(true))
            ..limit(1))
          .getSingleOrNull();
  if (user == null) return const {};
  return AuthorizationService(db).permissionsFor(user.id);
});

class PermissionGate extends ConsumerWidget {
  const PermissionGate({
    required this.permission,
    required this.child,
    super.key,
  });
  final String permission;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(activePermissionsProvider)
      .when(
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, _) => _Denied(onBack: () => context.go('/dashboard')),
        data: (permissions) => permissions.contains(permission)
            ? child
            : _Denied(onBack: () => context.go('/dashboard')),
      );
}

class PermissionBuilder extends ConsumerWidget {
  const PermissionBuilder({
    required this.permission,
    required this.builder,
    this.fallback = const SizedBox.shrink(),
    super.key,
  });
  final String permission;
  final Widget Function(BuildContext context) builder;
  final Widget fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(activePermissionsProvider).valueOrNull;
    return allowed?.contains(permission) == true ? builder(context) : fallback;
  }
}

class _Denied extends StatelessWidget {
  const _Denied({required this.onBack});
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('Acesso restrito')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            LocalizedText(
              'Não possui permissão para esta operação.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onBack,
              child: const LocalizedText('Voltar ao início'),
            ),
          ],
        ),
      ),
    ),
  );
}
