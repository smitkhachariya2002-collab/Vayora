begin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated","is_anonymous":true}',true);
select public.accept_app_consent('2026-11-15-v2');
select public.accept_app_consent('2026-11-15-v2');
do $$begin
 if (select count(*) from public.app_policy_acceptances) <> 1 then raise exception 'Guest consent missing or duplicate'; end if;
 if exists(select 1 from public.consents) then raise exception 'App consent changed channel access'; end if;
 begin
  perform public.accept_app_consent('unknown');
  raise exception 'Invalid policy accepted';
 exception when check_violation then null; end;
 begin
  insert into public.app_policy_acceptances(user_id,policy_version) values('10000000-0000-0000-0000-000000000002','2026-11-15-v2');
  raise exception 'Other user consent forged';
 exception when insufficient_privilege then null; end;
 begin
  perform public.accept_consent('2026-11-15-v2');
  raise exception 'Guest gained member consent';
 exception when insufficient_privilege then null; end;
end$$;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated","is_anonymous":false}',true);
do $$begin
 if exists(select 1 from public.app_policy_acceptances) then raise exception 'Cross-user consent leak'; end if;
end$$;
select public.accept_app_consent('2026-11-15-v2');
set local role anon;
do $$begin
 begin
  perform public.accept_app_consent('2026-11-15-v2');
  raise exception 'Unauthenticated caller accepted';
 exception when insufficient_privilege then null; end;
end$$;
rollback;
