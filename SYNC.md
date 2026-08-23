# Sincronização e conflitos

Alterações sincronizáveis gravam uma operação outbox com `operation_id`, entidade, versão, payload canónico e SHA-256. O adaptador atual grava operações imutáveis individuais no `appDataFolder`, verifica existência antes de upload, pagina downloads e aplica retry exponencial. `applied_operations` torna a aplicação idempotente; pacotes agregados/comprimidos podem ser introduzidos sem mudar o contrato.

Fluxo: escrever SQLite → enfileirar outbox na mesma transação → continuar offline → verificar Internet real → publicar pacotes → ler manifestos remotos → validar checksum/schema → deduplicar → aplicar numa transação → atualizar cursores. Falha remota nunca reverte escrita local nem bloqueia operações.

Campos simples usam versão e LWW determinístico (`updated_at`, depois `device_id`) quando seguro. Edições concorrentes relevantes criam `sync_conflicts` e preservam ambos os payloads. Vendas, pagamentos, compras e stock não usam LWW: eventos imutáveis coexistem; cancelamentos são novos eventos compensatórios. O saldo é recalculado após importar movimentos.

Backup é separado: snapshot SQLite consistente via `VACUUM INTO`, manifesto com schema/tamanho/checksum e histórico local. Restore valida checksum e `integrity_check`, salva o estado atual e substitui de forma atómica. Criptografia de backup não é ativada por padrão; quando configurada deverá usar uma biblioteca auditada e chave no armazenamento seguro.
