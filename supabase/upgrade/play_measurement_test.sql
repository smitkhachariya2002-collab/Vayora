begin;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
set local role authenticated;
select public.set_measurement_preferences(true,true,'{"install_id":"11111111-1111-4111-8111-111111111111","extinfo":["a2","com.vayora.play","21","1.0.12","14","test","en-IN","IST","","1080","1920","3","4","","",""]}'::jsonb);
select public.set_measurement_preferences(false,false,'{}'::jsonb);
reset role;
do $$begin
 if exists(select 1 from private.app_measurement_context where user_id=auth.uid()) then raise exception 'Withdrawal did not remove context'; end if;
 if exists(select 1 from public.measurement_preferences where user_id=auth.uid() and (analytics or advertising)) then raise exception 'Withdrawal not saved'; end if;
end $$;
rollback;
