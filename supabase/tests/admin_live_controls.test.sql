begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email,is_anonymous) values
('a7000000-0000-4000-8000-000000000001','live-owner@example.test',false),
('a7000000-0000-4000-8000-000000000002','live-organic@example.test',false),
('a7000000-0000-4000-8000-000000000003','live-ads@example.test',false),
('a7000000-0000-4000-8000-000000000004',null,true),
('a7000000-0000-4000-8000-000000000005','live-organic2@example.test',false);
insert into public.admins values('a7000000-0000-4000-8000-000000000001','owner');
insert into private.user_sources(user_id,source) values('a7000000-0000-4000-8000-000000000003','ads');
insert into public.plans(id,code,name,price_inr,duration_days,perks,active,position)values
('a8000000-0000-4000-8000-000000000001','livemonth','Live month',99,30,array['Perk'],true,20),
('a8000000-0000-4000-8000-000000000002','liveyear','Live year',499,365,array['Perk'],true,21);
update public.plans set free_eligible=false where code not in ('livemonth','liveyear');
update public.app_mode set free_mode=false,free_plans_for='none';
update public.payment_settings set enabled=true,upi_id='old@upi',payee_name='Old Payee',activation_mode='instant';
create temporary table live_orders(kind text primary key,data jsonb);
grant all on live_orders to authenticated;

