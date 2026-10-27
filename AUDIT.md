# Auditoria ENEMIZADES Orbit — 27/10/2026

Esta entrega conserva o site existente e implementa uma atualização funcional parcial do escopo integral solicitado. Recursos pendentes não são apresentados como concluídos.

## Fontes e integridade

Base: repositório `PkUai/enemizadesorbit`, commit `a59002c1562791e599e83cd8a4b9c25331da1df7`. Os anexos `enemizades-simbolos-orbit.html` e `enemizades-popup-recompensas-temas.html` foram lidos diretamente. O popup foi derivado da referência; seus valores ilustrativos foram removidos. Os desenhos oficiais de PR, XP, Sinapse, Orbes e das quatro patentes continuam incorporados ao site.

O mecanismo de recuperação de conversas antigas retornou indisponibilidade. Foram usadas as decisões fornecidas nesta conversa e o código/SQL atuais. Não foi possível recuperar integralmente todas as rodadas; essa parte da auditoria permanece incompleta.

O Supabase novo foi confirmado por nome e identificador: `enemizades`, `rpmgilawltgekecudeqx`. O antigo não foi acessado nem alterado. Foram inspecionadas tabelas, funções, triggers, políticas e a publicação Realtime. Não houve reset nem recálculo de recompensas históricas nesta execução.

Após testes: os registros originais continuam em 2 perfis, 7 tentativas e 11 eventos. Fixtures transacionais foram revertidas; uma conta criada exclusivamente para o teste concorrente foi removida.

## Inventário antes e depois

