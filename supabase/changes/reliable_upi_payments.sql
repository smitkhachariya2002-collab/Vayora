-- Durable UPI reporting and explicit review lifecycle. Existing orders retain their price/time.
alter table public.payment_orders drop constraint payment_orders_status_check;
update public.payment_orders set status=case status when 'success' then 'paid' when 'initiated' then 'pending' else status end;
alter table public.payment_orders alter column status set default 'pending';
alter table public.payment_orders add constraint payment_orders_status_check check(status in ('pending','submitted','review','paid','failed','cancelled','rejected','revoked'));
alter table public.payment_orders add column txn_id text;
alter table public.payment_orders add column upi_response text generated always as (raw_response) stored;
alter table public.payment_orders add column verified_at timestamptz;
alter table public.payment_orders add column verification_source text;
alter table public.payment_orders add column result_note text;
alter table public.payment_orders add column reviewed_by uuid references auth.users on delete set null;
alter table public.payment_orders add column updated_at timestamptz not null default now();
update public.payment_orders set verified_at=paid_at, verification_source=case when auto_activated then 'upi_app' else 'admin' end where status='paid';
drop index public.orders_open_idx;
create index orders_open_idx on public.payment_orders(created_at) where status in ('pending','submitted','review');
drop index public.orders_auto_review_idx;
create index orders_auto_review_idx on public.payment_orders(paid_at) where auto_activated and bank_verified_at is null and status='paid';
alter table public.subscriptions drop constraint subscriptions_source_check;
alter table public.subscriptions add constraint subscriptions_source_check check(source in ('upi_app','admin','provider_api','bank_credit','google_play'));
-- New API inserts supply only a plan. Trigger creates the complete server snapshot.
create function private.payment_snapshot() returns trigger language plpgsql security definer set search_path='' as $$
declare pl public.plans;
begin
 if TG_OP='INSERT' and new.reference is null then
  if not private.is_member() then raise exception 'Login required'; end if;
  select * into pl from public.plans where id=new.plan_id and active for share;
  if not found then raise exception 'Plan unavailable'; end if;
  new.id=gen_random_uuid(); new.user_id=auth.uid();
  new.amount_paise=pl.price_inr::bigint*100; new.duration_days=pl.duration_days;
  new.reference='VY'||to_char(now(),'YYMMDD')||encode(extensions.gen_random_bytes(10),'hex');
  new.status='pending';new.created_at=now();
  new.raw_response=null;new.client_status=null;new.txn_id=null;new.utr=null;
  new.verified_at=null;new.verification_source=null;new.result_note=null;new.reviewed_by=null;
 end if;
 new.updated_at=clock_timestamp();
 if TG_OP='UPDATE' and new.reason is distinct from old.reason then new.result_note=new.reason; end if;
 return new;
end $$;
revoke all on function private.payment_snapshot() from public,anon,authenticated;
create trigger payment_snapshot before insert or update on public.payment_orders for each row execute function private.payment_snapshot();
revoke insert,update,delete,truncate on public.payment_orders from public,anon,authenticated;

create function private.reserve_payment_id(p_order uuid,p_id text) returns void
language plpgsql security definer set search_path='' as $$
declare canonical text=upper(btrim(p_id)); used_by uuid;
begin
 if canonical is null or canonical !~ '^[A-Z0-9]{6,40}$' then raise exception 'Valid transaction id required'; end if;
 insert into private.used_payment_utrs(utr,order_id) values(canonical,p_order) on conflict do nothing;
 select order_id into used_by from private.used_payment_utrs where utr=canonical;
 if used_by is distinct from p_order then raise exception 'transaction id already used'; end if;
end $$;
revoke all on function private.reserve_payment_id(uuid,text) from public,anon,authenticated;

create function private.activate_subscription(p_order uuid,p_source text,p_by uuid) returns void
language plpgsql security definer set search_path='' as $$
declare ord public.payment_orders; end_time timestamptz;
begin
 select * into ord from public.payment_orders where id=p_order;
 if not found or ord.user_id is null then raise exception 'Order not found'; end if;
 perform 1 from public.profiles where id=ord.user_id for update;
 select * into ord from public.payment_orders where id=p_order for update;
 if ord.status='paid' then return; end if;
 if ord.status not in ('pending','submitted','review') then raise exception 'Order closed'; end if;
 if p_source not in ('upi_app','admin','provider_api','bank_credit') then raise exception 'Invalid activation source'; end if;
 select greatest(now(),coalesce(max(ends_at),now())) into end_time from public.subscriptions
 where user_id=ord.user_id and revoked_at is null and starts_at<=now() and ends_at>now();
 update public.payment_orders set status='paid',paid_at=now(),verified_at=now(),verification_source=p_source,
 reviewed_by=p_by,reason=null,auto_activated=p_source='upi_app',
 bank_verified_at=case when p_source in ('admin','provider_api','bank_credit') then now() else null end where id=p_order;
 insert into public.subscriptions(user_id,plan_id,starts_at,ends_at,source,order_id)
 values(ord.user_id,ord.plan_id,now(),end_time+make_interval(days=>ord.duration_days),p_source,p_order);
 if private.source_of(ord.user_id)='organic' then
 update public.profiles set ads_access_status='pending' where id=ord.user_id and ads_access_status='none'; end if;
 insert into public.payment_events(order_id,kind) values(p_order,'activated:'||p_source);
