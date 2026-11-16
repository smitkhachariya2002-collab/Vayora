begin;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
do $$
declare src text; before_source text;
begin
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
rollback;
