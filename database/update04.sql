-- Orbit 0.4: server-owned wallet, single-use boosts and deferred competitive rewards.
create table orbit_private.wallet(user_id uuid not null references auth.users(id) on delete cascade,ref text not null,amount numeric(14,2) not null,created_at timestamptz not null default now(),primary key(user_id,ref));
create table orbit_private.inventory(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,sku text not null,request_id uuid not null,created_at timestamptz not null default now(),activated_at timestamptz,expires_at timestamptz,unique(user_id,request_id));
create index on orbit_private.inventory(user_id,expires_at);
create table orbit_private.pending_rewards(user_id uuid not null references auth.users(id) on delete cascade,ref text not null,run_id uuid not null references public.orbit_runs(id) on delete cascade,payload jsonb not null,ready_at timestamptz,claimed_at timestamptz,primary key(user_id,ref));
create index on orbit_private.pending_rewards(ready_at) where claimed_at is null;
create table orbit_private.bank_rewards(user_id uuid primary key references auth.users(id) on delete cascade,last_event bigint not null default 0,seconds integer not null default 0,last_tick timestamptz not null default now());
-- Historical events remain unchanged; the new economy begins with this release.
insert into orbit_private.bank_rewards(user_id,last_event) select user_id,max(id) from public.orbit_events group by user_id;
alter table public.orbit_materials add column if not exists orbes_reward numeric(10,2) check(orbes_reward>=0);
update public.orbit_config set settings=settings||'{"daily_start_hours":8}'::jsonb;

create function orbit_private.economy_event() returns trigger language plpgsql security definer set search_path='' as $$
declare amount numeric:=0;item record;resource text;remaining numeric;coverage numeric;countq integer;rid uuid;player public.orbit_run_players;r public.orbit_runs;
begin
 if new.reward_meta->>'claimed_snapshot'='true' then return new;end if;
 if exists(select 1 from public.orbit_events where user_id=new.user_id and ref=new.ref) then return null;end if;
 perform pg_advisory_xact_lock(hashtextextended(new.user_id::text,41));
 if exists(select 1 from orbit_private.pending_rewards where user_id=new.user_id and ref=new.ref) then return null;end if;
 if new.ref like 'contest-%' then
  rid:=split_part(new.ref,':',2)::uuid;
  select * into r from public.orbit_runs where id=rid;
  select * into player from public.orbit_run_players where run_id=rid and user_id=new.user_id;
  if new.ref like 'contest-xp:%' and player.status='finished' then amount:=case when r.mode='daily' then 20 else 6 end;
  elsif new.ref like 'contest-pr:%' and coalesce((new.reward_meta->>'wins')::int,0)>0 then amount:=case when r.mode='daily' then 8 else 2 end;end if;
 elsif new.ref like 'material:%' then
  select coalesce(orbes_reward,0) into amount from public.orbit_materials where id=split_part(new.ref,':',2)::uuid;
 elsif new.kind='external' then amount:=(new.correct+new.wrong)*.8+new.correct*.2;
 elsif new.kind='pomodoro' then amount:=floor(new.seconds/300.0);
 end if;
 new.reward_meta:=coalesce(new.reward_meta,'{}')||jsonb_build_object('orbes',round(amount,2));
 countq:=new.correct+new.wrong;
 for item in select * from orbit_private.inventory where user_id=new.user_id and activated_at is not null and expires_at>now() order by activated_at,id for update loop
  resource:=split_part(item.sku,'-',1);remaining:=extract(epoch from item.expires_at-now());
  coverage:=case when new.kind in ('external','sim') and countq>0 then least(1,remaining/(countq*30)) else 1 end;
  if resource='xp' and new.xp>0 then new.reward_meta:=new.reward_meta||jsonb_build_object('boost_xp',round(new.xp*.25*coverage,2));new.xp:=round(new.xp*(1+.25*coverage),2);
  elsif resource='pr' and new.pr>0 then new.reward_meta:=new.reward_meta||jsonb_build_object('boost_pr',round(new.pr*.25*coverage,2));new.pr:=round(new.pr*(1+.25*coverage),2);end if;
  if new.kind in ('external','sim') and countq>0 then update orbit_private.inventory set expires_at=greatest(now(),expires_at-make_interval(secs=>countq*30)) where id=item.id;end if;
 end loop;
 new.reward_meta:=new.reward_meta||jsonb_build_object('xp',new.xp,'final_pr',new.pr);
 if rid is not null then
  insert into orbit_private.pending_rewards(user_id,ref,run_id,payload) values(new.user_id,new.ref,rid,to_jsonb(new)) on conflict do nothing;
  return null;
 end if;
 if amount<>0 then insert into orbit_private.wallet(user_id,ref,amount) values(new.user_id,new.ref,round(amount,2)) on conflict do nothing;end if;
 return new;
