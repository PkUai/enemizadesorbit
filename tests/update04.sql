begin;
create temp table ids as select gen_random_uuid() a,gen_random_uuid() b,gen_random_uuid() c,gen_random_uuid() run;
insert into auth.users(id,email) select a,'a@example.invalid' from ids union all select b,'b@example.invalid' from ids union all select c,'c@example.invalid' from ids;
insert into orbit_private.pilot_members select a from ids union all select b from ids union all select c from ids;
insert into public.orbit_profiles(user_id,display_name) select a,'A' from ids union all select b,'B' from ids union all select c,'C' from ids;
-- Completed Pomodoro only: 14m59 = 2 Orbes.
select orbit_private.award(a,'study:test','pomodoro',0,0,10,0,899) from ids;
do $$declare a uuid;b uuid;c uuid;r jsonb;beforebalance numeric;i uuid;begin
 select ids.a,ids.b,ids.c into a,b,c from ids;
 perform set_config('request.jwt.claim.sub',a::text,true);
 assert (public.orbit_update('state')->>'balance')::numeric=2,'Pomodoro must floor 5-minute blocks';
 perform orbit_private.award(a,'study:test','pomodoro',0,0,10,0,899);
 assert (public.orbit_update('state')->>'balance')::numeric=2,'Repeated event duplicated currency';
 perform orbit_private.award(a,'bank:test1','bank',1,0,15,10,0);
 perform orbit_private.award(a,'bank:test2','bank',0,1,10,5,0);
 assert (public.orbit_update('state')->>'balance')::numeric=2,'Bank awarded before completion';
 perform public.orbit_update('bank_tick');update orbit_private.bank_rewards set seconds=600 where user_id=a;
 r:=public.orbit_update('finish_bank');assert jsonb_array_length(r)=2,'Bank receipt missing';
 assert (public.orbit_update('state')->>'balance')::numeric=4.16,'Bank aggregate base/time cap wrong';
 assert public.orbit_update('finish_bank')='[]'::jsonb,'Bank replay not empty';
 perform orbit_private.award(a,'ext:test','external',2,1,40,25,0);
 assert (public.orbit_update('state')->>'balance')::numeric=6.96,'External has wrong Orbes';
 insert into orbit_private.wallet values(a,'test-funding',1000,now());
 perform public.orbit_update('purchase',jsonb_build_object('sku','pr-15','request_id',b));
 perform public.orbit_update('purchase',jsonb_build_object('sku','pr-15','request_id',b));
 assert (public.orbit_update('state')->>'balance')::numeric=946.96,'Purchase not idempotent';
 select id into i from orbit_private.inventory where user_id=a;
 perform public.orbit_update('activate',jsonb_build_object('id',i));
 perform orbit_private.award(a,'boost:test','external',10,0,150,100,0);
 assert (select (reward_meta->>'boost_pr')::numeric>0 from public.orbit_events where ref='boost:test'),'PR boost missing';
 assert (select expires_at<=now()+interval '10 minutes' from orbit_private.inventory where id=i),'Batch did not consume 30 seconds/question';
 perform public.orbit_update('chat_send',jsonb_build_object('channel','dm:'||least(a,b)||':'||greatest(a,b),'body','private test'));
 perform set_config('request.jwt.claim.sub',c::text,true);
 assert not orbit_private.chat_allowed('dm:'||least(a,b)||':'||greatest(a,b)),'Third party DM access';
 begin perform public.orbit_update('chat_send',jsonb_build_object('channel','dm:'||least(a,b)||':'||greatest(a,b),'body','intrusion'));raise exception 'DM write allowed';exception when raise_exception then assert SQLERRM='Canal indisponível','DM write not blocked';end;