end $$;
revoke all on function private.activate_subscription(uuid,text,uuid) from public,anon,authenticated;
create or replace function private.activate_payment(p_order uuid,p_amount bigint,p_utr text,p_source text) returns void
language plpgsql security definer set search_path='' as $$
declare ord public.payment_orders; canonical text=upper(btrim(p_utr));
begin
 select * into ord from public.payment_orders where id=p_order;
 if not found or ord.user_id is null then raise exception 'Order not found'; end if;
 perform 1 from public.profiles where id=ord.user_id for update;
 select * into ord from public.payment_orders where id=p_order for update;
 if p_amount is distinct from ord.amount_paise then raise exception 'Amount mismatch'; end if;
 if ord.status='paid' then
  if canonical is distinct from upper(ord.utr) then raise exception 'Payment already activated with different details'; end if;
  return;
 end if;
 if ord.status not in ('pending','submitted','review') then raise exception 'Order closed'; end if;
 perform private.reserve_payment_id(p_order,canonical);
 if ord.txn_id is not null then perform private.reserve_payment_id(p_order,ord.txn_id); end if;
 update public.payment_orders set utr=canonical where id=p_order;
 perform private.activate_subscription(p_order,p_source,case when p_source='admin' then auth.uid() else null end);
end $$;

create or replace function private.report_payment_result(p_order uuid,p_raw text) returns text
language plpgsql security definer set search_path='' as $$
declare ord public.payment_orders; data jsonb; st text; ref text; tx text; why text; mode text; count_auto integer;
begin
 if not private.is_member() then raise exception 'Login required'; end if;
 if length(coalesce(p_raw,''))>8192 then raise exception 'Response too long'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 select * into ord from public.payment_orders where id=p_order and user_id=auth.uid() for update;
 if not found then raise exception 'Order not found'; end if;
 -- Save first. The exception subtransaction below cannot roll back this evidence.
 update public.payment_orders set raw_response=coalesce(p_raw,'') where id=p_order;
 insert into public.payment_events(order_id,kind,detail) values(p_order,'client_report',coalesce(p_raw,''));
 begin
  data=private.payment_response(p_raw); st=upper(coalesce(data->>'status',''));
  update public.payment_orders set client_status=left(st,80) where id=p_order;
  if ord.status not in ('pending','submitted','review') then return ord.status; end if;
  if st in ('FAILURE','FAILED') then
   update public.payment_orders set status='failed',reason='client reported failure' where id=p_order; return 'failed';
  elsif st<>'SUCCESS' then return ord.status;
  end if;
  ref=nullif(data->>'txnref','');tx=upper(coalesce(nullif(data->>'approvalrefno',''),nullif(data->>'txnid','')));
  why=case when ref is not null and ref<>ord.reference then 'reference mismatch'
   when tx is null or tx !~ '^[A-Z0-9]{6,40}$' then 'missing transaction id'
   when exists(select 1 from private.used_payment_utrs where utr=tx and order_id is distinct from p_order) then 'transaction id already used'
   when exists(select 1 from public.payment_orders where id<>p_order and (upper(txn_id)=tx or upper(utr)=tx)) then 'transaction id already used'
   when ord.created_at<=now()-interval '2 hours' then 'order older than 2 hours' end;
  if why is not null then
   update public.payment_orders set status='pending',reason=why where id=p_order;return 'pending';
  end if;
  perform private.reserve_payment_id(p_order,tx);
  update public.payment_orders set txn_id=tx where id=p_order;
  select activation_mode into mode from public.payment_settings where id;
  select count(*) into count_auto from public.payment_orders where user_id=auth.uid() and auto_activated and paid_at>now()-interval '24 hours';
  if mode='manual' or count_auto>=3 then
   why=case when mode='manual' then 'awaiting bank verification by owner' else 'automatic activation limit reached' end;
   update public.payment_orders set status='review',reason=why where id=p_order;return 'review';
  end if;
  perform private.activate_payment(p_order,ord.amount_paise,tx,'upi_app');
  return 'paid';
 exception when others then
  update public.payment_orders set reason=SQLERRM where id=p_order;
  return (select status from public.payment_orders where id=p_order);
 end;
