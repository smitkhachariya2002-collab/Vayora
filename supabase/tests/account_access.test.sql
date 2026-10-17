begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email,is_anonymous) values
 ('10000000-0000-0000-0000-000000000001','owner@example.test',false),('10000000-0000-0000-0000-000000000002','organic@example.test',false),
 ('10000000-0000-0000-0000-000000000003','ads@example.test',false),('10000000-0000-0000-0000-000000000004',null,true),
 ('10000000-0000-0000-0000-000000000005','approved@example.test',false);
insert into public.admins values('10000000-0000-0000-0000-000000000001','owner');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);

insert into public.channels(id,name,audience,created_by) values
 ('20000000-0000-0000-0000-000000000001','All','all','10000000-0000-0000-0000-000000000001'),
 ('20000000-0000-0000-0000-000000000002','Ads','ads','10000000-0000-0000-0000-000000000001'),
 ('20000000-0000-0000-0000-000000000003','Organic','organic','10000000-0000-0000-0000-000000000001');
insert into public.posts(id,channel_id,title,status,created_by) values
 ('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Free','published','10000000-0000-0000-0000-000000000001'),
 ('30000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','Premium','published','10000000-0000-0000-0000-000000000001');
insert into public.post_items(post_id,media_key,trailer_key,is_premium) values
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/main',null,false),
 ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000002/main','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000002/trailer',true);
