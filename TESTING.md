# Roteiro de testes — Orbit 0.3

Execute com duas contas autorizadas no piloto. Use registros pequenos e identificáveis. Não execute resets, seeds ou o upgrade SQL no banco que já recebeu as migrações.

| Teste | Passos | Resultado esperado |
|---|---|---|
| Login por e-mail | Entrar, recarregar e abrir outro navegador | Mesma conta, pontos e dados; sem duplicação. |
| Google | Entrar com o mesmo e-mail verificado da conta atual | Retorno ao GitHub Pages; mesmo identificador e pontuação. Registrar qualquer conta duplicada. |
| Vínculo Google | Entrar na conta existente e usar Conta → Vincular Google | Vínculo ao usuário atual. Se o servidor não permitir vínculo manual, deve exibir erro, sem migrar pontos. |
| Recuperação | Solicitar e-mail e seguir o link recebido | Retorno ao site correto e definição da senha; sem aparecer localhost. |
| Cadastro | Preencher as cinco etapas, fechar e retomar | Dados não secretos retomados; senha precisa ser reinformada após recarregar. Acesso depende da autorização administrativa. |
| Logout | Sair localmente; depois testar saída global | Saída local afeta o navegador atual; global impede renovação das demais sessões. Considerar expiração dos tokens de acesso. |
| Preferências | Mudar tema, negrito e densidade em um aparelho | Outro aparelho atualiza via Realtime/fallback; as preferências persistem após recarregar. |
| Ranking simultâneo | Conta A responde uma questão; B acompanha ranking | PR/XP/nível/Sinapse atualizam sem recarregar, normalmente pelo Realtime; fallback em até um ciclo de 10s mais rede. |
| Sessões | A entra/troca/sai de sala; B observa a ilha | Contagem e participantes correspondem às sessões reais. Correção não deve ser tratada como Banco. |
| Conexões | Abrir a conta em dois navegadores independentes | A lista de conexões mostra os dois sinais recentes. Duas abas do mesmo navegador compartilham o identificador. |
| XP | Atingir exatamente um limiar de nível | Barra começa em zero no nível novo; XP acumulado permanece separado. Nível máximo não divide por zero. |
| Repetição de resposta | Responder, recarregar, tentar repetir | Uma tentativa e uma recompensa por questão no Banco. |
| Dicas | Admin adiciona até três dicas sem gabarito; jogador abre a questão | Dicas aparecem progressivamente; explicação só fica disponível após responder. |
| Foto | Enviar foto/GIF, ajustar recorte, testar ranking/perfil | Proporção quadrada; enquadramento persiste; Ocultar fotos remove as imagens da interface. |
| Pesquisa | Buscar nome de jogador, material, tarefa e questão | Nome/foto/patente/nível corretos; perfil público abre; não expõe documentos privados de outro jogador. |
| Popup da sessão | Responder e encerrar manualmente a sala | Ganhos reais; PR expansível; Sinapse quente; claro/escuro legíveis; repetir não altera saldos. |
| Externas | Enviar lote e repetir o envio da mesma janela após erro de rede | Mesmo request ID não cria outro registro. Antes da aprovação, nenhum ganho. Após aprovação, recibo real e somente uma recompensa. |
| Comet B | Criar com rival de mesma patente; ambos aceitar | 6 questões; janela 48h; cada jogador inicia no próprio momento. |
| Tempo Comet | Iniciar, fechar/recarregar a página e voltar | Prazo da questão não reinicia. Não há pausa voluntária. |
| Comet assíncrono | A conclui antes de B | A recebe XP; participação individual termina; a partida continua aguardando B. PR competitivo só após resultado. |
| Resultado | A e B terminam com desempenho diferente | Vitória/derrota, PR correto e XP normal para ambos; finalizar novamente não concede nada. |
| W.O. Comet | Teste controlado de prazo, sem editar o relógio do cliente | Prazo conferido no servidor; 1×1 segue 75%/−50; repetição não duplica penalidade. Evitar esperar 48h sem planejar teste administrativo controlado. |
| Comet A | Tentar criar antes de revisar oito curtas | Erro explícito de acervo; não substitui por questões longas. Após curadoria, 8×60s. |
| Diários | Tentar criar sem confirmar prazo pós-aceite | Bloqueio explícito. Depois da regra configurada: 24×90s, convites 36h, limites diários e recusas. |
| Casos pendentes | Empate exato ou W.O. dos Diários | PR fica pendente, sem valor inventado; XP das respostas continua registrado. |
| Meu Norte | Progredir parcialmente uma tarefa; propor reagendamento | Progresso persiste; datas só mudam depois de Aprovar. IA não produz conteúdo. |
| Vídeo | Alterar velocidade, pausar e reabrir | Posição salva e retomada; velocidade escolhida é persistida no registro. |
| Segurança | Usar conta comum para tentar revisar questões/administrar | Operação bloqueada no servidor. Não basta esconder botão. |
| Mobile e acessibilidade | Testar 360/390/768px, teclado e reduzir movimento | Sem ícones deformados ou sobreposição entre cronômetro/participantes; controles acessíveis. Anotar falhas visuais. |

## Verificações automatizadas executadas

- `tests/database.sql`: isolamento, correção, idempotência, permissões de aliança/admin, chat, externas e faixas/teto de flashcards.
- `tests/revision.sql`: preferências/RLS, aceites, estado individual, relógio, resposta repetida, XP/PR, recibos privados, limites, expiração, W.O., dicas/explicações e queda de uma patente por Ato.
- `tests/presence.sql`: conexões e autorização.
- `tests/ui.cjs`: 19 rotas, persistência de tarefas/redações, XSS, pesquisa de jogadores, opções, barra de XP, payload Google/redirect, estabilidade da ilha e criação do popup sem recompensa.
- `tests/reward-frame.cjs`: valores reais, Orbes desconhecidos, tema claro, movimento reduzido, seta do PR, repetição e escape de conteúdo.
- Duas chamadas SQL concorrentes para a mesma resposta: resultado de 1 tentativa, 1 evento e 15 XP. Conta temporária removida.
- Pós-publicação: página pública de login conferida visualmente em Chrome; Google, cadastro e recuperação presentes, sem erros do aplicativo nos logs.
- Advisor de segurança: apenas o aviso de proteção contra senhas vazadas desabilitada, já existente.

Não foram realizados: login real com credenciais, OAuth completo, entrega de e-mails, inspeção visual das áreas autenticadas e do layout mobile, sincronização ponta a ponta em aparelhos físicos, teste prolongado de reconexão Realtime e carga em escala. Esses itens permanecem na lista dos testadores.
