import 'package:systock/core/widgets/error_dialog.dart';
import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show InsertMode;
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/app/theme/theme_controller.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/features/onboarding/application/demo_data_seeder.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final en = Localizations.localeOf(context).languageCode == 'en';
    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(en ? 'Settings' : 'Configurações', localized: false),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.business_outlined),
                  title: Text(en ? 'Company' : 'Empresa'),
                  subtitle: Text(
                    en
                        ? 'Tax details, currency and receipts'
                        : 'Dados fiscais, moeda e recibos',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/settings/company'),
                ),
                ListTile(
                  leading: const Icon(Icons.rule_outlined),
                  title: Text(
                    en ? 'Stock, prices and taxes' : 'Stock, preços e impostos',
                  ),
                  subtitle: Text(
                    en
                        ? 'Configurable rules and rates'
                        : 'Políticas e taxas configuráveis',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/settings/business-rules'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _PreferenceCard(
            icon: Icons.palette_outlined,
            title: en ? 'Appearance' : 'Aparência',
            subtitle: en
                ? 'Choose how the system looks'
                : 'Escolha como o sistema se apresenta',
            options: [
              (
                en ? 'System' : 'Sistema',
                en ? 'Follows the device' : 'Segue o dispositivo',
                ThemeMode.system,
              ),
              (
                en ? 'Light' : 'Claro',
                en ? 'Bright interface' : 'Interface luminosa',
                ThemeMode.light,
              ),
              (
                en ? 'Dark' : 'Escuro',
                en ? 'Comfort in low light' : 'Conforto em pouca luz',
                ThemeMode.dark,
              ),
            ],
            selected: ref.watch(themeModeProvider),
            onSelected: (value) =>
                ref.read(themeModeProvider.notifier).state = value,
          ),
          const SizedBox(height: 12),
          _ColorPaletteCard(en: en),
          const SizedBox(height: 12),
          _PreferenceCard<Locale>(
            icon: Icons.language_outlined,
            title: en ? 'Language' : 'Idioma',
            subtitle: en
                ? 'Changes are applied immediately'
                : 'A alteração é aplicada imediatamente',
            options: const [
              ('Português', 'Moçambique', Locale('pt')),
              ('English', 'International', Locale('en')),
            ],
            selected: ref.watch(appLocaleProvider),
            onSelected: (value) =>
                ref.read(appLocaleProvider.notifier).state = value,
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const LocalizedText('Backup'),
                  subtitle: const LocalizedText(
                    'Criar e validar cópias locais',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/settings/backup'),
                ),
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const LocalizedText('Sincronização'),
                  subtitle: const LocalizedText(
                    'Apenas neste dispositivo ou Google Drive',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/settings/sync'),
                ),
                ListTile(
                  leading: const Icon(Icons.point_of_sale),
                  title: const LocalizedText('Controle de caixa'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/cash'),
                ),
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: const LocalizedText('Despesas'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/expenses'),
                ),
                ListTile(
                  leading: const Icon(Icons.security_outlined),
                  title: const LocalizedText('Utilizadores e segurança'),
                  subtitle: const LocalizedText('PIN, perfis e permissões'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/settings/users'),
                ),
                ListTile(
                  leading: const Icon(Icons.print_outlined),
                  title: const LocalizedText('Impressão e recibos'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/settings/printing'),
                ),
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const LocalizedText('Dados de demonstração'),
                  subtitle: const LocalizedText(
                    'Carregar catálogo e operações fictícias',
                  ),
                  trailing: const Icon(Icons.download_outlined),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialog) => AlertDialog(
                        title: const LocalizedText(
                          'Carregar dados de demonstração?',
                        ),
                        content: const LocalizedText(
                          'Os registos serão identificados como fictícios e não duplicam quando esta ação é repetida.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialog, false),
                            child: const LocalizedText('Cancelar'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialog, true),
                            child: const LocalizedText('Carregar'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !context.mounted) return;
                    final db = ref.read(databaseProvider);
                    final company = await db.select(db.companies).getSingle();
                    await DemoDataSeeder(db).seed(company, refresh: true);
                    if (!context.mounted) return;
                    await showAppAlert(
                      context,
                      'Dados de demonstração prontos.',
                    );
                  },
                ),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: LocalizedText('Sobre'),
                  subtitle: LocalizedText('Systock • schema 10'),
                ),
                ListTile(
                  leading: const Icon(Icons.monitor_heart_outlined),
                  title: const LocalizedText('Diagnóstico'),
                  subtitle: const LocalizedText(
                    'Integridade, banco, backup e sync',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/settings/diagnostics'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorPaletteCard extends ConsumerWidget {
  const _ColorPaletteCard({required this.en});

  final bool en;

  static const colors = <Color>[
    Color(0xFF2F6BFF),
    Color(0xFF6750A4),
    Color(0xFF00897B),
    Color(0xFF2E7D32),
    Color(0xFFF57C00),
    Color(0xFFD32F2F),
    Color(0xFFC2185B),
    Color(0xFF455A64),
    Color(0xFFF9A825),
    Color(0xFF689F38),
    Color(0xFF00ACC1),
  ];

  Future<void> _save(WidgetRef ref, AppPalette palette) async {
    ref.read(appPaletteProvider.notifier).state = palette;
    final db = ref.read(databaseProvider);
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: 'appearance.palette',
            valueJson:
                '${palette.primary.toARGB32()},${palette.secondary.toARGB32()}',
            updatedAt: DateTime.now().toUtc(),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(appPaletteProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.color_lens_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        en ? 'Color palette' : 'Paleta de cores',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        en
                            ? 'Personalize the system identity'
                            : 'Personalize a identidade do sistema',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: palette == AppPalette.defaults
                      ? null
                      : () => _save(ref, AppPalette.defaults),
                  child: Text(en ? 'Reset' : 'Repor'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _ColorSelector(
              label: en ? 'Primary color' : 'Cor primária',
              colors: colors,
              selected: palette.primary,
              onSelected: (color) =>
                  _save(ref, palette.copyWith(primary: color)),
            ),
            const SizedBox(height: 16),
            _ColorSelector(
              label: en ? 'Secondary color' : 'Cor secundária',
              colors: colors,
              selected: palette.secondary,
              onSelected: (color) =>
                  _save(ref, palette.copyWith(secondary: color)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorSelector extends StatelessWidget {
  const _ColorSelector({
    required this.label,
    required this.colors,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final color in colors)
            Semantics(
              label: label,
              selected: color == selected,
              button: true,
              child: InkWell(
                onTap: () => onSelected(color),
                customBorder: const CircleBorder(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color == selected
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: .28),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                  child: color == selected
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              ),
            ),
        ],
      ),
    ],
  );
}

class _PreferenceCard<T> extends StatelessWidget {
  const _PreferenceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.options,
    required this.selected,
    required this.onSelected,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final List<(String, String, T)> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final option in options)
                _PreferenceOption(
                  title: option.$1,
                  subtitle: option.$2,
                  selected: option.$3 == selected,
                  onTap: () => onSelected(option.$3),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _PreferenceOption extends StatelessWidget {
  const _PreferenceOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 230,
      height: 72,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: .1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            size: 19,
            color: selected ? Theme.of(context).colorScheme.primary : null,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
