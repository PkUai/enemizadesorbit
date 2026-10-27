begin;
create table orbit_private.admins(user_id uuid primary key references auth.users(id) on delete cascade);
alter table orbit_private.admins enable row level security;
create policy admin_self on orbit_private.admins for select to authenticated using(user_id=(select auth.uid()));
grant select on orbit_private.admins to authenticated;
-- Só inicializa o administrador se existe exatamente uma conta autorizada.
insert into orbit_private.admins select user_id from orbit_private.pilot_members where (select count(*) from orbit_private.pilot_members)=1;
create function public.orbit_is_admin() returns boolean language sql stable security invoker set search_path='' as $$select exists(select 1 from orbit_private.admins where user_id=(select auth.uid()))$$;
revoke all on function public.orbit_is_admin() from public,anon;grant execute on function public.orbit_is_admin() to authenticated;
create table public.orbit_config(id boolean primary key default true check(id), settings jsonb not null);
insert into public.orbit_config values(true,'{"rank_thresholds":[0,3000,7000,12000],"rank_multipliers":[1,0.9,0.8,0.7],"provisional_thresholds":true,"coliseum_factor":2,"reading_xp_per_minute":2,"reading_pr_per_minute":0.2,"provisional_activity_rewards":true,"enem_date":"2026-11-08"}');
alter table public.orbit_profiles add column avatar_path text,add column bio text not null default '' check(length(bio)<=500),add column public_history boolean not null default false;
create table public.orbit_documents(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,kind text not null check(kind in ('task','essay','flashcard','collection','progress','preferences','favorite','highlight')),title text not null default '' check(length(title)<=200),data jsonb not null default '{}' check(octet_length(data::text)<200000),updated_at timestamptz not null default now());
create index orbit_documents_owner_kind on public.orbit_documents(user_id,kind);
create table public.orbit_alliances(id uuid primary key default gen_random_uuid(),name text not null check(length(name) between 2 and 40),tag text not null unique check(length(tag) between 2 and 6),description text not null default '' check(length(description)<=500),leader uuid not null references auth.users(id),created_at timestamptz not null default now());
create index orbit_alliances_leader on public.orbit_alliances(leader);
create table public.orbit_alliance_members(user_id uuid primary key references auth.users(id) on delete cascade,alliance_id uuid not null references public.orbit_alliances(id) on delete cascade,joined_at timestamptz not null default now());
create index orbit_alliance_members_team on public.orbit_alliance_members(alliance_id);
create table public.orbit_messages(id bigint generated always as identity primary key,user_id uuid not null references auth.users(id) on delete cascade,channel text not null check(length(channel)<=80),body text not null check(length(body) between 1 and 1000),created_at timestamptz not null default now());
create index orbit_messages_channel_time on public.orbit_messages(channel,created_at desc);
create index orbit_messages_user_time on public.orbit_messages(user_id,created_at desc);
create table public.orbit_events(id bigint generated always as identity primary key,user_id uuid not null references auth.users(id) on delete cascade,ref text not null,kind text not null,correct integer not null default 0,wrong integer not null default 0,xp numeric not null default 0,pr numeric not null default 0,alliance_id uuid references public.orbit_alliances(id) on delete set null,seconds integer not null default 0,created_at timestamptz not null default now(),unique(user_id,ref));
create index orbit_events_user_time on public.orbit_events(user_id,created_at);
create index orbit_events_alliance on public.orbit_events(alliance_id,created_at);
create table public.orbit_achievements(user_id uuid not null references auth.users(id) on delete cascade,code text not null,earned_at timestamptz not null default now(),primary key(user_id,code));
create table public.orbit_external(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,source text not null check(length(source) between 1 and 200),correct integer not null check(correct between 0 and 10000),wrong integer not null check(wrong between 0 and 10000),proof_path text,status text not null default 'pending' check(status in ('pending','approved','rejected')),review_note text not null default '',created_at timestamptz not null default now());
create index orbit_external_user on public.orbit_external(user_id);
create table public.orbit_materials(id uuid primary key default gen_random_uuid(),title text not null,subject text not null default 'Geral',kind text not null check(kind in ('text','pdf','video','trail')),body text not null default '',url text,related_ids uuid[] not null default '{}',updated_at timestamptz not null default now());
create table public.orbit_material_votes(user_id uuid not null references auth.users(id) on delete cascade,material_id uuid not null references public.orbit_materials(id) on delete cascade,helpful boolean not null,primary key(user_id,material_id));
create index orbit_votes_material on public.orbit_material_votes(material_id);
create table public.orbit_runs(id uuid primary key default gen_random_uuid(),owner_id uuid not null references auth.users(id) on delete cascade,kind text not null check(kind in ('sim','match')),title text not null default '',question_ids text[] not null,seconds integer not null check(seconds between 60 and 21600),status text not null default 'waiting' check(status in ('waiting','active','finished','cancelled')),created_at timestamptz not null default now(),started_at timestamptz,ends_at timestamptz);
create index orbit_runs_owner on public.orbit_runs(owner_id);
create table public.orbit_run_players(run_id uuid not null references public.orbit_runs(id) on delete cascade,user_id uuid not null references auth.users(id) on delete cascade,status text not null default 'accepted' check(status in ('invited','accepted','declined','finished')),answers jsonb not null default '{}',correct integer,elapsed integer,finished_at timestamptz,primary key(run_id,user_id));
create index orbit_run_players_user on public.orbit_run_players(user_id);
create table public.orbit_study_blocks(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,kind text not null,started_at timestamptz not null default now(),last_seen timestamptz not null default now(),seconds integer not null default 0,finished boolean not null default false);
create index orbit_study_blocks_user on public.orbit_study_blocks(user_id);
alter table public.orbit_sessions add column options jsonb not null default '{}';
create table public.orbit_room_goals(room text primary key,goal integer not null check(goal between 1 and 100000),updated_at timestamptz not null default now());
create table public.orbit_reports(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,target text not null,reason text not null check(length(reason) between 3 and 1000),resolved boolean not null default false,created_at timestamptz not null default now());
create index orbit_reports_user on public.orbit_reports(user_id);
-- Exposição somente para participantes; dados pessoais mantêm isolamento.
do $$declare t text;begin
 foreach t in array array['orbit_config','orbit_documents','orbit_alliances','orbit_alliance_members','orbit_messages','orbit_events','orbit_achievements','orbit_external','orbit_materials','orbit_material_votes','orbit_runs','orbit_run_players','orbit_study_blocks','orbit_room_goals','orbit_reports'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 end loop;
 foreach t in array array['orbit_config','orbit_alliances','orbit_alliance_members','orbit_achievements','orbit_materials','orbit_material_votes','orbit_room_goals'] loop
 execute format('create policy member_read on public.%I for select to authenticated using((select public.orbit_is_member()))',t);
 end loop;
 foreach t in array array['orbit_documents','orbit_study_blocks'] loop
 execute format('create policy owner_read on public.%I for select to authenticated using(user_id=(select auth.uid()) and (select public.orbit_is_member()))',t);
 end loop;
 foreach t in array array['orbit_external','orbit_reports'] loop
 execute format('create policy owner_admin_read on public.%I for select to authenticated using((user_id=(select auth.uid()) or (select public.orbit_is_admin())) and (select public.orbit_is_member()))',t);
 end loop;
end $$;
create policy messages_read on public.orbit_messages for select to authenticated using((select public.orbit_is_member()) and (channel in ('geral','Banco de questões','Correção','Outro') or channel='alliance:'||(select alliance_id::text from public.orbit_alliance_members where user_id=(select auth.uid()))));
create policy events_read on public.orbit_events for select to authenticated using(user_id=(select auth.uid()) and (select public.orbit_is_member()));
-- Partidas só mostram respostas do próprio participante até terminar.
create policy runs_read on public.orbit_runs for select to authenticated using((select public.orbit_is_member()) and (kind='match' or owner_id=(select auth.uid())));
create policy players_read on public.orbit_run_players for select to authenticated using((select public.orbit_is_member()) and (user_id=(select auth.uid()) or exists(select 1 from public.orbit_runs r where r.id=run_id and r.status='finished')));
create function orbit_private.decay(s numeric,days numeric) returns numeric language sql immutable set search_path='' as $$select case when s<=0 then 0 else s*exp(-0.075*greatest(0,days))/(1+(0.0052/0.075)*s*(1-exp(-0.075*greatest(0,days)))) end$$;
create function orbit_private.stats(u uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare e record; s numeric:=0; best numeric:=0; last_at timestamptz; x numeric:=0;p numeric:=0;ap numeric:=0;c integer:=0;w integer:=0;secs integer:=0; tier integer:=0;prevact integer;act integer;actnow integer;cfg jsonb; thresholds jsonb;level integer;
begin
 select settings into cfg from public.orbit_config; thresholds:=cfg->'rank_thresholds';
 actnow:=extract(year from now() at time zone 'America/Fortaleza')::int*6+(extract(month from now() at time zone 'America/Fortaleza')::int-1)/2;
 for e in select * from public.orbit_events where user_id=u order by created_at,id loop
 act:=extract(year from e.created_at at time zone 'America/Fortaleza')::int*6+(extract(month from e.created_at at time zone 'America/Fortaleza')::int-1)/2;
 if prevact is not null and act<>prevact then tier:=greatest(0,tier-2*(act-prevact));ap:=0;end if;prevact:=act;
 ap:=ap+e.pr;for i in 0..3 loop if ap>=(thresholds->>i)::numeric then tier:=greatest(tier,i);end if;end loop;
 x:=x+e.xp;if extract(year from e.created_at at time zone 'America/Fortaleza')=extract(year from now() at time zone 'America/Fortaleza') then p:=p+e.pr;end if;
 c:=c+e.correct;w:=w+e.wrong;secs:=secs+e.seconds;
 if last_at is not null then s:=orbit_private.decay(s,extract(epoch from e.created_at-last_at)/86400);end if;
 s:=least(100,s+e.correct+e.wrong);best:=greatest(best,s);last_at:=e.created_at;
 end loop;
 if last_at is not null then s:=orbit_private.decay(s,extract(epoch from now()-last_at)/86400);end if;
 if prevact is not null and actnow<>prevact then tier:=greatest(0,tier-2*(actnow-prevact));ap:=0;end if;
 level:=least(100,greatest(0,floor((-15+sqrt(225+20*x))/10)::int));
 return jsonb_build_object('user_id',u,'xp',x,'pr',round(p,2),'act_pr',round(ap,2),'tier',tier,'level',level,'correct',c,'wrong',w,'synapse',round(s,2),'best_synapse',best,'seconds',secs);
end $$;
create function orbit_private.award(u uuid,refkey text,k text,c integer,w integer,x numeric,basepr numeric,sec integer default 0) returns void language plpgsql security definer set search_path='' as $$
declare st jsonb;cfg jsonb;factor numeric;team uuid;begin
 perform pg_advisory_xact_lock(hashtextextended(u::text,0));
 if exists(select 1 from public.orbit_events where user_id=u and ref=refkey) then return;end if;
 st:=orbit_private.stats(u);select settings into cfg from public.orbit_config;
 factor:=(0.8+0.2*((st->>'correct')::numeric+c)/greatest(1,(st->>'correct')::numeric+(st->>'wrong')::numeric+c+w))*(cfg->'rank_multipliers'->>((st->>'tier')::int))::numeric;
 select alliance_id into team from public.orbit_alliance_members where user_id=u;
 insert into public.orbit_events(user_id,ref,kind,correct,wrong,xp,pr,alliance_id,seconds) values(u,refkey,k,c,w,x,round(basepr*factor,2),team,sec);
 st:=orbit_private.stats(u);
 insert into public.orbit_achievements(user_id,code) select u,code from (values
 ('primeira_questao',((st->>'correct')::int+(st->>'wrong')::int)>=1),
 ('dias_luta_gloria',(st->>'correct')::int>=100 and (st->>'wrong')::int>=100),
 ('500_acertos',(st->>'correct')::int>=500),
 ('sinapse20',(st->>'best_synapse')::numeric>=20),('sinapse40',(st->>'best_synapse')::numeric>=40),('sinapse60',(st->>'best_synapse')::numeric>=60),('sinapse80',(st->>'best_synapse')::numeric>=80),('sobrecarga',(st->>'best_synapse')::numeric>=100),
 ('nivel10',(st->>'level')::int>=10),('nivel50',(st->>'level')::int>=50),('nivel100',(st->>'level')::int>=100),
 ('50_porcento',(select coalesce(sum(correct+wrong),0)>=45 from public.orbit_events where user_id=u and created_at>now()-interval '8 hours')),
 ('hahahahaha',(select coalesce(sum(correct+wrong),0)>=180 from public.orbit_events where user_id=u and created_at>now()-interval '24 hours'))
 ) a(code,unlocked) where unlocked on conflict do nothing;
end $$;
create function orbit_private.attempt_award() returns trigger language plpgsql security definer set search_path='' as $$begin
 perform orbit_private.award(new.user_id,'bank:'||new.question_id,'bank',case when new.is_correct then 1 else 0 end,case when new.is_correct then 0 else 1 end,new.points,new.points);return new;end$$;
create trigger orbit_attempt_award after insert on public.orbit_attempts for each row execute function orbit_private.attempt_award();
-- Migra progresso já existente, sem duplicar registros.
do $$declare a record;begin for a in select * from public.orbit_attempts order by answered_at loop perform orbit_private.award(a.user_id,'bank:'||a.question_id,'bank',case when a.is_correct then 1 else 0 end,case when a.is_correct then 0 else 1 end,a.points,a.points);update public.orbit_events set created_at=a.answered_at where user_id=a.user_id and ref='bank:'||a.question_id;end loop;end $$;
create function orbit_private.api(action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); idv uuid;rowv record;other record;rv public.orbit_runs;cfg jsonb;arr text[];result jsonb;ch text;team uuid;c integer;w integer;n integer;secs integer;ans jsonb;ids uuid[];
begin
 if u is null or not exists(select 1 from orbit_private.pilot_members where user_id=u) then raise exception 'Acesso restrito aos testadores';end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,1));
 select settings into cfg from public.orbit_config;
 case action
 when 'overview' then
 return jsonb_build_object('stats',orbit_private.stats(u),'admin',exists(select 1 from orbit_private.admins where user_id=u),'config',cfg,'ranks',(select coalesce(jsonb_agg(jsonb_build_object('profile',to_jsonb(pr),'stats',orbit_private.stats(pr.user_id))),'[]') from public.orbit_profiles pr join orbit_private.pilot_members pm on pm.user_id=pr.user_id),'alliance_scores',(select coalesce(jsonb_agg(t),'[]') from (select alliance_id,sum(pr) as pr,sum(xp) as xp,sum(correct+wrong) as questions,sum(pr) filter(where created_at>=date_trunc('week',now() at time zone 'America/Fortaleza') at time zone 'America/Fortaleza') as week_pr from public.orbit_events where alliance_id is not null group by alliance_id)t));
 when 'document_save' then
 if p->>'kind' not in ('task','essay','flashcard','collection','progress','preferences','favorite','highlight') then raise exception 'Tipo inválido';end if;
 idv:=coalesce((p->>'id')::uuid,gen_random_uuid());
 insert into public.orbit_documents(id,user_id,kind,title,data) values(idv,u,p->>'kind',coalesce(p->>'title',''),coalesce(p->'data','{}')) on conflict(id) do update set title=excluded.title,data=excluded.data,updated_at=now() where public.orbit_documents.user_id=u and public.orbit_documents.kind=excluded.kind;
 if not found then raise exception 'Documento indisponível';end if;return jsonb_build_object('id',idv);
 when 'document_delete' then delete from public.orbit_documents where id=(p->>'id')::uuid and user_id=u;return '{}';
 when 'chat_send' then
 ch:=p->>'channel';select alliance_id into team from public.orbit_alliance_members where user_id=u;
 if ch not in ('geral','Banco de questões','Correção','Outro') and (team is null or ch<>'alliance:'||team::text) then raise exception 'Canal indisponível';end if;
 if exists(select 1 from public.orbit_messages where user_id=u and created_at>now()-interval '2 seconds') then raise exception 'Aguarde dois segundos entre mensagens';end if;
 insert into public.orbit_messages(user_id,channel,body) values(u,ch,trim(p->>'body'));
 delete from public.orbit_messages where created_at<(now() at time zone 'America/Fortaleza')::date at time zone 'America/Fortaleza';
 delete from public.orbit_messages where channel=ch and id not in(select id from public.orbit_messages where channel=ch order by id desc limit 30);return '{}';
 when 'chat_delete' then delete from public.orbit_messages where id=(p->>'id')::bigint and (user_id=u or exists(select 1 from orbit_private.admins where user_id=u));return '{}';
 when 'alliance_create' then
 if exists(select 1 from public.orbit_alliance_members where user_id=u) then raise exception 'Saia da aliança atual primeiro';end if;
 insert into public.orbit_alliances(name,tag,description,leader) values(trim(p->>'name'),upper(trim(p->>'tag')),coalesce(p->>'description',''),u) returning id into idv;
 insert into public.orbit_alliance_members values(u,idv,now());return jsonb_build_object('id',idv);
 when 'alliance_join' then insert into public.orbit_alliance_members(user_id,alliance_id) values(u,(p->>'id')::uuid);return '{}';
 when 'alliance_leave' then
 if exists(select 1 from public.orbit_alliances where leader=u) then raise exception 'Transfira a liderança ou exclua sua aliança antes de sair';end if;
 delete from public.orbit_alliance_members where user_id=u;return '{}';
 when 'alliance_manage' then
 select * into rowv from public.orbit_alliances where id=(p->>'id')::uuid and leader=u for update;
 if not found then raise exception 'Apenas o líder pode realizar esta ação';end if;
 if p->>'operation'='delete' then delete from public.orbit_alliances where id=rowv.id;
 elsif p->>'operation'='transfer' then
 if not exists(select 1 from public.orbit_alliance_members where alliance_id=rowv.id and user_id=(p->>'user_id')::uuid) then raise exception 'Integrante inválido';end if;
 update public.orbit_alliances set leader=(p->>'user_id')::uuid where id=rowv.id;
 elsif p->>'operation'='remove' then delete from public.orbit_alliance_members where alliance_id=rowv.id and user_id=(p->>'user_id')::uuid and user_id<>u;end if;return '{}';
 when 'external_add' then
 c:=(p->>'correct')::int;w:=(p->>'wrong')::int;if c+w<1 then raise exception 'Informe ao menos uma questão';end if;
 insert into public.orbit_external(user_id,source,correct,wrong,proof_path) values(u,p->>'source',c,w,p->>'proof_path') returning id into idv;
 return jsonb_build_object('id',idv);
 when 'external_proof' then update public.orbit_external set proof_path=p->>'proof_path',status='pending' where id=(p->>'id')::uuid and user_id=u and status<>'approved';return '{}';
 when 'session_options' then update public.orbit_sessions set options=p->'options' where user_id=u;return '{}';
 when 'room_goal' then
 if not exists(select 1 from public.orbit_sessions where user_id=u and room=p->>'room') then raise exception 'Entre na sala primeiro';end if;
 insert into public.orbit_room_goals values(p->>'room',(p->>'goal')::int,now()) on conflict(room) do update set goal=excluded.goal,updated_at=now();return '{}';
 when 'study_start' then
 if p->>'kind' not in ('pomodoro','reading','flashcards') then raise exception 'Atividade inválida';end if;
 if exists(select 1 from public.orbit_study_blocks where user_id=u and not finished and last_seen>now()-interval '2 minutes') then raise exception 'Já existe uma atividade cronometrada em andamento';end if;
 update public.orbit_study_blocks set finished=true where user_id=u and not finished;
 insert into public.orbit_study_blocks(user_id,kind) values(u,p->>'kind') returning id into idv;
 insert into public.orbit_sessions(user_id,room) values(u,'Outro') on conflict(user_id) do update set last_activity=now();return jsonb_build_object('id',idv);
 when 'study_tick' then
 select * into rowv from public.orbit_study_blocks where id=(p->>'id')::uuid and user_id=u and not finished for update;
 if not found then raise exception 'Atividade encerrada';end if;
 secs:=least(30,greatest(0,floor(extract(epoch from now()-rowv.last_seen))::int));
 update public.orbit_study_blocks set seconds=seconds+secs,last_seen=now(),finished=coalesce((p->>'finish')::boolean,false) where id=rowv.id;
 update public.orbit_sessions set last_activity=now() where user_id=u;
 if coalesce((p->>'finish')::boolean,false) then perform orbit_private.award(u,'study:'||rowv.id,rowv.kind,0,0,floor((rowv.seconds+secs)/60)*(cfg->>'reading_xp_per_minute')::numeric,floor((rowv.seconds+secs)/60)*(cfg->>'reading_pr_per_minute')::numeric,rowv.seconds+secs);end if;return '{}';
 when 'run_create' then
 n:=least(180,greatest(1,(p->>'count')::int));
 if p->>'kind' not in ('sim','match') then raise exception 'Tipo inválido';end if;
 select array_agg(id) into arr from(select id from public.orbit_questions where coalesce(p->>'discipline','')='' or discipline=p->>'discipline' order by random() limit n) q;
 if coalesce(array_length(arr,1),0)<1 then raise exception 'Não há questões para este filtro';end if;
 insert into public.orbit_runs(owner_id,kind,title,question_ids,seconds) values(u,p->>'kind',left(coalesce(p->>'title',''),100),arr,(p->>'seconds')::int) returning id into idv;
 insert into public.orbit_run_players(run_id,user_id) values(idv,u);return jsonb_build_object('id',idv);
 when 'run_join' then
 select * into rv from public.orbit_runs where id=(p->>'id')::uuid and kind='match' and status='waiting' for update;
 if not found then raise exception 'Partida indisponível';end if;
 if (select count(*) from public.orbit_run_players where run_id=rv.id and status='accepted')>=8 then raise exception 'Partida cheia';end if;
 insert into public.orbit_run_players(run_id,user_id) values(rv.id,u) on conflict(run_id,user_id) do update set status='accepted';return '{}';
 when 'run_start' then
 select * into rv from public.orbit_runs where id=(p->>'id')::uuid and owner_id=u and status='waiting' for update;
 if not found then raise exception 'Prova indisponível';end if;
 if rv.kind='match' and (select count(*) from public.orbit_run_players where run_id=rv.id and status='accepted')<2 then raise exception 'Aguarde outro participante';end if;
 update public.orbit_runs set status='active',started_at=now(),ends_at=now()+make_interval(secs=>rv.seconds) where id=rv.id;
 insert into public.orbit_sessions(user_id,room) values(u,'Banco de questões') on conflict(user_id) do update set last_activity=now();return '{}';
 when 'run_answer' then
 select * into rv from public.orbit_runs where id=(p->>'id')::uuid for update;
 if rv.status<>'active' or now()>rv.ends_at then raise exception 'Tempo encerrado';end if;
 if not(p->>'question_id'=any(rv.question_ids)) or p->>'choice' not in ('A','B','C','D','E') then raise exception 'Resposta inválida';end if;
 update public.orbit_run_players set answers=answers||jsonb_build_object(p->>'question_id',p->>'choice') where run_id=rv.id and user_id=u and status='accepted';
 if not found then raise exception 'Participante indisponível';end if;return '{}';
 when 'run_finish' then
 select * into rv from public.orbit_runs where id=(p->>'id')::uuid for update;
 if not exists(select 1 from public.orbit_run_players where run_id=rv.id and user_id=u) then raise exception 'Você não participa desta prova';end if;
 if rv.status='finished' then return '{}';end if;if rv.status<>'active' then raise exception 'Prova não iniciada';end if;
 for other in select * from public.orbit_run_players where run_id=rv.id and status='accepted' and (user_id=u or now()>=rv.ends_at) for update loop
 select count(*) into c from orbit_private.answer_keys where question_id=any(rv.question_ids) and correct_letter=other.answers->>question_id;
 w:=array_length(rv.question_ids,1)-c;secs:=least(rv.seconds,greatest(0,floor(extract(epoch from now()-rv.started_at))::int));
 update public.orbit_run_players set status='finished',correct=c,elapsed=secs,finished_at=now() where run_id=rv.id and user_id=other.user_id;
 perform orbit_private.award(other.user_id,'run:'||rv.id,rv.kind,c,w,c*10+w*5,(c*10+w*5)*case when rv.kind='match' then (cfg->>'coliseum_factor')::numeric else 1 end,secs);
 end loop;
 if not exists(select 1 from public.orbit_run_players where run_id=rv.id and status='accepted') then update public.orbit_runs set status='finished' where id=rv.id;end if;return '{}';
 when 'run_cancel' then update public.orbit_runs set status='cancelled' where id=(p->>'id')::uuid and owner_id=u and status='waiting';return '{}';
 when 'run_results' then
 select * into rv from public.orbit_runs where id=(p->>'id')::uuid;
 if rv.status<>'finished' or not exists(select 1 from public.orbit_run_players where run_id=rv.id and user_id=u) then raise exception 'Correção disponível após o encerramento';end if;
 return jsonb_build_object('keys',(select jsonb_object_agg(question_id,correct_letter) from orbit_private.answer_keys where question_id=any(rv.question_ids)),'players',(select jsonb_agg(to_jsonb(rp)) from public.orbit_run_players rp where run_id=rv.id));
 when 'material_vote' then insert into public.orbit_material_votes values(u,(p->>'id')::uuid,(p->>'helpful')::boolean) on conflict(user_id,material_id) do update set helpful=excluded.helpful;return '{}';
 when 'report' then insert into public.orbit_reports(user_id,target,reason) values(u,left(p->>'target',200),p->>'reason');return '{}';
 when 'admin' then
 if not exists(select 1 from orbit_private.admins where user_id=u) then raise exception 'Acesso administrativo necessário';end if;
 case p->>'operation'
 when 'members' then return (select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'email',a.email,'allowed',pm.user_id is not null)),'[]') from auth.users a left join orbit_private.pilot_members pm on pm.user_id=a.id);
 when 'allow' then insert into orbit_private.pilot_members select id from auth.users where id=(p->>'user_id')::uuid on conflict do nothing;
 when 'revoke' then delete from orbit_private.pilot_members where user_id=(p->>'user_id')::uuid and user_id<>u;
 when 'review' then
 select * into rowv from public.orbit_external where id=(p->>'id')::uuid for update;
 if rowv.status='approved' then raise exception 'Registro já aprovado';end if;
 if (p->>'approve')::boolean then perform orbit_private.award(rowv.user_id,'external:'||rowv.id,'external',rowv.correct,rowv.wrong,rowv.correct*10+rowv.wrong*5,rowv.correct*10+rowv.wrong*5);end if;
 update public.orbit_external set status=case when (p->>'approve')::boolean then 'approved' else 'rejected' end,review_note=left(coalesce(p->>'note',''),1000) where id=(p->>'id')::uuid;
 when 'resolve' then update public.orbit_reports set resolved=true where id=(p->>'id')::uuid;
 when 'material_save' then
 idv:=coalesce((p->>'id')::uuid,gen_random_uuid());
 insert into public.orbit_materials(id,title,subject,kind,body,url) values(idv,left(p->>'title',200),left(coalesce(p->>'subject','Geral'),80),p->>'kind',coalesce(p->>'body',''),p->>'url') on conflict(id) do update set title=excluded.title,subject=excluded.subject,kind=excluded.kind,body=excluded.body,url=excluded.url,updated_at=now();
 when 'config' then
 if jsonb_array_length(p->'settings'->'rank_thresholds')<>4 then raise exception 'Informe quatro limiares';end if;
 if (p->'settings'->'rank_thresholds'->>0)::numeric<>0 or (p->'settings'->'rank_thresholds'->>1)::numeric<=0 or (p->'settings'->'rank_thresholds'->>2)::numeric<=(p->'settings'->'rank_thresholds'->>1)::numeric or (p->'settings'->'rank_thresholds'->>3)::numeric<=(p->'settings'->'rank_thresholds'->>2)::numeric then raise exception 'Limiares devem ser crescentes';end if;
 update public.orbit_config set settings=settings||jsonb_build_object('rank_thresholds',p->'settings'->'rank_thresholds','provisional_thresholds',false);
 else raise exception 'Operação administrativa inválida';end case;return '{}';
 else raise exception 'Operação desconhecida';end case;
