-- Part B: owner-selected instant/manual activation. Client responses are not bank proof.
alter table public.payment_settings add column if not exists activation_mode text not null default 'instant'
 check(activation_mode in ('instant','manual'));
alter table public.payment_orders add column client_status text;
alter table public.payment_orders add column auto_activated boolean not null default false;
alter table public.payment_orders add column bank_verified_at timestamptz;
alter table public.payment_orders drop constraint payment_orders_status_check;
update public.payment_orders set status='initiated' where status='created';
alter table public.payment_orders alter column status set default 'initiated';
alter table public.payment_orders add constraint payment_orders_status_check
 check(status in ('initiated','pending','success','failed','cancelled','revoked'));
drop index if exists public.orders_open_idx;
create index orders_open_idx on public.payment_orders(created_at) where status in ('initiated','pending');
create index orders_auto_review_idx on public.payment_orders(paid_at) where auto_activated and bank_verified_at is null and status='success';
create table private.used_payment_utrs(
 utr text primary key,order_id uuid references public.payment_orders on delete set null,created_at timestamptz not null default now());
alter table private.used_payment_utrs enable row level security;
revoke all on private.used_payment_utrs from public,anon,authenticated;
insert into private.used_payment_utrs(utr,order_id)
 select upper(utr),id from public.payment_orders where utr is not null on conflict do nothing;
