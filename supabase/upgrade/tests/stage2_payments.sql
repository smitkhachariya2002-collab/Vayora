-- Rollback-only test harness: impersonates users, raises an exception at the end whose text is the report.
-- Run with psql against a database that has all migrations applied. The expected 'error' is the report;
-- the run PASSES when the report contains no 'FAIL' lines.

do $outer$
declare
  owner_id uuid := gen_random_uuid();
  u1 uuid; u2 uuid; ua uuid; ug uuid; u4 uuid; u5 uuid; u6 uuid; u7 uuid; u8 uuid; u9 uuid; u10 uuid; u11 uuid;
  saved_guest uuid;
  p_trial uuid; p_silver uuid; p_gold uuid; p_plat uuid;
  c jsonb; c2 jsonb; r jsonb; v_o1 uuid; v_o2 uuid; v_o3 uuid; v_o4 uuid; v_ref text; v_st text; v_n int; v_raised boolean; v_t text;
  v_end timestamptz; i int; plans uuid[]; fail_list text; total int; failed int;
begin
  insert into private.owner_bootstrap(email) values ('owner@example.test') on conflict do nothing;
  create temp table t_res (n text, ok boolean) on commit drop;
  create function pg_temp.rec(nm text, o boolean) returns void language plpgsql security definer as $f$ begin insert into pg_temp.t_res values (nm, coalesce(o,false)); end $f$;
  create function pg_temp.imp(uid uuid, anon boolean) returns void language plpgsql as $f$
  begin
    perform set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated','is_anonymous',anon)::text, true);
    perform set_config('request.jwt.claim.sub', uid::text, true);
    set local role authenticated;
  end $f$;
  create function pg_temp.mk(em text, ads boolean) returns uuid language plpgsql as $f$
  declare id uuid := gen_random_uuid();
  begin
    insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, is_anonymous)
    values (id,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',em, case when em is null then null else now() end, em is null);
    insert into private.user_sources (user_id, source) values (id, case when ads then 'ads' else 'organic' end);
    return id;
  end $f$;
  create function pg_temp.pay(uid uuid, pl uuid, txn text) returns jsonb language plpgsql as $f$
  declare cc jsonb; rr jsonb;
  begin
    perform pg_temp.imp(uid,false);
    cc := public.create_order(pl);
    rr := public.report_result((cc->>'order_id')::uuid, 'txnId='||txn||'&responseCode=00&Status=SUCCESS&txnRef='||(cc->>'reference'));
    reset role;
    return rr;
  end $f$;

  insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, is_anonymous)
  values (owner_id,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner@example.test',now(),false);
  u1 := pg_temp.mk('u1@t.test', false); u2 := pg_temp.mk('u2@t.test', false); ua := pg_temp.mk('ua@t.test', true);
  u4 := pg_temp.mk('u4@t.test', false); u5 := pg_temp.mk('u5@t.test', false); u6 := pg_temp.mk('u6@t.test', false);
  u7 := pg_temp.mk('u7@t.test', false); u8 := pg_temp.mk('u8@t.test', false); u9 := pg_temp.mk('u9@t.test', false);
  u10 := pg_temp.mk('u10@t.test', true); u11 := pg_temp.mk('u11@t.test', false);
  ug := gen_random_uuid();
  insert into auth.users (id, instance_id, aud, role, is_anonymous) values (ug,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',true);
  select id into p_trial from public.plans where code='trial'; select id into p_silver from public.plans where code='silver';
  select id into p_gold from public.plans where code='gold'; select id into p_plat from public.plans where code='platinum';
  update public.plans set price_inr=49 where id=p_trial;
  update public.payment_settings set activation_mode='instant';

  -- guests (anonymous sessions) may buy; they add an email later. Cleaned up so later counts are unchanged.
  perform pg_temp.imp(ug,true); v_raised := false;
  begin perform public.create_order(p_gold); exception when others then v_raised := true; end; reset role;
  perform pg_temp.rec('guest can create order', not v_raised and exists (select 1 from public.payment_orders where user_id = ug and status = 'pending'));
  delete from public.meta_events where user_id = ug;
  delete from public.payment_orders where user_id = ug;
  -- Exercise the full ads guest purchase -> saved account -> pending channel flow.
  saved_guest := pg_temp.mk(null,true);
  perform pg_temp.imp(saved_guest,true);
  c := public.create_order(p_gold);
  r := public.report_result((c->>'order_id')::uuid, 'txnId=GUESTSAVE2026&responseCode=00&Status=SUCCESS&txnRef='||(c->>'reference'));
  reset role;
  perform pg_temp.rec('ads guest payment activates the same guest account', r->>'status'='paid' and private.has_plan(saved_guest));
  update auth.users set is_anonymous=false,email='saved-guest@example.test',email_confirmed_at=now() where id=saved_guest;
  perform pg_temp.imp(saved_guest,true); c2 := public.my_status(); reset role;
  perform pg_temp.rec('saved guest keeps Premium, ads source and user id with old token',
    c2->>'user_id'=saved_guest::text and not (c2->>'is_guest')::boolean and (c2->>'is_premium')::boolean and c2->>'source'='ads');
  perform pg_temp.imp(saved_guest,true); v_raised := false;
  begin insert into public.channels(name) values('Saved Premium guest channel'); exception when others then v_raised := true; end; reset role;
  perform pg_temp.rec('saved Premium guest can create channel without logging in again',not v_raised);
  perform pg_temp.rec('saved guest channel still needs admin approval',
    exists(select 1 from public.channels where created_by=saved_guest and name='Saved Premium guest channel' and review_status='pending' and status='draft'));

  perform pg_temp.imp(u1,false); c := public.create_order(p_gold); c2 := public.create_order(p_gold); reset role;
  v_o1 := (c->>'order_id')::uuid;
  perform pg_temp.rec('order snapshot: amount, OB reference, UPI id, payee', (c->>'amount_paise')::bigint=25900 and c->>'reference' ~ '^OB[0-9]{6}[A-F0-9]{8}$' and c->>'upi_id'='2728412a@bandhan' and c->>'payee_name'='As Enterprice');
  perform pg_temp.rec('same pending order is reused', c->>'order_id' = c2->>'order_id');
  perform pg_temp.imp(u1,false); c := public.create_order(p_silver); reset role;
  perform pg_temp.rec('order for another plan cancels the previous pending one', (select status from public.payment_orders where id=v_o1)='cancelled' and (c->>'status')='pending');
  perform pg_temp.imp(u1,false); c := public.create_order(p_gold); reset role; v_o1 := (c->>'order_id')::uuid;
  update public.plans set price_inr=300 where id=p_gold;
  perform pg_temp.imp(u1,false); c2 := public.create_order(p_gold); reset role;
  perform pg_temp.rec('repriced plan: old order cancelled, new order uses new price', (select status from public.payment_orders where id=v_o1)='cancelled' and (c2->>'amount_paise')::bigint=30000 and (select amount_paise from public.payment_orders where id=v_o1)=25900);
  update public.plans set price_inr=259 where id=p_gold;
  update public.app_mode set free_mode=true;
  perform pg_temp.imp(u1,false); v_raised := false;
  begin perform public.create_order(p_trial); exception when others then v_raised := true; end; reset role;
  perform pg_temp.rec('create_order refused in free mode', v_raised);
  update public.app_mode set free_mode=false, plans_visible_for='none';
  perform pg_temp.imp(u1,false); v_raised := false;
  begin perform public.create_order(p_trial); exception when others then v_raised := true; end; reset role;
  perform pg_temp.rec('create_order refused when plans hidden for user', v_raised);
  update public.app_mode set plans_visible_for='everyone', free_plans_for='organic'; update public.plans set free_eligible=true where id=p_trial;
  perform pg_temp.imp(u1,false); v_raised := false;
  begin perform public.create_order(p_trial); exception when others then v_raised := true; end; reset role;
  perform pg_temp.rec('create_order refused when plan is free for this user', v_raised);
  update public.app_mode set free_plans_for='none'; update public.plans set free_eligible=false where id=p_trial;
  update public.payment_settings set upi_id='';
  perform pg_temp.imp(u1,false); v_raised := false;
  begin perform public.create_order(p_trial); exception when others then v_raised := true; end; reset role;
  perform pg_temp.rec('create_order refused when UPI ID cleared (payments off)', v_raised and not (select public.payments_available()));
  update public.payment_settings set upi_id='2728412a@bandhan';
  update public.plans set active=false where id=p_silver;
  perform pg_temp.imp(u1,false); v_raised := false;
  begin perform public.create_order(p_silver); exception when others then v_raised := true; end; reset role;
  perform pg_temp.rec('removed/inactive plan refused', v_raised);
  update public.plans set active=true where id=p_silver;

  perform pg_temp.imp(u1,false); c := public.create_order(p_trial); reset role; v_o2 := (c->>'order_id')::uuid; v_ref := c->>'reference';
  perform pg_temp.imp(u1,false); r := public.report_result(v_o2, 'garbage-xyz'); reset role;
  perform pg_temp.rec('garbage result: raw saved, stays pending', (select raw_result='garbage-xyz' and status='pending' from public.payment_orders where id=v_o2));
  perform pg_temp.imp(u1,false); perform public.report_result(v_o2, 'Status=SUBMITTED&txnRef='||v_ref); perform public.report_result(v_o2, 'NO_RESPONSE'); reset role;
  perform pg_temp.rec('SUBMITTED / NO_RESPONSE stay pending', (select status='pending' from public.payment_orders where id=v_o2));
  perform pg_temp.imp(u1,false); perform public.report_result(v_o2, 'Status=SUCCESS&txnId=TXNWRONG123&txnRef=WRONGREF'); reset role;
  perform pg_temp.rec('SUCCESS with wrong txnRef is NOT activated', (select status='pending' and success_reported from public.payment_orders where id=v_o2) and not exists (select 1 from public.subscriptions where order_id=v_o2));
  perform pg_temp.imp(u1,false); perform public.report_result(v_o2, 'Status=FAILURE&txnRef='||v_ref); reset role;
  perform pg_temp.rec('FAILURE marks order failed', (select status from public.payment_orders where id=v_o2)='failed');
  perform pg_temp.imp(u1,false); perform public.report_result(v_o2, 'Status=SUCCESS&txnId=LATE123456&txnRef='||v_ref); reset role;
  perform pg_temp.rec('terminal order cannot be changed by later report', (select status from public.payment_orders where id=v_o2)='failed');

  r := pg_temp.pay(u1, p_trial, 'ABC1234567');
  perform pg_temp.rec('valid SUCCESS (instant mode) activates plan', r->>'status'='paid' and (select count(*) from public.subscriptions where user_id=u1 and kind='payment')=1);
  perform pg_temp.rec('organic buyer: plan active + approval pending', (select ads_access_status='pending' from public.profiles where id=u1) and private.has_plan(u1));
  select max(ends_at) into v_end from public.subscriptions where user_id=u1;
  perform pg_temp.rec('plan duration applied (7 days)', v_end between now()+interval '6 days 23 hours' and now()+interval '7 days 1 hour');
  select id into v_o3 from public.payment_orders where user_id=u1 and status='paid';
  perform pg_temp.imp(u1,false); perform public.report_result(v_o3, 'Status=SUCCESS&txnId=ABC1234567&txnRef='||(select reference from public.payment_orders where id=v_o3)); reset role;
  perform pg_temp.rec('double report = one grant', (select count(*) from public.subscriptions where order_id=v_o3)=1);
  r := pg_temp.pay(u2, p_trial, 'ABC1234567');
  perform pg_temp.rec('reused txn id is rejected (stays pending)', r->>'status'='pending' and not exists (select 1 from public.subscriptions where user_id=u2));
  perform pg_temp.imp(u2,false); c := public.create_order(p_trial); reset role;
  perform pg_temp.imp(u2,false);
  r := public.report_result((c->>'order_id')::uuid, 'status=success&TXNID=XYZ9876543&TXNREF='||lower(c->>'reference')); reset role;
  perform pg_temp.rec('keys/values parsed case-insensitively', r->>'status'='paid');

  perform pg_temp.imp(ua,false); c := public.create_order(p_silver); reset role;
  update public.payment_orders set created_at = now() - interval '3 hours' where id = (c->>'order_id')::uuid;
  perform pg_temp.imp(ua,false); r := public.report_result((c->>'order_id')::uuid, 'Status=SUCCESS&txnId=OLDORDER99&txnRef='||(c->>'reference')); reset role;
  perform pg_temp.rec('order older than 2 h is not activated', r->>'status'='pending');

  update public.payment_settings set activation_mode='manual';
  r := pg_temp.pay(u5, p_trial, 'MANUAL0001');
  perform pg_temp.rec('manual mode: valid SUCCESS goes to review, no plan yet', r->>'status'='review' and not private.has_plan(u5));
  select id into v_o4 from public.payment_orders where user_id=u5;
  perform pg_temp.imp(u5,false); v_raised := false;
  begin perform public.admin_mark_paid(v_o4, '123456789012'); exception when others then v_raised := true; end; reset role;
  perform pg_temp.rec('non-owner cannot mark paid', v_raised);
  perform pg_temp.imp(owner_id,false); v_raised := false;
  begin perform public.admin_mark_paid(v_o4, '12345'); exception when others then v_raised := true; end; reset role;
  perform pg_temp.rec('mark paid needs 12-digit UTR', v_raised);
  perform pg_temp.imp(owner_id,false); perform public.admin_mark_paid(v_o4, '123456789012'); reset role;
  perform pg_temp.rec('owner marks paid: plan active, bank verified, UTR stored', private.has_plan(u5) and (select status='paid' and bank_verified and utr='123456789012' from public.payment_orders where id=v_o4));
  r := pg_temp.pay(u6, p_trial, 'MANUAL0002');
  perform pg_temp.imp(owner_id,false); v_raised := false;
  begin perform public.admin_mark_paid((select id from public.payment_orders where user_id=u6), '123456789012'); exception when others then v_raised := true; end; reset role;
  perform pg_temp.rec('same UTR cannot activate two orders', v_raised);
  perform pg_temp.imp(owner_id,false); perform public.admin_reject_order((select id from public.payment_orders where user_id=u6), 'fake'); reset role;
  perform pg_temp.rec('owner can reject a review order', (select status from public.payment_orders where user_id=u6)='rejected' and not private.has_plan(u6));
  perform pg_temp.imp(owner_id,false); perform public.admin_revoke_order(v_o4, 'refund'); reset role;
  perform pg_temp.rec('revoke ends the subscription', (select status from public.payment_orders where id=v_o4)='revoked' and not private.has_plan(u5));

  update public.payment_settings set activation_mode='instant';
  plans := array[p_trial, p_silver, p_gold, p_plat];
  for i in 1..4 loop r := pg_temp.pay(u4, plans[i], 'CAPTXN00'||i||'ABC'); v_st := coalesce(v_st,'') || (r->>'status') || ','; end loop;
  perform pg_temp.rec('daily cap: 3 auto activations then review', v_st = 'paid,paid,paid,review,');
  select max(ends_at) into v_end from public.subscriptions where user_id=u4;
  perform pg_temp.rec('renewals extend from current end (7+7+30 days)', v_end between now()+interval '43 days 23 hours' and now()+interval '44 days 1 hour');

  perform pg_temp.imp(u7,false); c := public.create_order(p_gold); reset role;
  update public.plans set price_inr=999, duration_days=999 where id=p_gold;
  perform pg_temp.imp(u7,false);
  r := public.report_result((c->>'order_id')::uuid, 'Status=SUCCESS&txnId=SNAP123456&txnRef='||(c->>'reference')); reset role;
  update public.plans set price_inr=259, duration_days=30 where id=p_gold;
  select max(ends_at) into v_end from public.subscriptions where user_id=u7;
  perform pg_temp.rec('price/duration snapshot at order time', r->>'status'='paid' and v_end between now()+interval '29 days 23 hours' and now()+interval '30 days 1 hour' and (select amount_paise from public.payment_orders where user_id=u7)=25900);

  perform pg_temp.imp(u8,false); c := public.create_order(p_gold); reset role;
  update public.payment_settings set upi_id='newname@upi';
  perform pg_temp.imp(u8,false); c2 := public.create_order(p_gold); reset role;
  perform pg_temp.rec('UPI ID change cancels old-UPI pending order; new order uses new UPI', (select status from public.payment_orders where id=(c->>'order_id')::uuid)='cancelled' and c2->>'upi_id'='newname@upi');
  update public.payment_settings set upi_id='2728412a@bandhan';
  v_raised := false; begin update public.payment_settings set upi_id='not a upi id'; exception when others then v_raised := true; end;
  perform pg_temp.rec('invalid UPI id format rejected', v_raised);

  perform pg_temp.imp(u11,false); c := public.create_order(p_trial); reset role;
  r := public.provider_payment_update(c->>'reference','PROV123456','SUCCESS',100);
  perform pg_temp.rec('webhook amount mismatch goes to review', (select status from public.payment_orders where id=(c->>'order_id')::uuid)='review');
  r := public.provider_payment_update(c->>'reference','PROV123456','SUCCESS',4900);
  perform pg_temp.rec('webhook correct amount activates + bank verified', (select status='paid' and bank_verified and activation_kind='webhook' from public.payment_orders where id=(c->>'order_id')::uuid));
  perform pg_temp.imp(u11,false); v_raised := false;
  begin perform public.provider_payment_update('x','y','SUCCESS',1); exception when others then v_raised := true; end; reset role;
  perform pg_temp.rec('users cannot call provider_payment_update', v_raised);

  update public.app_mode set free_plans_for='organic'; update public.plans set free_eligible=true where id=p_trial;
  perform pg_temp.imp(u9,false); v_t := (select public.claim_free_plan(p_trial))::text; reset role;
  perform pg_temp.rec('organic member claims free plan: free_promo sub, NO payment order', exists (select 1 from public.subscriptions where user_id=u9 and kind='free_promo') and not exists (select 1 from public.payment_orders where user_id=u9));
  perform pg_temp.rec('organic free claimer needs approval', (select ads_access_status='pending' from public.profiles where id=u9));
  perform pg_temp.imp(u9,false); v_raised := false;
  begin perform public.claim_free_plan(p_trial); exception when others then v_raised := true; end; reset role;
  perform pg_temp.rec('cannot claim again while plan active', v_raised);
  delete from public.subscriptions where user_id=u9;
  perform pg_temp.imp(u9,false); v_raised := false;
  begin perform public.claim_free_plan(p_trial); exception when others then v_raised := true; end; reset role;
  perform pg_temp.rec('once per user per plan per promotion', v_raised);
  update public.app_mode set free_plans_for='none'; update public.app_mode set free_plans_for='organic';
  perform pg_temp.imp(u9,false); perform public.claim_free_plan(p_trial); reset role;
  perform pg_temp.rec('new promotion allows a new claim', (select count(*) from public.free_plan_claims where user_id=u9)=2);
  perform pg_temp.imp(u10,false); v_raised := false;
  begin perform public.claim_free_plan(p_trial); exception when others then v_raised := true; end; reset role;
  perform pg_temp.rec('ads user cannot claim organic-only free plan', v_raised);
  perform pg_temp.imp(ug,true); v_raised := false;
  begin perform public.claim_free_plan(p_trial); exception when others then v_raised := true; end; reset role;
  perform pg_temp.rec('guest cannot claim free plan', v_raised);
  perform pg_temp.imp(u10,false); r := public.plan_offers(); reset role;
  perform pg_temp.rec('plan_offers keys (ads user, organic promo: no free ids)', r ?& array['free_plan_ids','payments_available','plans_visible'] and jsonb_array_length(r->'free_plan_ids')=0 and (r->>'payments_available')::boolean);
  update public.app_mode set free_plans_for='none'; update public.plans set free_eligible=false where id=p_trial;

  perform pg_temp.imp(u1,false); v_raised := false;
  begin perform public.admin_dashboard(); exception when others then v_raised := true; end; reset role;
  perform pg_temp.rec('non-admin cannot read dashboard', v_raised);
  perform pg_temp.imp(u1,false); v_raised := false;
  begin perform public.admin_orders(); exception when others then v_raised := true; end; reset role;
  perform pg_temp.rec('non-admin cannot list orders', v_raised);
  perform pg_temp.imp(u1,false); select count(*) into v_n from public.payment_orders where user_id <> u1; reset role;
  perform pg_temp.rec('user sees only own orders', v_n=0);
  perform pg_temp.imp(u1,false); select count(*) into v_n from public.settings_audit; reset role;
  perform pg_temp.rec('non-owner cannot read audit log', v_n=0);
  perform pg_temp.imp(u1,false); select count(*) into v_n from public.payment_settings; reset role;
  perform pg_temp.rec('non-owner cannot read payment settings', v_n=0);
  perform pg_temp.imp(u1,false); update public.plans set price_inr=1 where id=p_gold; update public.payment_settings set upi_id='evil@upi'; reset role;
  perform pg_temp.rec('non-owner cannot edit plans or UPI', (select price_inr from public.plans where id=p_gold)=259 and (select upi_id from public.payment_settings)='2728412a@bandhan');
  perform pg_temp.imp(owner_id,false); r := public.admin_dashboard(); c := public.admin_payment_stats(); c2 := public.admin_users(null,null,null,null,null,10,0); reset role;
  perform pg_temp.rec('owner dashboard/stats/users RPCs work', r ?& array['ads_installs','organic_installs','users','logged_in','premium_users','revenue_today','revenue_month','free_claims','alerts'] and c ?& array['paid_orders','revenue_total','sales_per_plan','repeat_buyers'] and (c2->>'total')::int >= 10);
  v_raised := false; begin update public.plans set code='hacked' where id=p_gold; exception when others then v_raised := true; end;
  perform pg_temp.rec('plan code cannot be changed after create', v_raised);
  perform pg_temp.rec('settings_audit records plan + UPI changes', (select count(*) from public.settings_audit where table_name='plans' and field='price_inr')>=2 and (select count(*) from public.settings_audit where table_name='payment_settings' and field='upi_id')>=1);
  perform pg_temp.rec('plan_catalog revision bumped', (select revision>=10 from public.plan_catalog));

  update public.meta_settings set enabled=true, pixel_id='1234567890', capi_token='tok';
  perform pg_temp.imp(u8,false);
  perform public.set_measurement_preferences(true,true,jsonb_build_object('install_id',gen_random_uuid()::text,'extinfo',jsonb_build_array('a2','com.vayora.app','9','1.0.8','14','','en_IN','IST','','1080','1920','3','4','','','')));
  reset role;
  r := pg_temp.pay(u8, p_trial, 'METATX1234');
  perform pg_temp.rec('unverified payment never queues a Meta Purchase',(select count(*) from public.meta_events where user_id=u8 and event_name='Purchase')=0);
  select id into v_o1 from public.payment_orders where user_id=u8 and txn_id='METATX1234';
  perform pg_temp.imp(owner_id,false);perform public.admin_confirm_bank(v_o1);reset role;
  perform private.enqueue_meta('Purchase',u8,v_o1,99999);
  perform pg_temp.rec('Purchase + InitiateCheckout events queued for paid order (with value)', (select count(*) from public.meta_events where user_id=u8 and event_name='Purchase' and value_inr>0)=1 and (select count(*) from public.meta_events where user_id=u8 and event_name='InitiateCheckout' and value_inr>0)>=1);
  update public.app_mode set free_plans_for='everyone'; update public.plans set free_eligible=true where id=p_silver;
  perform pg_temp.imp(u10,false); perform public.claim_free_plan(p_silver); reset role;
  perform pg_temp.rec('free promo claim queues no Purchase event', (select count(*) from public.meta_events where user_id=u10 and event_name='Purchase')=0);

  select count(*), count(*) filter (where not x.ok), string_agg(x.n, ' | ') filter (where not x.ok) into total, failed, fail_list from t_res x;
  raise exception 'RESULT total=% failed=% :: %', total, failed, coalesce(fail_list,'none');
end $outer$;

