-- Immediate cutover rollback only: run before reopening writes to the new app.
-- New-schema records are retained for reconciliation; never drop either archive.
begin;
set local lock_timeout='10s';
do $$declare r record;begin
 if to_regclass('vayora_legacy_private_20261115.v109_cutover_backup') is null then raise exception 'No cutover backup exists';end if;
 for r in select t.tgname from pg_trigger t join pg_proc p on p.oid=t.tgfoid join pg_namespace n on n.oid=p.pronamespace where t.tgrelid='auth.users'::regclass and not t.tgisinternal and n.nspname in ('public','private') loop execute format('drop trigger %I on auth.users',r.tgname);end loop;
 for r in select policyname from pg_policies where schemaname='storage' and tablename='objects' loop execute format('drop policy %I on storage.objects',r.policyname);end loop;
 for r in select schemaname,tablename from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' loop execute format('alter publication supabase_realtime drop table %I.%I',r.schemaname,r.tablename);end loop;
end$$;
select cron.alter_job(jobid,active:=false) from cron.job where jobname in ('cancel-stale-orders','meta-send','measurement-retention');
alter schema public rename to vayora_v109_rollback_public;
alter schema private rename to vayora_v109_rollback_private;
revoke all on schema vayora_v109_rollback_public,vayora_v109_rollback_private from public,anon,authenticated,service_role;
revoke all on all tables in schema vayora_v109_rollback_public,vayora_v109_rollback_private from public,anon,authenticated,service_role;
revoke all on all functions in schema vayora_v109_rollback_public,vayora_v109_rollback_private from public,anon,authenticated,service_role;
alter schema vayora_legacy_20261115 rename to public;
alter schema vayora_legacy_private_20261115 rename to private;
do $$declare r record;begin
 for r in select definition from private.v109_cutover_backup where kind in ('grant','auth_trigger','storage_policy','publication') order by case kind when 'grant' then 0 else 1 end loop execute r.definition;end loop;
end$$;
select cron.alter_job(j.jobid,command:=b.definition,active:=true) from cron.job j join private.v109_cutover_backup b on b.kind='cron' and b.name=j.jobname;
update storage.buckets s set public=(b.definition::jsonb->>'public')::boolean,file_size_limit=(b.definition::jsonb->>'file_size_limit')::bigint,allowed_mime_types=case when b.definition::jsonb->'allowed_mime_types'='null'::jsonb then null else array(select jsonb_array_elements_text(b.definition::jsonb->'allowed_mime_types')) end from private.v109_cutover_backup b where b.kind='bucket' and b.name=s.id;
notify pgrst,'reload schema';
commit;
