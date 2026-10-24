begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email,is_anonymous) values
('b7000000-0000-4000-8000-000000000001','aud-owner@example.test',false),
('b7000000-0000-4000-8000-000000000002','aud-organic@example.test',false),
('b7000000-0000-4000-8000-000000000003','aud-ads@example.test',false);
insert into public.admins values('b7000000-0000-4000-8000-000000000001','owner');
insert into private.user_sources(user_id,source) values('b7000000-0000-4000-8000-000000000003','ads');
insert into public.plans(id,code,name,price_inr,duration_days,perks,active,position)values
('b8000000-0000-4000-8000-000000000001','audmonth','Audience month',99,30,array['Perk'],true,30);
update public.app_mode set free_mode=false,free_plans_for='none',plans_visible_for='everyone';
update public.payment_settings set enabled=true,upi_id='aud@upi',payee_name='Payee',activation_mode='instant';

create function pg_temp.act_as(p uuid) returns void language sql as $$
 select set_config('request.jwt.claim.sub',p::text,true);
 select set_config('request.jwt.claims',json_build_object('sub',p,'role','authenticated')::text,true);
$$;

-- Everyone (default): both groups see and can buy.
select pg_temp.act_as('b7000000-0000-4000-8000-000000000002');
set local role authenticated;
select is((public.my_status()->>'plans_visible')::boolean,true,'Organic sees plans by default');
select is((public.create_order('b8000000-0000-4000-8000-000000000001')->>'upi_id'),'aud@upi','Organic can buy by default');
reset role;

-- Ads users only.
update public.app_mode set plans_visible_for='ads';
set local role authenticated;
select is((public.my_status()->>'plans_visible')::boolean,false,'Organic does not see plans in ads-only mode');
select is((public.plan_offers()->>'plans_visible')::boolean,false,'Offers report plans hidden');
select throws_ok($$select public.create_order('b8000000-0000-4000-8000-000000000001')$$,'P0001','Plans are not available for your account','Organic cannot buy in ads-only mode');
reset role;
update public.app_mode set free_plans_for='everyone';
set local role authenticated;
select is(jsonb_array_length(public.plan_offers()->'free_plan_ids'),0,'Hidden plans are never free');
select throws_ok($$select public.claim_free_plan('b8000000-0000-4000-8000-000000000001')$$,'P0001','Plans are not available for your account','Organic cannot claim free plan when hidden');
reset role;
update public.app_mode set free_plans_for='none';
select pg_temp.act_as('b7000000-0000-4000-8000-000000000003');
set local role authenticated;
select is((public.my_status()->>'plans_visible')::boolean,true,'Ads user sees plans in ads-only mode');
select is((public.create_order('b8000000-0000-4000-8000-000000000001')->>'upi_id'),'aud@upi','Ads user can buy in ads-only mode');
reset role;

-- Organic users only: reversed.
update public.app_mode set plans_visible_for='organic';
set local role authenticated;
select is((public.my_status()->>'plans_visible')::boolean,false,'Ads user does not see plans in organic-only mode');
select throws_ok($$select public.create_order('b8000000-0000-4000-8000-000000000001')$$,'P0001','Plans are not available for your account','Ads user cannot buy in organic-only mode');
reset role;
select pg_temp.act_as('b7000000-0000-4000-8000-000000000002');
set local role authenticated;
select is((public.my_status()->>'plans_visible')::boolean,true,'Organic sees plans in organic-only mode');
reset role;

-- Existing subscribers keep seeing their plan when plans are hidden.
reset role;
insert into public.subscriptions(user_id,plan_id,starts_at,ends_at,source)
values('b7000000-0000-4000-8000-000000000002','b8000000-0000-4000-8000-000000000001',now(),now()+interval '30 days','admin');
update public.app_mode set plans_visible_for='none';
set local role authenticated;
select is(public.my_status()->>'plan_name','Audience month','Subscriber still sees their active plan when plans are hidden');
reset role;
update public.app_mode set plans_visible_for='organic';
select pg_temp.act_as('b7000000-0000-4000-8000-000000000003');

-- Off: nobody but admins.
update public.app_mode set plans_visible_for='none';
set local role authenticated;
select is((public.my_status()->>'plans_visible')::boolean,false,'Plans hidden for users when off');
select throws_ok($$select public.create_order('b8000000-0000-4000-8000-000000000001')$$,'P0001','Plans are not available for your account','No purchases when off');
reset role;
select pg_temp.act_as('b7000000-0000-4000-8000-000000000001');
set local role authenticated;
select is((public.my_status()->>'plans_visible')::boolean,true,'Admin always sees plans for testing');
update public.app_mode set plans_visible_for='everyone' where id;
select is((select plans_visible_for from public.app_mode where id),'everyone','Owner can change who sees plans');
reset role;
select * from finish();
rollback;
