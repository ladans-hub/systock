import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show OrderingTerm;
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
import 'package:systock/core/security/permission_gate.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';
import 'package:systock/core/widgets/secure_text_field.dart';
import 'package:systock/core/licensing/license_service.dart';
import 'package:systock/core/widgets/activation_contact_banner.dart';

class StartupPage extends ConsumerStatefulWidget {
  const StartupPage({super.key});
  @override
  ConsumerState<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends ConsumerState<StartupPage> {
  User? user;
  List<User> users = const [];
  final pin = TextEditingController();
  String? error;
  bool checking = true;
  bool licenseExpired = false;
  int trialDaysLeft = 0;
  LicensePlan? expiredPlan;

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
    final license = await LicenseService(db).status();
    if (!mounted) return;
    licenseExpired = !license.active;
    trialDaysLeft = license.trialDaysLeft;
    expiredPlan = license.plan;
    await ensureDefaultSeller(db);
    final active =
        await (db.select(db.users)
              ..where((u) => u.active.equals(true))
              ..orderBy([(u) => OrderingTerm.asc(u.name)]))
            .get();
    if (!mounted) return;
    final remembered = await currentSessionUser(db);
    if (!mounted) return;
    final selected = active.firstWhere(
      (candidate) => candidate.id == remembered.id,
      orElse: () => active.first,
    );
    final explicitlyLocked = ref.read(sessionLockedProvider);
    if (!licenseExpired &&
        !explicitlyLocked &&
        active.length == 1 &&
        (selected.pinHash == null || selected.pinSalt == null)) {
      ref.read(sessionUserIdProvider.notifier).state = selected.id;
      if (trialDaysLeft > 0 && mounted) {
        final viewPlans = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Trial ativo'),
            content: Text(
              'Faltam $trialDaysLeft ${trialDaysLeft == 1 ? 'dia' : 'dias'} do seu período de teste. Faça upgrade para continuar sem interrupções.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Continuar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Ver planos'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (viewPlans == true) {
          await _showPlansModal();
          if (!mounted) return;
          setState(() {
            users = active;
            user = selected;
            checking = false;
          });
          return;
        }
      }
      context.go('/dashboard');
    } else {
      setState(() {
        users = active;
        user = selected;
        checking = false;
      });
    }
  }

  Future<void> _showPlansModal() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Planos e subscrições'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Escolha o plano ideal para manter o Systock sempre ativo.',
              ),
              const SizedBox(height: 16),
              for (final plan in const [
                ('Trimestral', '349,00 MT', '3 meses'),
                ('Semestral', '649,00 MT', '6 meses'),
                ('Anual', '1.199,00 MT', '12 meses'),
                ('Vitalício', '3.499,00 MT', 'para sempre'),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 19,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          '${plan.$1} • ${plan.$3}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        plan.$2,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              const ActivationContactBanner(),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );

  Future<void> unlock() async {
    final current = user!;
    if (current.pinHash == null || current.pinSalt == null) {
      await _openSession(current);
      return;
    }
    final valid = await PinHasher().verify(
      pin.text,
      PinDigest(current.pinHash!, current.pinSalt!),
    );
    if (!mounted) return;
    if (valid) {
      await _openSession(current);
    } else {
      setState(() => error = 'PIN incorreto.');
    }
  }

  Future<void> _openSession(User selected) async {
    if (licenseExpired) {
      context.go('/activation');
      return;
    }
    final db = ref.read(databaseProvider);
    await setCurrentSessionUser(db, selected);
    ref.read(sessionUserIdProvider.notifier).state = selected.id;
    ref.invalidate(activePermissionsProvider);
    final permissions = await AuthorizationService(
      db,
    ).permissionsFor(selected.id);
    if (!mounted) return;
    ref.read(sessionLockedProvider.notifier).state = false;
    context.go(
      permissions.length == 1 && permissions.contains('sales.create')
          ? '/pos'
          : '/dashboard',
    );
  }

  Future<void> biometric() async {
    final ok = await SystemBiometricGate().authenticate(
      'Desbloquear o Systock',
    );
    if (ok && mounted) {
      await _openSession(user!);
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
              SecureTextField(
                controller: first,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Novo PIN'.localized(context),
                ),
              ),
              const SizedBox(height: 12),
              SecureTextField(
                controller: confirmation,
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
        await _openSession(user!);
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.primary.withValues(alpha: .07),
            ],
          ),
        ),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 20, 20),
                child: _LoginBrand(
                  english: Localizations.localeOf(context).languageCode == 'en',
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 28, bottom: 16),
                child: Text(
                  'by | LADANS',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: .72),
                  ),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 92, 20, 60),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Card(
                    elevation: 0,
                    margin: const EdgeInsets.all(24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 30, 28, 22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 4),
                          LocalizedText(
                            'Olá, ${user!.name}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 16),
                          if (licenseExpired) ...[
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.error.withValues(alpha: .28),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    expiredPlan == null
                                        ? 'O seu período de teste de 7 dias terminou.'
                                        : 'O seu plano ${expiredPlan!.label} expirou.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  FilledButton.icon(
                                    onPressed: () => context.go('/activation'),
                                    icon: const Icon(Icons.verified_outlined),
                                    label: const Text('Ativar agora'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (!licenseExpired && trialDaysLeft > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: .65),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.schedule_outlined,
                                    size: 20,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      'Trial ativo: faltam $trialDaysLeft ${trialDaysLeft == 1 ? 'dia' : 'dias'}. Faça upgrade para continuar sem interrupções.',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _showPlansModal,
                                    child: const Text('Ver planos'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          DropdownButtonFormField<String>(
                            initialValue: user!.id,
                            decoration: InputDecoration(
                              labelText: 'Utilizador'.localized(context),
                            ),
                            items: [
                              for (final candidate in users)
                                DropdownMenuItem(
                                  value: candidate.id,
                                  child: Text(
                                    '${candidate.name} (${candidate.username})',
                                  ),
                                ),
                            ],
                            onChanged: (id) => setState(() {
                              user = users.firstWhere(
                                (candidate) => candidate.id == id,
                              );
                              pin.clear();
                              error = null;
                            }),
                          ),
                          const SizedBox(height: 20),
                          if (user!.pinHash != null)
                            SecureTextField(
                              controller: pin,
                              autofocus: true,
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
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand({required this.english});
  final bool english;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.layers_rounded,
            color: Colors.white,
            size: 27,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                english
                    ? 'Systock - Stock Management and more'
                    : 'Systock - Gestão de Stock e mais',
                maxLines: 1,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              english ? 'Simple. Powerful. Yours.' : 'Simples. Poderoso. Seu.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}
