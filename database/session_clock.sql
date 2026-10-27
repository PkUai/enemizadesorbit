begin;
create or replace function orbit_private.api(action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); idv uuid;rowv record;other record;rv public.orbit_runs;cfg jsonb;arr text[];result jsonb;ch text;team uuid;c integer;w integer;n integer;secs integer;ans jsonb;ids uuid[];
begin
 if u is null or not exists(select 1 from orbit_private.pilot_members where user_id=u) then raise exception 'Acesso restrito aos testadores';end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,1));
 select settings into cfg from public.orbit_config;
 case action
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
 return (select coalesce(jsonb_agg(t),'[]') from(select kind,correct,wrong,xp,pr,created_at from public.orbit_events where user_id=(p->>'id')::uuid order by created_at desc limit 100)t);
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


revoke insert,update,delete on public.orbit_sessions from authenticated;
commit;
