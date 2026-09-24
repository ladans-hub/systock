# Sincronização e conflitos

Alterações sincronizáveis gravam uma operação outbox com `operation_id`, entidade, versão, payload canónico e SHA-256. O adaptador atual grava operações imutáveis individuais no `appDataFolder`, verifica existência antes de upload, pagina downloads e aplica retry exponencial. `applied_operations` torna a aplicação idempotente; pacotes agregados/comprimidos podem ser introduzidos sem mudar o contrato.

Fluxo: escrever SQLite → enfileirar outbox na mesma transação → continuar offline → verificar Internet real → publicar pacotes → ler manifestos remotos → validar checksum/schema → deduplicar → aplicar numa transação → atualizar cursores. Falha remota nunca reverte escrita local nem bloqueia operações.

Campos simples usam versão e LWW determinístico (`updated_at`, depois `device_id`) quando seguro. Edições concorrentes relevantes criam `sync_conflicts` e preservam ambos os payloads. Vendas, pagamentos, compras e stock não usam LWW: eventos imutáveis coexistem; cancelamentos são novos eventos compensatórios. O saldo é recalculado após importar movimentos.

Backup é separado: snapshot SQLite consistente via `VACUUM INTO`, manifesto com schema/tamanho/checksum e histórico local. Restore valida checksum e `integrity_check`, salva o estado atual e substitui de forma atómica. Criptografia de backup não é ativada por padrão; quando configurada deverá usar uma biblioteca auditada e chave no armazenamento seguro.

## Configuração OAuth do Google Drive

1. No Google Cloud Console, ative a Google Drive API e configure a tela de consentimento.
2. Crie clientes OAuth separados para cada plataforma. No Android, crie uma credencial do tipo **Android** com o package name `mz.ladans.systock` e o SHA-1 correspondente ao certificado usado para assinar o aplicativo:

   - Debug local: `FD:C3:DD:04:10:F6:66:68:BF:93:7D:DA:EF:B5:43:78:CB:F4:C8:21`
   - Release local: `33:E2:52:24:DE:84:63:A7:C4:82:F9:0F:F1:44:E1:35:71:00:77:94`
   - Google Play: registe também o SHA-1 do certificado de assinatura fornecido pelo Play Console.

   O package name e o SHA-1 precisam corresponder exatamente ao APK/AAB instalado. O erro Android `ApiException: 10` (`DEVELOPER_ERROR`) normalmente indica que essa associação está ausente ou incorreta. Credenciais diferentes podem ser criadas para o mesmo package name, uma para cada certificado.
3. O Android não lê `GOOGLE_ANDROID_CLIENT_ID` no fluxo atual e não precisa de `google-services.json` para esta autenticação. O `google_sign_in` identifica o aplicativo pela credencial OAuth Android configurada no Google Cloud com package name e SHA-1. Não passe o Client ID Android como `serverClientId`; somente uma credencial OAuth do tipo **Web application** pode ser usada como `GOOGLE_SERVER_CLIENT_ID`, quando realmente necessária.
4. Em iOS/macOS, adicione `GIDClientID` e o URL scheme `REVERSED_CLIENT_ID` ao `Info.plist` de cada Runner. O URL scheme é obrigatório mesmo quando o client id é fornecido via Dart.
5. O client id da Apple também pode ser injetado sem entrar no repositório:

   `flutter run -d ios --dart-define=GOOGLE_IOS_CLIENT_ID=CLIENT_ID.apps.googleusercontent.com`

   Um Client ID Web opcional para autenticação de servidor usa `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`.

Depois de alterar credenciais Android no Google Cloud, aguarde a propagação da configuração, desinstale o aplicativo do dispositivo e instale-o novamente. Ao executar pelo VS Code, as configurações `Systock`, `Systock (profile mode)` e `Systock (release mode)` usam certificados diferentes conforme o modo selecionado; o SHA-1 correspondente deve estar registado.

O app solicita somente `drive.appdata`, portanto os pacotes ficam na pasta privada do aplicativo e não aparecem entre os ficheiros normais do utilizador. O macOS já inclui acesso de rede. No Runner local, o armazenamento usa o Keychain clássico para funcionar sem uma conta de assinatura Xcode. Para distribuir uma versão assinada, habilite Keychain Sharing no target Runner e use um grupo associado à equipa Apple da aplicação.

## Operação comercial de uma caixa por loja

Cada loja fica associada a uma conta Google e a uma época de caixa (`claim`). O primeiro computador que liga a loja recebe uma chave de recuperação de 256 bits; a chave não é guardada no banco nem enviada para o Drive. O proprietário deve guardá-la fora do computador. Uma instalação nova, sem dados, pode escolher a loja encontrada no Drive e restaurar a versão mais recente depois de introduzir a chave.

As cópias da loja são cifradas com AES-GCM antes do upload e incluem o SQLite, imagens e um fingerprint lógico. Cada cópia tem nome imutável; não existe um ficheiro `latest` que possa ser sobrescrito por uma caixa antiga. A transferência para outro computador cria uma nova época ligada à anterior. Em caso de duas transferências concorrentes, a sincronização é bloqueada para evitar escolher um vencedor automaticamente.

Em computadores desktop, o OAuth usa o navegador do sistema, redirect loopback local e PKCE. O client id instalado deve ser fornecido no build sem entrar no repositório:

`flutter run -d macos --dart-define=GOOGLE_DESKTOP_CLIENT_ID=CLIENT_ID.apps.googleusercontent.com`

Alguns clientes OAuth desktop criados no Google Cloud exigem também o segredo apresentado no JSON das credenciais. Nesse caso, o ficheiro local de defines deve conter ambos os valores (não publique esse ficheiro):

```json
{
  "GOOGLE_DESKTOP_CLIENT_ID": "CLIENT_ID.apps.googleusercontent.com",
  "GOOGLE_DESKTOP_CLIENT_SECRET": "CLIENT_SECRET"
}
```

Execute com `flutter run -d macos --dart-define-from-file=defines.json`.

O processo automático tenta sincronizar a cada dois minutos e ao retomar a aplicação. Uma falha de rede deixa as vendas locais intactas e tenta novamente mais tarde. Antes da distribuição comercial, publique o consentimento OAuth e conclua a verificação aplicável; o fluxo instalado não deve conter segredos de servidor.
