import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/security/authorization_service.dart';
import 'package:systock/core/security/pin_hasher.dart';
import 'package:systock/core/security/session_state.dart';
import 'package:systock/core/security/pin_recovery_service.dart';
import 'package:systock/core/errors/result.dart';

class StartupPage extends ConsumerStatefulWidget {
  const StartupPage({super.key});
  @override
  ConsumerState<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends ConsumerState<StartupPage> {
  User? user;
  final pin = TextEditingController();
  String? error;
  bool checking = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_start);
  }

  Future<void> _start() async {
    final db = ref.read(databaseProvider);
    final company = await db.select(db.companies).getSingleOrNull();
    if (!mounted) return;
    if (company == null) {
      context.go('/onboarding');
      return;
    }
    final active =
        await (db.select(db.users)
              ..where((u) => u.active.equals(true))
              ..limit(1))
            .getSingle();
    if (!mounted) return;
    final explicitlyLocked = ref.read(sessionLockedProvider);
    if (!explicitlyLocked &&
        (active.pinHash == null || active.pinSalt == null)) {
      context.go('/dashboard');
    } else {
      setState(() {
        user = active;
        checking = false;
      });
    }
  }

  Future<void> unlock() async {
    final current = user!;
    if (current.pinHash == null || current.pinSalt == null) {
      ref.read(sessionLockedProvider.notifier).state = false;
      if (mounted) context.go('/dashboard');
      return;
    }
    final valid = await PinHasher().verify(
      pin.text,
      PinDigest(current.pinHash!, current.pinSalt!),
    );
    if (!mounted) return;
    if (valid) {
      ref.read(sessionLockedProvider.notifier).state = false;
      context.go('/dashboard');
    } else {
      setState(() => error = 'PIN incorreto.');
    }
  }

  Future<void> biometric() async {
    final ok = await SystemBiometricGate().authenticate(
      'Desbloquear o Systock',
    );
    if (ok && mounted) {
      ref.read(sessionLockedProvider.notifier).state = false;
      context.go('/dashboard');
    } else if (mounted) {
      setState(
        () => error =
            'Não foi possível confirmar a biometria. Use o PIN ou verifique as definições do dispositivo.',
      );
    }
  }

  Future<void> recoverPin() async {
    final first = TextEditingController();
    final confirmation = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const LocalizedText('Recuperar acesso'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LocalizedText(
                'Por segurança, será necessário confirmar a sua identidade com a biometria deste dispositivo.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: first,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Novo PIN'.localized(context),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmation,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Confirmar novo PIN'.localized(context),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const LocalizedText('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialog, true),
            icon: const Icon(Icons.fingerprint),
            label: const LocalizedText('Confirmar identidade'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    if (first.text != confirmation.text) {
      setState(() => error = 'Os PINs informados não são iguais.');
      return;
    }
    final result = await PinRecoveryService(
      ref.read(databaseProvider),
    ).resetWithBiometrics(user: user!, newPin: first.text);
    if (!mounted) return;
    switch (result) {
      case Success():
        ref.read(sessionLockedProvider.notifier).state = false;
        context.go('/dashboard');
      case Failure(:final error):
        setState(() => this.error = error.userMessage);
    }
  }

  @override
  void dispose() {
    pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 16),
                  LocalizedText(
                    'Olá, ${user!.name}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 20),
                  if (user!.pinHash != null)
                    TextField(
                      controller: pin,
                      autofocus: true,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      onSubmitted: (_) => unlock(),
                      decoration: InputDecoration(
                        labelText: 'PIN'.localized(context),
                        errorText: error,
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: unlock,
                    child: const LocalizedText('Entrar'),
                  ),
                  if (user!.pinHash != null)
                    TextButton.icon(
                      onPressed: biometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const LocalizedText('Usar biometria'),
                    ),
                  if (user!.pinHash != null)
                    TextButton(
                      onPressed: recoverPin,
                      child: const LocalizedText('Esqueci o PIN'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