create or replace function private.create_payment_order(p_plan uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare pl public.plans; settings public.payment_settings; ord public.payment_orders;
begin
 if not private.is_member() then raise exception 'Login required'; end if;
 if not exists(select 1 from public.app_mode where id and not free_mode) then raise exception 'Payments unavailable in free mode'; end if;
 select * into settings from public.payment_settings where id and enabled and length(btrim(upi_id))>2 and length(btrim(payee_name))>0;
 if not found then raise exception 'Payments are not available right now'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 select * into pl from public.plans where id=p_plan and active;
 if not found then raise exception 'Plan unavailable'; end if;
 update public.payment_orders set status='cancelled',reason='Replaced or expired'
 where user_id=auth.uid() and status in ('initiated','pending') and (plan_id<>p_plan or created_at<=now()-interval '24 hours');
 select * into ord from public.payment_orders where user_id=auth.uid() and plan_id=p_plan and status in ('initiated','pending')
 and created_at>now()-interval '24 hours' order by created_at desc limit 1 for update;
 if not found then
 insert into public.payment_orders(user_id,plan_id,amount_paise,duration_days,reference)
 values(auth.uid(),p_plan,(pl.price_inr*100)::bigint,pl.duration_days,'VY'||to_char(now(),'YYMMDD')||encode(extensions.gen_random_bytes(6),'hex'))
 returning * into ord;
 end if;
 return to_jsonb(ord)||jsonb_build_object('upi_id',settings.upi_id,'payee_name',settings.payee_name);
end $$;

create or replace function private.activate_payment(p_order uuid,p_amount bigint,p_utr text,p_source text) returns void
language plpgsql security definer set search_path='' as $$
declare ord public.payment_orders; end_time timestamptz; canonical text=upper(btrim(p_utr));
begin
 select * into ord from public.payment_orders where id=p_order;
 if not found or ord.user_id is null then raise exception 'Order unavailable'; end if;
 perform 1 from public.profiles where id=ord.user_id for update;
 select * into ord from public.payment_orders where id=p_order for update;
 if ord.status='success' then
   if ord.amount_paise<>p_amount or upper(ord.utr)<>canonical then raise exception 'Payment already activated with different details'; end if;
   return;
 end if;
 if ord.status in ('revoked','cancelled') then raise exception 'Order closed'; end if;
 if p_source not in ('upi_app','admin','provider_api') then raise exception 'Invalid activation source'; end if;
 if p_amount<>ord.amount_paise then raise exception 'Amount mismatch'; end if;
 if canonical is null or canonical !~ '^[A-Z0-9]{6,40}$' then raise exception 'Valid UTR required'; end if;
 if exists(select 1 from private.used_payment_utrs where utr=canonical) then raise exception 'transaction id already used'; end if;
 insert into private.used_payment_utrs(utr,order_id) values(canonical,ord.id);
 select greatest(now(),coalesce(max(ends_at),now())) into end_time from public.subscriptions
 where user_id=ord.user_id and revoked_at is null and starts_at<=now() and ends_at>now();
 update public.payment_orders set status='success',utr=canonical,paid_at=now(),reason=null,
 auto_activated=p_source='upi_app',bank_verified_at=case when p_source='admin' then now() else null end where id=p_order;
 insert into public.subscriptions(user_id,plan_id,starts_at,ends_at,source,order_id)
 values(ord.user_id,ord.plan_id,now(),end_time+make_interval(days=>ord.duration_days),p_source,p_order);
 if coalesce((select source from private.user_sources where user_id=ord.user_id),'organic')='organic' then
 update public.profiles set ads_access_status='pending' where id=ord.user_id and ads_access_status='none';
 end if;
 insert into public.payment_events(order_id,kind) values(p_order,'activated:'||p_source);
end $$;
revoke all on function private.activate_payment(uuid,bigint,text,text) from public,anon,authenticated;

create function private.payment_response(p_raw text) returns jsonb language sql immutable set search_path='' as $$
 select coalesce(jsonb_object_agg(lower(private.url_decode(split_part(pair,'=',1))),
 private.url_decode(substr(pair,strpos(pair,'=')+1))) filter(where strpos(pair,'=')>0),'{}'::jsonb)
 from regexp_split_to_table(ltrim(coalesce(p_raw,''),'?'),'[&;]') pair
$$;
revoke all on function private.payment_response(text) from public,anon,authenticated;
create or replace function private.report_payment_result(p_order uuid,p_raw text) returns text
language plpgsql security definer set search_path='' as $$
declare ord public.payment_orders; data jsonb; st text; ref text; tx text; why text; mode text; count_auto integer;
begin
 if not private.is_member() then raise exception 'Login required'; end if;
 if length(coalesce(p_raw,''))>8192 then raise exception 'Response too long'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 select * into ord from public.payment_orders where id=p_order and user_id=auth.uid() for update;
 if not found then raise exception 'Order unavailable'; end if;
 data=private.payment_response(p_raw);st=upper(coalesce(data->>'status',''));
 ref=nullif(data->>'txnref','');tx=upper(coalesce(nullif(data->>'approvalrefno',''),nullif(data->>'txnid','')));
 insert into public.payment_events(order_id,kind,detail) values(p_order,'client_report',left(st,80));
 if ord.status not in ('initiated','pending') then return ord.status; end if;
 update public.payment_orders set raw_response=coalesce(p_raw,''),client_status=left(st,80) where id=p_order;
 if st in ('FAILURE','FAILED') then
 update public.payment_orders set status='failed',reason='client reported failure' where id=p_order;return 'failed';
 elsif st<>'SUCCESS' then
 update public.payment_orders set status='initiated',reason='payment not completed' where id=p_order;return 'initiated';
 end if;
 select activation_mode into mode from public.payment_settings where id;
 select count(*) into count_auto from public.payment_orders where user_id=auth.uid() and auto_activated and paid_at>now()-interval '24 hours';
 why=case
 when ref is not null and ref<>ord.reference then 'reference mismatch'
 when tx is null or tx !~ '^[A-Z0-9]{6,40}$' then 'missing transaction id'
 when exists(select 1 from private.used_payment_utrs where utr=tx) then 'transaction id already used'
 when ord.created_at<=now()-interval '2 hours' then 'order older than 2 hours'
 when mode='manual' then 'awaiting bank verification by owner'
 when count_auto>=3 then 'automatic activation limit reached'
 else null end;
 if why is null then
   begin
     perform private.activate_payment(p_order,ord.amount_paise,tx,'upi_app');
     return 'success';
   exception when unique_violation then why='transaction id already used';
   when raise_exception then
     if SQLERRM='transaction id already used' then why='transaction id already used'; else raise; end if;
   end;
 end if;
 update public.payment_orders set status='pending',reason=why where id=p_order;
 insert into public.payment_events(order_id,kind,detail) values(p_order,'pending_review',why);
 return 'pending';
end $$;

create or replace function private.admin_mark_payment_paid(p_order uuid,p_utr text) returns void
language plpgsql security definer set search_path='' as $$
declare amount bigint;
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 select amount_paise into amount from public.payment_orders where id=p_order;
 perform private.activate_payment(p_order,amount,p_utr,'admin');
 update public.payment_orders set bank_verified_at=now() where id=p_order;
 insert into public.audit_logs(actor_id,action,target_id) values(auth.uid(),'mark_payment_paid',p_order::text);
end $$;
create function public.admin_confirm_bank_payment(order_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 update public.payment_orders set bank_verified_at=now() where id=order_id and status='success';
 if not found then raise exception 'Successful order required'; end if;
 insert into public.audit_logs(actor_id,action,target_id) values(auth.uid(),'bank_payment_verified',order_id::text);
end $$;
revoke all on function public.admin_confirm_bank_payment(uuid) from public,anon;
grant execute on function public.admin_confirm_bank_payment(uuid) to authenticated;
create or replace function private.cancel_stale_payment_orders() returns void
language sql security definer set search_path='' as $$
 update public.payment_orders set status='cancelled',reason='Expired after 24 hours'
 where status in ('initiated','pending') and created_at<now()-interval '24 hours'
$$;
revoke all on function private.cancel_stale_payment_orders() from public,anon,authenticated;

create function public.provider_activate_payment(reference text,amount_paise bigint,utr text) returns void
language plpgsql security definer set search_path='' as $$
declare target uuid;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 select id into target from public.payment_orders o where o.reference=provider_activate_payment.reference;
 if target is null then raise exception 'Order unavailable'; end if;
 perform private.activate_payment(target,amount_paise,utr,'provider_api');
end $$;
revoke all on function public.provider_activate_payment(text,bigint,text) from public,anon,authenticated;
grant execute on function public.provider_activate_payment(text,bigint,text) to service_role;

create function public.admin_payments_to_verify() returns bigint language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 return (select count(*) from public.payment_orders where auto_activated and bank_verified_at is null and status='success'
 and (paid_at at time zone 'Asia/Kolkata')::date=(now() at time zone 'Asia/Kolkata')::date);
end $$;
revoke all on function public.admin_payments_to_verify() from public,anon;
grant execute on function public.admin_payments_to_verify() to authenticated;

create or replace function public.admin_payment_summary() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 return (select jsonb_build_object(
 'today',coalesce(sum(amount_paise) filter(where status='success' and (paid_at at time zone 'Asia/Kolkata')::date=(now() at time zone 'Asia/Kolkata')::date),0),
 'month',coalesce(sum(amount_paise) filter(where status='success' and date_trunc('month',paid_at at time zone 'Asia/Kolkata')=date_trunc('month',now() at time zone 'Asia/Kolkata')),0),
 'success',count(*) filter(where status='success'),
 'pending',count(*) filter(where status in ('initiated','pending'))) from public.payment_orders);
end $$;
