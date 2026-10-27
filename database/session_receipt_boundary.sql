CREATE OR REPLACE FUNCTION orbit_private.submit_answer(p_question text, p_choice text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=auth.uid(); k text; a public.orbit_attempts;
begin
 if u is null or not exists(select 1 from orbit_private.pilot_members where user_id=u) then raise exception 'Acesso restrito aos testadores'; end if;
 if p_choice is null or p_choice not in ('A','B','C','D','E') then raise exception 'Alternativa inválida'; end if;
 select correct_letter into k from orbit_private.answer_keys where question_id=p_question;
 if k is null then raise exception 'Questão indisponível'; end if;
 insert into public.orbit_attempts(user_id,question_id,choice,correct_letter,is_correct,points) values(u,p_question,p_choice,k,p_choice=k,case when p_choice=k then 10 else 5 end) on conflict(user_id,question_id) do nothing;
 select * into a from public.orbit_attempts where user_id=u and question_id=p_question;
 insert into public.orbit_sessions(user_id,room) values(u,'Banco de questões') on conflict(user_id) do update set room='Banco de questões',started_at=case when public.orbit_sessions.room<>'Banco de questões' or public.orbit_sessions.last_activity<now()-interval '30 minutes' then now() else public.orbit_sessions.started_at end,last_activity=now();
 return to_jsonb(a);
end;$function$
;
