-- pgTAP tests for Vayora 1.0.12, run only against a disposable database.
begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();

select is(private.meta_source('Instagram'),'meta','Meta aliases have a single canonical source');
select is(private.meta_source('google-play'),'google-play','Non-Meta source stays distinct');
select is(private.classify_install_referrer('ok','utm_source=google-play&utm_medium=organic'),'organic','Play Store default is organic');
select is(private.classify_install_referrer('none',''),'direct','Plain APK is direct');
select is(private.classify_install_referrer('unavailable',''),'unknown','Play transient failure is unknown');
select is(private.classify_install_referrer('apk_define','utm_source=meta&utm_medium=paid_social'),'meta','Ads APK source is Meta');
select is(private.parse_install_referrer('utm_source%3Dmeta%26utm_medium%3Dpaid_social%26utm_campaign%3Dwinter')->>'utm_campaign','winter','Encoded Play referrer decodes campaign');
select is(private.parse_install_referrer('utm_source=meta&utm_content=creative_a')->>'utm_content','creative_a','Creative dimension is preserved');

insert into auth.users(id,email,is_anonymous)
values ('93000000-0000-4000-8000-000000000001','attribution-test@example.test',true);
select set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"93000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select is(public.record_install_attributed('meta-install-test-0001','apk_define',
 'utm_source=meta&utm_medium=paid_social&utm_campaign=launch','install-test-secret-01',null,null),
 'ads','Meta install is identified as ads');
select is(public.record_install_attributed('meta-install-test-0001','none',
 '','install-test-secret-01',null,null),
 'ads','Lower confidence repeat does not erase Meta first touch');
select is(public.link_install_attribution('meta-install-test-0001','install-test-secret-01'),
 'ads','User attribution can be linked to authenticated account');
reset role;

select is((select utm_campaign from public.installs where install_id='meta-install-test-0001'),
 'launch','Campaign retained after a lower-confidence repeat');
select is((select attribution_class from public.installs where install_id='meta-install-test-0001'),
 'meta','First-touch class is still Meta');
select is((select first_touch_campaign from private.user_attribution where user_id='93000000-0000-4000-8000-000000000001'),
 'launch','First-touch campaign recorded on account');
select is((select last_touch_source from private.user_attribution where user_id='93000000-0000-4000-8000-000000000001'),
 'meta','Last-touch source recorded on account');
select * from finish();
rollback;
