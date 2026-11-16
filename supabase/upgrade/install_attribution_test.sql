begin;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
do $$
declare src text; before_source text;
begin
 insert into private.user_sources(user_id,source) values(auth.uid(),'organic') on conflict(user_id) do nothing;
 before_source:=private.source_of(auth.uid());
 src:=public.record_install_v2('test-attribution-install','test-attribution-secret','{"status":"play_referrer","params":{"utm_source":"meta","utm_medium":"paid_social","utm_campaign":"release-test"},"click_timestamp":100,"install_timestamp":200}');
 if src<>before_source then raise exception 'Existing account source changed'; end if;
 if not exists(select 1 from private.install_attribution where install_id='test-attribution-install' and classification='meta' and confidence=100 and utm_campaign='release-test') then raise exception 'Attribution missing'; end if;
 perform public.record_install_v2('test-attribution-install','test-attribution-secret','{"status":"unavailable","params":{}}');
 if not exists(select 1 from private.install_attribution where install_id='test-attribution-install' and classification='meta' and confidence=100) then raise exception 'Evidence downgraded'; end if;
 begin
  perform public.record_install_v2('test-attribution-install','wrong-install-secret','{}');
  raise exception 'Wrong secret accepted';
 exception when insufficient_privilege then null;
 end;
 if has_table_privilege('authenticated','private.install_attribution','SELECT') or has_function_privilege('anon','public.record_install_v2(text,text,jsonb)','EXECUTE') then raise exception 'Attribution publicly accessible'; end if;
end $$;
-- Isolated transaction: a separate synthetic account tests first launch.
insert into auth.users(id,email,is_anonymous) values('77777777-7777-4777-8777-777777777777',null,true);
select set_config('request.jwt.claims','{"sub":"77777777-7777-4777-8777-777777777777","role":"authenticated"}',true);
select public.record_install_v2('test-retry-install','test-retry-install-secret','{"status":"unavailable","params":{}}');
do $$begin
 if exists(select 1 from private.user_sources where user_id=auth.uid()) then raise exception 'Unknown evidence permanently assigned source'; end if;
end $$;
select public.record_install_v2('test-retry-install','test-retry-install-secret','{"status":"play_referrer","params":{"utm_source":"meta","utm_campaign":"retry-test"}}');
do $$begin
 if private.source_of(auth.uid())<>'ads' then raise exception 'Play retry did not classify Meta'; end if;
 if not exists(select 1 from public.installs where install_id='test-retry-install' and source='ads') then raise exception 'Install cache not updated'; end if;
end $$;
rollback;

