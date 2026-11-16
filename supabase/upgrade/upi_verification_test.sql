-- Disposable local fixture test only. Never grants a real subscription.
begin;
update public.app_mode set free_mode=false,plans_visible_for='everyone',free_plans_for='none';
update public.payment_settings set enabled=true,upi_id='test@bank',payee_name='Local test';
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","is_anonymous":false}',true);
do $$declare o jsonb; n bigint; begin
 select count(*) into n from public.subscriptions where user_id=auth.uid();
 o:=public.create_order((select id from public.plans where code='trial'));
 perform public.report_result((o->>'order_id')::uuid,'Status=SUCCESS&txnId=LOCALCHECK1234&txnRef='||(o->>'reference'));
 if (select status from public.payment_orders where id=(o->>'order_id')::uuid)<>'review' or (select count(*) from public.subscriptions where user_id=auth.uid())<>n then raise exception 'Untrusted callback activated'; end if;
 perform public.provider_payment_update(o->>'reference','LOCALCHECK1234','SUCCESS',999999::bigint);
 if (select status from public.payment_orders where id=(o->>'order_id')::uuid)='paid' then raise exception 'Wrong amount activated'; end if;
 perform public.provider_payment_update(o->>'reference','LOCALCHECK1234','SUCCESS',(o->>'amount_paise')::bigint);
 perform public.provider_payment_update(o->>'reference','LOCALCHECK1234','SUCCESS',(o->>'amount_paise')::bigint);
 if (select status from public.payment_orders where id=(o->>'order_id')::uuid)<>'paid' or (select count(*) from public.subscriptions where user_id=auth.uid())<>n+1 then raise exception 'Verified callback mismatch'; end if;
 if has_function_privilege('authenticated','public.provider_payment_update(text,text,text,bigint)','execute') then raise exception 'Provider callable by client'; end if;
end$$;
rollback;
