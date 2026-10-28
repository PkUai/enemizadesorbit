# ENEMIZADES Orbit 0.4 — atualização preparada

Esta entrega restaura a organização visual da captura enviada e implementa as decisões recuperadas de “Corrigir versão online”, incluindo os três ajustes adicionais de primeiro acesso e alternativas.

## Interface

- Visão geral: card principal, Questões hoje, Aproveitamento, Tempo de estudo, Pontuação, plano, atalhos, Coliseu, participantes e ranking, usando dados da conta.
- Cards principais nas abas Coliseu, Sinapse e Alianças; plano manual personalizável. Redação e “Meu Norte” removidos da navegação.
- Opções apenas no topo, com paletas visíveis e sem seletor Clássico/Orbit/Pulse/Aura.
- Sessões de Estudo com contagem de presentes, sem chat de sala. Comunidade, Aliança e Mensagens Diretas em página completa; atalho lateral em telas largas.
- Resultados ocupam a tela, sem moldura nem Repetir. Cálculo de PR expansível; símbolos oficiais e Sinapse em tons quentes preservados.
- Novo cadastro: solicitação de apelido no primeiro acesso; contas existentes mantêm o nome.
- Banco e Coliseu: riscar/restaurar alternativas antes de confirmar.
- Coliseu: selecionar e confirmar não avança; Próxima questão avança explicitamente; Questão anterior permite rever sem reiniciar prazo. Encerrar participação removido. Concluir prova aparece na última questão.

## Economia e resultados

- Pomodoro: 1 Orbe por bloco completo de 5 minutos rodados; crédito no encerramento, sem PR.
- Banco: Q × (0,8 + 0,2 × acertos/Q), mais 1 Orbe por 5 minutos ativos, limitado a 20% da base; crédito ao concluir a atividade/sessão. Valores fracionários preservados com duas casas, sem arredondar cada questão isolada.
- Externas: mesma base sem bônus de tempo, após validação.
- Comet: 6 por participação concluída + 2 quando há vitória; Diário: 20 + 8. Flashcards: zero Orbes.
- Trilhas/Biblioteca: valor configurável por conteúdo, sem valor padrão inventado; concessão única na conclusão registrada.
- Cartões PR: 60/110/180 Orbes; XP: 50/90/150; durações 15/30/60 min; +25% no recurso correspondente. Compra com identificador idempotente, ativação única no Inventário, tempo corrido e consumo de 30s por questão em lote/correção. Um cartão ativo por recurso; XP e PR podem coexistir. Penalidades não recebem bônus.
- Loja no contador de Orbes; Inventário lateral. Fundos e demais itens têm espaço reservado, sem catálogo ou preços fictícios.
- Progresso e recompensas competitivas ficam pendentes até visualizar o resultado. Rotina de manutenção aplica resultados não vistos após 48h, uma vez, e remove o aviso. Repetir a consulta não duplica saldo.
- Duelo Diário: 8 horas para iniciar após os aceites; esse limite não encerra quem já começou. Os prazos individuais por questão continuam valendo.

## Validação e publicação

Os testes de DOM cobrem 21 rotas, primeiro acesso/apelido, alternativas riscadas, confirmação separada de avanço, retorno à questão anterior, cards, temas, escape de conteúdo e recibos. A migração foi executada em um PostgreSQL local isolado (PGlite), recriado a partir dos metadados do esquema atual, com fixtures e rollback. Foram testados saldo, compra idempotente, bônus, consumo por lote, fórmula agregada, Pomodoro, resgates, aplicação após 48h, prazo do Diário e isolamento das mensagens diretas.

A rotina de manutenção foi testada por chamada direta local. A instalação de pg_cron foi confirmada no destino. O comportamento visual em navegador não foi verificado nesta sessão.

**Autorização e aplicação:** o proprietário autorizou explicitamente a migração e a publicação. A migração foi aplicada em 28/10/2026; testes SQL com fixtures e rollback passaram no Supabase de destino. A rotina `orbit-results-04` está ativa, com execução a cada minuto. As tabelas privadas de economia permanecem inacessíveis diretamente aos clientes, intencionalmente sem políticas permissivas. O único alerta de segurança do Auth é a proteção contra senhas vazadas desativada, configuração anterior não alterada por esta entrega.

## Limites preservados

Guerra de Alianças, empates exatos e W.O. Diário continuam com regras pendentes; não foram inventadas fórmulas. O piloto continua limitado à mesma patente. Não foi definida uma nova fórmula de Orbes para Simulados. O bônus de XP/PR e os recibos existentes de simulados foram preservados; o cartão pode ser ativado antes da correção final. IA, catálogo de fundos e outros recursos sem regras/conteúdo aprovados não foram simulados.
