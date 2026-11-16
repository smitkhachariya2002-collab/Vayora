begin;
update public.app_mode set free_mode=false,plans_visible_for='everyone',free_plans_for='none';
update public.payment_settings set enabled=true,upi_id='test@bank',payee_name='Local test',activation_mode='instant';
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","is_anonymous":false}',true);
do $$declare o jsonb; n bigint; begin
 select count(*) into n from public.subscriptions where user_id=auth.uid();
 o:=public.create_order((select id from public.plans where code='trial'));
 perform public.report_result((o->>'order_id')::uuid,'Status=SUCCESS&txnId=INSTANTLOCAL123&txnRef='||(o->>'reference'));
 perform public.report_result((o->>'order_id')::uuid,'Status=SUCCESS&txnId=INSTANTLOCAL123&txnRef='||(o->>'reference'));
 if (select status from public.payment_orders where id=(o->>'order_id')::uuid)<>'paid' or (select bank_verified from public.payment_orders where id=(o->>'order_id')::uuid) or (select count(*) from public.subscriptions where user_id=auth.uid())<>n+1 then raise exception 'Instant activation mismatch'; end if;
 update public.payment_settings set activation_mode='manual';
 o:=public.create_order((select id from public.plans where code='gold'));
 perform public.report_result((o->>'order_id')::uuid,'Status=SUCCESS&txnId=MANUALLOCAL123&txnRef='||(o->>'reference'));
 if (select status from public.payment_orders where id=(o->>'order_id')::uuid)<>'review' then raise exception 'Manual option ignored'; end if;
end$$;
rollback;
