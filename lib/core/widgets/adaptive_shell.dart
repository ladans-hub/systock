import 'dart:io';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/widgets/global_search.dart';
import 'package:systock/core/security/session_state.dart';
import 'package:systock/core/security/permission_gate.dart';
import 'package:systock/core/widgets/platform_controls.dart';
import 'package:systock/l10n/generated/app_localizations.dart';
import 'package:systock/core/licensing/license_service.dart';

class AdaptiveShell extends ConsumerWidget {
  const AdaptiveShell({required this.location, required this.child, super.key});
  final String location;
  final Widget child;
  static const destinations = <({String label, String path, IconData icon})>[
    (label: 'Dashboard', path: '/dashboard', icon: Icons.home_outlined),
    (label: 'Ponto de venda', path: '/pos', icon: Icons.point_of_sale_outlined),
    (label: 'Produtos', path: '/products', icon: Icons.inventory_2_outlined),
    (label: 'Stock', path: '/inventory', icon: Icons.warehouse_outlined),
    (label: 'Vendas', path: '/sales', icon: Icons.shopping_cart_outlined),
    (label: 'Cotações', path: '/quotes', icon: Icons.request_quote_outlined),
    (label: 'Relatórios', path: '/reports', icon: Icons.analytics_outlined),
    (label: 'Configurações', path: '/settings', icon: Icons.settings_outlined),
    (
      label: 'Planos',
      path: '/settings/plan',
      icon: Icons.workspace_premium_outlined,
    ),
  ];

