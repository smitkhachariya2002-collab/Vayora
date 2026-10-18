begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email,is_anonymous) values
('92000000-0000-4000-8000-000000000001','fresh-buyer@example.test',false);
update public.payment_settings set enabled=true,upi_id='test@upi',payee_name='Test',activation_mode='instant';
update public.plans set price_inr=1,duration_days=1 where code='trial';
create temporary table checkout_orders(kind text primary key,data jsonb);
grant all on checkout_orders to authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"92000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
insert into checkout_orders values('first',public.create_order((select id from public.plans where code='trial')));
insert into checkout_orders values('second',public.create_order((select id from public.plans where code='trial')));
select isnt((select data->>'id' from checkout_orders where kind='first'),(select data->>'id' from checkout_orders where kind='second'),'Every checkout creates a fresh ID');
select isnt((select data->>'reference' from checkout_orders where kind='first'),(select data->>'reference' from checkout_orders where kind='second'),'Every checkout creates a fresh bank reference');
select is((select (data->>'amount_paise')::bigint from checkout_orders where kind='second'),100::bigint,'One rupee is exactly 100 paise');
select is((select (data->>'duration_days')::integer from checkout_orders where kind='second'),1,'Duration comes from selected plan');
select is(public.report_result((select (data->>'id')::uuid from checkout_orders where kind='second'),'Status=SUCCESS&txnId=FRESHWIN01'),'pending','Missing txnRef rejected');
select is(public.report_result((select (data->>'id')::uuid from checkout_orders where kind='second'),'Status=SUCCESS&txnRef=WRONG&txnId=FRESHWIN01'),'pending','Wrong txnRef rejected');
select is(public.report_result((select (data->>'id')::uuid from checkout_orders where kind='second'),
'Status=SUCCESS&txnId=FRESHWIN01&txnRef='||(select data->>'reference' from checkout_orders where kind='second')),'paid','Exact valid SUCCESS activates fresh order');
select is(public.report_result((select (data->>'id')::uuid from checkout_orders where kind='second'),
'Status=SUCCESS&txnId=FRESHWIN01&txnRef='||(select data->>'reference' from checkout_orders where kind='second')),'paid','Duplicate result is idempotent');
select is((select count(*) from public.subscriptions where order_id=(select (data->>'id')::uuid from checkout_orders where kind='second')),1::bigint,'Exactly one entitlement');
select is((select ends_at-starts_at from public.subscriptions where order_id=(select (data->>'id')::uuid from checkout_orders where kind='second')),interval '1 day','Entire plan duration granted');
insert into checkout_orders values('third',public.create_order((select id from public.plans where code='trial')));
select is(public.report_result((select (data->>'id')::uuid from checkout_orders where kind='third'),
'Status=SUCCESS&txnId=FRESHWIN01&txnRef='||(select data->>'reference' from checkout_orders where kind='third')),'pending','Transaction ID reuse still rejected');
select is(public.report_result((select (data->>'id')::uuid from checkout_orders where kind='third'),
'Status=SUCCESS&txnId=FRESHWIN02&txnRef='||(select data->>'reference' from checkout_orders where kind='third')),'paid','Second fresh payment activates');
select is((select ends_at from public.subscriptions where order_id=(select (data->>'id')::uuid from checkout_orders where kind='third'))-
(select ends_at from public.subscriptions where order_id=(select (data->>'id')::uuid from checkout_orders where kind='second')),interval '1 day','Renewal extends current expiry by full plan duration');
insert into checkout_orders values('late',public.create_order((select id from public.plans where code='trial')));
reset role;
update public.payment_orders set created_at=now()-interval '3 hours' where id=(select (data->>'id')::uuid from checkout_orders where kind='late');
set local role authenticated;
select is(public.report_result((select (data->>'id')::uuid from checkout_orders where kind='late'),
'Status=SUCCESS&txnId=LATEWIN01&txnRef='||(select data->>'reference' from checkout_orders where kind='late')),'pending','Two-hour activation guard unchanged');
insert into checkout_orders values('after-late',public.create_order((select id from public.plans where code='trial')));
select isnt((select data->>'id' from checkout_orders where kind='late'),(select data->>'id' from checkout_orders where kind='after-late'),'Old payment does not block a fresh checkout');
select is((select client_status from public.payment_orders where id=(select (data->>'id')::uuid from checkout_orders where kind='late')),'SUCCESS','Old claim is left untouched');
select is(public.report_result((select (data->>'id')::uuid from checkout_orders where kind='after-late'),'Status=FAILURE'),'failed','FAILURE stored and shown as failed');
insert into checkout_orders values('unknown',public.create_order((select id from public.plans where code='trial')));
select is(public.report_result((select (data->>'id')::uuid from checkout_orders where kind='unknown'),'Status=NO_RESPONSE&resultCode=0'),'pending','No response stays pending');
reset role;
select ok(not has_function_privilege('authenticated','private.activate_payment(uuid,bigint,text,text)','execute'),'Client cannot grant itself access');
select * from finish();
rollback;
