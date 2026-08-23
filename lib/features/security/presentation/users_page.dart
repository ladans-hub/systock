import 'package:flutter/material.dart';
import 'package:systock/l10n/localized_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:systock/core/database/app_database.dart';
import 'package:systock/core/database/database_provider.dart';
import 'package:systock/core/errors/result.dart';
import 'package:systock/features/security/application/user_admin_service.dart';
import 'package:systock/core/widgets/platform_controls.dart';

class UsersPage extends ConsumerWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const AdaptiveBackButton(),
        title: const LocalizedText('Utilizadores e permissões'),
        actions: [
          TextButton.icon(
            onPressed: () => _createRole(context, db),
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const LocalizedText('Novo perfil'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, db),
        icon: const Icon(Icons.person_add),
        label: const LocalizedText('Adicionar'),
      ),
      body: StreamBuilder<List<User>>(
        stream: db.select(db.users).watch(),
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final user = rows[i];
              return FutureBuilder<Role>(
                future: (db.select(
                  db.roles,
                )..where((r) => r.id.equals(user.roleId))).getSingle(),
                builder: (_, role) => SwitchListTile(
                  secondary: CircleAvatar(
                    child: Text(user.name.characters.first.toUpperCase()),
                  ),
                  title: Text(user.name),
                  subtitle: LocalizedText(
                    '${user.username} · ${role.data?.name ?? '…'}',
                  ),
                  value: user.active,
                  onChanged: (value) =>
                      UserAdminService(db).setActive(user.id, value),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _create(BuildContext context, AppDatabase db) async {
    final name = TextEditingController(),
        username = TextEditingController(),
        pin = TextEditingController();
    final roles = await db.select(db.roles).get();
    if (!context.mounted || roles.isEmpty) return;
    var roleId = roles.first.id;
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const LocalizedText('Novo utilizador'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(
                    labelText: 'Nome'.localized(context),
                  ),
                ),
                TextField(
                  controller: username,
                  decoration: InputDecoration(
                    labelText: 'Utilizador'.localized(context),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: roleId,
                  decoration: InputDecoration(
                    labelText: 'Perfil'.localized(context),
                  ),
                  items: [
                    for (final r in roles)
                      DropdownMenuItem(value: r.id, child: Text(r.name)),
                  ],
                  onChanged: (v) => setState(() => roleId = v!),
                ),
                TextField(
                  controller: pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'PIN opcional'.localized(context),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const LocalizedText('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const LocalizedText('Criar'),
            ),
          ],
        ),
      ),
    );
    if (submit != true) return;
    final company = await db.select(db.companies).getSingle();
    final result = await UserAdminService(db).create(
      companyId: company.id,
      roleId: roleId,
      name: name.text,
      username: username.text,
      deviceId: company.deviceId,
      pin: pin.text,
    );
    if (!context.mounted) return;
    final message = switch (result) {
      Success() => 'Utilizador criado.',
      Failure(:final error) => error.userMessage,
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createRole(BuildContext context, AppDatabase db) async {
    final all = await db.select(db.permissions).get(),
        company = await db.select(db.companies).getSingle();
    if (!context.mounted) return;
    final name = TextEditingController(), selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: const LocalizedText('Perfil personalizado'),
          content: SizedBox(
            width: 520,
            height: 520,
            child: Column(
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(
                    labelText: 'Nome do perfil'.localized(context),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      for (final permission in all)
                        CheckboxListTile(
                          dense: true,
                          title: Text(permission.code),
                          subtitle: Text(permission.description),
                          value: selected.contains(permission.code),
                          onChanged: (value) => setState(
                            () => value == true
                                ? selected.add(permission.code)
                                : selected.remove(permission.code),
                          ),
                        ),
                    ],
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
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const LocalizedText('Criar perfil'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final result = await UserAdminService(db).createRole(
      companyId: company.id,
      name: name.text,
      deviceId: company.deviceId,
      permissions: selected,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          Success() => 'Perfil criado.',
          Failure(:final error) => error.userMessage,
        }),
      ),
    );
  }
}
