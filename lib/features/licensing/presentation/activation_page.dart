import 'package:systock/core/widgets/error_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/licensing/license_service.dart';
import 'package:systock/core/widgets/activation_contact_banner.dart';
import 'package:systock/l10n/localized_text.dart';

class ActivationPage extends ConsumerStatefulWidget {
  const ActivationPage({super.key});
  @override
  ConsumerState<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends ConsumerState<ActivationPage> {
  final code = TextEditingController();
  String? error;
  bool saving = false;
  LicenseStatus? currentStatus;
  String? deviceId;

  ({String label, String price, String detail, IconData icon, bool popular})
  _planData(LicensePlan plan) => switch (plan) {
    LicensePlan.quarterly => (
      label: 'Trimestral',
      price: '449,00 MT',
      detail: 'a cada 3 meses',
      icon: Icons.eco_outlined,
      popular: false,
    ),
    LicensePlan.semiannual => (
      label: 'Semestral',
      price: '849,00 MT',
      detail: 'a cada 6 meses',
      icon: Icons.diamond_outlined,
      popular: false,
    ),
    LicensePlan.annual => (
      label: 'Anual',
      price: '1.499,00 MT',
      detail: 'a cada 12 meses',
      icon: Icons.star_rounded,
      popular: true,
    ),
    LicensePlan.lifetime => (
      label: 'Vitalício',
      price: '4.999,00 MT',
      detail: 'pagamento único',
      icon: Icons.all_inclusive,
      popular: false,
    ),
  };

  @override
  void initState() {
    super.initState();
    _loadLicense();
  }

  Future<void> _loadLicense() async {
    final db = ref.read(databaseProvider);
    final company = await db.select(db.companies).getSingleOrNull();
    if (!mounted) return;
    setState(() => deviceId = company?.deviceId);
    final status = await LicenseService(db).status();
    if (!mounted) return;
    setState(() => currentStatus = status);
  }

  Future<void> _copyDeviceId() async {
    final id = deviceId;
    if (id == null || id.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    await showAppAlert(context, 'ID do dispositivo copiado');
  }

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> submitActivation() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final plan = await LicenseService(
        ref.read(databaseProvider),
      ).activate(code.text);
      if (!mounted) return;
      await showAppAlert(
        context,
        '${'Plano'.localized(context)} ${plan.label.localized(context)} ${'ativado com sucesso.'.localized(context)}',
      );
      if (!mounted) return;
      context.go('/');
    } on FormatException catch (e) {
      if (mounted) await showAppError(context, e.message);
    } catch (error) {
      if (mounted) {
        await showAppError(
          context,
          'Não foi possível ativar o plano.',
          details: error,
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    body: Container(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ActivationContactBanner(showBackground: false),
                const SizedBox(height: 18),
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          child: const Icon(
                            Icons.workspace_premium_outlined,
                            size: 30,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: LocalizedText(
                            'Planos',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: LocalizedText(
                            'Escolha o plano ideal para manter o seu sistema sempre ativo e atualizado.',
                          ),
                        ),
                        const SizedBox(height: 22),
                        if (currentStatus?.plan != null ||
                            currentStatus?.trial == true) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: .10),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  currentStatus!.trial
                                      ? Icons.schedule_outlined
                                      : Icons.verified,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    currentStatus!.trial
                                        ? '${'Plano atual'.localized(context)}: ${'Trial'.localized(context)} (${currentStatus!.trialDaysLeft} ${currentStatus!.trialDaysLeft == 1 ? 'dia restante'.localized(context) : 'dias restantes'.localized(context)})'
                                        : '${'Plano atual'.localized(context)}: ${currentStatus!.plan!.label.localized(context)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (!currentStatus!.trial &&
                                    currentStatus!.expiresAt != null)
                                  Text(
                                    currentStatus!.plan == LicensePlan.lifetime
                                        ? 'Para sempre'.localized(context)
                                        : '${currentStatus!.expiresAt!.day.toString().padLeft(2, '0')}/${currentStatus!.expiresAt!.month.toString().padLeft(2, '0')}/${currentStatus!.expiresAt!.year}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: LocalizedText(
                              'Faça upgrade quando quiser',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: LocalizedText(
                            'Escolha o seu plano',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final plan in LicensePlan.values)
                              () {
                                final data = _planData(plan);
                                return _PlanCard(
                                  label: data.label,
                                  price: data.price,
                                  detail: data.detail,
                                  icon: data.icon,
                                  popular: data.popular,
                                  current:
                                      currentStatus?.plan == plan &&
                                      currentStatus?.active == true,
                                );
                              }(),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: LocalizedText(
                            'Ativar plano',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const LocalizedText(
                          'Insira o token UUID de ativação fornecido pelo proprietário.',
                          textAlign: TextAlign.left,
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: code,
                          autofocus: false,
                          maxLength: 100,
                          keyboardType: TextInputType.text,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Za-z0-9|.-]'),
                            ),
                          ],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            letterSpacing: .8,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Código de ativação'.localized(context),
                            hintText: 'Cole aqui o código UUID'.localized(
                              context,
                            ),
                            errorText: error?.localized(context),
                          ),
                          onSubmitted: (_) => submitActivation(),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: saving ? null : submitActivation,
                            child: LocalizedText(
                              saving ? 'A validar...' : 'Ativar',
                            ),
                          ),
                        ),
                        if (deviceId != null) ...[
                          const SizedBox(height: 20),
                          Text(
                            'ID do dispositivo'.localized(context),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            deviceId!,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                          TextButton.icon(
                            onPressed: _copyDeviceId,
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              textStyle: Theme.of(context).textTheme.labelSmall,
                            ),
                            icon: const Icon(Icons.copy_outlined, size: 16),
                            label: const LocalizedText('Copiar ID'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.label,
    required this.price,
    required this.detail,
    required this.icon,
    this.popular = false,
    this.current = false,
  });
  final String label;
  final String price;
  final String detail;
  final IconData icon;
  final bool popular;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = switch (label) {
      'Vitalício' => const Color(0xFFD4A72C),
      'Anual' => const Color(0xFF25D366),
      'Semestral' => const Color(0xFF8B5CF6),
      _ => scheme.primary,
    };
    return Semantics(
      selected: current,
      child: Container(
        width: 165,
        height: 210,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: current ? accent.withValues(alpha: .20) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: accent.withValues(alpha: .14),
                  child: Icon(icon, size: 19, color: accent),
                ),
                if (popular || current) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      (current ? 'Plano atual' : 'Popular').localized(context),
                      style: TextStyle(
                        fontSize: 10,
                        color: accent.computeLuminance() > .179
                            ? Colors.black
                            : Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Text(
              label.localized(context),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 28,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  price,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              detail.localized(context),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
