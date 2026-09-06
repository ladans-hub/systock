import 'dart:io';

import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/onboarding/application/setup_company.dart';
import 'package:systock/core/sync/google_drive_auth_service.dart';
import 'package:systock/core/sync/google_drive_transport.dart';
import 'package:systock/core/sync/drive_recovery_snapshot.dart';
import 'package:systock/core/security/session_state.dart';
import 'package:systock/core/widgets/secure_text_field.dart';
import 'package:systock/core/licensing/license_service.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});
  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final company = TextEditingController(),
      admin = TextEditingController(),
      username = TextEditingController(),
      pin = TextEditingController(),
      seller = TextEditingController(text: 'Vendedor'),
      sellerUsername = TextEditingController(text: 'vendedor'),
      sellerPin = TextEditingController(text: '1234');
  String currency = 'MZN';
  bool saving = false;

  Future<void> recoverFromDrive() async {
    setState(() => saving = true);
    try {
      final session = await GoogleDriveAuthService.instance.connect();
      final result = await DriveRecoverySnapshot(
        ref.read(databaseProvider),
        GoogleDriveSyncTransport(session.client),
      ).restoreIfLocalIsFresh();
      if (!mounted) return;
      switch (result) {
        case Success(value: InitialDriveRecovery.restored):
          if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
            await Process.start(
              Platform.resolvedExecutable,
              const [],
              mode: ProcessStartMode.detached,
            );
            exit(0);
          }
          await SystemNavigator.pop();
        case Success(value: InitialDriveRecovery.noRemoteSnapshot):
          _message(
            'Esta conta ainda não possui dados do Systock no Google Drive.',
          );
        case Success(value: InitialDriveRecovery.localDataPresent):
          _message(
            'Este dispositivo já possui dados locais. Use a sincronização nas Configurações.',
          );
        case Failure(:final error):
          _message(error.userMessage);
      }
    } catch (_) {
      _message('Não foi possível conectar ao Google Drive.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  void dispose() {
    company.dispose();
    admin.dispose();
    username.dispose();
    pin.dispose();
    seller.dispose();
    sellerUsername.dispose();
    sellerPin.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (seller.text.trim().isEmpty || sellerUsername.text.trim().isEmpty) {
      _message('Preencha o nome e o utilizador do vendedor.');
      return;
    }
    if (!RegExp(r'^\d{4,12}$').hasMatch(sellerPin.text)) {
      _message('O PIN do vendedor deve conter entre 4 e 12 dígitos.');
      return;
    }
    setState(() => saving = true);
    final result = await SetupCompany(ref.read(databaseProvider))(
      tradeName: company.text,
      adminName: admin.text,
      username: username.text,
      currency: currency,
      pin: pin.text,
    );
    if (!mounted) return;
    setState(() => saving = false);
    switch (result) {
      case Success():
        final db = ref.read(databaseProvider);
        await ensureDefaultSeller(
          db,
          name: seller.text,
          username: sellerUsername.text,
          pin: sellerPin.text,
        );
        final adminUser = await (db.select(
          db.users,
        )..where((u) => u.username.equals(username.text.trim()))).getSingle();
        await setCurrentSessionUser(db, adminUser);
        // Inicia o período de teste no momento em que a empresa é criada.
        await LicenseService(db).status();
        if (!mounted) return;
        ref.read(sessionUserIdProvider.notifier).state = adminUser.id;
        context.go('/dashboard');
      case Failure(:final error):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.userMessage)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.inventory_rounded,
                    size: 52,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  LocalizedText(
                    'Bem-vindo ao Systock',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const LocalizedText(
                    'Controle stock, vendas e compras sem depender da Internet.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: company,
                    decoration: InputDecoration(
                      labelText: 'Nome comercial'.localized(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: admin,
                    decoration: InputDecoration(
                      labelText: 'Nome do administrador'.localized(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: username,
                    decoration: InputDecoration(
                      labelText: 'Utilizador'.localized(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SecureTextField(
                    controller: pin,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'PIN de acesso opcional (4–12 dígitos)'
                          .localized(context),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const LocalizedText(
                    'Login do vendedor (acesso somente ao Ponto de Venda)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: seller,
                    decoration: InputDecoration(
                      labelText: 'Nome do vendedor'.localized(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sellerUsername,
                    decoration: InputDecoration(
                      labelText: 'Utilizador do vendedor'.localized(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SecureTextField(
                    controller: sellerPin,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'PIN do vendedor'.localized(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField(
                    initialValue: currency,
                    decoration: InputDecoration(
                      labelText: 'Moeda'.localized(context),
                    ),
                    items: const ['MZN', 'USD', 'EUR', 'ZAR']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) => setState(() => currency = v!),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: saving ? null : submit,
                    child: Text(saving ? 'A configurar…' : 'Começar'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: saving ? null : recoverFromDrive,
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const LocalizedText(
                      'Recuperar da minha Conta Google',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const LocalizedText(
                    'Use esta opção num dispositivo novo para baixar automaticamente os dados já sincronizados.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
