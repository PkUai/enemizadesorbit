begin;
-- Identificadores aleatórios por navegador, não identificadores físicos do aparelho.
create table orbit_private.device_presence (
 user_id uuid not null references auth.users(id) on delete cascade,
 device_id uuid not null,
 last_seen timestamptz not null default now(),
 primary key(user_id,device_id)
);
create index device_presence_last_seen on orbit_private.device_presence(last_seen);
alter table orbit_private.device_presence enable row level security;
revoke all on orbit_private.device_presence from public,anon,authenticated;
create policy device_presence_no_client_access on orbit_private.device_presence for all to authenticated using(false) with check(false);
create function orbit_private.presence(p_device uuid,p_leave boolean default false)
returns integer language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); total integer;
begin
 if u is null or not exists(select 1 from orbit_private.pilot_members where user_id=u) then raise exception 'Acesso restrito aos testadores';end if;
 if p_device is null then raise exception 'Dispositivo inválido';end if;
 if p_leave then
  delete from orbit_private.device_presence where user_id=u and device_id=p_device;
 else
  insert into orbit_private.device_presence(user_id,device_id) values(u,p_device)
  on conflict(user_id,device_id) do update set last_seen=now();
 end if;
 delete from orbit_private.device_presence where last_seen<now()-interval '1 day';
 select count(*)::int into total from orbit_private.device_presence p join orbit_private.pilot_members m on m.user_id=p.user_id where p.last_seen>now()-interval '90 seconds';
 return total;
end $$;
revoke all on function orbit_private.presence(uuid,boolean) from public,anon,authenticated;
grant execute on function orbit_private.presence(uuid,boolean) to authenticated;
create function public.orbit_presence(p_device uuid,p_leave boolean default false)
returns integer language sql security invoker set search_path='' as $$ select orbit_private.presence(p_device,p_leave) $$;
revoke all on function public.orbit_presence(uuid,boolean) from public,anon;
grant execute on function public.orbit_presence(uuid,boolean) to authenticated;
commit;
