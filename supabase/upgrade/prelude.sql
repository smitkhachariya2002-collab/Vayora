-- Executed atomically with the v1.0.9 schema and the data conversion.
-- Original tables, functions, data and policies are retained in private archive schemas.
set local lock_timeout = '10s';
create table private.v109_cutover_backup(kind text, name text, definition text);
insert into private.v109_cutover_backup
select 'auth_trigger',t.tgname,pg_get_triggerdef(t.oid) from pg_trigger t
join pg_proc p on p.oid=t.tgfoid join pg_namespace n on n.oid=p.pronamespace
where t.tgrelid='auth.users'::regclass and not t.tgisinternal and n.nspname in ('public','private');
insert into private.v109_cutover_backup
select 'storage_policy',policyname,format('create policy %I on %I.%I as %s for %s to %s %s %s;',policyname,schemaname,tablename,permissive,cmd,array_to_string(roles,','),case when qual is null then '' else 'using ('||qual||')' end,case when with_check is null then '' else 'with check ('||with_check||')' end)
from pg_policies where schemaname='storage' and tablename='objects';
insert into private.v109_cutover_backup select 'cron',jobname,command from cron.job where jobname like 'vayora-%' and active;
update cron.job set active=false where jobname like 'vayora-%';
do $$declare r record;begin
 for r in select tablename,schemaname from pg_tables where schemaname in ('public','private') loop
  execute format('lock table %I.%I in access exclusive mode',r.schemaname,r.tablename);
 end loop;
 for r in select name from private.v109_cutover_backup where kind='auth_trigger' loop
  execute format('drop trigger %I on auth.users',r.name);
 end loop;
 for r in select name from private.v109_cutover_backup where kind='storage_policy' loop
  execute format('drop policy %I on storage.objects',r.name);
 end loop;
 for r in select schemaname,tablename from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' loop
  execute format('alter publication supabase_realtime drop table %I.%I',r.schemaname,r.tablename);
 end loop;
end$$;
alter schema public rename to vayora_legacy_20261115;
alter schema private rename to vayora_legacy_private_20261115;
revoke all on schema vayora_legacy_20261115,vayora_legacy_private_20261115 from public,anon,authenticated,service_role;
revoke all on all tables in schema vayora_legacy_20261115,vayora_legacy_private_20261115 from public,anon,authenticated,service_role;
revoke all on all functions in schema vayora_legacy_20261115,vayora_legacy_private_20261115 from public,anon,authenticated,service_role;
create schema public;
create schema private;
grant usage on schema public to anon,authenticated,service_role;
grant usage on schema private to service_role;
alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
alter default privileges in schema public grant all on sequences to anon,authenticated,service_role;