end $$;
create trigger economy_event before insert on public.orbit_events for each row execute function orbit_private.economy_event();

create function orbit_private.claim_rewards(uid uuid,rid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare p record;e public.orbit_events;result jsonb:='[]';st jsonb;
begin
 perform pg_advisory_xact_lock(hashtextextended(uid::text,41));
 for p in select * from orbit_private.pending_rewards where user_id=uid and run_id=rid and ready_at is not null and claimed_at is null order by ref desc for update loop
  e:=jsonb_populate_record(null::public.orbit_events,p.payload);
  -- Claimed refs are distinct; trigger recognizes snapshots and never recalculates them.
  insert into public.orbit_events(user_id,ref,kind,correct,wrong,xp,pr,alliance_id,seconds,reward_meta) values(uid,'claimed:'||p.ref,e.kind,e.correct,e.wrong,e.xp,e.pr,e.alliance_id,e.seconds,e.reward_meta||'{"claimed_snapshot":true}') on conflict(user_id,ref) do nothing returning * into e;
  if found then result:=result||jsonb_build_array(to_jsonb(e));insert into orbit_private.wallet(user_id,ref,amount) values(uid,p.ref,coalesce((e.reward_meta->>'orbes')::numeric,0)) on conflict do nothing;end if;
  update orbit_private.pending_rewards set claimed_at=now() where user_id=uid and ref=p.ref;
 end loop;
 if result='[]'::jsonb then select coalesce(jsonb_agg(to_jsonb(ev)),'[]') into result from public.orbit_events ev where ev.user_id=uid and ev.ref in ('claimed:contest-xp:'||rid,'claimed:contest-pr:'||rid);end if;
 st:=orbit_private.stats(uid);
 insert into public.orbit_achievements(user_id,code) select uid,code from (values
 ('primeira_questao',((st->>'correct')::int+(st->>'wrong')::int)>=1),
 ('dias_luta_gloria',(st->>'correct')::int>=100 and (st->>'wrong')::int>=100),
 ('500_acertos',(st->>'correct')::int>=500),
 ('sinapse20',(st->>'best_synapse')::numeric>=20),('sinapse40',(st->>'best_synapse')::numeric>=40),('sinapse60',(st->>'best_synapse')::numeric>=60),('sinapse80',(st->>'best_synapse')::numeric>=80),('sobrecarga',(st->>'best_synapse')::numeric>=100),
 ('nivel10',(st->>'level')::int>=10),('nivel50',(st->>'level')::int>=50),('nivel100',(st->>'level')::int>=100),
 ('50_porcento',(select coalesce(sum(correct+wrong),0)>=45 from public.orbit_events where user_id=uid and created_at>now()-interval '8 hours')),
 ('hahahahaha',(select coalesce(sum(correct+wrong),0)>=180 from public.orbit_events where user_id=uid and created_at>now()-interval '24 hours'))
 ) a(code,unlocked) where unlocked on conflict do nothing;
 return result;
end $$;

create function orbit_private.chat_allowed(ch text) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(auth.uid() is not null and exists(select 1 from orbit_private.pilot_members where user_id=auth.uid()) and (ch='geral' or ch='alliance:'||(select alliance_id::text from public.orbit_alliance_members where user_id=auth.uid()) or (ch ~ '^dm:[0-9a-f-]{36}:[0-9a-f-]{36}$' and auth.uid()::text in (split_part(ch,':',2),split_part(ch,':',3)) and split_part(ch,':',2)<split_part(ch,':',3) and exists(select 1 from orbit_private.pilot_members where user_id::text=split_part(ch,':',2)) and exists(select 1 from orbit_private.pilot_members where user_id::text=split_part(ch,':',3)))),false);
$$;
alter policy messages_read on public.orbit_messages using((select public.orbit_is_member()) and created_at >= (now() at time zone 'America/Fortaleza')::date at time zone 'America/Fortaleza' and orbit_private.chat_allowed(channel));

create function orbit_private.update_api(action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();result jsonb;item record;sku text;price integer;mins integer;resource text;balance numeric;statev orbit_private.bank_rewards;ids bigint[];lastid bigint;c integer;w integer;base numeric;bonus numeric;total numeric;eid bigint;req uuid;
begin
 if u is null or not exists(select 1 from orbit_private.pilot_members where user_id=u) then raise exception 'Acesso restrito aos testadores';end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,41));
 if action='state' then
  return jsonb_build_object('balance',coalesce((select sum(amount) from orbit_private.wallet where user_id=u),0),'inventory',(select coalesce(jsonb_agg(to_jsonb(i) order by created_at desc),'[]') from orbit_private.inventory i where user_id=u),'pending',(select coalesce(jsonb_agg(x),'[]') from(select pr.run_id,r.title,min(pr.ready_at) ready_at from orbit_private.pending_rewards pr join public.orbit_runs r on r.id=pr.run_id where pr.user_id=u and pr.ready_at is not null and pr.claimed_at is null group by pr.run_id,r.title)x));
 elsif action='purchase' then
  sku:=p->>'sku';if sku not in ('pr-15','pr-30','pr-60','xp-15','xp-30','xp-60') then raise exception 'Cartão inválido';end if;
  req:=(p->>'request_id')::uuid;if req is null then raise exception 'Identificador obrigatório';end if;
  if exists(select 1 from orbit_private.inventory where user_id=u and request_id=req) then return '{}';end if;
  price:=case sku when 'pr-15' then 60 when 'pr-30' then 110 when 'pr-60' then 180 when 'xp-15' then 50 when 'xp-30' then 90 else 150 end;
  select coalesce(sum(amount),0) into balance from orbit_private.wallet where user_id=u;
  if balance<price then raise exception 'Saldo de Orbes insuficiente';end if;
  insert into orbit_private.inventory(user_id,sku,request_id) values(u,sku,req);
  insert into orbit_private.wallet(user_id,ref,amount) values(u,'purchase:'||req,-price);return '{}';
 elsif action='activate' then
  select * into item from orbit_private.inventory where user_id=u and id=(p->>'id')::uuid for update;
  if not found then raise exception 'Cartão indisponível';end if;if item.activated_at is not null then raise exception 'Cartão já utilizado';end if;
  resource:=split_part(item.sku,'-',1);mins:=split_part(item.sku,'-',2)::int;
  if exists(select 1 from orbit_private.inventory where user_id=u and split_part(inventory.sku,'-',1)=resource and expires_at>now()) then raise exception 'Já existe um cartão deste recurso ativo';end if;
  update orbit_private.inventory set activated_at=now(),expires_at=now()+make_interval(mins=>mins) where id=item.id;return '{}';
 elsif action='claim' then
  if not exists(select 1 from public.orbit_run_players where user_id=u and run_id=(p->>'id')::uuid) then raise exception 'Resultado privado';end if;
  return orbit_private.claim_rewards(u,(p->>'id')::uuid);
 elsif action='bank_tick' then
  insert into orbit_private.bank_rewards(user_id) values(u) on conflict do nothing;
  update orbit_private.bank_rewards set seconds=seconds+least(30,greatest(0,extract(epoch from now()-last_tick)::int)),last_tick=now() where user_id=u;return '{}';
 elsif action='finish_bank' then
  insert into orbit_private.bank_rewards(user_id) values(u) on conflict do nothing;
  select * into statev from orbit_private.bank_rewards where user_id=u for update;
  select array_agg(id),max(id),coalesce(sum(correct),0),coalesce(sum(wrong),0) into ids,lastid,c,w from public.orbit_events where user_id=u and kind='bank' and id>statev.last_event;
  if lastid is null then return '[]';end if;
  base:=(c+w)*.8+c*.2;bonus:=least(floor(statev.seconds/300.0),base*.2);total:=round(base+bonus,2);
  insert into orbit_private.wallet(user_id,ref,amount) values(u,'bank-set:'||lastid,total) on conflict do nothing;
  update public.orbit_events set reward_meta=reward_meta||jsonb_build_object('orbes',case when id=lastid then total else 0 end,'orbes_set',lastid,'orbes_base',base,'orbes_time_bonus',bonus) where id=any(ids);
  update orbit_private.bank_rewards set last_event=lastid,seconds=0,last_tick=now() where user_id=u;
  return (select jsonb_agg(to_jsonb(e) order by id) from public.orbit_events e where id=any(ids));
 elsif action='chat_send' then
  if not coalesce(orbit_private.chat_allowed(p->>'channel'),false) then raise exception 'Canal indisponível';end if;
  if length(trim(p->>'body')) not between 1 and 1000 or p->>'body' is null then raise exception 'Mensagem inválida';end if;
  if exists(select 1 from public.orbit_messages where user_id=u and created_at>now()-interval '2 seconds') then raise exception 'Aguarde dois segundos entre mensagens';end if;
  insert into public.orbit_messages(user_id,channel,body) values(u,p->>'channel',trim(p->>'body'));return '{}';
 elsif action='chat_delete' then
  delete from public.orbit_messages where id=(p->>'id')::bigint and user_id=u;return '{}';
 else raise exception 'Operação inválida';end if;
