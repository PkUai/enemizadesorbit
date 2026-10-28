import {PGlite} from '@electric-sql/pglite';
import fs from 'node:fs';
const db=new PGlite();const s=JSON.parse(fs.readFileSync('tests/fixtures/schema-0.3.json','utf8'));const q=x=>'"'+x.replaceAll('"','""')+'"';
try{
await db.exec(`create role authenticated;create role anon;create schema auth;create schema orbit_private;create schema cron;create table auth.users(id uuid primary key,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth,public,orbit_private to authenticated;grant execute on function auth.uid() to authenticated;set check_function_bodies=off;create function cron.schedule(text,text,text) returns bigint language sql as $$select 1::bigint$$;`);
for(const t of s.tables){await db.exec('create table '+q(t.schema)+'.'+q(t.name)+'('+t.columns.map(c=>q(c.name)+' '+c.type+(c.identity?' generated '+(c.identity==='a'?'always':'by default')+' as identity':c.default?' default '+c.default:'')+(c.notnull?' not null':'')).join(',')+');');}
for(const c of [...s.constraints].sort((a,b)=>a.includes('FOREIGN KEY')-b.includes('FOREIGN KEY')))await db.exec(c);
for(const f of s.functions)await db.exec(f);
for(const t of s.triggers)await db.exec(t);
for(const p of s.policies)await db.exec('create policy '+q(p.name)+' on '+q(p.schema)+'.'+q(p.table)+' for '+p.cmd+' to authenticated'+(p.qual?' using ('+p.qual+')':'')+(p.check?' with check ('+p.check+')':'')+';');
for(const t of s.tables)if(t.rls)await db.exec('alter table '+q(t.schema)+'.'+q(t.name)+' enable row level security');
await db.exec('grant select on all tables in schema public to authenticated;grant select on orbit_private.pilot_members,orbit_private.admins to authenticated;');
const cols=Object.keys(s.config);await db.query('insert into public.orbit_config ('+cols.map(q).join(',')+') values ('+cols.map((_,i)=>'$'+(i+1)).join(',')+')',Object.values(s.config));
let migration=fs.readFileSync('database/update04.sql','utf8').replace('create extension if not exists pg_cron;','');await db.exec(migration);
await db.exec(fs.readFileSync('tests/update04.sql','utf8'));
console.log('PASS: migration against live schema snapshot; wallet, boosts, bank sets, Pomodoro, pending claims, cron, DM isolation');
}catch(e){console.error(e.message);console.error(e.query?.slice(-1800));process.exitCode=1;}finally{await db.close();}