| Área | Situação inicial identificada | Entrega e limites |
|---|---|---|
| Visão Geral | Shell Orbit, cards e navegação existentes | Estrutura mantida; barra de XP corrigida e ganhos históricos preservados. |
| Ícones e fotos | Marca 37×40; controles sujeitos a compressão; foto com recorte fixo | Marca 1:1, SVGs sem compressão, fotos quadradas e ajuste vertical de enquadramento salvo no perfil. Validação visual real pendente. |
| Ilha Dinâmica | Sessões em polling de 30s; Pomodoro local; contador de navegadores | Atualização por sinal Realtime e fallback de 10s; novas salas do Coliseu aparecem; hover imediato; controles sem compressão em telas pequenas. Pomodoro continua local, sem retomada/sincronização do cronômetro entre aparelhos. |
| Ranking | Atualizava apenas por carregamento/ações locais | Realtime por invalidação, atualização de estatísticas a cada 10s, perfis, fotos, símbolos e variação de posições observada nesta sessão. A opção de ocultar a variação é persistida. |
| Pesquisa | Apenas atalhos de páginas | Jogadores com foto/patente/nível e perfil público, materiais, tarefas privadas, questões e recursos existentes; estados de busca, vazio e erro. Pesquisa sobre o acervo carregado, sem índice global paginado. |
| Opções | Interface local | Grupos Preferências, Estudos e Conta; pesquisa por categoria; alterações por chave salvas no servidor, RLS e sincronização. Algumas preferências dependentes de serviços continuam parciais, conforme abaixo. |
| Interfaces | Orbit existente | Orbit preservada; variações básicas Clássico/Pulse/Aura disponíveis. Não equivalem à implementação integral de desenhos aprovados dessas interfaces: faltam referências completas. |
| Temas | 11 temas existentes | Preservados. Não foi inventado um novo Creme Escuro para substituir um desenho ausente. |
| Animações | ZenB e Ilha existentes | ZenB mantém escala/desfoque/continuidade, com saída de 170→290ms e entrada de 310→440ms; intensidade e movimento reduzido respeitados. Ilha mantida. |
| XP | Barra dividia XP total pelo próximo limiar | Progresso `(XP − XP(N)) / (XP(N+1) − XP(N))`, com acumulado separado e nível 100 tratado como máximo. |
| Pontuação | Correção/recompensas no PostgreSQL, referências únicas | Mantidas; recibos novos armazenam base, freio, multiplicador e resultado. Nenhuma recompensa concedida pelo popup ou pelo navegador. |
| Sinapse | Fórmula instalada, +1 por questão e decaimento temporal | Preservada; ganho do evento registrado no recibo. A correspondência com toda a fórmula histórica aprovada ainda precisa ser confirmada. |
| Patentes | Quatro símbolos; limites provisórios; queda de 2 divisões/Ato | Queda corrigida para 1 divisão/Ato. PR positivo ganho determina o Ato; perdas não reduzem esse acumulador. Calendário/limiares ainda parciais. |
| Orbes | Símbolo com saldo indisponível | Mantido `—`, sem emissão fictícia. Não existe regra de concessão confirmada no material disponível. |
| Comet B | Partida genérica com início comum | Novo fluxo assíncrono: 6 questões ENEM, 90s por questão, aceites, janela de 48h, início individual, retomada do estado e prazos no servidor. Piloto restringe confrontos à mesma patente. |
| Comet A | Não existia como modalidade própria | Motor 8 questões/60s implementado. Criação bloqueada até existirem 8 questões curtas revisadas, sem seleção automática por tamanho. Administração pode classificá-las. |
| Duelos Diários | Não existiam como modalidade própria | Motor 24/90s, convite 36h, 1 enviado/2 recebidos por dia e recusa obrigatória após duas recusas. Criação fica bloqueada até confirmar o prazo de participação após aceite; 48h não foi presumido como regra dos Diários. |
| Multiplayer | Prova genérica até 8 participantes | Novo motor com até 8, confrontos virtuais e média excluindo rivais ausentes. Resultados de casos sem regra confirmada ficam pendentes. |
| W.O. | Sem regras específicas aprovadas implementadas | Comet 1×1: 75% da base própria ao vencedor e −50 ao infrator; prazo validado no servidor. W.O. dos Diários e multiplayer com todos os rivais ausentes aguardam regra. Liquidação ocorre quando a partida é consultada, não por um job de fundo. |
| Popup | Apenas arquivo demonstrativo separado | Referência integrada com tema claro/escuro, Sinapse quente, seta no PR, progressão visual, repetição e recibos reais. Encerrar sessão com questões, concluir participação e registrar externas possuem apresentação. Externas pendentes mostram explicitamente zero concedido. |
| Histórico | Categorias e valores textuais simples | Categorias com ícones e símbolos oficiais dos ganhos; acesso ao recibo. Eventos antigos não ganham metadados reconstruídos artificialmente. |
| Banco | 178 questões de 2023; gabarito no servidor | Preservado. Dicas editoriais em até 3 níveis; explicação separada e liberada após resposta; revisão administrativa; prevenção de duplicação na interface e no banco. O acervo continua incompleto e sem curadoria de explicações em massa. |
| Autenticação | E-mail/senha e lista de testadores | Botão Google, vínculo à conta atual, recuperação, alteração de senha, cadastro em 5 etapas com rascunho sem senha, logout local/global. Google/e-mail habilitados confirmados pelo endpoint de Auth; fluxo real não testado com credenciais. |
| Meu Norte | Tela de IA indisponível; tarefas em outro módulo | Objetivo, cronograma, progresso, prioridades e proposta de reagendamento que só salva após aprovação. IA/chat inteligente permanecem desativados. |
| Biblioteca | Texto; links PDF; vídeos; progresso manual; coleções | Preservada; retomada, velocidade do vídeo, salvamento de posição a cada 10s/pausa e sugestões de materiais da mesma matéria. Leitor próprio de PDF ainda ausente. |
| Flashcards | Cartões e espaçamento existentes | Preservados; teto diário e idempotência testados. Não houve redesenho do algoritmo de repetição. |
| Trilhas | Materiais publicados como trilha e tempo genérico de leitura | Preservadas; interação obrigatória, mínimo de 50%, remuneração de repetição e regras específicas ainda não implementados. |
| Alianças | Criação, entrada, líder, transferência, chat e pontuação | Preservadas. Vice-lideranças, reservas, Guerras e PA não foram implementados nesta execução. |
| Notificações e sons | Feedback visual e chat | Preferências persistidas; aviso de novo nível e de aprovação externa; tons locais sintetizados provisórios. Push, som geral e pacotes oficiais permanecem pendentes. |
| Administração | Acesso e funções no servidor | Preservada; revisão editorial adicionada. Nenhuma autorização depende apenas de botão no cliente. |
| Backup/restauração | Exportação administrativa manual | Preservada, ainda parcial. Não há backup automático diário/30 dias nem restauração completa/seletiva. |

## Regras preservadas e lacunas

Questões do Banco/Externas continuam com 10 PR-base/15 XP por acerto e 5 PR-base/10 XP por erro. O freio `0,8 + 0,2A` usa o aproveitamento acumulado do jogador, como no servidor anterior. Isso precisa ser confirmado caso a decisão histórica pretendesse aproveitamento por lote/sessão. Leitura e flashcards não recebem esse freio; Pomodoro não recebe PR.

Os valores instalados de patentes continuam `[0, 2000, 7000, 12000]` e multiplicadores `[1, 0.9, 0.8, 0.7]`. O próprio banco já os marcava como provisórios. Não foram convertidos em regras definitivas por suposição.

O calendário existente calcula seis períodos bimestrais por ano. A memória disponível menciona quatro Atos de cerca de oito semanas; falta definir datas, intervalos e eventual período sem Ato. A queda máxima de uma divisão já foi corrigida, mas o calendário completo não foi inventado.

Sinapse instalada: `S*exp(-0.075*d)/(1+(0.0052/0.075)*S*(1-exp(-0.075*d)))`, com `d` em dias e ganho de uma unidade por questão válida. Foi testada a execução dessa fórmula, não uma confirmação de que ela reproduz toda a regra histórica, incluindo a referência a 48h.

