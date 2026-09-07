import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:systock/l10n/localized_text.dart';

class ActivationContactBanner extends StatelessWidget {
  const ActivationContactBanner({this.onContact, super.key});
  final VoidCallback? onContact;

  Future<void> _openWhatsApp() async {
    // Tenta primeiro a aplicação nativa; se não estiver instalada, abre o
    // WhatsApp Web no navegador padrão.
    final nativeUri = Uri.parse('whatsapp://send?phone=258840552930');
    if (await launchUrl(nativeUri, mode: LaunchMode.externalApplication)) {
      return;
    }
    await launchUrl(
      Uri.parse('https://wa.me/258840552930'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final details = Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.phone_in_talk_outlined,
            color: scheme.primary,
            size: 28,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LocalizedText(
                'Precisa do seu código de ativação?',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 3),
              LocalizedText(
                'Contacte a LADANS para obter o seu código de ativação.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 5),
              const Text(
                '+258 84 055 29 30',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ],
          ),
        ),
      ],
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: .28)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: .08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const whatsappGreen = Color(0xFF25D366);
          final button = OutlinedButton.icon(
            onPressed: onContact ?? _openWhatsApp,
            icon: Image.asset(
              'assets/branding/whatsapp.png',
              width: 22,
              height: 22,
            ),
            label: const LocalizedText('Contactar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: whatsappGreen,
              side: const BorderSide(color: whatsappGreen, width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
          );
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                details,
                const SizedBox(height: 12),
                Align(alignment: Alignment.center, child: button),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 12),
              button,
            ],
          );
        },
      ),
    );
  }
}