  int get selectedIndex {
    if (location.startsWith('/settings/plan')) return 8;
    final index = destinations.indexWhere((d) => location.startsWith(d.path));
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(activePermissionsProvider).valueOrNull;
    final sellerOnly =
        permissions != null &&
        permissions.length == 1 &&
        permissions.contains('sales.create');
    if (sellerOnly) {
      return LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 700
            ? Scaffold(
                body: child,
                bottomNavigationBar: NavigationBar(
                  selectedIndex: 0,
                  onDestinationSelected: (_) => context.go('/pos'),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.point_of_sale_outlined),
                      label: 'Ponto de venda',
                    ),
                  ],
                ),
              )
            : Scaffold(
                body: Row(
                  children: [
                    SizedBox(
                      width: 240,
                      child: SafeArea(
                        child: Column(
                          children: [
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: _BrandMark(),
                            ),
                            ListTile(
                              selected: true,
                              leading: const Icon(Icons.point_of_sale_outlined),
                              title: const LocalizedText('Ponto de venda'),
                              onTap: () => context.go('/pos'),
                            ),
                            const Spacer(),
                            const _UserFooter(),
                          ],
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: child),
                  ],
                ),
              ),
      );
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            showCommandPalette(context, ref.read(databaseProvider)),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            showCommandPalette(context, ref.read(databaseProvider)),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            showSearch(
              context: context,
              delegate: GlobalSearchDelegate(ref.read(databaseProvider)),
            ),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 700) return _mobile(context);
            if (constraints.maxWidth < 1100) return _tablet(context);
            return _desktop(context);
          },
        ),
      ),
    );
  }

  Widget _mobile(BuildContext context) {
    const indexes = [0, 1, 2, 3];
    final current = indexes.indexOf(selectedIndex);
    final selected = current < 0 ? 4 : current;
    return AdaptiveScaffold(
      body: location == '/dashboard'
          ? Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const _BrandMark(),
                        const SizedBox(width: 10),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          onPressed: () => context.go('/alerts'),
                          icon: const Icon(
                            Icons.notifications_outlined,
                            size: 21,
                          ),
                          tooltip: 'Alertas'.localized(context),
                        ),
                        const SizedBox(width: 6),
                        const Chip(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          avatar: Icon(Icons.offline_bolt_outlined, size: 15),
                          label: LocalizedText('SQLite local'),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(child: child),
              ],
            )
          : child,
      bottomNavigationBar: AdaptiveBottomNavigationBar(
        selectedIndex: selected,
        onTap: (i) => i == 4
            ? _showMore(context)
            : context.go(destinations[indexes[i]].path),
        selectedItemColor: Theme.of(context).colorScheme.primary,
        items: [
          for (final i in indexes)
            AdaptiveNavigationDestination(
              icon: _mobileNavigationIcon(context, i),
              selectedIcon: _mobileNavigationIcon(context, i, selected: true),
              label: _label(context, destinations[i]),
            ),
          AdaptiveNavigationDestination(
            icon: _moreNavigationIcon(context),
            selectedIcon: _moreNavigationIcon(context, selected: true),
            label: Localizations.localeOf(context).languageCode == 'en'
                ? 'More'
                : 'Mais',
          ),
        ],
      ),
    );
  }

  dynamic _mobileNavigationIcon(
    BuildContext context,
    int index, {
    bool selected = false,
  }) {
    if (Theme.of(context).platform != TargetPlatform.iOS) {
      return destinations[index].icon;
    }
    return switch (index) {
      0 => selected ? 'house.fill' : 'house',
      1 => selected ? 'cart.fill' : 'cart',
      2 => selected ? 'shippingbox.fill' : 'shippingbox',
      3 => selected ? 'archivebox.fill' : 'archivebox',
      4 => selected ? 'bag.fill' : 'bag',
      5 => selected ? 'doc.text.fill' : 'doc.text',
      6 => selected ? 'chart.bar.fill' : 'chart.bar',
      8 => selected ? 'star.fill' : 'star',
      _ => selected ? 'gearshape.fill' : 'gearshape',
    };
  }

  dynamic _moreNavigationIcon(BuildContext context, {bool selected = false}) {
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return selected ? 'ellipsis.circle.fill' : 'ellipsis.circle';
    }
    return Icons.more_horiz_rounded;
  }

  IconData _mobileIcon(BuildContext context, int index) {
    final apple =
        Theme.of(context).platform == TargetPlatform.iOS ||
        Theme.of(context).platform == TargetPlatform.macOS;
    if (!apple) return destinations[index].icon;
    return switch (index) {
      0 => CupertinoIcons.house,
      1 => CupertinoIcons.cart,
      2 => CupertinoIcons.cube_box,
      3 => CupertinoIcons.archivebox,
      4 => CupertinoIcons.bag,
      5 => CupertinoIcons.doc_text,
      6 => CupertinoIcons.chart_bar,
      8 => CupertinoIcons.star,
      _ => CupertinoIcons.settings,
    };
  }

  Future<void> _showMore(BuildContext context) async {
    final choices = destinations
        .where(
          (item) => !const [
            '/dashboard',
            '/pos',
            '/products',
            '/inventory',
          ].contains(item.path),
        )
        .toList();
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      await showCupertinoModalPopup<void>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: const LocalizedText('Mais opções'),
          actions: [
            for (final item in choices)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  context.go(item.path);
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _mobileIcon(context, destinations.indexOf(item)),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(_label(context, item)),
                  ],
                ),
              ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(sheetContext);
                _signOut(context);
              },
              child: const LocalizedText('Terminar sessão'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext),
            child: const LocalizedText('Cancelar'),
          ),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final item in choices)
              ListTile(
                leading: Icon(item.icon),
                title: Text(_label(context, item)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.go(item.path);
                },
              ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const LocalizedText('Terminar sessão'),
              onTap: () {
                Navigator.pop(sheetContext);
                _signOut(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _signOut(BuildContext context) {
    // Session state is held only in memory; local data is preserved.
    final container = ProviderScope.containerOf(context);
    container.read(sessionLockedProvider.notifier).state = true;
    container.read(sessionUserIdProvider.notifier).state = null;
    container.invalidate(activePermissionsProvider);
    context.go('/');
  }

  Widget _tablet(BuildContext context) => Scaffold(
    body: Row(
      children: [
        NavigationRail(
          selectedIndex: selectedIndex,
          labelType: NavigationRailLabelType.selected,
          leading: const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: _BrandMark(compact: true),
          ),
          onDestinationSelected: (i) => context.go(destinations[i].path),
          destinations: [
            for (final d in destinations)
              NavigationRailDestination(
                icon: Icon(d.icon),
                label: Text(_label(context, d)),
              ),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: child),
      ],
    ),
  );

  Widget _desktop(BuildContext context) {
    final mac = Theme.of(context).platform == TargetPlatform.macOS;
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: mac ? 236 : 248,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                right: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 22, 16, 24),
                    child: _BrandMark(),
                  ),
                  _section('VISÃO GERAL'),
                  _item(context, 0),
                  _section('OPERAÇÕES'),
                  _item(context, 1),
                  _item(context, 4),
                  _item(context, 5),
                  _section('INVENTÁRIO'),
                  _item(context, 2),
                  _item(context, 3),
                  _section('GESTÃO'),
                  _item(context, 6),
                  const Spacer(),
                  _item(context, 7),
                  _item(context, 8),
                  const _UserFooter(),
                ],
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, int index) {
    final selected = selectedIndex == index;
    final d = destinations[index];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.go(d.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(d.icon, size: 19, color: selected ? Colors.white : null),
                const SizedBox(width: 12),
                Text(
                  _label(context, d),
                  style: TextStyle(
                    color: selected ? Colors.white : null,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String value) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 18, 12, 6),
    child: Text(
      value,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: .7,
        color: Colors.blueGrey,
      ),
    ),
  );

  String _label(
    BuildContext context,
    ({String label, String path, IconData icon}) destination,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final en = Localizations.localeOf(context).languageCode == 'en';
    return switch (destination.path) {
      '/dashboard' => l10n.dashboard,
      '/products' => l10n.products,
      '/inventory' => l10n.inventory,
      '/sales' => l10n.sales,
      '/settings' => l10n.settings,
      '/settings/plan' => en ? 'Plans' : 'Planos',
      '/pos' => en ? 'Point of sale' : 'Ponto de venda',
      '/quotes' => en ? 'Quotes' : 'Cotações',
      '/reports' => en ? 'Reports' : 'Relatórios',
      _ => destination.label,
    };
  }
}

