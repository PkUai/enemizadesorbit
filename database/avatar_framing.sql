alter table public.orbit_profiles add column if not exists avatar_position integer not null default 50 check(avatar_position between 0 and 100);
