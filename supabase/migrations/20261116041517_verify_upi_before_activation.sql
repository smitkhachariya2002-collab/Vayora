CREATE OR REPLACE FUNCTION public.report_result(p_order uuid, p_raw text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
          -- Client callbacks are untrusted; activation requires provider/admin verification.
          update public.payment_orders set status = 'review' where id = o.id;
        end if;
      end if;
    end if;
  end if;
  return private.order_json(o.id);
end $function$