Flashcards: 20×3 + 20×2 + 60×1 = **160 PR brutos**, embora o teto citado no planejamento seja 180. O teto de 180 não é atingível com as faixas fornecidas. As faixas foram preservadas, sem elevar valores silenciosamente.

No competitivo, o motor conserva a base 20/10 usada pelo Coliseu anterior, com freio e multiplicador inverso no servidor. A patente é registrada no convite para manter a base estável no piloto. Contra equivalente: vitória sem bônus e derrota em 30% da base efetiva do vencedor. Os ganhos de XP/Sinapse são registrados na conclusão individual; o PR é liquidado quando o resultado coletivo está determinado. Os dois recibos representam etapas distintas e não duplicam questões ou XP.

Faltam regras indispensáveis: bônus exato contra superior, definição de “muito inferior”, remuneração de empate exato, W.O. dos Diários, prazo de início/participação dos Diários após aceite e casos multiplayer sem nenhum rival válido. O motor restringe ou retém PR nesses casos. Em empate exato, o XP continua concedido. A interface informa a pendência.

Orbes não são creditados. `—` significa regra/saldo indisponível; não equivale a um saldo confirmado de zero.

## Segurança, sincronização e operação

A assinatura Realtime escuta somente uma tabela de invalidação sem dados pessoais. Os eventos de pontuação de outros jogadores não foram tornados públicos para atualizar o ranking. O cliente busca os dados autorizados e agrupa os sinais; há uma assinatura por instância, limpeza no logout e fallback de 10s. Abas ocultas suspendem o polling geral. Registros de presença continuam com sinais de 30s e expiração de 90s.

Preferências são atualizadas por chave no servidor, evitando substituir todo o documento ao alterar uma opção. Respostas, recibos, comprovantes e documentos privados conservam RLS. Explicações não são enviadas a jogadores comuns antes da resposta. Administradores podem acessá-las para revisão editorial.

Dados de recompensa são calculados no servidor. O cliente não tem permissão para editar o ledger. A API antiga não pode finalizar partidas do novo motor nem criar novos confrontos legados. Referências únicas, locks transacionais e chamadas idempotentes protegem pontuação e liquidação.

O desligamento global revoga as sessões de renovação do Supabase. Tokens de acesso já emitidos podem continuar válidos até expirar; não foi implantado um bloqueio adicional por `session_id` em todas as operações.

O advisor de segurança terminou com o aviso já existente de proteção contra senhas vazadas desabilitada. Verificar disponibilidade sem custo antes de habilitar: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection. Não foi alterado plano nem ativada cobrança.

O ranking ainda calcula estatísticas percorrendo o histórico no servidor. Para os dois testadores atuais, a atualização é pequena; a solução precisa de medição e possível agregação incremental antes de escalar a muitos jogadores.

## Dependências externas e testes pendentes

- Validar no Supabase a Site URL e a lista de redirects com `https://pkuai.github.io/enemizadesorbit/` e confirmar o callback Google `https://rpmgilawltgekecudeqx.supabase.co/auth/v1/callback` no projeto OAuth correspondente. O provedor está habilitado; a configuração completa não foi acessada por esta integração.
- Confirmar vínculo manual de identidades habilitado. Login com o mesmo e-mail verificado usa o vínculo automático do Supabase; e-mails diferentes devem ser vinculados a partir da conta existente. Não foi criada uma fusão manual de pontuações entre contas.
- Validar entrega dos e-mails de cadastro/recuperação e a política de reautenticação. A alteração por senha atual está implementada; contas sem senha usam recuperação. Reautenticação universal para toda ação sensível ainda não está pronta.
- Cadastrar testadores na autorização do piloto. O cadastro não concede acesso aos dados do site por si só.
- Revisar e marcar questões curtas para Comet A; publicar dicas/explicações e materiais reais.
- Fornecer as regras ausentes listadas acima e as referências completas das interfaces/pacotes sonoros.
- Implantar serviço de push, leitor PDF, backup/restauração e infraestrutura futura da IA. IA permanece bloqueada e sem chamadas pagas.
- Executar testes reais de Google/e-mail, dois dispositivos, queda de rede e layout mobile. O ambiente não dispunha de navegador Chromium utilizável; a tentativa de instalação falhou. JSDOM verificou lógica e DOM, sem comprovar pixels, recorte real da foto ou fluidez visual.

## Entrega

O pacote inclui HTML, assets, SQL, este relatório e roteiro de testes. As migrações já foram aplicadas ao Supabase novo. A publicação do frontend deve conservar a pasta `assets/` junto do HTML. O status de GitHub/PR e eventual publicação é informado na mensagem de entrega; a existência deste relatório, isoladamente, não significa que a branch principal já foi atualizada.
