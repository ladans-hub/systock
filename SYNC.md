# Sincronização e conflitos

Alterações sincronizáveis gravam uma operação outbox com `operation_id`, entidade, versão, payload canónico e SHA-256. O adaptador atual grava operações imutáveis individuais no `appDataFolder`, verifica existência antes de upload, pagina downloads e aplica retry exponencial. `applied_operations` torna a aplicação idempotente; pacotes agregados/comprimidos podem ser introduzidos sem mudar o contrato.

Fluxo: escrever SQLite → enfileirar outbox na mesma transação → continuar offline → verificar Internet real → publicar pacotes → ler manifestos remotos → validar checksum/schema → deduplicar → aplicar numa transação → atualizar cursores. Falha remota nunca reverte escrita local nem bloqueia operações.

Campos simples usam versão e LWW determinístico (`updated_at`, depois `device_id`) quando seguro. Edições concorrentes relevantes criam `sync_conflicts` e preservam ambos os payloads. Vendas, pagamentos, compras e stock não usam LWW: eventos imutáveis coexistem; cancelamentos são novos eventos compensatórios. O saldo é recalculado após importar movimentos.

Backup é separado: snapshot SQLite consistente via `VACUUM INTO`, manifesto com schema/tamanho/checksum e histórico local. Restore valida checksum e `integrity_check`, salva o estado atual e substitui de forma atómica. Criptografia de backup não é ativada por padrão; quando configurada deverá usar uma biblioteca auditada e chave no armazenamento seguro.

## Configuração OAuth do Google Drive

1. No Google Cloud Console, ative a Google Drive API e configure a tela de consentimento.
2. Crie clientes OAuth para `mz.ladans.systock` em cada plataforma. No Android, registe também os SHA-1 dos certificados debug e release.
3. Em iOS/macOS, adicione `GIDClientID` e o URL scheme `REVERSED_CLIENT_ID` ao `Info.plist` de cada Runner. O URL scheme é obrigatório mesmo quando o client id é fornecido via Dart.
4. O client id também pode ser injetado sem entrar no repositório:

   `flutter run -d macos --dart-define=GOOGLE_APPLE_CLIENT_ID=CLIENT_ID.apps.googleusercontent.com`

   Um client id de servidor opcional usa `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`.

O app solicita somente `drive.appdata`, portanto os pacotes ficam na pasta privada do aplicativo e não aparecem entre os ficheiros normais do utilizador. O macOS já inclui acesso de rede. Ao configurar a assinatura Apple, habilite Keychain Sharing com o grupo `$(AppIdentifierPrefix)com.google.GIDSignIn`; essa capability exige uma equipa/certificado de desenvolvimento e não pode ser ativada num Runner local sem assinatura.