end $$;

create function private.submit_payment_utr(p_order uuid,p_utr text) returns void
language plpgsql security definer set search_path='' as $$
declare ord public.payment_orders;
begin
 if not private.is_member() then raise exception 'Login required'; end if;
 if p_utr is null or p_utr !~ '^[0-9]{12}$' then raise exception 'Enter the 12-digit bank UTR'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 select * into ord from public.payment_orders where id=p_order and user_id=auth.uid() for update;
 if not found then raise exception 'Order not found'; end if;
 if ord.status not in ('pending','failed','cancelled','submitted','review') then raise exception 'Order closed'; end if;
 perform private.reserve_payment_id(p_order,p_utr);
 update public.payment_orders set utr=p_utr,status='submitted',reason='UTR submitted for bank verification' where id=p_order;
 insert into public.payment_events(order_id,kind,detail)values(p_order,'utr_submitted',p_utr);
end $$;
create function public.submit_payment_utr(order_id uuid,utr text) returns void language sql set search_path='' as $$select private.submit_payment_utr(order_id,utr)$$;
revoke all on function private.submit_payment_utr(uuid,text),public.submit_payment_utr(uuid,text) from public,anon;
grant execute on function private.submit_payment_utr(uuid,text),public.submit_payment_utr(uuid,text) to authenticated;

create or replace function private.admin_mark_payment_paid(p_order uuid,p_utr text) returns void
language plpgsql security definer set search_path='' as $$
declare ord public.payment_orders;
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 if p_utr is null or p_utr !~ '^[0-9]{12}$' then raise exception 'Enter the 12-digit bank UTR'; end if;
 select * into ord from public.payment_orders where id=p_order;
 if not found then raise exception 'Order not found'; end if;
 perform 1 from public.profiles where id=ord.user_id for update;
 select * into ord from public.payment_orders where id=p_order for update;
 if ord.status in ('failed','cancelled') then
  update public.payment_orders set status='review' where id=p_order;
 end if;
 perform private.activate_payment(p_order,ord.amount_paise,p_utr,'admin');
 update public.payment_orders set bank_verified_at=now(),reviewed_by=auth.uid() where id=p_order;
 insert into public.audit_logs(actor_id,action,target_id) values(auth.uid(),'mark_payment_paid',p_order::text);
