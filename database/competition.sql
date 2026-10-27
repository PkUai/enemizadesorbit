-- Incremental competitive engine. Legacy runs remain compatible.
begin;
alter table public.orbit_questions add column if not exists short_reviewed boolean not null default false;
alter table public.orbit_runs add column if not exists mode text not null default 'legacy' check(mode in ('legacy','daily','comet-a','comet-b'));
alter table public.orbit_runs add column if not exists invite_expires_at timestamptz;
alter table public.orbit_runs add column if not exists question_seconds integer;
alter table public.orbit_runs add column if not exists settlement text not null default 'pending' check(settlement in ('pending','settled','rules_pending'));
alter table public.orbit_run_players drop constraint if exists orbit_run_players_status_check;
alter table public.orbit_run_players add constraint orbit_run_players_status_check check(status in ('invited','accepted','playing','declined','finished','wo'));
alter table public.orbit_run_players add column if not exists started_at timestamptz;
alter table public.orbit_run_players add column if not exists question_index integer not null default 1;
alter table public.orbit_run_players add column if not exists question_deadline timestamptz;
alter table public.orbit_run_players add column if not exists tier_snapshot integer;
alter table public.orbit_run_players add column if not exists pr_result numeric;
create table if not exists orbit_private.daily_refusals(user_id uuid primary key references auth.users(id),refusals integer not null default 0);
alter table orbit_private.daily_refusals enable row level security;
revoke all on orbit_private.daily_refusals from public,anon,authenticated;

