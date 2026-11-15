-- Synthetic local-only records. Never run this file against production.
insert into auth.users(id,email,is_anonymous,email_confirmed_at) values
('10000000-0000-0000-0000-000000000001','owner@migration.test',false,now()),
('10000000-0000-0000-0000-000000000002','member@migration.test',false,now()),
('10000000-0000-0000-0000-000000000003','guest@migration.test',true,null);
set session_replication_role=replica;
insert into public.admins(user_id,role) values('10000000-0000-0000-0000-000000000001','owner');
insert into private.user_sources(user_id,source) values('10000000-0000-0000-0000-000000000002','organic');
insert into public.payment_orders(id,user_id,plan_id,amount_paise,duration_days,reference,status,paid_at,bank_verified_at,utr)
select '20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002',id,12345,30,'MIGRATION-PAID','paid',now()-interval '2 days',now(),'987654321098' from public.plans where code='gold';
insert into public.payment_orders(id,user_id,plan_id,amount_paise,duration_days,reference,status)
select '20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002',id,4900,7,'MIGRATION-PENDING','pending' from public.plans where code='trial';
insert into public.subscriptions(id,user_id,plan_id,starts_at,ends_at,source,order_id)
select '30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002',plan_id,paid_at,paid_at+interval '30 days','admin',id from public.payment_orders where reference='MIGRATION-PAID';
insert into private.used_payment_utrs(utr,order_id) values('987654321098','20000000-0000-0000-0000-000000000001');
insert into public.channels(id,name,created_by,status,review_status,audience) values('40000000-0000-0000-0000-000000000001','Preserved channel','10000000-0000-0000-0000-000000000001','published','approved','all');
insert into public.support_requests(user_id,reason) values('10000000-0000-0000-0000-000000000002','Preserved request');
set session_replication_role=origin;

