-- Fixtures roll back; run as postgres against NEW project only.
begin;
update public.orbit_config set settings=settings||'{"daily_start_hours":48}'::jsonb; -- Fixture only: rollback restores unconfigured production value.
create temp table revision_ids as select gen_random_uuid() a,gen_random_uuid() b,gen_random_uuid() outsider;
grant select on revision_ids to authenticated;
insert into auth.users(id,email) select a,'revision-a-'||a||'@example.invalid' from revision_ids union all select b,'revision-b-'||b||'@example.invalid' from revision_ids union all select outsider,'revision-o-'||outsider||'@example.invalid' from revision_ids;
insert into orbit_private.pilot_members select a from revision_ids union all select b from revision_ids;
insert into public.orbit_profiles(user_id,display_name) select a,'Revision A' from revision_ids union all select b,'Revision B' from revision_ids;
create temp table revision_keys as select * from orbit_private.answer_keys;
grant select on revision_keys to authenticated;
set local role authenticated;
do $$declare a uuid;b uuid;o uuid;rid uuid;daily uuid;r jsonb;q text;k text;eid bigint;beforexp numeric;blocked boolean;ext uuid:=gen_random_uuid();begin
 select revision_ids.a,revision_ids.b,outsider into a,b,o from revision_ids;
 perform set_config('request.jwt.claim.sub',a::text,true);
 perform public.orbit_api('preferences_patch','{"theme":"dark","hidePhotos":true}');
 assert public.orbit_api('preferences_get')->>'theme'='dark','Preferences not persisted';
 perform set_config('request.jwt.claim.sub',b::text,true);
 assert public.orbit_api('preferences_get')='{}'::jsonb,'Preferences leaked';
 assert not exists(select 1 from public.orbit_preferences where user_id=a),'Preferences RLS failed';
 blocked:=false;begin insert into public.orbit_preferences(user_id,data) values(b,'{}');exception when insufficient_privilege then blocked:=true;end;assert blocked,'Direct preference write allowed';
 perform set_config('request.jwt.claim.sub',a::text,true);
 rid:=(public.orbit_competition('create',jsonb_build_object('mode','comet-b','title','Revision Comet','players',jsonb_build_array(b)))->>'id')::uuid;

 -- Legacy RPCs cannot bypass the asynchronous engine.
 perform set_config('request.jwt.claim.sub',a::text,true);blocked:=false;begin perform public.orbit_api('run_start',jsonb_build_object('id',rid));exception when others then blocked:=true;end;assert blocked,'Legacy start bypassed new engine';
 assert (select count(*)=0 from public.orbit_sessions where user_id=a),'Creating match entered active room';
 perform set_config('request.jwt.claim.sub',b::text,true);
 r:=public.orbit_competition('accept',jsonb_build_object('id',rid));
 assert r->'run'->>'status'='active','All accepts did not activate';
 assert (r->'run'->>'ends_at')::timestamptz>now()+interval '47 hours','48h window incorrect';
 perform set_config('request.jwt.claim.sub',a::text,true);
 r:=public.orbit_competition('begin',jsonb_build_object('id',rid));
 assert r->'mine'->>'status'='playing','Player not playing';
 assert (select room='Coliseu' from public.orbit_sessions where user_id=a),'Coliseu presence missing';
 q:=r->'run'->'question_ids'->>0;select correct_letter into k from revision_keys where question_id=q;
 r:=public.orbit_competition('answer',jsonb_build_object('id',rid,'question_id',q,'choice',k));
 assert (r->'mine'->>'question_index')::int=2,'Question not advanced';
 r:=public.orbit_competition('answer',jsonb_build_object('id',rid,'question_id',q,'choice',k));
 assert (r->'mine'->>'question_index')::int=2,'Retried answer advanced twice';
 q:=r->'run'->'question_ids'->>1;select correct_letter into k from revision_keys where question_id=q;
 perform public.orbit_competition('answer',jsonb_build_object('id',rid,'question_id',q,'choice',k));
 r:=public.orbit_competition('finish',jsonb_build_object('id',rid));
 assert r->'mine'->>'status'='finished','Finish not persisted';
 assert not exists(select 1 from public.orbit_sessions where user_id=a),'Finished presence leaked';
 assert (public.orbit_api('overview')->'stats'->>'xp')::numeric=30,'Participation XP incorrect';
 assert r->'run'->>'status'='active','Individual finish prematurely finished match';
 perform set_config('request.jwt.claim.sub',b::text,true);
 r:=public.orbit_competition('begin',jsonb_build_object('id',rid));
 q:=r->'run'->'question_ids'->>0;select correct_letter into k from revision_keys where question_id=q;
 perform public.orbit_competition('answer',jsonb_build_object('id',rid,'question_id',q,'choice',case when k='A' then 'B' else 'A' end));
 r:=public.orbit_competition('finish',jsonb_build_object('id',rid));
 assert r->'run'->>'status'='finished','Match not finalized';
 assert (r->'mine'->>'pr_result')::numeric=-12,'Equivalent loss must be 30% of winner PR';
 assert (public.orbit_api('overview')->'stats'->>'xp')::numeric=10,'Loser XP incorrect';
 perform set_config('request.jwt.claim.sub',a::text,true);
 r:=public.orbit_competition('state',jsonb_build_object('id',rid));assert (r->'mine'->>'pr_result')::numeric=40,'Winner PR incorrect';
 perform public.orbit_competition('finish',jsonb_build_object('id',rid));
 assert (select count(*)=2 from public.orbit_events where user_id=a and ref in ('contest-xp:'||rid,'contest-pr:'||rid)),'Duplicate settlement';
 select id into eid from public.orbit_events where user_id=a and ref='contest-pr:'||rid;
 r:=public.orbit_api('reward_receipt',jsonb_build_object('id',eid));assert r->'reward_meta'->>'final_pr'='40.00','Receipt not stored';
 perform set_config('request.jwt.claim.sub',b::text,true);assert public.orbit_api('reward_receipt',jsonb_build_object('id',eid)) is null,'Receipt leaked';
 perform set_config('request.jwt.claim.sub',a::text,true);
 beforexp:=(public.orbit_api('overview')->'stats'->>'xp')::numeric;
 perform public.orbit_api('external_add',jsonb_build_object('request_id',ext,'source','Idempotence','correct',2,'wrong',1));
 perform public.orbit_api('external_add',jsonb_build_object('request_id',ext,'source','Idempotence','correct',2,'wrong',1));
 assert (select count(*)=1 from public.orbit_external where id=ext),'Duplicate external request';
 assert (public.orbit_api('overview')->'stats'->>'xp')::numeric=beforexp,'Pending external awarded';
 daily:=(public.orbit_competition('create',jsonb_build_object('mode','daily','players',jsonb_build_array(b)))->>'id')::uuid;
 assert (select array_length(question_ids,1)=24 and question_seconds=90 from public.orbit_runs where id=daily),'Daily format incorrect';
 blocked:=false;begin perform public.orbit_competition('create',jsonb_build_object('mode','daily','players',jsonb_build_array(b)));exception when others then blocked:=true;end;assert blocked,'Daily sent limit bypass';
 perform set_config('request.jwt.claim.sub',o::text,true);blocked:=false;begin perform public.orbit_competition('state',jsonb_build_object('id',rid));exception when others then blocked:=true;end;assert blocked,'Outsider allowed';
