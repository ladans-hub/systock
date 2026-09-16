import 'package:flutter/material.dart';
import 'drive_vault_identity.dart';

Future<VaultClaim?> selectDriveStore(
  BuildContext context,
  List<VaultClaim> stores,
) async {
  if (stores.length == 1) return stores.single;
  return showDialog<VaultClaim>(
    context: context,
    builder: (dialog) => SimpleDialog(
      title: const Text('Selecione a loja'),
      children: [
        for (final store in stores)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialog, store),
            child: Text(store.companyName),
          ),
      ],
    ),
  );
}

Future<String?> requestDriveRecoveryKey(BuildContext context) async {
  return showDialog<String>(
    context: context,
    builder: (_) => const _RecoveryKeyDialog(),
  );
}

class _RecoveryKeyDialog extends StatefulWidget {
  const _RecoveryKeyDialog();
  @override
  State<_RecoveryKeyDialog> createState() => _RecoveryKeyDialogState();
}

class _RecoveryKeyDialogState extends State<_RecoveryKeyDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ligar à loja existente'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Introduza a chave de recuperação da loja. Este dispositivo poderá enviar e receber alterações junto com o computador.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Chave de recuperação'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          final key = controller.text.trim();
          if (key.isNotEmpty) Navigator.pop(context, key);
        },
        child: const Text('Conectar e sincronizar'),
      ),
    ],
  );
}