end $$;
revoke all on all functions in schema orbit_private from public,anon,authenticated;
grant execute on function orbit_private.submit_answer(text,text) to authenticated;
grant execute on function orbit_private.api(text,jsonb) to authenticated;
create function public.orbit_api(action text,p jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select orbit_private.api(action,p)$$;
revoke all on function public.orbit_api(text,jsonb) from public,anon;grant execute on function public.orbit_api(text,jsonb) to authenticated;
-- Storage privado: arquivos por conta, avatares visíveis aos participantes.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('orbit-uploads','orbit-uploads',false,5242880,array['image/png','image/jpeg','image/webp','image/gif','application/pdf']) on conflict(id) do nothing;
create policy orbit_upload_insert on storage.objects for insert to authenticated with check(bucket_id='orbit-uploads' and (storage.foldername(name))[1]=(select auth.uid())::text and (select public.orbit_is_member()));
create policy orbit_upload_read on storage.objects for select to authenticated using(bucket_id='orbit-uploads' and (select public.orbit_is_member()) and ((storage.foldername(name))[1]=(select auth.uid())::text or (storage.foldername(name))[2]='avatar' or (select public.orbit_is_admin())));
create policy orbit_upload_delete on storage.objects for delete to authenticated using(bucket_id='orbit-uploads' and (storage.foldername(name))[1]=(select auth.uid())::text and (select public.orbit_is_member()));
commit;