end $$;
reset role;
-- Expired invitations, per-question clocks and WO are checked against SERVER time.
update public.orbit_runs set invite_expires_at=now()-interval '1 minute' where mode='daily' and owner_id=(select a from revision_ids);
set local role authenticated;
do $$declare r jsonb;rid uuid;a uuid;b uuid;begin
 select revision_ids.a,revision_ids.b into a,b from revision_ids;perform set_config('request.jwt.claim.sub',b::text,true);
 select id into rid from public.orbit_runs where mode='daily' and owner_id=a;
 r:=public.orbit_competition('state',jsonb_build_object('id',rid));assert r->'run'->>'status'='cancelled','Expired invite remains open';
 perform set_config('request.jwt.claim.sub',a::text,true);
 rid:=(public.orbit_competition('create',jsonb_build_object('mode','comet-b','players',jsonb_build_array(b)))->>'id')::uuid;
 perform set_config('request.jwt.claim.sub',b::text,true);perform public.orbit_competition('accept',jsonb_build_object('id',rid));
 perform set_config('request.jwt.claim.sub',a::text,true);perform public.orbit_competition('begin',jsonb_build_object('id',rid));
end $$;
reset role;
update public.orbit_run_players set question_deadline=now()-interval '1 second' where status='playing' and user_id=(select a from revision_ids);
set local role authenticated;
do $$declare r jsonb;rid uuid;a uuid;begin
 select revision_ids.a into a from revision_ids;perform set_config('request.jwt.claim.sub',a::text,true);
 select rr.id into rid from public.orbit_runs rr where rr.owner_id=a and rr.mode='comet-b' and rr.status='active';
 r:=public.orbit_competition('tick',jsonb_build_object('id',rid));assert (r->'mine'->>'question_index')::int=2,'Expired question was reset';