update public.payment_settings set enabled=true,upi_id='test@upi',payee_name='Test';
select public.set_ads_access('10000000-0000-0000-0000-000000000005','approved');
create temporary table test_orders(id uuid,ref text,kind text);
grant all on test_orders to authenticated;
insert into auth.users(id,is_anonymous) values('10000000-0000-0000-0000-000000000006',true);
insert into public.posts(id,channel_id,title,audience,status,created_by) values
('30000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','Ads post','ads','published','10000000-0000-0000-0000-000000000001');
insert into public.post_items(post_id,media_key,trailer_key,is_premium) values
('30000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000003/main','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000003/trailer',true);
insert into storage.objects(bucket_id,name) select 'media',media_key from public.post_items
union all select 'media',trailer_key from public.post_items where trailer_key is not null;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000006',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated"}',true);
select public.record_install('40000000-0000-0000-0000-000000000006','provided','utm_source=IG','ads-guest-secret-abcdefghijklmnopqrstuvwxyz');
select is(public.source_of(auth.uid()),'ads','IG attribution is case insensitive');
select is((public.my_status()->>'is_guest')::boolean,true,'Guest status comes from Auth');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000002/trailer'),true,'Ads guest may read trailer');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000003/trailer'),true,'Ads guest may read ads-only trailer');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000002/main'),false,'Ads guest cannot read premium full media');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/main'),false,'Full free items still require member login');
select is((select count(*) from storage.objects where bucket_id='media' and name='10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000002/trailer'),1::bigint,'Storage RLS exposes ads guest trailer key');
select throws_ok($$select public.create_payment_order((select id from public.plans limit 1))$$,'P0001',null,'Ads guest cannot create payment');
select throws_ok($$select public.record_install('40000000-0000-0000-0000-000000000006','provided','utm_source=meta','invalid-claim-abcdefghijklmnopqrstuvwxyz')$$,'P0001',null,'Install UUID alone cannot steal a claim');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',true);
select public.record_install('40000000-0000-0000-0000-000000000004','none','','organic-guest-secret-abcdefghijklmnopqrstuvwxyz');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000002/trailer'),false,'Organic guest cannot read trailer');
select is((select count(*) from public.posts where audience='ads'),0::bigint,'Organic guest cannot see ads posts');
select is((select count(*) from storage.objects where name='10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000002/trailer'),0::bigint,'Storage RLS hides organic guest trailer');
insert into public.consents(user_id,policy_version) values(auth.uid(),'v1');
reset role;
update auth.users set email='upgraded@example.test',is_anonymous=false where id='10000000-0000-0000-0000-000000000004';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',true);
select is((public.my_status()->>'is_guest')::boolean,false,'Guest upgrade keeps id and becomes member');
select is((select count(*) from public.consents where user_id=auth.uid()),1::bigint,'Guest consent history survives upgrade');
select public.attribute_user('40000000-0000-0000-0000-000000000006','ads-guest-secret-abcdefghijklmnopqrstuvwxyz');
select is(public.source_of(auth.uid()),'organic','Existing account keeps first source on an ads install');
select public.record_install('40000000-0000-0000-0000-000000000004','provided','utm_source=facebook','organic-guest-secret-abcdefghijklmnopqrstuvwxyz');
select is(public.source_of(auth.uid()),'organic','Repeat referrer cannot alter source');
reset role;
select throws_ok($$update private.user_sources set source='ads' where user_id='10000000-0000-0000-0000-000000000004'$$,'P0001','First-touch source is immutable','Privileged account source edits are rejected');
select throws_ok($$update public.installs set source='ads' where install_id='40000000-0000-0000-0000-000000000004'$$,'P0001','First-touch source is immutable','Privileged install source edits are rejected');
insert into public.subscriptions(user_id,plan_id,starts_at,ends_at,source)
select '10000000-0000-0000-0000-000000000004',id,now(),now()+interval '1 day','admin' from public.plans where code='trial';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',true);
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000002/main'),true,'Organic subscriber reads visible premium before approval');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000003/main'),false,'Plan alone cannot expose ads-only premium');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000003/trailer'),false,'Plan alone cannot expose ads-only trailer');
select is(public.has_ads_access(),false,'Plan alone does not grant audience access');
select is((public.my_status()->>'is_premium')::boolean,true,'Status reflects paid organic premium');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.set_ads_access('10000000-0000-0000-0000-000000000004','approved');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',true);
select is((select count(*) from public.posts where audience='ads'),1::bigint,'Approved organic sees ads posts');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000003/trailer'),true,'Approved organic plays trailers');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000003/main'),true,'Approved organic subscriber plays ads premium');
reset role;
update public.subscriptions set ends_at=now() where user_id='10000000-0000-0000-0000-000000000004';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',true);
select is(public.has_ads_access(),true,'Plan expiry does not revoke owner approval');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000003/trailer'),true,'Approved organic keeps trailers without a plan');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000003/main'),false,'Premium full media requires active plan');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.set_ads_access('10000000-0000-0000-0000-000000000004','rejected');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',true);
select is((select count(*) from public.posts where audience='ads'),0::bigint,'Revoking approval hides ads posts');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000003/trailer'),false,'Revoking approval hides trailers');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
update public.app_mode set free_mode=true;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000006',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated"}',true);
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000002/trailer'),true,'Free mode ads guest still gets trailer');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000002/main'),false,'Free mode still denies guest full premium');
select is(public.quota_bytes(auth.uid()),0::bigint,'Free mode guest has no cloud quota');
reset role;
update auth.users set is_anonymous=false,email='ads-upgraded@example.test' where id='10000000-0000-0000-0000-000000000006';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000006',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated"}',true);
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000003/main'),true,'Free mode ads member reads full premium without plan');
select is(public.quota_bytes(auth.uid()),16106127360::bigint,'Free mode member gets 15 GiB');
select is((select count(*) from public.plans),0::bigint,'Free mode hides plan catalog through RLS');
select throws_ok($$select public.create_payment_order('00000000-0000-0000-0000-000000000001')$$,'P0001','Payments unavailable in free mode','Free mode disallows UPI orders');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',true);
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000002/main'),false,'Free mode organic requires approval even with prior plan');
select public.request_full_access();
select is(public.my_status()->>'access_status','pending','Organic free request enters approval queue');
select is(public.quota_bytes(auth.uid()),16106127360::bigint,'Organic member also gets free cloud allowance');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.set_ads_access('10000000-0000-0000-0000-000000000004','approved');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',true);
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000003/main'),true,'Free mode approved organic gets full premium without plan');
select is(public.my_status()->'plan_name','null'::jsonb,'Free mode status conceals plan name');
select is(public.my_status()->'plan_ends_at','null'::jsonb,'Free mode status conceals paid expiry');
select ok(public.my_status() ?& array['is_guest','source','has_ads_access','is_premium','plan_name','plan_ends_at','free_mode','access_status'],'Status includes every required decision field');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
update public.app_mode set free_mode=false;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',true);
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000003/main'),false,'Switching back to paid mode immediately requires active plan');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000003/main'),true,'Admin always reads premium');
reset role;
select ok(not (select public from storage.buckets where id='media'),'Media bucket stays private');
select * from finish();
rollback;