class _BrandMark extends ConsumerWidget {
  const _BrandMark({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) => StreamBuilder(
    stream: ref
        .watch(databaseProvider)
        .customSelect(
          '''SELECT c.trade_name,c.logo_path,COALESCE((SELECT value_json FROM app_settings WHERE key='branding.subtitle'),'Gestão de Stock') subtitle FROM companies c LIMIT 1''',
          readsFrom: {
            ref.watch(databaseProvider).companies,
            ref.watch(databaseProvider).appSettings,
          },
        )
        .watchSingleOrNull(),
    builder: (context, snapshot) {
      final row = snapshot.data;
      final name = row?.read<String>('trade_name') ?? 'Systock';
      final subtitle = row?.read<String>('subtitle') ?? 'Gestão de Stock';
      final logoPath = row?.readNullable<String>('logo_path');
      return Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(9),
            ),
            clipBehavior: Clip.antiAlias,
            child: logoPath != null && File(logoPath).existsSync()
                ? Image.file(File(logoPath), fit: BoxFit.cover)
                : const Icon(
                    Icons.layers_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
          ),
          if (!compact) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    softWrap: true,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _UserFooter extends ConsumerWidget {
  const _UserFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder(
    future: currentSessionUser(ref.watch(databaseProvider)),
    builder: (context, snapshot) {
      final name = snapshot.data?.name ?? 'Utilizador';
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: const Color(0xFF207A4B),
                  child: Text(
                    name.characters.first.toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<LicenseStatus>(
              future: LicenseService(ref.watch(databaseProvider)).status(),
              builder: (context, licenseSnapshot) {
                final status = licenseSnapshot.data;
                if (status == null) return const SizedBox.shrink();
                final label = status.trial
                    ? '${'Plano'.localized(context)} ${'Trial'.localized(context)}'
                    : '${'Plano'.localized(context)} ${status.plan?.label.localized(context) ?? ''}';
                final detail = status.trial
                    ? '${status.trialDaysLeft} ${status.trialDaysLeft == 1 ? 'dia'.localized(context) : 'dias'.localized(context)} ${'restantes'.localized(context)}'
                    : status.plan == LicensePlan.lifetime
                    ? 'Para sempre'.localized(context)
                    : 'Ativo'.localized(context);
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => context.go('/settings/plan'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.workspace_premium_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          detail,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Material(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  ref.read(sessionLockedProvider.notifier).state = true;
                  ref.read(sessionUserIdProvider.notifier).state = null;
                  ref.invalidate(activePermissionsProvider);
                  context.go('/');
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      AdaptiveIcon(PlatformGlyph.logout, size: 18),
                      SizedBox(width: 10),
                      LocalizedText('Terminar sessão'),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            const Align(
              alignment: Alignment.centerLeft,
              child: LocalizedText(
                'Dados neste dispositivo',
                style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      );
    },
  );
}
