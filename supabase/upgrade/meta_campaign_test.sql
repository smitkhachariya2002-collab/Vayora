-- Disposable populated upgrade fixture only. Every write is rolled back.
begin;
insert into private.user_sources(user_id,source)
 values('10000000-0000-0000-0000-000000000003','organic')
 on conflict(user_id) do nothing;
insert into public.installs(install_id,user_id,source,referrer_status,install_secret)
 values('campaign-test-install-01','10000000-0000-0000-0000-000000000003',
 'organic','play_referrer','campaign-test-secret-01');
insert into private.install_attribution(install_id,classification,confidence,
 referrer_status,utm_source,utm_medium,utm_campaign)
 values('campaign-test-install-01','meta',100,'play_referrer','meta',
 'paid_social','winter_launch');

select set_config('request.jwt.claims',
 '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select public.link_install_touch_v2('campaign-test-install-01','campaign-test-secret-01');
do $$
declare uid uuid:='10000000-0000-0000-0000-000000000003';
begin
 if not exists(select 1 from private.user_attribution
   where user_id=uid and first_touch_source='organic'
     and last_touch_source='meta' and last_touch_campaign='winter_launch'
     and last_touch_install_id='campaign-test-install-01') then
   raise exception 'Existing organic first touch or latest Meta campaign was lost';
 end if;
 if private.source_of(uid)<>'organic' then
   raise exception 'Existing account acquisition source was overwritten';
 end if;
 if public.record_web_ad_click('a0000000-0000-4000-8000-000000000001',
   false,'','','','https://vayora-eta.vercel.app/d',
   'meta','paid_social','winter_launch','creative_a') then
   raise exception 'Unconsented web click recorded';
 end if;
 if exists(select 1 from public.ad_clicks where event_id=
   'a0000000-0000-4000-8000-000000000001'::uuid) then
   raise exception 'Unconsented click row persisted';
 end if;
 if has_function_privilege('anon',
     'public.link_install_touch_v2(text,text)','EXECUTE') then
   raise exception 'Anonymous role can reassign install attribution';
 end if;
end
$$;
rollback;
