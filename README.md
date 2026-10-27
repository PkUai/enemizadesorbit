# ENEMIZADES Orbit — piloto online 0.1

Base visual: Ilha Dinâmica. Ambiente Supabase: `rpmgilawltgekecudeqx`.

## Funciona nesta etapa
- Login por e-mail e senha com Supabase Auth.
- Acesso ao banco restrito aos participantes autorizados.
- 20 questões reais do ENEM 2023, importadas da API ENEM (https://enem.dev).
- Correção no servidor; primeira resposta imutável, sem duplicação de pontos.
- Histórico e nome de perfil salvos na conta.
- Sessões com lista atualizada a cada 30 segundos e expiração visual após 30 minutos sem atividade.
- Opções de interface e Pomodoro local.

Os demais módulos são identificados como ainda não integrados. Não há IA conectada. Os pontos são de teste, não implementam patentes, PR nem temporadas definitivas.

## Publicar
GitHub → Settings → Pages → Deploy from a branch → main → / (root) → Save.
Endereço esperado: https://pkuai.github.io/enemizadesorbit/.

## Criar a primeira conta
No projeto novo do Supabase: Authentication → Users → Add user → Create new user. Defina seu e-mail e senha e confirme o e-mail manualmente para o piloto. Não compartilhe a senha no chat.
Em seguida, autorize SOMENTE o e-mail dessa conta pelo SQL Editor:
```sql
insert into orbit_private.pilot_members(user_id)
select id from auth.users where email = 'SEU_EMAIL_AQUI'
on conflict do nothing;
```
A tela não oferece cadastro aberto. Mesmo que alguém use diretamente a API de cadastro, o banco continua restrito à lista de participantes. Cadastro por e-mail e recuperação de senha não fazem parte desta etapa; configure SMTP e redirects antes de disponibilizá-los.

## Banco
`database/schema.sql` documenta a estrutura JÁ APLICADA. Não execute novamente no mesmo projeto. `database/seed.sql` documenta a importação inicial. Gabaritos são públicos na fonte original, mas não são entregues pelo aplicativo antes da resposta. Nenhuma chave privilegiada é incluída.

## Verificação
Testes transacionais no banco: correção, idempotência, criação de sessão, isolamento e bloqueio de escrita direta. Consultoria de segurança do Supabase sem alertas. Testes de interface com DOM simulado passaram para login, carregamento, questões, resposta, perfil e sessões, sem erros de execução. A verificação visual automatizada ficou pendente porque o navegador de testes não pôde ser instalado neste ambiente. Login com conta real e sincronização entre dispositivos requerem a criação da primeira conta pelo administrador.

Dependência: supabase-js 2.102.0 (MIT), distribuída localmente em assets/supabase.min.js. Fonte: https://github.com/supabase/supabase-js.