end $$;
create function public.orbit_update(action text,p jsonb default '{}') returns jsonb language sql set search_path='' as $$select orbit_private.update_api(action,p)$$;
revoke all on function public.orbit_update(text,jsonb) from public,anon;
grant execute on function public.orbit_update(text,jsonb) to authenticated;

CREATE OR REPLACE FUNCTION orbit_private.settle_competition(rid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  base_raw:=basea;select (settings->'rank_multipliers'->>a.tier_snapshot)::numeric into multi from public.orbit_config;select coalesce((reward_meta->>'brake')::numeric,1) into brakea from (select (payload->'reward_meta') reward_meta from orbit_private.pending_rewards where user_id=a.user_id and ref='contest-xp:'||rid) x;brakea:=coalesce(brakea,1);basea:=basea*multi*brakea;
  if a.status='wo' then
   -- Defined Comet 1x1 WO. Multiplayer WO has no new unapproved fixed penalty.
   if n=2 and r.mode in ('comet-a','comet-b') then v:=-50;penalty:=50;end if;
  elsif n=2 and wo_count=1 and r.mode in ('comet-a','comet-b') then v:=round(basea*.75,2);wins:=1;
  else
   -- Ignore missing rivals in the mean for multiplayer, as approved.
   for b in select * from public.orbit_run_players where run_id=rid and user_id<>a.user_id and status='finished' loop
    baseb:=(b.correct*20+((select count(*) from jsonb_object_keys(b.answers))-b.correct)*10);
    select coalesce((reward_meta->>'brake')::numeric,1) into brakeb from (select (payload->'reward_meta') reward_meta from orbit_private.pending_rewards where user_id=b.user_id and ref='contest-xp:'||rid) x;brakeb:=coalesce(brakeb,1);select baseb*(settings->'rank_multipliers'->>b.tier_snapshot)::numeric*brakeb into baseb from public.orbit_config;
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
 update orbit_private.pending_rewards set ready_at=coalesce(ready_at,now()) where run_id=rid;
end $function$

;

CREATE OR REPLACE FUNCTION orbit_private.competition(action text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  for other in select user_id from public.orbit_run_players where run_id=r.id and (status='accepted' or (status='playing' and r.mode<>'daily')) order by user_id loop perform orbit_private.finish_competition_player(r.id,other.user_id,true);end loop;
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
  update public.orbit_run_players set status='playing',started_at=now(),question_index=1,question_deadline=case when r.mode='daily' then now()+make_interval(secs=>r.question_seconds) else least(r.ends_at,now()+make_interval(secs=>r.question_seconds)) end where run_id=r.id and user_id=u;
  insert into public.orbit_sessions(user_id,room) values(u,'Coliseu') on conflict(user_id) do update set room='Coliseu',started_at=now(),last_activity=now();
 elsif action in ('answer','next','tick','finish') then
  if rp.status='playing' and r.status='active' then
   -- Advance expired slots using their original deadlines, so reloads cannot reset a timer.
   while rp.question_deadline<=now() and rp.question_index<=array_length(r.question_ids,1) loop
    rp.question_index:=rp.question_index+1;rp.question_deadline:=case when r.mode='daily' then rp.question_deadline+make_interval(secs=>r.question_seconds) else least(r.ends_at,rp.question_deadline+make_interval(secs=>r.question_seconds)) end;
   end loop;
   if action='answer' and rp.question_index<=array_length(r.question_ids,1) then
    keyv:=r.question_ids[rp.question_index];
    if p->>'question_id' is distinct from keyv then
     -- A retried, already saved answer is a read, not a second reward or an advance.
     if not(rp.answers ? (p->>'question_id')) then raise exception 'Questão expirada ou fora da ordem';end if;
    else
     if p->>'choice' is null or p->>'choice' not in ('A','B','C','D','E') then raise exception 'Alternativa inválida';end if;
     rp.answers:=rp.answers||jsonb_build_object(keyv,p->>'choice');
    end if;
   end if;
   if action='next' and rp.question_index<=array_length(r.question_ids,1) then
    if (p->>'question_index')::int=rp.question_index then
     if not(rp.answers ? r.question_ids[rp.question_index]) then raise exception 'Confirme a resposta antes de avançar';end if;
     rp.question_index:=rp.question_index+1;
     rp.question_deadline:=case when r.mode='daily' then now()+make_interval(secs=>r.question_seconds) else least(r.ends_at,now()+make_interval(secs=>r.question_seconds)) end;
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
end $function$

;

CREATE OR REPLACE FUNCTION orbit_private.stats(u uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare e record; s numeric:=0; best numeric:=0; last_at timestamptz; x numeric:=0;p numeric:=0;ap numeric:=0;c integer:=0;w integer:=0;secs integer:=0; tier integer:=0;prevact integer;act integer;actnow integer;cfg jsonb; thresholds jsonb;level integer;
begin
 select settings into cfg from public.orbit_config; thresholds:=cfg->'rank_thresholds';
 actnow:=extract(year from now() at time zone 'America/Fortaleza')::int*6+(extract(month from now() at time zone 'America/Fortaleza')::int-1)/2;
 for e in select * from public.orbit_events where user_id=u order by created_at,id loop
 act:=extract(year from e.created_at at time zone 'America/Fortaleza')::int*6+(extract(month from e.created_at at time zone 'America/Fortaleza')::int-1)/2;
 if prevact is not null and act<>prevact then tier:=greatest(0,tier-(act-prevact));ap:=0;end if;prevact:=act;
 ap:=ap+greatest(e.pr,0);for i in 0..3 loop if ap>=(thresholds->>i)::numeric then tier:=greatest(tier,i);end if;end loop;
 x:=x+e.xp;if extract(year from e.created_at at time zone 'America/Fortaleza')=extract(year from now() at time zone 'America/Fortaleza') then p:=p+e.pr;end if;
 c:=c+e.correct;w:=w+e.wrong;secs:=secs+e.seconds;
 if last_at is not null then s:=orbit_private.decay(s,extract(epoch from e.created_at-last_at)/86400);end if;
 s:=least(100,s+e.correct+e.wrong);best:=greatest(best,s);last_at:=e.created_at;
 end loop;
 if last_at is not null then s:=orbit_private.decay(s,extract(epoch from now()-last_at)/86400);end if;
 if prevact is not null and actnow<>prevact then tier:=greatest(0,tier-(actnow-prevact));ap:=0;end if;
 level:=least(100,greatest(0,floor((-15+sqrt(225+20*x))/10)::int));
 return jsonb_build_object('orbes',coalesce((select sum(amount) from orbit_private.wallet where user_id=u),0),'user_id',u,'xp',x,'pr',round(p,2),'act_pr',round(ap,2),'tier',tier,'level',level,'correct',c,'wrong',w,'synapse',round(s,2),'best_synapse',best,'seconds',secs);
end $function$

;
create function orbit_private.maintenance04() returns void language plpgsql security definer set search_path='' as $$
declare item record;oldsub text:=current_setting('request.jwt.claim.sub',true);
begin
 for item in select pl.run_id,pl.user_id from public.orbit_run_players pl join public.orbit_runs r on r.id=pl.run_id where exists(select 1 from orbit_private.pilot_members pm where pm.user_id=pl.user_id) and r.mode<>'legacy' and r.status='active' and ((pl.status='playing' and pl.question_deadline<=now()) or (pl.status='accepted' and r.ends_at<=now())) order by pl.run_id,pl.user_id loop
  perform set_config('request.jwt.claim.sub',item.user_id::text,true);
  perform orbit_private.competition('tick',jsonb_build_object('id',item.run_id));
 end loop;
 perform set_config('request.jwt.claim.sub',coalesce(oldsub,''),true);
 for item in select distinct user_id,run_id from orbit_private.pending_rewards where claimed_at is null and ready_at<=now()-interval '48 hours' order by user_id,run_id loop perform orbit_private.claim_rewards(item.user_id,item.run_id);end loop;
 delete from public.orbit_messages where created_at<(now() at time zone 'America/Fortaleza')::date at time zone 'America/Fortaleza';
end $$;
create extension if not exists pg_cron;
select cron.schedule('orbit-results-04','* * * * *','select orbit_private.maintenance04()');
alter table orbit_private.wallet enable row level security;
alter table orbit_private.inventory enable row level security;
alter table orbit_private.pending_rewards enable row level security;
alter table orbit_private.bank_rewards enable row level security;
revoke all on orbit_private.wallet,orbit_private.inventory,orbit_private.pending_rewards,orbit_private.bank_rewards from public,anon,authenticated;
revoke all on function orbit_private.economy_event(),orbit_private.claim_rewards(uuid,uuid),orbit_private.chat_allowed(text),orbit_private.update_api(text,jsonb),orbit_private.maintenance04() from public,anon,authenticated;
grant execute on function orbit_private.chat_allowed(text),orbit_private.update_api(text,jsonb) to authenticated;

CREATE OR REPLACE FUNCTION orbit_private.api(action text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=auth.uid(); idv uuid;rowv record;other record;rv public.orbit_runs;cfg jsonb;arr text[];result jsonb;ch text;team uuid;c integer;w integer;n integer;secs integer;ans jsonb;ids uuid[];
begin
 if u is null or not exists(select 1 from orbit_private.pilot_members where user_id=u) then raise exception 'Acesso restrito aos testadores';end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,1));
 select settings into cfg from public.orbit_config;
 if action in ('run_invite','run_join','run_decline','run_start','run_answer','run_finish','run_cancel') and exists(select 1 from public.orbit_runs where id=(p->>'id')::uuid and mode<>'legacy') then raise exception 'Use o fluxo competitivo assíncrono para esta partida';end if;
 if action='run_create' and p->>'kind'='match' then raise exception 'Crie o confronto pelo novo Coliseu';end if;
 if action in ('chat_send','chat_delete') then return orbit_private.update_api(action,p);end if;
 case action
 when 'preferences_get' then
 return coalesce((select data from public.orbit_preferences where user_id=u),'{}');
 when 'preferences_patch' then
 if jsonb_typeof(p)<>'object' or octet_length(p::text)>18000 then raise exception 'Preferências inválidas';end if;
 insert into public.orbit_preferences(user_id,data) values(u,p) on conflict(user_id) do update set data=public.orbit_preferences.data||excluded.data,updated_at=now();
 return (select data from public.orbit_preferences where user_id=u);
 when 'connected_devices' then
 return (select coalesce(jsonb_agg(jsonb_build_object('device_id',device_id,'last_seen',last_seen)),'[]') from orbit_private.device_presence where user_id=u and last_seen>now()-interval '90 seconds');
 when 'reward_receipt' then
 return (select to_jsonb(e) from public.orbit_events e where user_id=u and id=(p->>'id')::bigint);
  when 'flashcard_review' then
 select * into rowv from public.orbit_documents where id=(p->>'id')::uuid and user_id=u and kind='flashcard' for update;
 if not found then raise exception 'Cartão indisponível';end if;
 n:=case when (p->>'remembered')::boolean then least(180,coalesce((rowv.data->>'interval')::int,1)*2) else 1 end;
 update public.orbit_documents set data=data||jsonb_build_object('interval',n,'due',((now() at time zone 'America/Fortaleza')::date+n)::text),updated_at=now() where id=rowv.id;
 select count(*) into c from public.orbit_events where user_id=u and kind='flashcards' and ref like 'card:%' and created_at>=(now() at time zone 'America/Fortaleza')::date at time zone 'America/Fortaleza';
 if c<100 then perform orbit_private.award(u,'card:'||rowv.id||':'||(now() at time zone 'America/Fortaleza')::date,'flashcards',0,0,6,case when c<20 then 3 when c<40 then 2 else 1 end);end if;
 return '{}';
 when 'session_join' then
 if p->>'room' not in ('Banco de questões','Correção','Outro') then raise exception 'Sala inválida';end if;
 insert into public.orbit_sessions(user_id,room) values(u,p->>'room') on conflict(user_id) do update set room=excluded.room,started_at=case when public.orbit_sessions.room<>excluded.room or public.orbit_sessions.last_activity<now()-interval '30 minutes' then now() else public.orbit_sessions.started_at end,last_activity=now();return '{}';
 when 'session_leave' then delete from public.orbit_sessions where user_id=u;return '{}';
 when 'lobby' then
 select * into rv from public.orbit_runs where id=(p->>'id')::uuid;
 if rv.kind<>'match' and rv.owner_id<>u then raise exception 'Prova privada';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('user_id',user_id,'status',status,'correct',case when rv.status='finished' then correct else null end,'elapsed',case when rv.status='finished' then elapsed else null end)),'[]') from public.orbit_run_players where run_id=rv.id);
 when 'profile_history' then
 if not exists(select 1 from public.orbit_profiles where user_id=(p->>'id')::uuid and (public_history or user_id=u)) then return '[]';end if;
 return (select coalesce(jsonb_agg(t),'[]') from(select id,user_id,kind,correct,wrong,xp,pr,reward_meta,created_at from public.orbit_events where user_id=(p->>'id')::uuid order by created_at desc limit 100)t);
 when 'run_invite' then
 select * into rv from public.orbit_runs where id=(p->>'id')::uuid and owner_id=u and kind='match' and status='waiting' for update;
 if not found then raise exception 'Partida indisponível';end if;
 if not exists(select 1 from orbit_private.pilot_members where user_id=(p->>'user_id')::uuid) then raise exception 'Participante inválido';end if;
 insert into public.orbit_run_players(run_id,user_id,status) values(rv.id,(p->>'user_id')::uuid,'invited') on conflict do nothing;return '{}';
 when 'run_decline' then
 select * into rv from public.orbit_runs where id=(p->>'id')::uuid and status='waiting' for update;
 if not found or rv.owner_id=u then raise exception 'Convite indisponível';end if;
 update public.orbit_run_players set status='declined' where run_id=rv.id and user_id=u;return '{}';
 when 'overview' then
 return jsonb_build_object('stats',orbit_private.stats(u),'admin',exists(select 1 from orbit_private.admins where user_id=u),'config',cfg,'ranks',(select coalesce(jsonb_agg(jsonb_build_object('profile',to_jsonb(pr),'stats',orbit_private.stats(pr.user_id))),'[]') from public.orbit_profiles pr join orbit_private.pilot_members pm on pm.user_id=pr.user_id),'alliance_scores',(select coalesce(jsonb_agg(t),'[]') from (select alliance_id,sum(pr) as pr,sum(xp) as xp,sum(correct+wrong) as questions,sum(pr) filter(where created_at>=date_trunc('week',now() at time zone 'America/Fortaleza') at time zone 'America/Fortaleza') as week_pr from public.orbit_events where alliance_id is not null group by alliance_id)t));
 when 'document_save' then
 if p->>'kind' not in ('task','essay','flashcard','collection','progress','preferences','favorite','highlight') then raise exception 'Tipo inválido';end if;
 idv:=coalesce((p->>'id')::uuid,gen_random_uuid());
 insert into public.orbit_documents(id,user_id,kind,title,data) values(idv,u,p->>'kind',coalesce(p->>'title',''),coalesce(p->'data','{}')) on conflict(id) do update set title=excluded.title,data=excluded.data,updated_at=now() where public.orbit_documents.user_id=u and public.orbit_documents.kind=excluded.kind;
 if not found then raise exception 'Documento indisponível';end if;
 if p->>'kind'='progress' and coalesce((p->'data'->>'done')::boolean,false) and exists(select 1 from public.orbit_materials where id=(p->'data'->>'material')::uuid and orbes_reward>0) then
  insert into public.orbit_events(user_id,ref,kind,reward_meta) values(u,'material:'||(p->'data'->>'material'),'reading','{}') on conflict(user_id,ref) do nothing;
 end if;
 return jsonb_build_object('id',idv);
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
 if p->>'proof_path' is not null and p->>'proof_path' not like u::text||'/proof/%' then raise exception 'Comprovante deve pertencer à sua conta';end if;
 c:=(p->>'correct')::int;w:=(p->>'wrong')::int;if c+w<1 then raise exception 'Informe ao menos uma questão';end if;
 idv:=coalesce((p->>'request_id')::uuid,gen_random_uuid());
 if exists(select 1 from public.orbit_external where id=idv and user_id<>u) then raise exception 'Identificador indisponível';end if;
 insert into public.orbit_external(id,user_id,source,correct,wrong,proof_path) values(idv,u,p->>'source',c,w,p->>'proof_path') on conflict(id) do nothing;
 return jsonb_build_object('id',idv);
 when 'external_proof' then
 if p->>'proof_path' not like u::text||'/proof/%' then raise exception 'Comprovante deve pertencer à sua conta';end if;
 update public.orbit_external set proof_path=p->>'proof_path',status='pending' where id=(p->>'id')::uuid and user_id=u and status<>'approved';return '{}';
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
 secs:=case when coalesce((p->>'paused')::boolean,false) then 0 else least(30,greatest(0,floor(extract(epoch from now()-rowv.last_seen))::int)) end;
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
 if exists(select 1 from public.orbit_run_players here join public.orbit_run_players otherp on otherp.user_id=here.user_id join public.orbit_runs other_run on other_run.id=otherp.run_id where here.run_id=rv.id and here.status='accepted' and otherp.status='accepted' and other_run.status='active' and other_run.id<>rv.id) then raise exception 'Um participante já está em outra prova ativa';end if;
 update public.orbit_run_players set status='declined' where run_id=rv.id and status='invited';
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
 w:=(select count(*) from jsonb_object_keys(other.answers))-c;secs:=least(rv.seconds,greatest(0,floor(extract(epoch from now()-rv.started_at))::int));
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
 when 'export' then
 result:=jsonb_build_object('version','orbit-0.2','exported_at',now(),'project','rpmgilawltgekecudeqx');
 foreach ch in array array['orbit_profiles','orbit_questions','orbit_attempts','orbit_sessions','orbit_config','orbit_documents','orbit_alliances','orbit_alliance_members','orbit_messages','orbit_events','orbit_achievements','orbit_external','orbit_materials','orbit_material_votes','orbit_runs','orbit_run_players','orbit_study_blocks','orbit_room_goals','orbit_reports'] loop
 execute format('select coalesce(jsonb_agg(t),''[]''::jsonb) from public.%I t',ch) into ans;
 result:=result||jsonb_build_object(ch,ans);
 end loop;
 return result||jsonb_build_object('pilot_members',(select coalesce(jsonb_agg(m),'[]') from orbit_private.pilot_members m),'admins',(select coalesce(jsonb_agg(a),'[]') from orbit_private.admins a),'answer_keys',(select coalesce(jsonb_agg(k),'[]') from orbit_private.answer_keys k));
 when 'members' then return (select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'email',a.email,'allowed',pm.user_id is not null)),'[]') from auth.users a left join orbit_private.pilot_members pm on pm.user_id=a.id);
 when 'allow' then insert into orbit_private.pilot_members select id from auth.users where id=(p->>'user_id')::uuid on conflict do nothing;
 when 'revoke' then delete from orbit_private.pilot_members where user_id=(p->>'user_id')::uuid and user_id<>u;
 when 'review' then
 select * into rowv from public.orbit_external where id=(p->>'id')::uuid for update;
 if rowv.status='approved' then raise exception 'Registro já aprovado';end if;
 if (p->>'approve')::boolean then perform orbit_private.award(rowv.user_id,'external:'||rowv.id,'external',rowv.correct,rowv.wrong,rowv.correct*10+rowv.wrong*5,rowv.correct*10+rowv.wrong*5);end if;
 update public.orbit_external set status=case when (p->>'approve')::boolean then 'approved' else 'rejected' end,review_note=left(coalesce(p->>'note',''),1000) where id=(p->>'id')::uuid;
 when 'resolve' then update public.orbit_reports set resolved=true where id=(p->>'id')::uuid;
 when 'material_orbes' then
 if p->>'amount' is not null and (p->>'amount')::numeric<0 then raise exception 'Valor inválido';end if;
 update public.orbit_materials set orbes_reward=(p->>'amount')::numeric where id=(p->>'id')::uuid;
 when 'material_save' then
 idv:=coalesce((p->>'id')::uuid,gen_random_uuid());
 insert into public.orbit_materials(id,title,subject,kind,body,url) values(idv,left(p->>'title',200),left(coalesce(p->>'subject','Geral'),80),p->>'kind',coalesce(p->>'body',''),p->>'url') on conflict(id) do update set title=excluded.title,subject=excluded.subject,kind=excluded.kind,body=excluded.body,url=excluded.url,updated_at=now();
 when 'config' then
 if jsonb_array_length(p->'settings'->'rank_thresholds')<>4 then raise exception 'Informe quatro limiares';end if;
 if (p->'settings'->'rank_thresholds'->>0)::numeric<>0 or (p->'settings'->'rank_thresholds'->>1)::numeric<=0 or (p->'settings'->'rank_thresholds'->>2)::numeric<=(p->'settings'->'rank_thresholds'->>1)::numeric or (p->'settings'->'rank_thresholds'->>3)::numeric<=(p->'settings'->'rank_thresholds'->>2)::numeric then raise exception 'Limiares devem ser crescentes';end if;
 update public.orbit_config set settings=settings||jsonb_build_object('rank_thresholds',p->'settings'->'rank_thresholds','provisional_thresholds',false);
 else raise exception 'Operação administrativa inválida';end case;return '{}';
 else raise exception 'Operação desconhecida';end case;
end $function$

;

-- Existing accounts keep their current nickname. Newly registered profiles get onboarding.
insert into public.orbit_preferences(user_id,data) select user_id,'{"nicknameOnboarded":true}'::jsonb from public.orbit_profiles on conflict(user_id) do update set data=public.orbit_preferences.data||excluded.data;
