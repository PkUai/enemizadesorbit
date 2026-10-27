begin;
create temp table qa_presence as select gen_random_uuid() u1,gen_random_uuid() u2,gen_random_uuid() outsider,gen_random_uuid() device1,gen_random_uuid() device2;
grant select on qa_presence to authenticated;
insert into auth.users(id,email) select u1,'presence1-'||u1||'@example.invalid' from qa_presence union all select u2,'presence2-'||u2||'@example.invalid' from qa_presence union all select outsider,'presence3-'||outsider||'@example.invalid' from qa_presence;
insert into orbit_private.pilot_members select u1 from qa_presence union all select u2 from qa_presence;
set local role authenticated;
do $$
declare a uuid;b uuid;o uuid;d1 uuid;d2 uuid;n integer;blocked boolean;
begin
 select u1,u2,outsider,device1,device2 into a,b,o,d1,d2 from qa_presence;
 perform set_config('request.jwt.claim.sub',a::text,true);
 n:=public.orbit_presence(d1,false);
 assert public.orbit_presence(d1,false)=n,'Heartbeat duplicates one browser';
 perform set_config('request.jwt.claim.sub',b::text,true);
 assert public.orbit_presence(d2,false)=n+1,'Second browser not counted';
 assert public.orbit_presence(d2,true)=n,'Logout not reflected';
 blocked:=false;begin perform count(*) from orbit_private.device_presence;exception when insufficient_privilege then blocked:=true;end;assert blocked,'Presence rows exposed directly';
 perform set_config('request.jwt.claim.sub',o::text,true);
 blocked:=false;begin perform public.orbit_presence(d1,false);exception when others then blocked:=true;end;assert blocked,'Outsider accepted';
end $$;
rollback;
