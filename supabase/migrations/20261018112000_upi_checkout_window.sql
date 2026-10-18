-- Reuse orders only while they are eligible for the existing two-hour SUCCESS rule.
-- A reported payment is recovered for review instead of starting another debit.
create or replace function private.direct_payment_order(p_plan uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare pl public.plans; settings public.payment_settings; ord public.payment_orders;
begin
 if not private.is_member() then raise exception 'Login required'; end if;
 if private.client_free_mode() then raise exception 'Payments unavailable in free mode'; end if;
 select * into settings from public.payment_settings where id and enabled and length(btrim(upi_id))>2 and length(btrim(payee_name))>0;
 if not found then raise exception 'Payments are not available right now'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 -- Preserve payment claims, even when the plan was since changed or hidden.
 select * into ord from public.payment_orders
 where user_id=auth.uid() and plan_id=p_plan and status in ('pending','submitted','review')
 and (status in ('submitted','review') or upper(coalesce(client_status,''))='SUCCESS' or utr is not null)
 order by created_at desc limit 1 for update;
 if found then
  return to_jsonb(ord)||jsonb_build_object('upi_id',settings.upi_id,'payee_name',settings.payee_name,'checkout_allowed',false);
 end if;
 select * into pl from public.plans where id=p_plan and active for share;
 if not found then raise exception 'Plan unavailable'; end if;
 update public.payment_orders set status='cancelled',reason='Replaced or checkout window expired'
 where user_id=auth.uid() and status='pending' and upper(coalesce(client_status,''))<>'SUCCESS' and utr is null
 and (plan_id<>p_plan or created_at<=now()-interval '2 hours'
 or amount_paise<>pl.price_inr::bigint*100 or duration_days<>pl.duration_days);
 select * into ord from public.payment_orders where user_id=auth.uid() and plan_id=p_plan and status='pending'
 and upper(coalesce(client_status,''))<>'SUCCESS' and utr is null
 and created_at>now()-interval '2 hours' order by created_at desc limit 1 for update;
 if not found then
  insert into public.payment_orders(plan_id) values(p_plan) returning * into ord;
 end if;
 return to_jsonb(ord)||jsonb_build_object('upi_id',settings.upi_id,'payee_name',settings.payee_name,'checkout_allowed',true);
end $$;