end $$;
-- Two completed participants, precise results deferred until claim.
insert into public.orbit_runs(id,owner_id,kind,title,question_ids,seconds,mode,status,question_seconds) select run,a,'match','Test Comet',array['q1','q2'],180,'comet-b','active',90 from ids;
insert into public.orbit_run_players(run_id,user_id,status,correct,elapsed,answers,tier_snapshot) select run,a,'finished',2,30,'{"q1":"A","q2":"A"}'::jsonb,0 from ids union all select run,b,'finished',1,40,'{"q1":"A","q2":"B"}'::jsonb,0 from ids;
select orbit_private.award(a,'contest-xp:'||run,'match',2,0,30,0,30) from ids;
select orbit_private.award(b,'contest-xp:'||run,'match',1,1,25,0,40) from ids;
select orbit_private.settle_competition(run) from ids;
do $$declare a uuid;b uuid;rid uuid;n numeric;r jsonb;begin
 select ids.a,ids.b,run into a,b,rid from ids;
 assert not exists(select 1 from public.orbit_events where ref in ('contest-xp:'||rid,'contest-pr:'||rid)),'Competitive progress awarded too early';
 perform set_config('request.jwt.claim.sub',a::text,true);
 assert jsonb_array_length(public.orbit_update('state')->'pending')=1,'Unseen result missing';
 select sum(amount) into n from orbit_private.wallet where user_id=a;
 r:=public.orbit_update('claim',jsonb_build_object('id',rid));
 assert jsonb_array_length(r)=2,'Claim missing XP/PR receipts';
 assert (public.orbit_update('state')->>'balance')::numeric=n+8,'Comet 6+2 incorrect';
 perform public.orbit_update('claim',jsonb_build_object('id',rid));
 assert (public.orbit_update('state')->>'balance')::numeric=n+8,'Claim replay duplicated';
 update orbit_private.pending_rewards set ready_at=now()-interval '49 hours' where user_id=b;
 perform orbit_private.maintenance04();
 assert (select sum(amount)=6 from orbit_private.wallet where user_id=b),'48h automatic reward missing';
 assert not exists(select 1 from orbit_private.pending_rewards where user_id=b and claimed_at is null),'Automatic claim remained pending';
end $$;
-- Manual confirmation and explicit Next are separate, replay-safe operations.
insert into public.orbit_questions(id,year,number,discipline,context,prompt,alternatives,source_url)
select 'manual-'||i,2023,i,'matematica','Context','Question','[{"letter":"A","text":"A"},{"letter":"B","text":"B"}]'::jsonb,'https://example.invalid' from generate_series(1,24) i;
insert into orbit_private.answer_keys(question_id,correct_letter) select 'manual-'||i,'A' from generate_series(1,24) i;
do $$declare a uuid;b uuid;rid uuid;r jsonb;q text;deadline timestamptz;begin
 select ids.a,ids.b into a,b from ids;perform set_config('request.jwt.claim.sub',a::text,true);
 rid:=(public.orbit_competition('create',jsonb_build_object('mode','comet-b','players',jsonb_build_array(b)))->>'id')::uuid;
 perform set_config('request.jwt.claim.sub',b::text,true);perform public.orbit_competition('accept',jsonb_build_object('id',rid));
 perform set_config('request.jwt.claim.sub',a::text,true);r:=public.orbit_competition('begin',jsonb_build_object('id',rid));q:=r->'run'->'question_ids'->>0;deadline:=(r->'mine'->>'question_deadline')::timestamptz;
 r:=public.orbit_competition('answer',jsonb_build_object('id',rid,'question_id',q,'choice','A'));
 assert (r->'mine'->>'question_index')::int=1,'Confirm advanced automatically';
 assert (r->'mine'->>'question_deadline')::timestamptz=deadline,'Confirm reset clock';
 r:=public.orbit_competition('next',jsonb_build_object('id',rid,'question_index',1));
 assert (r->'mine'->>'question_index')::int=2,'Explicit Next did not advance';
 r:=public.orbit_competition('next',jsonb_build_object('id',rid,'question_index',1));
 assert (r->'mine'->>'question_index')::int=2,'Repeated Next advanced twice';
 -- Daily's start window does not terminate a player who already started.
 update public.orbit_runs set status='cancelled' where id=rid;
 rid:=(public.orbit_competition('create',jsonb_build_object('mode','daily','players',jsonb_build_array(b)))->>'id')::uuid;
 perform set_config('request.jwt.claim.sub',b::text,true);r:=public.orbit_competition('accept',jsonb_build_object('id',rid));
 assert (r->'run'->>'ends_at')::timestamptz=now()+interval '8 hours','Daily start window incorrect';
 perform set_config('request.jwt.claim.sub',a::text,true);perform public.orbit_competition('begin',jsonb_build_object('id',rid));
 update public.orbit_runs set ends_at=now()-interval '1 second' where id=rid;
 r:=public.orbit_competition('tick',jsonb_build_object('id',rid));
 assert r->'mine'->>'status'='playing','Daily terminated started player at start-window cutoff';
end $$;
-- RLS actually executed as authenticated, not only predicates checked.
grant select on ids to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub',c::text,true) from ids;
do $$begin assert not exists(select 1 from public.orbit_messages where channel=(select 'dm:'||least(a,b)||':'||greatest(a,b) from ids)),'DM read leaked via RLS';end $$;
rollback;
