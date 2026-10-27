# ENEMIZADES Orbit — testes online 0.2

Site: https://pkuai.github.io/enemizadesorbit/
Supabase de testes: `rpmgilawltgekecudeqx`. Não usa o projeto antigo.

## Recursos conectados

- Login com lista de participantes autorizados. Administração em **Meu perfil → Administração**.
- 178 questões únicas de 2023 importadas da API ENEM, quatro áreas, filtros de não respondidas/erros/favoritas. Esse acervo não é anunciado como uma prova completa; a fonte retornou duplicatas e lacunas.
- Correção no servidor, primeira tentativa do banco imutável, gabaritos separados dos dados de questões.
- Questões: acerto 15 XP/10 PR-base; erro 10 XP/5 PR-base. Freio de aproveitamento só nas questões, não em leitura/flashcards. Pomodoro sem PR.
- XP permanente, níveis, PR, atos bimestrais, patentes, Sinapse por tempo decorrido e conquistas.
- Perfis, foto, biografia, privacidade do histórico, ranking.
- Tarefas com meta, progresso, prioridade, ordem e recorrência por intervalo ou dias da semana. Redações privadas salvas manualmente.
- Flashcards próprios e intervalo de revisão: 6 XP por cartão até 100/dia; PR bruto 3 nos primeiros 20, 2 nos próximos 20, 1 até o centésimo. Cada cartão é remunerado uma vez por dia. Registro de tempo para leitura, revisão e Pomodoro.
- Biblioteca e trilhas administráveis: texto, links HTTPS para PDF/vídeo, progresso, anotações, trechos destacados, coleções, lista/grade e avaliação de utilidade.
- Questões em branco nas provas não concedem XP, PR nem Sinapse.
- Simulados e Coliseu individual com até oito participantes: convites, aceite/recusa, sala de espera, questões e prazo comuns, respostas persistentes, correção após encerramento, classificação por acertos/tempo.
- Ilha dinâmica: contador de conexões por navegador com atividade nos últimos 90 segundos, não uma identificação física de dispositivos; Pomodoro ativo ou pausado tem prioridade na forma compacta.
- Sessões com horários gerados no servidor e expiração de 30 minutos, metas pessoais e coletivas.
- Chat geral, de sala e de aliança: até 30 mensagens do dia por canal, exclusão e denúncias. Atualização por consulta a cada oito segundos; não depende de Realtime.
- Uma aliança por usuário, liderança, remoção/transferência, PR semanal e permanente atribuído à aliança no momento da conquista.
- Questões externas com comprovante privado e aprovação administrativa antes de conceder recompensa.
- Temas, densidade, negrito, movimento reduzido, foco e calculadora SISU preservados. Ilha sem participantes fictícios e sem reconstrução periódica dos elementos inalterados.

## Limites explícitos desta entrega

Não é uma declaração de conclusão de todas as ideias históricas. IA e TRI calibrada não estão habilitadas. Biblioteca/trilhas começam sem acervo editorial: o administrador publica os materiais. Vídeo requer URL reproduzível no navegador; PDF abre no leitor do navegador (não há editor de anotações sobre a página do PDF). Destaques e progresso são salvos pelo usuário.

Duelo entre alianças, PR por diferença de desempenho, WO específico de 30 minutos, ligas competitivas separadas, cronômetro sincronizado entre dispositivos, média de tempo por questão e movimentação por arrastar ainda não foram implementados. O Coliseu desta entrega é individual, com prazo configurável. Esses limites não são ocultados por dados simulados.

Configuração provisória: limiares de teste das patentes 2.000/7.000 PR, multiplicador de Coliseu 2, leitura 2 XP e 1 PR por minuto ativo completo; foco 2 XP e zero PR por minuto ativo completo. Astralita requer 12.000 PR no ato. XP de nível N: `5N²+15N`, até nível 100. Sinapse: +1 por questão válida, teto 100, decaimento `S*exp(-.075*d)/(1+(.0052/.075)*S*(1-exp(-.075*d)))`.

O registro de tempo exige início/encerramento explícitos; conta apenas sinais periódicos enquanto a aba está visível. Não é uma medição de atenção humana. Preferências visuais permanecem locais ao navegador.

## Dados e autorização

Nenhum reset foi realizado. Os dados anteriores foram preservados. O usuário administrador inicial é a única conta que estava autorizada na implantação. Novas contas são criadas em Supabase → Authentication → Users; libere-as em Meu perfil → Administração. Não há cadastro aberto na interface nem recuperação por e-mail configurada.

Somente a chave pública aparece no cliente. RLS protege documentos privados, respostas e comprovantes. Chamadas de recompensa exigem participação autorizada; funções internas de pontuação não têm permissão de execução para o cliente. Uploads: bucket privado, 5 MB, formatos limitados.

O reset pré-lançamento é uma operação futura, separada: exportar backup, conferir restauração, definir o que preservar (acervo/configuração/admin), então limpar apenas os dados de testes explicitamente aprovados. Não há botão destrutivo de reset geral nesta versão. Exportação administrativa disponível em Meu perfil → Administração; inclui dados das tabelas do aplicativo, sem senhas, arquivos do Storage ou configuração de Auth. Backup automático diário e restauração ainda pendentes.

## Arquivos e publicação

- `index.html`: base visual original e utilidades locais. `assets/online.js`: autenticação, banco e ilha. `assets/features.js`: módulos online. `assets/features.css`: ajustes responsivos.
- Migrações já aplicadas, na ordem: `schema.sql`, `expansion.sql`, `flows.sql`, `session_clock.sql`, `scoring.sql`, `confirmed_rules.sql`, `device_presence.sql`. Não reexecutar as migrações com CREATE TABLE no mesmo projeto.
- `seed.sql` e `bank_2023.sql`: importações idempotentes de questões. Alternativas não contêm `isCorrect`.
- GitHub Pages publica a raiz da branch `main`. Assets possuem versão na URL para evitar mistura de versões em cache.
- supabase-js 2.102.0 vendorizado, licença MIT em `assets/SUPABASE-LICENSE`.

## Validação

`tests/database.sql`: cenários transacionais com duas contas temporárias e uma não autorizada; rollback final. Verifica isolamento, bloqueio de edição alheia, correção, idempotência, liderança, chats, partida com duas pessoas, ocultação do gabarito, aprovação de registros externos e acesso administrativo.

`tests/ui.cjs`: JSDOM 26, teste de 19 rotas, login, resposta, tarefa, redação, escape de conteúdo, chat, prioridade e estabilidade da ilha, contador de Orbes, fotos e patentes no ranking, leitor e administração. Execute com Node e jsdom disponível; `JSDOM_PATH` pode apontar para a instalação.

Os testes automatizados não substituem verificação visual em navegador real e uso simultâneo por testadores. A instalação do navegador automatizado não estava disponível no ambiente de implementação. O advisor do Supabase apontou proteção contra senhas vazadas desativada, uma configuração de Auth: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection.