-- Organic buyer: paid checkout uses the current UPI ID and price.
select set_config('request.jwt.claim.sub','a7000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"a7000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
select is((public.plan_offers()->>'payments_available')::boolean,true,'Payments available with UPI set');
select is(jsonb_array_length(public.plan_offers()->'free_plan_ids'),0,'No free plans while free plans are off');
insert into live_orders values('old',public.create_order('a8000000-0000-4000-8000-000000000001'));
select is((select data->>'upi_id' from live_orders where kind='old'),'old@upi','Order returns current UPI ID');
select is((select upi_id_used from public.payment_orders where id=(select (data->>'id')::uuid from live_orders where kind='old')),'old@upi','Order stores UPI ID used');
select throws_ok($$select public.claim_free_plan('a8000000-0000-4000-8000-000000000001')$$,'P0001','This plan is not free for you','Cannot claim while free plans are off');
update public.app_mode set free_plans_for='everyone';
reset role;
select is((select free_plans_for from public.app_mode where id),'none','Free plans unchanged by non-owner');

-- Owner changes price and UPI ID.
select set_config('request.jwt.claim.sub','a7000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"a7000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
update public.plans set price_inr=149,duration_days=60 where code='livemonth';
update public.payment_settings set upi_id='new@upi',payee_name='New Payee' where id;
select throws_ok($$update public.payment_settings set upi_id='not a upi' where id$$,'23514',null,'Invalid UPI ID rejected');
select ok(exists(select 1 from public.settings_audit where table_name='payment_settings' and field='upi_id' and old_value='old@upi' and new_value='new@upi'
 and changed_by='a7000000-0000-4000-8000-000000000001'),'UPI change written to history');
select ok(exists(select 1 from public.settings_audit where table_name='plans' and record_id='livemonth' and field='price_inr' and old_value='99' and new_value='149'),'Price change written to history');
reset role;

select set_config('request.jwt.claim.sub','a7000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"a7000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
select is((select count(*) from public.settings_audit),0::bigint,'History hidden from non-owners');
insert into live_orders values('new',public.create_order('a8000000-0000-4000-8000-000000000001'));
select is((select data->>'upi_id' from live_orders where kind='new'),'new@upi','New order uses new UPI ID');
select is((select (data->>'amount_paise')::bigint from live_orders where kind='new'),14900::bigint,'New order uses new price');
select is((select (data->>'duration_days')::integer from live_orders where kind='new'),60,'New order uses new duration');
select is((select amount_paise from public.payment_orders where id=(select (data->>'id')::uuid from live_orders where kind='old')),9900::bigint,'Old order keeps its price');
select is((select status from public.payment_orders where id=(select (data->>'id')::uuid from live_orders where kind='old')),'cancelled','Unpaid old-UPI order replaced');
reset role;

-- Owner clears the UPI ID: payments stop.
update public.payment_settings set upi_id=null where id;
select is((select enabled from public.payment_settings where id),false,'Clearing UPI ID turns payments off');
set local role authenticated;
select is((public.plan_offers()->>'payments_available')::boolean,false,'Payments unavailable without UPI ID');
select is((public.my_status()->>'payments_available')::boolean,false,'Status reports payments unavailable');
select throws_ok($$select public.create_order('a8000000-0000-4000-8000-000000000001')$$,'P0001','Payments are not available right now','No order without UPI ID');
reset role;
update public.payment_settings set upi_id='new@upi',payee_name='New Payee',enabled=true where id;

-- Free plans for organic users only.
update public.app_mode set free_plans_for='organic';
update public.plans set free_eligible=false where code='liveyear';
set local role authenticated;
select is(public.plan_offers()->'free_plan_ids',jsonb_build_array('a8000000-0000-4000-8000-000000000001'),'Organic user sees only eligible plan as free');
select throws_ok($$select public.create_order('a8000000-0000-4000-8000-000000000001')$$,'P0001','This plan is free for you. Tap Activate for free','Free plan cannot be bought');
select throws_ok($$select public.claim_free_plan('a8000000-0000-4000-8000-000000000002')$$,'P0001','This plan is not free for you','Non-eligible plan cannot be claimed');
select is((public.claim_free_plan('a8000000-0000-4000-8000-000000000001')->>'duration_days')::integer,60,'Organic user claims free plan');
select is((select ends_at-starts_at from public.subscriptions where user_id=auth.uid() and source='free_promo'),interval '60 days','Free plan runs for its full duration');
select is((select ads_access_status from public.profiles where id=auth.uid()),'pending','Organic free claim goes to approval');
select throws_ok($$select public.claim_free_plan('a8000000-0000-4000-8000-000000000001')$$,'P0001','You already have an active plan','No second claim while a plan is active');
reset role;
select is((select count(*) from public.payment_orders where user_id='a7000000-0000-4000-8000-000000000002' and status='paid'),0::bigint,'Free claim creates no payment');

-- Ads user must pay while free plans are organic only.
select set_config('request.jwt.claim.sub','a7000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"a7000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
set local role authenticated;
select is(jsonb_array_length(public.plan_offers()->'free_plan_ids'),0,'Ads user sees no free plans');
select throws_ok($$select public.claim_free_plan('a8000000-0000-4000-8000-000000000001')$$,'P0001','This plan is not free for you','Ads user cannot claim organic-only plan');
select is((public.create_order('a8000000-0000-4000-8000-000000000001')->>'upi_id'),'new@upi','Ads user can still pay by UPI');
reset role;

-- Ads only: reversed.
update public.app_mode set free_plans_for='ads';
set local role authenticated;
select is(jsonb_array_length(public.plan_offers()->'free_plan_ids'),1,'Ads user sees free plan in ads-only mode');
select is((public.claim_free_plan('a8000000-0000-4000-8000-000000000001')->>'plan_name'),'Live month','Ads user claims free plan');
select is((select ads_access_status from public.profiles where id=auth.uid()),'none','Ads free claim needs no approval');
reset role;
select set_config('request.jwt.claim.sub','a7000000-0000-4000-8000-000000000005',true);
select set_config('request.jwt.claims','{"sub":"a7000000-0000-4000-8000-000000000005","role":"authenticated"}',true);
set local role authenticated;
select throws_ok($$select public.claim_free_plan('a8000000-0000-4000-8000-000000000001')$$,'P0001','This plan is not free for you','Organic user pays in ads-only mode');
reset role;

-- Everyone; guests must log in.
update public.app_mode set free_plans_for='everyone';
select set_config('request.jwt.claim.sub','a7000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"a7000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":true}',true);
set local role authenticated;
select throws_ok($$select public.claim_free_plan('a8000000-0000-4000-8000-000000000001')$$,'P0001','Login required','Guest must log in to claim');
reset role;
select set_config('request.jwt.claim.sub','a7000000-0000-4000-8000-000000000005',true);
select set_config('request.jwt.claims','{"sub":"a7000000-0000-4000-8000-000000000005","role":"authenticated"}',true);
set local role authenticated;
select is((public.claim_free_plan('a8000000-0000-4000-8000-000000000001')->>'plan_name'),'Live month','Everyone mode lets organic user claim');
reset role;

-- One claim per plan per promotion: an expired claim cannot be reclaimed until a new promotion.
update public.subscriptions set starts_at=now()-interval '90 days',ends_at=now()-interval '1 day' where user_id='a7000000-0000-4000-8000-000000000005' and source='free_promo';
set local role authenticated;
select throws_ok($$select public.claim_free_plan('a8000000-0000-4000-8000-000000000001')$$,'P0001','You already claimed this free plan','One claim per plan per promotion');
reset role;
update public.app_mode set free_plans_for='none';
update public.app_mode set free_plans_for='everyone';
set local role authenticated;
select is((public.claim_free_plan('a8000000-0000-4000-8000-000000000001')->>'plan_name'),'Live month','New promotion allows a new claim');
reset role;

-- Turning free plans off stops claims.
update public.app_mode set free_plans_for='none';
select set_config('request.jwt.claim.sub','a7000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"a7000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
select is(jsonb_array_length(public.plan_offers()->'free_plan_ids'),0,'Free plans off: nothing free');
select is((select count(*) from public.free_plan_claims),0::bigint,'Claims hidden from non-owners');
select throws_ok($$select public.admin_free_plan_claims()$$,'42501','Owner required','Claim counts owner only');
reset role;
select ok(not has_function_privilege('anon','public.claim_free_plan(uuid)','execute'),'Anonymous role cannot claim');
select * from finish();
rollback;