end $$;
create function private.reject_payment(p_order uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 if length(btrim(coalesce(p_reason,'')))=0 then raise exception 'Reason required'; end if;
 update public.payment_orders set status='rejected',reason=p_reason,reviewed_by=auth.uid()
 where id=p_order and status in ('submitted','review');
 if not found then raise exception 'Reviewable order required'; end if;
 insert into public.audit_logs(actor_id,action,target_id)values(auth.uid(),'reject_payment:'||p_reason,p_order::text);
end $$;
create function public.admin_reject_payment(order_id uuid,reason text) returns void language sql set search_path='' as $$select private.reject_payment(order_id,reason)$$;
revoke all on function private.reject_payment(uuid,text),public.admin_reject_payment(uuid,text) from public,anon;
grant execute on function private.reject_payment(uuid,text),public.admin_reject_payment(uuid,text) to authenticated;

create or replace function private.admin_revoke_payment(p_order uuid,p_reason text) returns void
language plpgsql security definer set search_path='' as $$
declare ord public.payment_orders; sub public.subscriptions;
begin
 if not private.is_owner() or length(btrim(coalesce(p_reason,'')))=0 then raise exception 'Owner and reason required'; end if;
 select * into ord from public.payment_orders where id=p_order;
 if not found then raise exception 'Order not found'; end if;
 perform 1 from public.profiles where id=ord.user_id for update;
 select * into ord from public.payment_orders where id=p_order for update;
 if ord.status='revoked' then return; end if;
 if ord.status<>'paid' then raise exception 'Successful order required'; end if;
 select * into sub from public.subscriptions where order_id=p_order;
 update public.subscriptions set revoked_at=now() where order_id=p_order;
 -- Later stacked renewals included this order's duration: remove it once from those expiries.
 update public.subscriptions set ends_at=greatest(starts_at,ends_at-make_interval(days=>ord.duration_days))
 where user_id=ord.user_id and revoked_at is null and ends_at>sub.ends_at;
 update public.payment_orders set status='revoked',reason=p_reason,reviewed_by=auth.uid() where id=p_order;
 insert into public.audit_logs(actor_id,action,target_id)values(auth.uid(),'revoke_payment:'||p_reason,p_order::text);
end $$;
create or replace function private.cancel_stale_payment_orders() returns void language sql security definer set search_path='' as $$
 update public.payment_orders set status='cancelled',reason='Expired after 24 hours'
 where status='pending' and created_at<now()-interval '24 hours'
$$;
create or replace function private.direct_payment_order(p_plan uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare pl public.plans; settings public.payment_settings; ord public.payment_orders;
begin
 if not private.is_member() then raise exception 'Login required'; end if;
 if private.client_free_mode() then raise exception 'Payments unavailable in free mode'; end if;
 select * into settings from public.payment_settings where id and enabled and length(btrim(upi_id))>2 and length(btrim(payee_name))>0;
 if not found then raise exception 'Payments are not available right now'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 select * into pl from public.plans where id=p_plan and active for share;
 if not found then raise exception 'Plan unavailable'; end if;
 update public.payment_orders set status='cancelled',reason='Replaced or expired'
 where user_id=auth.uid() and status in ('pending','submitted','review') and (plan_id<>p_plan or created_at<=now()-interval '24 hours'
 or amount_paise<>pl.price_inr::bigint*100 or duration_days<>pl.duration_days);
 select * into ord from public.payment_orders where user_id=auth.uid() and plan_id=p_plan and status in ('pending','submitted','review')
 and created_at>now()-interval '24 hours' order by created_at desc limit 1 for update;
 if not found then
 insert into public.payment_orders(plan_id) values(p_plan) returning * into ord;
 end if;
 return to_jsonb(ord)||jsonb_build_object('upi_id',settings.upi_id,'payee_name',settings.payee_name);
end $$;
create or replace function private.admin_plan_sales() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from (
 select p.name,count(o.id) as sales,coalesce(sum(o.amount_paise),0) as amount_paise from public.plans p
 left join public.payment_orders o on o.plan_id=p.id and o.status='paid' group by p.id) x),'[]');
end $$;
create or replace function private.admin_buyers() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from (
 select user_id,count(*) as purchases,sum(amount_paise) as total_paise from public.payment_orders
 where status='paid' group by user_id having count(*)>1) x),'[]');
end $$;
create or replace function public.admin_metrics() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'Admin required'; end if;
 if not private.is_owner() then return jsonb_build_object(
 'channels',(select count(*) from public.channels c where private.manage_channel(c.id)),
 'posts',(select count(*) from public.posts p where private.manage_channel(p.channel_id) and p.status='published'));
 end if;
 return jsonb_build_object(
 'ads',(select count(*) from public.installs where source='ads'),
 'organic',(select count(*) from public.installs where source='organic'),
 'users',(select count(*) from public.profiles),
 'members',(select count(*) from auth.users where not coalesce(is_anonymous,false) and deleted_at is null),
 'premium',(select count(distinct user_id) from public.subscriptions where revoked_at is null and starts_at<=now() and ends_at>now()),
 'channels',(select count(*) from public.channels),
 'posts',(select count(*) from public.posts where status='published'),
 'campaigns',coalesce((select jsonb_agg(to_jsonb(x)) from (
 select i.source,coalesce(i.utm_campaign,'Direct / no campaign') as campaign,count(*) as installs,
 count(distinct i.user_id) filter(where not coalesce(u.is_anonymous,true)) as registrations,
 count(distinct i.user_id) filter(where exists(select 1 from public.payment_orders o where o.user_id=i.user_id and o.status='paid')) as buyers
 from public.installs i left join auth.users u on u.id=i.user_id group by i.source,i.utm_campaign order by count(*) desc) x),'[]'));
end $$;
create or replace function public.admin_payment_summary() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 return (select jsonb_build_object(
 'today',coalesce(sum(amount_paise) filter(where status='paid' and (paid_at at time zone 'Asia/Kolkata')::date=(now() at time zone 'Asia/Kolkata')::date),0),
 'month',coalesce(sum(amount_paise) filter(where status='paid' and date_trunc('month',paid_at at time zone 'Asia/Kolkata')=date_trunc('month',now() at time zone 'Asia/Kolkata')),0),
 'success',count(*) filter(where status='paid'),
 'pending',count(*) filter(where status in ('pending','submitted','review'))) from public.payment_orders);
