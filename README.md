# ENEMIZADES Orbit — versão 0.4

Restauração dos cards Orbit, primeiro acesso com apelido, alternativas riscáveis, confirmação e navegação separadas no Coliseu, chat em página completa, loja e inventário, Orbes e resultados competitivos pendentes.

Veja [mudanças, regras, limites e validação](UPDATE-0.4.md).

## Estado da entrega

Migração 0.4 aplicada no Supabase em 28/10/2026 após autorização do proprietário. Os testes SQL passaram também no ambiente de destino usando fixtures com rollback, sem alterar dados de participantes. A manutenção automática está agendada a cada minuto.

`index.html` e toda a pasta `assets/` compõem o frontend. Não executar novamente `database/update04.sql`, seeds ou migrações antigas neste ambiente.

## Testes

```sh
npm ci
npm test
```

Testes de interface usam JSDOM. Testes SQL usam PostgreSQL local isolado via PGlite, metadados de esquema sem dados pessoais, fixtures e rollback. O agendamento de pg_cron foi confirmado no ambiente de destino. A apresentação visual em navegador não foi revalidada nesta sessão.

A [auditoria anterior](AUDIT.md) e o [roteiro 0.3](TESTING.md) foram preservados como registros históricos.
