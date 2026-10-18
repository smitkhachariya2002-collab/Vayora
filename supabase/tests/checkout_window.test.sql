begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email,is_anonymous) values
('92000000-0000-4000-8000-000000000001','window-buyer@example.test',false);
update public.payment_settings set enabled=true,upi_id='test@upi',payee_name='Test',activation_mode='instant';
create temporary table checkout_orders(kind text primary key, data jsonb);
grant all on checkout_orders to authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
insert into checkout_orders values('initial', public.create_payment_order((select id from public.plans where code='trial')));
select is((select data->>'checkout_allowed' from checkout_orders where kind='initial'),'true','Fresh order can launch UPI');
select is(public.create_payment_order((select id from public.plans where code='trial'))->>'id',
(select data->>'id' from checkout_orders where kind='initial'),'Same fresh order is reused');
reset role;
update public.payment_orders set created_at=now()-interval '2 hours' where id=(select (data->>'id')::uuid from checkout_orders where kind='initial');
set local role authenticated;
insert into checkout_orders values('renewed',public.create_payment_order((select id from public.plans where code='trial')));
select isnt((select data->>'id' from checkout_orders where kind='renewed'),
(select data->>'id' from checkout_orders where kind='initial'),'Expired order is replaced at two-hour boundary');
select is((select status from public.payment_orders where id=(select (data->>'id')::uuid from checkout_orders where kind='initial')),'cancelled','Old unpaid order cancelled');
select is(public.report_payment_result((select (data->>'id')::uuid from checkout_orders where kind='renewed'),
'Status=SUCCESS&txnId=FRESHWIN01'),'paid','Replacement order success activates');
select is((select count(*) from public.subscriptions where order_id=(select (data->>'id')::uuid from checkout_orders where kind='renewed')),1::bigint,'Exactly one subscription');
insert into checkout_orders values('late', public.create_payment_order((select id from public.plans where code='trial')));
reset role;
update public.payment_orders set created_at=now()-interval '3 hours' where id=(select (data->>'id')::uuid from checkout_orders where kind='late');
set local role authenticated;
select is(public.report_payment_result((select (data->>'id')::uuid from checkout_orders where kind='late'),
'Status=SUCCESS&txnId=LATEWIN01'),'pending','Late SUCCESS still does not bypass two-hour activation rule');
insert into checkout_orders values('recovery',public.create_payment_order((select id from public.plans where code='trial')));
select is((select data->>'id' from checkout_orders where kind='recovery'),
(select data->>'id' from checkout_orders where kind='late'),'Late SUCCESS is recovered without another debit');
select is((select data->>'checkout_allowed' from checkout_orders where kind='recovery'),'false','Claimed payment cannot relaunch UPI');
select is((select count(*) from public.payment_orders),3::bigint,'Recovery creates no duplicate order');
select is((select client_status from public.payment_orders where id=(select (data->>'id')::uuid from checkout_orders where kind='late')),'SUCCESS','Recovery preserves reported success');
select lives_ok($$select public.submit_payment_utr((select (data->>'id')::uuid from checkout_orders where kind='late'),'920000000001')$$,'Late payment accepts bank UTR for owner review');
reset role;
update public.plans set active=false,price_inr=price_inr+1 where code='trial';
set local role authenticated;
select is(public.create_payment_order((select (data->>'plan_id')::uuid from checkout_orders where kind='late'))->>'checkout_allowed','false','Submitted recovery survives plan hiding and price changes');
reset role;
select is((select status from public.payment_orders where id=(select (data->>'id')::uuid from checkout_orders where kind='late')),'submitted','Submitted claim not cancelled by checkout');
select ok(not has_function_privilege('authenticated','private.activate_payment(uuid,bigint,text,text)','execute'),'Clients still cannot activate payments');
select * from finish();
rollback;
