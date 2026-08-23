# Segurança

OAuth é opcional e pede somente o scope de ficheiros da aplicação no Drive. Credenciais sensíveis usam Keystore/Keychain/Credential Manager e nunca entram no SQLite ou nos logs. Device ID é UUID aleatório da instalação. O serviço de autorização resolve permissões RBAC diretamente das relações utilizador→perfil→permissão. PIN usa PBKDF2-HMAC-SHA256 com salt aleatório e comparação constante; biometria delega ao sistema operativo. Logs não incluem tokens ou PINs.

Restauração, desconexão, cancelamento e devolução exigem confirmação e preservam dados/auditoria. Desconectar revoga a sessão Google, para a sincronização e mantém o banco local.
