import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/app/router/app_router.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/sync/background_sync_coordinator.dart';

class SessionLifecycle extends ConsumerStatefulWidget {
  const SessionLifecycle({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<SessionLifecycle> createState() => _SessionLifecycleState();
}

class _SessionLifecycleState extends ConsumerState<SessionLifecycle>
    with WidgetsBindingObserver {
  DateTime? backgroundedAt;
  Timer? syncTimer;
  static const timeout = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    syncTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      unawaited(
        BackgroundSyncCoordinator(
          ref.read(databaseProvider),
        ).synchronizeIfAuthorized(),
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(
        BackgroundSyncCoordinator(
          ref.read(databaseProvider),
        ).synchronizeIfAuthorized(),
      );
      final since = backgroundedAt;
      backgroundedAt = null;
      if (since != null && DateTime.now().difference(since) >= timeout) {
        appRouter.go('/');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    syncTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
