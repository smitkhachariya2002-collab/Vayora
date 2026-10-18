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
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);

select lives_ok($$select public.record_install('40000000-0000-0000-0000-000000000001','none','','abcdefghijklmnopqrstuvwxyz123456')$$,'Record organic install');
select is(public.source_of('10000000-0000-0000-0000-000000000002'),'organic','Organic attribution');
select lives_ok($$select public.record_install('40000000-0000-0000-0000-000000000001','provided','utm_source=meta','abcdefghijklmnopqrstuvwxyz123456')$$,'Repeat install is idempotent');
select is(public.source_of('10000000-0000-0000-0000-000000000002'),'organic','First touch cannot change');
select is((select count(*) from public.channels),2::bigint,'Organic cannot read ads channels');
select is(public.has_ads_access(),false,'Organic has no ads access');
select throws_ok($$select public.request_full_access()$$,'P0001',null,'Paid mode cannot request free full access');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000005',true);
select is(public.has_ads_access(),true,'Owner approval unlocks ads audience without a plan');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);

select is(public.quota_bytes('10000000-0000-0000-0000-000000000002'),0::bigint,'Paid mode has no free cloud quota');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/main'),true,'Free media needs member login');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000002/main'),false,'Premium media denied without plan or ads access');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000002/trailer'),false,'Organic trailer denied');
select throws_ok($$update public.profiles set ads_access_status='approved' where id='10000000-0000-0000-0000-000000000002'$$,'42501',null,'Cannot self approve');
select throws_ok($$insert into public.admins values('10000000-0000-0000-0000-000000000002','owner')$$,'42501',null,'Cannot become owner');
select throws_ok($$update public.installs set source='ads'$$,'42501',null,'Cannot modify installs');
select lives_ok($$insert into public.channels(name,created_by) values('Pending','10000000-0000-0000-0000-000000000002')$$,'Member can propose channel');
select is((select review_status from public.channels where name='Pending'),'pending','User channel starts pending');
select throws_ok($$update public.channels set review_status='approved' where name='Pending'$$,'P0001',null,'Creator cannot approve channel');
select lives_ok($$insert into public.channel_members(user_id,channel_id) values('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001')$$,'Member can join visible channel');
insert into test_orders select (j->>'id')::uuid,j->>'reference','first' from (select public.create_payment_order((select id from public.plans where code='trial')) j) a;
select is((select amount_paise from public.payment_orders where id=(select id from test_orders where kind='first')),4900::bigint,'Server sets plan price');
select isnt((public.create_payment_order((select id from public.plans where code='trial'))->>'id')::uuid,(select id from test_orders where kind='first'),'Every checkout creates fresh order');
select is(public.report_payment_result((select id from test_orders where kind='first'),'Status=SUCCESS&txnRef=wrong&txnId=ABCDEF123456'),'pending','Wrong reference never activates');
select is(public.is_premium_user(),false,'Forged client success never grants premium');
select throws_ok($$update public.payment_orders set status='paid'$$,'42501',null,'Orders cannot be edited');
select throws_ok($$insert into public.subscriptions(user_id,plan_id,starts_at,ends_at,source) select '10000000-0000-0000-0000-000000000002',id,now(),now()+interval '1 day','admin' from public.plans limit 1$$,'42501',null,'Cannot insert subscription');
select throws_ok($$select private.activate_payment((select id from test_orders where kind='first'),4900,'ABCDEF123456','upi_app')$$,'42501',null,'Internal activation not callable');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);

select lives_ok($$select public.record_install('40000000-0000-0000-0000-000000000002','provided','utm_source=meta&utm_campaign=hello%20india','abcdefghijklmnopqrstuvwxyz654321')$$,'Record ads install');
select is(public.source_of('10000000-0000-0000-0000-000000000003'),'ads','Ads attribution');
select is(public.has_ads_access(),true,'Ads access works');
select is((select count(*) from public.channels where name in ('All','Ads','Organic')),2::bigint,'Ads cannot read organic-only channel');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000002/trailer'),true,'Ads trailer allowed');
select is(public.is_premium_user(),false,'Paid mode ads member needs a plan for full premium');
insert into test_orders select (j->>'id')::uuid,j->>'reference','second' from (select public.create_payment_order((select id from public.plans where code='silver')) j) a;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);

