import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/licensing/license_service.dart';
import 'package:systock/core/widgets/activation_contact_banner.dart';

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

  List<LicensePlan> get _visiblePlans {
    const all = LicensePlan.values;
    final status = currentStatus;
    if (status == null || status.trial || status.plan == null) return all;
    final expires = status.expiresAt;
    final nearExpiry =
        expires != null &&
        expires.difference(DateTime.now().toUtc()).inDays <= 7;
    if (!status.active || nearExpiry) return all;
    final index = all.indexOf(status.plan!);
    return all.sublist(index);
  }

  ({String label, String price, String detail, IconData icon, bool popular})
  _planData(LicensePlan plan) => switch (plan) {
    LicensePlan.quarterly => (
      label: 'Trimestral',
      price: '349,00 MT',
      detail: 'a cada 3 meses',
      icon: Icons.eco_outlined,
      popular: false,
    ),
    LicensePlan.semiannual => (
      label: 'Semestral',
      price: '649,00 MT',
      detail: 'a cada 6 meses',
      icon: Icons.diamond_outlined,
      popular: false,
    ),
    LicensePlan.annual => (
      label: 'Anual',
      price: '1.199,00 MT',
      detail: 'a cada 12 meses',
      icon: Icons.star_rounded,
      popular: true,
    ),
    LicensePlan.lifetime => (
      label: 'Vitalício',
      price: '3.499,00 MT',
      detail: 'pagamento único',
      icon: Icons.all_inclusive,
      popular: false,
    ),
  };

  @override
  void initState() {
    super.initState();
    LicenseService(ref.read(databaseProvider)).status().then((value) {
      if (mounted) setState(() => currentStatus = value);
    });
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plano ${plan.label} ativado com sucesso.')),
      );
      context.go('/');
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
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
                const ActivationContactBanner(),
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
                          child: Text(
                            'Planos e subscrições',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
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
                                        ? 'Plano atual: Trial (${currentStatus!.trialDaysLeft} ${currentStatus!.trialDaysLeft == 1 ? 'dia restante' : 'dias restantes'})'
                                        : 'Plano atual: ${currentStatus!.plan!.label}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (!currentStatus!.trial &&
                                    currentStatus!.expiresAt != null)
                                  Text(
                                    currentStatus!.plan == LicensePlan.lifetime
                                        ? 'Para sempre'
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
                            child: Text(
                              'Faça upgrade quando quiser',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
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
                            for (final plan in _visiblePlans)
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
                          child: Text(
                            'Ativar plano',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Insira o token UUID de ativação fornecido pelo proprietário.',
                          textAlign: TextAlign.left,
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: code,
                          autofocus: true,
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
                            labelText: 'Código de ativação',
                            errorText: error,
                          ),
                          onSubmitted: (_) => submitActivation(),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: saving ? null : submitActivation,
                            child: Text(saving ? 'A validar...' : 'Ativar'),
                          ),
                        ),
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
    return Opacity(
      opacity: current ? .58 : 1,
      child: Container(
        width: 165,
        height: 210,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: popular ? accent.withValues(alpha: .10) : scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accent.withValues(alpha: popular ? 1 : .45),
            width: popular ? 2 : 1,
          ),
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
                      color: current ? scheme.outline : accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      current ? 'Atual' : 'Popular',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Text(
              label,
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
              detail,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
