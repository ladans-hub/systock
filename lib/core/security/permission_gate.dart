import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/security/authorization_service.dart';
import 'package:systock/core/security/session_state.dart';

final activePermissionsProvider = FutureProvider<Set<String>>((ref) async {
  final db = ref.watch(databaseProvider);
  final inMemoryId = ref.watch(sessionUserIdProvider);
  final user = inMemoryId == null
      ? await currentSessionUser(db)
      : await (db.select(
          db.users,
        )..where((u) => u.id.equals(inMemoryId))).getSingleOrNull();
  if (user == null || !user.active) return const {};
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

class AnyPermissionGate extends ConsumerWidget {
  const AnyPermissionGate({
    required this.permissions,
    required this.child,
    super.key,
  });
  final List<String> permissions;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(activePermissionsProvider)
      .when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) => _Denied(onBack: () => context.go('/dashboard')),
        data: (value) => permissions.any(value.contains)
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

/// Prevents a POS-only profile from opening administrative routes directly.
class SessionAccessGate extends ConsumerWidget {
  const SessionAccessGate({
    required this.location,
    required this.child,
    super.key,
  });

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(activePermissionsProvider)
      .when(
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, _) => _Denied(onBack: () => context.go('/')),
        data: (permissions) {
          final sellerOnly =
              permissions.length == 1 && permissions.contains('sales.create');
          return sellerOnly && location != '/pos'
              ? _Denied(onBack: () => context.go('/pos'))
              : child;
        },
      );
}

class _Denied extends StatelessWidget {
  const _Denied({required this.onBack});
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppBarTitle('Acesso restrito')),
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
