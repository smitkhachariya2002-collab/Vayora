-- Every explicit checkout creates a fresh server-snapshotted order.
-- Do not mutate existing payment claims or subscriptions.
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
 -- Preserve evidence of actual payments; only expire unclaimed/stale or repriced orders.
 update public.payment_orders set status='cancelled',reason='Replaced or checkout window expired'
 where user_id=auth.uid() and status='pending' and upper(coalesce(client_status,''))<>'SUCCESS' and utr is null
 and (created_at<=now()-interval '2 hours' or plan_id<>p_plan
 or amount_paise<>pl.price_inr::bigint*100 or duration_days<>pl.duration_days);
 insert into public.payment_orders(plan_id) values(p_plan) returning * into ord;
 return to_jsonb(ord)||jsonb_build_object('upi_id',settings.upi_id,'payee_name',settings.payee_name);
end $$;

-- SUCCESS must identify this exact order, including when the reference is missing.
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
 begin
  data=private.payment_response(p_raw); st=upper(coalesce(data->>'status',''));
 exception when others then
  data='{}'::jsonb;st='UNPARSEABLE';
 end;
 update public.payment_orders set client_status=left(st,80) where id=p_order;
 insert into public.payment_events(order_id,kind,detail) values(p_order,'client_report',coalesce(p_raw,''));
 begin
  if ord.status not in ('pending','submitted','review') then return ord.status; end if;
  if st in ('FAILURE','FAILED') then
   update public.payment_orders set status='failed',reason='client reported failure' where id=p_order; return 'failed';
  elsif st<>'SUCCESS' then return ord.status;
  end if;
  ref=nullif(data->>'txnref','');tx=upper(coalesce(nullif(data->>'approvalrefno',''),nullif(data->>'txnid','')));
  why=case when ref is distinct from ord.reference then 'reference mismatch'
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