select is(public.quota_bytes('10000000-0000-0000-0000-000000000004'),0::bigint,'Guest has zero quota');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/main'),false,'Guest cannot play free full video');
select throws_ok($$insert into public.channel_members(user_id,channel_id) values('10000000-0000-0000-0000-000000000004','20000000-0000-0000-0000-000000000001')$$,'42501',null,'Guest cannot join');
select throws_ok($$select public.create_payment_order((select id from public.plans where code='trial'))$$,'P0001',null,'Guest cannot order');
select throws_ok($$select public.request_full_access()$$,'P0001',null,'Guest cannot request full access');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);

select lives_ok($$select public.admin_mark_payment_paid((select id from test_orders where kind='first'),'123456789012')$$,'Owner verifies payment');
select lives_ok($$select public.admin_mark_payment_paid((select id from test_orders where kind='first'),'123456789012')$$,'Activation is idempotent');
select throws_ok($$select public.admin_mark_payment_paid((select id from test_orders where kind='second'),'123456789012')$$,'P0001',null,'UTR usable once');
select is((select count(*) from public.subscriptions where order_id=(select id from test_orders where kind='first')),1::bigint,'One subscription per order');
select is((select ads_access_status::text from public.profiles where id='10000000-0000-0000-0000-000000000002'),'pending','Organic buyer becomes pending');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
select is(public.is_premium_user(),true,'Organic buyer can play visible premium before approval');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);

select lives_ok($$select public.set_ads_access('10000000-0000-0000-0000-000000000002','approved')$$,'Owner approves organic access');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);

select is(public.has_ads_access(),true,'Approved organic has ads access');
select is((select count(*) from public.channels where name='Ads'),1::bigint,'Approved organic can see ads channel');
select is(public.quota_bytes('10000000-0000-0000-0000-000000000002'),2199023255552::bigint,'Paid plan gets 2 TiB');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);

update public.app_mode set free_mode=false;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);

select is(public.is_premium_user(),false,'Paid mode requires a subscription for premium');
select is(public.can_read_media('10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000002/main'),false,'Ads without plan cannot play premium in paid-only mode');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);

update public.app_mode set free_mode=true;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);

select is(public.is_premium_user(),true,'Free mode grants ads member premium');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000005',true);
select is(public.has_ads_access(),true,'Free mode approval needs no paid plan');
select is(public.is_premium_user(),true,'Approved organic can play premium in free mode without payment');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);

select is(public.quota_bytes('10000000-0000-0000-0000-000000000003'),16106127360::bigint,'Free mode gives members 15 GiB');
select lives_ok($$select public.request_full_access()$$,'Access requests are allowed without payment in free mode');

select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
select is(public.quota_bytes('10000000-0000-0000-0000-000000000002'),16106127360::bigint,'Free mode uses 15 GiB even with a stored paid subscription');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
select ok((select count(*) from public.plans)>0,'Active catalog remains readable; free/Play UI hides purchases');
select throws_ok($$select public.create_payment_order('00000000-0000-0000-0000-000000000001')$$,'P0001',null,'Exclusive free mode blocks orders');
reset role;
update public.payment_orders set created_at=now()-interval '25 hours' where id=(select id from test_orders where kind='second');
select private.cancel_stale_payment_orders();
select is((select status from public.payment_orders where id=(select id from test_orders where kind='second')),'cancelled','Stale orders cancelled');
set local role anon;
select throws_ok($$select * from public.profiles$$,'42501',null,'Signed out cannot read profiles');
select throws_ok($$select public.my_status()$$,'42501',null,'Signed out cannot invoke member RPC');
reset role;
select ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity),'All public tables have RLS');
select * from finish();
rollback;