end $$;
reset role;
-- WO settlement after the 48h deadline; never-awarded blank questions stay at zero XP.
update public.orbit_runs set ends_at=now()-interval '1 minute' where mode='comet-b' and status='active' and owner_id=(select a from revision_ids);
set local role authenticated;
do $$declare r jsonb;rid uuid;a uuid;beforexp numeric;begin
 select revision_ids.a into a from revision_ids;perform set_config('request.jwt.claim.sub',a::text,true);
 select rr.id into rid from public.orbit_runs rr where rr.owner_id=a and rr.mode='comet-b' and rr.status='active';
 beforexp:=(public.orbit_api('overview')->'stats'->>'xp')::numeric;
 r:=public.orbit_competition('state',jsonb_build_object('id',rid));assert r->'run'->>'status'='finished','WO not settled';assert r->'mine'->>'status'='wo','Individual WO missing';assert (r->'mine'->>'pr_result')::numeric=-50,'Comet 1x1 WO penalty incorrect';
 assert (public.orbit_api('overview')->'stats'->>'xp')::numeric=beforexp,'WO blank questions got XP';
 perform public.orbit_competition('state',jsonb_build_object('id',rid));assert (select count(*)=1 from public.orbit_events where user_id=a and ref='contest-pr:'||rid),'WO penalized twice';
end $$;
reset role;
insert into orbit_private.admins select a from revision_ids;
set local role authenticated;
do $$declare a uuid;b uuid;q text;r jsonb;rid uuid;blocked boolean;begin
 select revision_ids.a,revision_ids.b into a,b from revision_ids;select question_id into q from revision_keys limit 1;
 perform set_config('request.jwt.claim.sub',b::text,true);blocked:=false;begin perform public.orbit_review_question(q,'["conceito"]','explicação',true);exception when others then blocked:=true;end;assert blocked,'Nonadmin edited question';
 perform set_config('request.jwt.claim.sub',a::text,true);perform public.orbit_review_question(q,'["conceito","fórmula"]','Explicação editorial',true);
 perform set_config('request.jwt.claim.sub',b::text,true);r:=public.orbit_question_help(q);assert r->>'explanation' is null,'Explanation leaked before answer';assert jsonb_array_length(r->'hints')=2,'Hints unavailable';
 perform public.orbit_submit_answer(q,'A');r:=public.orbit_question_help(q);assert r->>'explanation'='Explicação editorial','Explanation hidden after answer';
end $$;
reset role;
-- Latest approved maximum fall: one division per act. Historical PR is not rewritten.
insert into public.orbit_events(user_id,ref,kind,pr,created_at) select outsider,'act-drop-fixture','reading',8000,make_date(extract(year from now())::int,((extract(month from now())::int-1)/2)*2+1,1)-interval '1 day' from revision_ids;
do $$begin
 assert (orbit_private.stats((select outsider from revision_ids))->>'tier')::int=1,'Act drop must be one division';
 assert orbit_private.decay(100,0)=100 and orbit_private.decay(100,1)<100 and orbit_private.decay(100,1)>0,'Installed Sinapse decay bounds failed';
end $$;
-- Guard against a third Daily refusal; Comet refusals use a separate path.
reset role;
update public.orbit_runs set created_at=now()-interval '1 day' where mode='daily' and owner_id=(select a from revision_ids);
insert into orbit_private.daily_refusals(user_id,refusals) select b,2 from revision_ids on conflict(user_id) do update set refusals=2;
set local role authenticated;
do $$declare a uuid;b uuid;rid uuid;r jsonb;blocked boolean;q text;begin
 select revision_ids.a,revision_ids.b into a,b from revision_ids;perform set_config('request.jwt.claim.sub',a::text,true);
 rid:=(public.orbit_competition('create',jsonb_build_object('mode','daily','players',jsonb_build_array(b)))->>'id')::uuid;
 perform set_config('request.jwt.claim.sub',b::text,true);blocked:=false;begin perform public.orbit_competition('decline',jsonb_build_object('id',rid));exception when others then blocked:=true;end;assert blocked,'Third refusal allowed';
 perform public.orbit_competition('accept',jsonb_build_object('id',rid));
 perform set_config('request.jwt.claim.sub',a::text,true);
 for q in select question_id from revision_keys limit 8 loop perform public.orbit_review_question(q,'[]','',true);end loop;
 rid:=(public.orbit_competition('create',jsonb_build_object('mode','comet-a','players',jsonb_build_array(b)))->>'id')::uuid;
 assert (select array_length(question_ids,1)=8 and question_seconds=60 from public.orbit_runs where id=rid),'Reviewed Comet A format incorrect';
end $$;
reset role;
do $$begin assert (select refusals=0 from orbit_private.daily_refusals where user_id=(select b from revision_ids)),'Daily acceptance did not reset refusals';end $$;
rollback;