create or replace function orbit_private.finish_competition_player(rid uuid,uid uuid,wo boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare r public.orbit_runs;rp public.orbit_run_players;c integer;w integer;t integer;
begin
 select * into r from public.orbit_runs where id=rid;
 select * into rp from public.orbit_run_players where run_id=rid and user_id=uid for update;
 if rp.status in ('finished','wo') then return;end if;
 select count(*) into c from orbit_private.answer_keys where question_id=any(r.question_ids) and correct_letter=rp.answers->>question_id;
 w:=(select count(*) from jsonb_object_keys(rp.answers))-c;
 t:=case when rp.started_at is null then 0 else least(r.seconds,greatest(0,floor(extract(epoch from now()-rp.started_at))::int)) end;
 update public.orbit_run_players set status=case when wo then 'wo' else 'finished' end,correct=c,elapsed=t,finished_at=now() where run_id=rid and user_id=uid;
 perform orbit_private.award(uid,'contest-xp:'||rid,'match',c,w,c*15+w*10,0,t);
 delete from public.orbit_sessions where user_id=uid and room='Coliseu';
end $$;
revoke all on function orbit_private.finish_competition_player(uuid,uuid,boolean) from public,anon,authenticated;

create or replace function orbit_private.settle_competition(rid uuid) returns void language plpgsql security definer set search_path='' as $$
declare r public.orbit_runs;a record;b record;n integer;v numeric;basea numeric;baseb numeric;team uuid;pending boolean:=false;penalty numeric;wins integer;wo_count integer;base_raw numeric;multi numeric;brakea numeric;brakeb numeric;virtual jsonb;
begin
 select * into r from public.orbit_runs where id=rid for update;
 if r.settlement='settled' or r.mode='legacy' then return;end if;
 if exists(select 1 from public.orbit_run_players where run_id=rid and status not in ('finished','wo','declined')) then return;end if;
 select count(*),count(*) filter(where status='wo') into n,wo_count from public.orbit_run_players where run_id=rid and status in ('finished','wo');
 -- Unknown daily WO and exact ties are held for rule confirmation, never improvised.
 if (r.mode='daily' and wo_count>0) or (n>2 and wo_count>=n-1) then pending:=true;end if;
 if exists(select 1 from public.orbit_run_players lp join public.orbit_run_players rp2 on lp.run_id=rp2.run_id and lp.user_id<rp2.user_id where lp.run_id=rid and lp.status='finished' and rp2.status='finished' and lp.correct=rp2.correct and lp.elapsed=rp2.elapsed) then pending:=true;end if;
 if pending then update public.orbit_runs set status='finished',settlement='rules_pending' where id=rid;return;end if;
 for a in select * from public.orbit_run_players where run_id=rid and status in ('finished','wo') order by user_id loop
  v:=0;wins:=0;penalty:=0;virtual:='[]';
  basea:=(a.correct*20+((select count(*) from jsonb_object_keys(a.answers))-a.correct)*10);
  base_raw:=basea;select (settings->'rank_multipliers'->>a.tier_snapshot)::numeric into multi from public.orbit_config;select coalesce((reward_meta->>'brake')::numeric,1) into brakea from public.orbit_events where user_id=a.user_id and ref='contest-xp:'||rid;brakea:=coalesce(brakea,1);basea:=basea*multi*brakea;
  if a.status='wo' then
   -- Defined Comet 1x1 WO. Multiplayer WO has no new unapproved fixed penalty.
   if n=2 and r.mode in ('comet-a','comet-b') then v:=-50;penalty:=50;end if;
  elsif n=2 and wo_count=1 and r.mode in ('comet-a','comet-b') then v:=round(basea*.75,2);wins:=1;
  else
   -- Ignore missing rivals in the mean for multiplayer, as approved.
   for b in select * from public.orbit_run_players where run_id=rid and user_id<>a.user_id and status='finished' loop
    baseb:=(b.correct*20+((select count(*) from jsonb_object_keys(b.answers))-b.correct)*10);
    select coalesce((reward_meta->>'brake')::numeric,1) into brakeb from public.orbit_events where user_id=b.user_id and ref='contest-xp:'||rid;brakeb:=coalesce(brakeb,1);select baseb*(settings->'rank_multipliers'->>b.tier_snapshot)::numeric*brakeb into baseb from public.orbit_config;
    if a.correct>b.correct or (a.correct=b.correct and a.elapsed<b.elapsed) then v:=v+basea;wins:=wins+1;virtual:=virtual||jsonb_build_array(jsonb_build_object('rival',b.user_id,'result','win','pr',basea));
    else v:=v-baseb*.30;virtual:=virtual||jsonb_build_array(jsonb_build_object('rival',b.user_id,'result','loss','pr',-baseb*.30));end if;
   end loop;
   v:=round(v/greatest(1,(select count(*) from public.orbit_run_players where run_id=rid and user_id<>a.user_id and status='finished')),2);
  end if;
  select alliance_id into team from public.orbit_alliance_members where user_id=a.user_id;
  insert into public.orbit_events(user_id,ref,kind,xp,pr,alliance_id,reward_meta) values(a.user_id,'contest-pr:'||rid,'match_result',0,v,team,jsonb_build_object('version',1,'base_pr',base_raw,'brake',brakea,'rank_multiplier',multi,'bonus',0,'penalty',case when v<0 then -v else 0 end,'final_pr',v,'xp',0,'synapse',0,'orbes',null,'wins',wins,'rivals',n-1,'wo',a.status='wo','competitive',true,'virtual',virtual,'rule',case when a.status='wo' then 'W.O.' when n=2 and wo_count=1 then 'W.O. 1×1: 75% da base própria' else 'Média dos confrontos virtuais; derrota equivalente: 30% da base do vencedor' end)) on conflict(user_id,ref) do nothing;
  update public.orbit_run_players set pr_result=v where run_id=rid and user_id=a.user_id;
 end loop;
 update public.orbit_runs set status='finished',settlement='settled' where id=rid;
end $$;
revoke all on function orbit_private.settle_competition(uuid) from public,anon,authenticated;

create or replace function orbit_private.competition(action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();r public.orbit_runs;rp public.orbit_run_players;other record;modev text;ids uuid[];uid uuid;rid uuid;n integer;t integer;tier integer;questions text[];startday timestamptz;finished boolean;keyv text;
begin
 if u is null or not exists(select 1 from orbit_private.pilot_members where user_id=u) then raise exception 'Acesso restrito aos testadores';end if;
 if action='create' then
  modev:=p->>'mode';if modev not in ('daily','comet-a','comet-b') then raise exception 'Modalidade inválida';end if;
  select array_agg(distinct x::uuid order by x::uuid) into ids from jsonb_array_elements_text(p->'players') x;
  if coalesce(array_length(ids,1),0)<1 or array_length(ids,1)>7 or u=any(ids) then raise exception 'Convide de um a sete rivais';end if;
  if modev='daily' and not exists(select 1 from public.orbit_config where (settings->>'daily_start_hours')::numeric>0) then raise exception 'Prazo de início do Duelo Diário após aceite ainda não confirmado';end if;
  if modev='daily' and array_length(ids,1)<>1 then raise exception 'Duelo Diário exige um rival';end if;
  -- Lock all users in deterministic order, so daily limits withstand concurrent invitations.
  for uid in select x from unnest(ids||array[u]) x order by x loop perform pg_advisory_xact_lock(hashtextextended(uid::text,7));end loop;
  tier:=(orbit_private.stats(u)->>'tier')::int;
  foreach uid in array ids loop
   if not exists(select 1 from orbit_private.pilot_members where user_id=uid) then raise exception 'Rival não autorizado';end if;
   if (orbit_private.stats(uid)->>'tier')::int<>tier then raise exception 'Piloto competitivo limitado à mesma patente até confirmar bônus por superioridade e muito inferior';end if;
  end loop;
  startday:=(now() at time zone 'America/Fortaleza')::date at time zone 'America/Fortaleza';
  if modev='daily' then
   if (select count(*) from public.orbit_runs where mode='daily' and owner_id=u and created_at>=startday)>=1 then raise exception 'Limite de um desafio enviado por dia';end if;
   foreach uid in array ids loop
    if (select count(*) from public.orbit_run_players pl join public.orbit_runs rr on rr.id=pl.run_id where rr.mode='daily' and rr.owner_id<>uid and pl.user_id=uid and rr.created_at>=startday)>=2 then raise exception 'Rival já recebeu dois desafios hoje';end if;
   end loop;
  end if;
  n:=case modev when 'daily' then 24 when 'comet-a' then 8 else 6 end;t:=case when modev='comet-a' then 60 else 90 end;
  select array_agg(id) into questions from(select id from public.orbit_questions where modev<>'comet-a' or short_reviewed order by random() limit n) q;
  if coalesce(array_length(questions,1),0)<>n then raise exception 'Acervo insuficiente: Comet A requer oito questões curtas revisadas pela administração';end if;
  insert into public.orbit_runs(owner_id,kind,title,question_ids,seconds,mode,question_seconds,invite_expires_at) values(u,'match',left(coalesce(nullif(p->>'title',''),'Partida Orbit'),100),questions,n*t,modev,t,case when modev='daily' then now()+interval '36 hours' else null end) returning id into rid;
  foreach uid in array ids||array[u] loop insert into public.orbit_run_players(run_id,user_id,status,tier_snapshot) values(rid,uid,case when uid=u then 'accepted' else 'invited' end,tier);end loop;
  return jsonb_build_object('id',rid);
 end if;
 if action in ('accept','decline') then perform pg_advisory_xact_lock(hashtextextended(u::text,7));end if;
 select * into r from public.orbit_runs where id=(p->>'id')::uuid and mode<>'legacy' for update;
 if not found then raise exception 'Partida indisponível';end if;
 select * into rp from public.orbit_run_players where run_id=r.id and user_id=u for update;
 if not found then raise exception 'Você não participa desta partida';end if;
 -- Expiry is checked in every request; it never depends on browser time.
 if r.status='waiting' and r.invite_expires_at<now() then update public.orbit_runs set status='cancelled' where id=r.id;r.status:='cancelled';end if;
 if r.status='active' and now()>=r.ends_at then
  for other in select user_id from public.orbit_run_players where run_id=r.id and status in ('accepted','playing') order by user_id loop perform orbit_private.finish_competition_player(r.id,other.user_id,true);end loop;
  perform orbit_private.settle_competition(r.id);select * into r from public.orbit_runs where id=r.id;
 end if;
 if action='accept' then
  if r.status<>'waiting' or rp.status<>'invited' then raise exception 'Convite indisponível';end if;
  update public.orbit_run_players set status='accepted' where run_id=r.id and user_id=u;
  if r.mode='daily' then insert into orbit_private.daily_refusals values(u,0) on conflict(user_id) do update set refusals=0;end if;
  if not exists(select 1 from public.orbit_run_players where run_id=r.id and status='invited') then update public.orbit_runs set status='active',started_at=now(),ends_at=now()+case when r.mode='daily' then make_interval(hours=>(select (settings->>'daily_start_hours')::int from public.orbit_config)) else interval '48 hours' end where id=r.id;end if;
 elsif action='decline' then
  if r.status<>'waiting' or rp.status<>'invited' then raise exception 'Convite indisponível';end if;
  if r.mode='daily' then
   if coalesce((select refusals from orbit_private.daily_refusals where user_id=u),0)>=2 then raise exception 'Após duas recusas, aceite um Duelo Diário';end if;
   insert into orbit_private.daily_refusals values(u,1) on conflict(user_id) do update set refusals=orbit_private.daily_refusals.refusals+1;
  end if;
  update public.orbit_run_players set status='declined' where run_id=r.id and user_id=u;update public.orbit_runs set status='cancelled' where id=r.id;
 elsif action='begin' then
  if r.status<>'active' or rp.status<>'accepted' then raise exception 'Participação indisponível';end if;
  if exists(select 1 from public.orbit_run_players pl join public.orbit_runs rr on rr.id=pl.run_id where pl.user_id=u and pl.status='playing' and rr.status='active' and rr.id<>r.id) then raise exception 'Finalize sua outra participação ativa';end if;
  update public.orbit_run_players set status='playing',started_at=now(),question_index=1,question_deadline=least(r.ends_at,now()+make_interval(secs=>r.question_seconds)) where run_id=r.id and user_id=u;
  insert into public.orbit_sessions(user_id,room) values(u,'Coliseu') on conflict(user_id) do update set room='Coliseu',started_at=now(),last_activity=now();
 elsif action in ('answer','tick','finish') then
  if rp.status='playing' and r.status='active' then
   -- Advance expired slots using their original deadlines, so reloads cannot reset a timer.
   while rp.question_deadline<=now() and rp.question_index<=array_length(r.question_ids,1) loop
    rp.question_index:=rp.question_index+1;rp.question_deadline:=least(r.ends_at,rp.question_deadline+make_interval(secs=>r.question_seconds));
   end loop;
   if action='answer' and rp.question_index<=array_length(r.question_ids,1) then
    keyv:=r.question_ids[rp.question_index];
    if p->>'question_id' is distinct from keyv then
     -- A retried, already saved answer is a read, not a second reward or an advance.
     if not(rp.answers ? (p->>'question_id')) then raise exception 'Questão expirada ou fora da ordem';end if;
    else
     if p->>'choice' is null or p->>'choice' not in ('A','B','C','D','E') then raise exception 'Alternativa inválida';end if;
     rp.answers:=rp.answers||jsonb_build_object(keyv,p->>'choice');rp.question_index:=rp.question_index+1;rp.question_deadline:=least(r.ends_at,now()+make_interval(secs=>r.question_seconds));
    end if;
   end if;
   update public.orbit_run_players set answers=rp.answers,question_index=rp.question_index,question_deadline=rp.question_deadline where run_id=r.id and user_id=u;
   update public.orbit_sessions set last_activity=now() where user_id=u and room='Coliseu';
   if rp.question_index>array_length(r.question_ids,1) or action='finish' then perform orbit_private.finish_competition_player(r.id,u,false);end if;
   perform orbit_private.settle_competition(r.id);
  end if;
 elsif action<>'state' then raise exception 'Operação inválida';end if;
 select * into r from public.orbit_runs where id=r.id;
 return jsonb_build_object('run',to_jsonb(r),'mine',(select to_jsonb(pl) from public.orbit_run_players pl where run_id=r.id and user_id=u),'lobby',(select jsonb_agg(jsonb_build_object('user_id',user_id,'status',status,'correct',case when r.status='finished' then correct else null end,'elapsed',case when r.status='finished' then elapsed else null end,'pr_result',case when r.status='finished' then pr_result else null end)) from public.orbit_run_players where run_id=r.id));
end $$;
revoke all on function orbit_private.competition(text,jsonb) from public,anon;
grant execute on function orbit_private.competition(text,jsonb) to authenticated;
create or replace function public.orbit_competition(action text,p jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select orbit_private.competition(action,p)$$;
revoke all on function public.orbit_competition(text,jsonb) from public,anon;
grant execute on function public.orbit_competition(text,jsonb) to authenticated;
alter table public.orbit_sessions drop constraint if exists orbit_sessions_room_check;
alter table public.orbit_sessions add constraint orbit_sessions_room_check check(room in ('Banco de questões','Correção','Outro','Coliseu'));
create or replace function orbit_private.guard_bank() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from public.orbit_run_players p join public.orbit_runs r on r.id=p.run_id where p.user_id=new.user_id and r.status='active' and ((r.mode='legacy' and p.status='accepted') or (r.mode<>'legacy' and p.status='playing'))) then raise exception 'Finalize sua participação ativa antes de responder no banco';end if;return new;end$$;
commit;
