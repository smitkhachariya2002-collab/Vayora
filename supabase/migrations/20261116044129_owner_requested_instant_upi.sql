CREATE OR REPLACE FUNCTION public.report_result(p_order uuid, p_raw text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$;
declare uid uuid := auth.uid(); o public.payment_orders%rowtype; raw text := coalesce(p_raw, '');
        st text; txn text; ref text; apr text; mode text; recent int; got boolean;
begin
  select * into o from public.payment_orders where id = p_order and user_id = uid for update;
  if not found then raise exception 'order not found'; end if;
  if o.status not in ('pending','submitted') then return private.order_json(o.id); end if;

  update public.payment_orders set raw_result = left(raw, 4000), reported_at = now() where id = o.id;

  st := upper(coalesce(private.upi_param(raw, 'Status'), ''));
  apr := nullif(private.upi_param(raw, 'ApprovalRefNo'), '');
  txn := coalesce(nullif(private.upi_param(raw, 'txnId'), ''), apr);
  ref := private.upi_param(raw, 'txnRef');

  if st in ('FAILURE','FAILED') then
    update public.payment_orders set status = 'failed' where id = o.id;
  elsif st = 'SUCCESS' then
    update public.payment_orders set success_reported = true where id = o.id;
    if lower(coalesce(ref, '')) = lower(o.reference)
       and txn ~ '^[A-Za-z0-9]{6,40}$'
       and o.created_at > now() - interval '2 hours' then
      insert into private.used_payment_utrs (txn_id, order_id) values (upper(txn), o.id) on conflict (txn_id) do nothing;
      get diagnostics recent = row_count;
      got := recent = 1;
      if got then
        update public.payment_orders set txn_id = txn, approval_ref = apr where id = o.id;
        select activation_mode into mode from public.payment_settings where id = 1;
        select count(*) into recent from public.payment_orders
         where user_id = uid and status = 'paid' and activation_kind = 'auto' and activated_at > now() - interval '24 hours';
        if mode = 'manual' or recent >= 3 then
          update public.payment_orders set status = 'review' where id = o.id;
        else
          -- Owner explicitly accepts instant access based on a client-reported SUCCESS.
          perform private.activate_order(o.id, 'auto');
        end if;
      end if;
    end if;
  end if;
  return private.order_json(o.id);
end $function$;

CREATE OR REPLACE FUNCTION private.activate_order(p_order uuid, p_kind text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$;
declare o public.payment_orders%rowtype; base timestamptz; new_end timestamptz;
begin
  select * into o from public.payment_orders where id = p_order for update;
  if not found then raise exception 'order not found'; end if;
  if exists (select 1 from public.subscriptions where order_id = o.id) then
    update public.payment_orders set status = 'paid', updated_at = now() where id = o.id and status <> 'paid';
    return;
  end if;
  select greatest(now(), coalesce(max(ends_at), now())) into base
    from public.subscriptions where user_id = o.user_id and not revoked and ends_at > now();
  new_end := base + private.plan_interval(o.duration_days, o.duration_hours);
  insert into public.subscriptions (user_id, plan_id, plan_code, plan_name, kind, order_id, starts_at, ends_at)
  values (o.user_id, o.plan_id, o.plan_code, o.plan_name, 'payment', o.id, base, new_end);
  update public.payment_orders set status = 'paid', activated_at = now(), activation_kind = p_kind, updated_at = now() where id = o.id;
  if private.source_of(o.user_id) = 'organic' then
    update public.profiles set ads_access_status = 'pending' where id = o.user_id and ads_access_status in ('none','rejected');
  end if;
  -- Do not send unverified instant activations as verified advertising revenue.
  if o.bank_verified then
    perform private.enqueue_meta('Purchase', o.user_id, o.id, o.amount_paise / 100.0);
  end if;
end $function$;

update public.payment_settings set activation_mode='instant' where id=1;
