# ENEMIZADES Orbit — testes online 0.3

Atualização incremental sobre `a59002c` de `PkUai/enemizadesorbit`. A estrutura da Visão Geral e os componentes Orbit foram preservados.

- [Relatório completo, inventário e pendências](AUDIT.md).
- [Roteiro dos testadores e validação automatizada](TESTING.md).
- [Upgrade SQL consolidado da versão 0.2](database/upgrade_from_0_2.sql).

O banco novo `rpmgilawltgekecudeqx` já recebeu as migrações desta entrega. **Não execute novamente o upgrade nele.** Nenhum ambiente antigo foi alterado. Dados dos dois testadores foram preservados: 2 perfis, 7 tentativas e 11 eventos existentes ao concluir a validação.

O frontend depende de `index.html` e da pasta `assets/` completa. Publique ambos na raiz do mesmo GitHub Pages. A URL de OAuth no cliente é `https://pkuai.github.io/enemizadesorbit/`. Abrir o HTML isolado sem seus arquivos auxiliares não representa a instalação online.

Não é uma declaração de implementação integral de todas as rodadas históricas. Orbes, regras competitivas não confirmadas, Guerras, leitor completo de PDF, push, backup automático/restauração e demais limites estão discriminados no relatório.

## Arquivos

`index.html` conserva o shell visual. `assets/online.js` e `assets/features.js` mantêm as integrações existentes. `assets/revision.js` acrescenta sincronização, preferências, pesquisa, OAuth, recibos e o novo fluxo competitivo. `assets/reward-frame.html` integra o popup aprovado com valores recebidos do servidor. A biblioteca Supabase 2.102.0 e sua licença MIT continuam vendorizadas.

O SQL consolidado destina-se exclusivamente ao esquema original 0.2 do projeto novo. Os demais SQL desta atualização registram as etapas aplicadas e correções; não são um instalador para executar indiscriminadamente. Seeds de questões e migrações antigas não devem ser reexecutados.

## Verificação

Os testes SQL usam fixtures e `ROLLBACK`. Um teste concorrente adicional confirmou uma tentativa, um evento e 15 XP para duas submissões simultâneas; sua conta temporária foi removida.

```bash
JSDOM_PATH=/caminho/node_modules/jsdom node tests/ui.cjs
JSDOM_PATH=/caminho/node_modules/jsdom node tests/reward-frame.cjs
```

JSDOM 26 verifica comportamento e DOM; não substitui testes visuais em navegador nem login real com Google. Os arquivos `tests/database.sql`, `tests/revision.sql` e `tests/presence.sql` foram executados no projeto novo.
