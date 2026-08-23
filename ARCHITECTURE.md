# Arquitetura

Systock é local-first: UI → presentation (Riverpod) → application/use cases → domain → repository → fontes local/remota. SQLite/Drift é a única fonte de verdade operacional. Google Drive é transporte assíncrono de eventos e backups, nunca requisito para vender.

O código é feature-first; cada módulo cresce em `domain`, `application`, `data` e `presentation` apenas quando necessário. Valores monetários são inteiros na menor unidade e quantidades usam milésimos, evitando `double`. Entidades sincronizáveis usam UUID/ULID, versão, device ID e soft delete. Vendas, pagamentos e movimentos são eventos imutáveis.

## Fronteiras

- Widgets renderizam estado e despacham intenções.
- Use cases aplicam autorização e regras.
- Repositórios traduzem falhas técnicas para `Result<T>`.
- Escritas críticas agrupam documento, itens, pagamentos, movimentos, auditoria e outbox numa transação.
- Adapters isolam Drive, impressão, scanner, armazenamento seguro e conectividade.

## Roadmap

1. Fundação: shell, tema, Drift, Result, logging, router, CI e migrations.
2. Cadastros e onboarding.
3. ledger de stock, contagem e transferências.
4. compras e recebimentos.
5. vendas/POS, caixa, pagamentos e devoluções.
6. scanner, barcode e impressão.
7. relatórios/exportação.
8. backup e sync Drive.
9. RBAC, PIN, biometria e auditoria completa.
10. QA, performance e hardening.