end $$;
create or replace function public.admin_confirm_bank_payment(order_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 update public.payment_orders set bank_verified_at=now() where id=order_id and status='paid';
 if not found then raise exception 'Successful order required'; end if;
 insert into public.audit_logs(actor_id,action,target_id) values(auth.uid(),'bank_payment_verified',order_id::text);
end $$;
create or replace function public.admin_payments_to_verify() returns bigint language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 return (select count(*) from public.payment_orders where auto_activated and bank_verified_at is null and status='paid'
 and (paid_at at time zone 'Asia/Kolkata')::date=(now() at time zone 'Asia/Kolkata')::date);
end $$;
create or replace function public.claim_play_reports()returns jsonb language plpgsql security definer set search_path='' as $$
declare jobs jsonb;
begin
 if coalesce(auth.role(),'')<>'service_role' or not private.play_billing_ready() then raise exception 'Play billing is disabled'; end if;
 update private.play_external_orders set report_status='failed',response='Worker interrupted'
 where report_status='sending' and last_attempt_at<now()-interval '10 minutes';
 with eligible as(select x.order_id from private.play_external_orders x join public.payment_orders o on o.id=x.order_id
 where x.report_status in('pending','failed') and o.status='paid' and (last_attempt_at is null or last_attempt_at<now()-interval '5 minutes')
 order by o.paid_at limit 20 for update of x skip locked),
 claimed as(update private.play_external_orders x set report_status='sending',attempts=attempts+1,last_attempt_at=now()
 from eligible e where x.order_id=e.order_id returning x.*)
 select coalesce(jsonb_agg(jsonb_build_object('id',x.order_id,'token',x.external_token,'amount_paise',o.amount_paise,'paid_at',o.paid_at,
 'administrative_area',x.administrative_area,'tax_rate_bps',(select tax_rate_bps from private.play_settings where id))),'[]')into jobs from claimed x join public.payment_orders o on o.id=x.order_id;
 return jobs;
end $$;
create or replace function private.play_report_dispatch()returns void language plpgsql security definer set search_path='' as $$
begin
 if private.play_billing_ready() and exists(select 1 from private.play_external_orders x join public.payment_orders o on o.id=x.order_id where x.report_status<>'sent' and o.status='paid')then
 perform net.http_post(url:='https://fzloulsjhkdxwagonsgt.supabase.co/functions/v1/play-report',body:='{}',
 headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select secret from private.play_report_config where id)),timeout_milliseconds:=10000);
 end if;
end $$;
create or replace function private.enqueue_purchase_event() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='paid' and old.status is distinct from 'paid' then
 perform private.enqueue_meta('Purchase',new.id::text,new.user_id,jsonb_build_object('value',new.amount_paise/100.0,'currency','INR','plan',
 (select name from public.plans where id=new.plan_id))); end if;
 return new;
end $$;

create function private.provider_payment_update(p_order uuid,p_status text,p_amount bigint,p_utr text,p_ref text) returns void
language plpgsql security definer set search_path='' as $$
declare ord public.payment_orders;
begin
 select * into ord from public.payment_orders where id=p_order;
 if not found then raise exception 'Order not found'; end if;
 perform 1 from public.profiles where id=ord.user_id for update;
 select * into ord from public.payment_orders where id=p_order for update;
 if ord.status in ('paid','revoked','rejected') then return; end if;
 if p_amount is distinct from ord.amount_paise then
  update public.payment_orders set status='review',reason='Provider amount mismatch' where id=p_order;return;
 end if;
 if upper(p_status) in ('SUCCESS','PAID') then
  if ord.status in ('failed','cancelled') then update public.payment_orders set status='review' where id=p_order; end if;
  perform private.activate_payment(p_order,p_amount,p_utr,'provider_api');
 elsif upper(p_status) in ('FAILURE','FAILED') then
  update public.payment_orders set status='failed',reason='Provider reported failure' where id=p_order;
 else
  update public.payment_orders set status='review',reason='Provider verification pending' where id=p_order;
 end if;
 insert into public.payment_events(order_id,kind,detail)values(p_order,'provider_update',left(coalesce(p_ref,''),200));
end $$;
create function public.provider_payment_update(order_id uuid,status text,amount_paise bigint,utr text,provider_ref text) returns void
language sql set search_path='' as $$select private.provider_payment_update(order_id,status,amount_paise,utr,provider_ref)$$;
revoke all on function private.provider_payment_update(uuid,text,bigint,text,text),public.provider_payment_update(uuid,text,bigint,text,text) from public,anon,authenticated;
grant execute on function private.provider_payment_update(uuid,text,bigint,text,text),public.provider_payment_update(uuid,text,bigint,text,text) to service_role;
