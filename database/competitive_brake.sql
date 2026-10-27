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
