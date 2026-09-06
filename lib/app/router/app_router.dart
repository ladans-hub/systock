import 'package:go_router/go_router.dart';
import 'package:systock/core/widgets/adaptive_shell.dart';
import 'package:systock/features/dashboard/presentation/dashboard_page.dart';
import 'package:systock/features/onboarding/presentation/onboarding_page.dart';
import 'package:systock/features/onboarding/presentation/startup_page.dart';
import 'package:systock/features/products/presentation/products_page.dart';
import 'package:systock/features/inventory/presentation/inventory_page.dart';
import 'package:systock/features/inventory/presentation/inventory_product_page.dart';
import 'package:systock/features/pos/presentation/pos_page.dart';
import 'package:systock/features/sales/presentation/sale_detail_page.dart';
import 'package:systock/features/sales/presentation/sales_page.dart';
import 'package:systock/features/purchases/presentation/purchases_page.dart';
import 'package:systock/features/reports/presentation/reports_page.dart';
import 'package:systock/features/settings/presentation/settings_page.dart';
import 'package:systock/features/backups/presentation/backup_page.dart';
import 'package:systock/features/synchronization/presentation/sync_page.dart';
import 'package:systock/features/transfers/presentation/transfers_page.dart';
import 'package:systock/features/warehouses/presentation/warehouses_page.dart';
import 'package:systock/features/inventory/presentation/stock_counts_page.dart';
import 'package:systock/features/inventory/presentation/stock_count_detail_page.dart';
import 'package:systock/features/categories/presentation/categories_page.dart';
import 'package:systock/features/contacts/presentation/contacts_page.dart';
import 'package:systock/features/inventory/presentation/movements_page.dart';
import 'package:systock/features/products/presentation/product_detail_page.dart';
import 'package:systock/features/products/presentation/product_edit_page.dart';
import 'package:systock/features/cash/presentation/cash_page.dart';
import 'package:systock/features/expenses/presentation/expenses_page.dart';
import 'package:systock/features/security/presentation/users_page.dart';
import 'package:systock/features/settings/presentation/diagnostics_page.dart';
import 'package:systock/features/products/presentation/product_import_page.dart';
import 'package:systock/features/products/presentation/labels_page.dart';
import 'package:systock/features/quotes/presentation/quotes_page.dart';
import 'package:systock/features/quotes/presentation/quote_detail_page.dart';
import 'package:systock/features/alerts/presentation/alerts_page.dart';
import 'package:systock/features/settings/presentation/company_settings_page.dart';
import 'package:systock/features/settings/presentation/printing_settings_page.dart';
import 'package:systock/features/settings/presentation/business_rules_page.dart';
import 'package:systock/features/purchases/presentation/purchase_orders_page.dart';
import 'package:systock/features/inventory/presentation/lots_page.dart';
import 'package:systock/features/purchases/presentation/purchase_detail_page.dart';
import 'package:systock/core/security/permission_gate.dart';
import 'package:systock/features/licensing/presentation/activation_page.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const StartupPage()),
    GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingPage()),
    GoRoute(path: '/activation', builder: (_, _) => const ActivationPage()),
    ShellRoute(
      builder: (_, state, child) => SessionAccessGate(
        location: state.uri.path,
        child: AdaptiveShell(location: state.uri.path, child: child),
      ),
      routes: [
        GoRoute(path: '/dashboard', builder: (_, _) => const DashboardPage()),
        GoRoute(
          path: '/products',
          builder: (_, _) => const PermissionGate(
            permission: 'products.view',
            child: ProductsPage(),
          ),
        ),
        GoRoute(
          path: '/products/import',
          builder: (_, _) => const PermissionGate(
            permission: 'products.create',
            child: ProductImportPage(),
          ),
        ),
        GoRoute(
          path: '/products/labels',
          builder: (_, _) => const PermissionGate(
            permission: 'products.view',
            child: LabelsPage(),
          ),
        ),
        GoRoute(
          path: '/inventory',
          builder: (_, _) => const PermissionGate(
            permission: 'inventory.view',
            child: InventoryPage(),
          ),
        ),
        GoRoute(
          path: '/inventory/product/:id',
          builder: (_, state) => PermissionGate(
            permission: 'inventory.view',
            child: InventoryProductPage(state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/inventory/lots',
          builder: (_, _) => const PermissionGate(
            permission: 'inventory.view',
            child: LotsPage(),
          ),
        ),
        GoRoute(
          path: '/pos',
          builder: (_, _) => const PermissionGate(
            permission: 'sales.create',
            child: PosPage(),
          ),
        ),
        GoRoute(
          path: '/sales',
          builder: (_, _) => const PermissionGate(
            permission: 'sales.create',
            child: SalesPage(),
          ),
        ),
        GoRoute(path: '/quotes', builder: (_, _) => const QuotesPage()),
        GoRoute(
          path: '/quotes/:id',
          builder: (_, state) => QuoteDetailPage(state.pathParameters['id']!),
        ),
        GoRoute(path: '/alerts', builder: (_, _) => const AlertsPage()),
        GoRoute(
          path: '/purchases',
          builder: (_, _) => const PermissionGate(
            permission: 'purchases.create',
            child: PurchasesPage(),
          ),
        ),
        GoRoute(
          path: '/purchases/orders',
          builder: (_, _) => const PurchaseOrdersPage(),
        ),
        GoRoute(
          path: '/purchases/:id',
          builder: (_, state) =>
              PurchaseDetailPage(state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/reports',
          builder: (_, _) => const PermissionGate(
            permission: 'reports.view',
            child: ReportsPage(),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const PermissionGate(
            permission: 'settings.manage',
            child: SettingsPage(),
          ),
        ),
        GoRoute(
          path: '/settings/backup',
          builder: (_, _) => const PermissionGate(
            permission: 'backup.manage',
            child: BackupPage(),
          ),
        ),
        GoRoute(
          path: '/settings/sync',
          builder: (_, _) => const PermissionGate(
            permission: 'settings.manage',
            child: SyncPage(),
          ),
        ),
        GoRoute(path: '/warehouses', builder: (_, _) => const WarehousesPage()),
        GoRoute(path: '/transfers', builder: (_, _) => const TransfersPage()),
        GoRoute(
          path: '/inventory/counts',
          builder: (_, _) => const StockCountsPage(),
        ),
        GoRoute(
          path: '/inventory/counts/:id',
          builder: (_, state) =>
              StockCountDetailPage(state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/sales/:id',
          builder: (_, state) => SaleDetailPage(state.pathParameters['id']!),
        ),
        GoRoute(path: '/categories', builder: (_, _) => const CategoriesPage()),
        GoRoute(
          path: '/customers',
          builder: (_, _) => const ContactsPage(ContactKind.customer),
        ),
        GoRoute(
          path: '/suppliers',
          builder: (_, _) => const ContactsPage(ContactKind.supplier),
        ),
        GoRoute(
          path: '/inventory/adjustments',
          builder: (_, _) => const PermissionGate(
            permission: 'inventory.adjust',
            child: MovementsPage(),
          ),
        ),
        GoRoute(
          path: '/products/:id',
          builder: (_, state) => ProductDetailPage(state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/products/:id/edit',
          builder: (_, state) => ProductEditPage(state.pathParameters['id']!),
        ),
        GoRoute(path: '/cash', builder: (_, _) => const CashPage()),
        GoRoute(path: '/expenses', builder: (_, _) => const ExpensesPage()),
        GoRoute(
          path: '/settings/users',
          builder: (_, _) => const AnyPermissionGate(
            permissions: ['users.manage', 'users.reset_admin_pin'],
            child: UsersPage(),
          ),
        ),
        GoRoute(
          path: '/settings/diagnostics',
          builder: (_, _) => const DiagnosticsPage(),
        ),
        GoRoute(
          path: '/settings/company',
          builder: (_, _) => const CompanySettingsPage(),
        ),
        GoRoute(
          path: '/settings/printing',
          builder: (_, _) => const PrintingSettingsPage(),
        ),
        GoRoute(
          path: '/settings/business-rules',
          builder: (_, _) => const BusinessRulesPage(),
        ),
        GoRoute(
          path: '/settings/plan',
          builder: (_, _) => const ActivationPage(),
        ),
      ],
    ),
  ],
);
