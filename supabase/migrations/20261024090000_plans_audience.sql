-- Owner chooses who can see and buy plans: nobody, ads users, organic users or everyone.
-- Admins always see plans so they can test. Enforced on the server, not only in the app.
alter table public.app_mode add column plans_visible_for text not null default 'everyone'
 check(plans_visible_for in ('none','ads','organic','everyone'));

create function private.plans_visible_for_me() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (private.is_admin() or exists(select 1 from public.app_mode m where m.id
 and (m.plans_visible_for='everyone' or m.plans_visible_for=private.source_of(auth.uid()))))
$$;
revoke all on function private.plans_visible_for_me() from public,anon;
grant execute on function private.plans_visible_for_me() to authenticated;

-- Hidden plans are never free either.
create or replace function private.free_plan_for_me(p_plan uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not private.client_free_mode() and private.plans_visible_for_me() and exists(
  select 1 from public.plans p cross join public.app_mode m
  where p.id=p_plan and p.active and p.free_eligible and m.id
  and (m.free_plans_for='everyone' or m.free_plans_for=private.source_of(auth.uid())))
$$;

create or replace function private.direct_payment_order(p_plan uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare pl public.plans; settings public.payment_settings; ord public.payment_orders;
begin
 if not private.is_member() then raise exception 'Login required'; end if;
 if private.client_free_mode() then raise exception 'Payments unavailable in free mode'; end if;
 if not private.plans_visible_for_me() then raise exception 'Plans are not available for your account'; end if;
 if private.free_plan_for_me(p_plan) then raise exception 'This plan is free for you. Tap Activate for free'; end if;
 select * into settings from public.payment_settings where id and enabled and length(btrim(upi_id))>2 and length(btrim(payee_name))>0;
 if not found then raise exception 'Payments are not available right now'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 select * into pl from public.plans where id=p_plan and active for share;
 if not found then raise exception 'Plan unavailable'; end if;
 -- Preserve evidence of actual payments; only expire unclaimed/stale, repriced or old-UPI orders.
 update public.payment_orders set status='cancelled',reason='Replaced or checkout window expired'
 where user_id=auth.uid() and status='pending' and upper(coalesce(client_status,''))<>'SUCCESS' and utr is null
 and (created_at<=now()-interval '2 hours' or plan_id<>p_plan
 or amount_paise<>pl.price_inr::bigint*100 or duration_days<>pl.duration_days
 or upi_id_used is distinct from settings.upi_id);
 insert into public.payment_orders(plan_id) values(p_plan) returning * into ord;
 update public.payment_orders set upi_id_used=settings.upi_id,payee_used=settings.payee_name where id=ord.id returning * into ord;
 return to_jsonb(ord)||jsonb_build_object('upi_id',settings.upi_id,'payee_name',settings.payee_name);
end $$;

create or replace function private.claim_free_plan(p_plan uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare pl public.plans; promo uuid; who text; sub public.subscriptions;
begin
 if not private.is_member() then raise exception 'Login required'; end if;
 if not private.plans_visible_for_me() then raise exception 'Plans are not available for your account'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 select * into pl from public.plans where id=p_plan and active for share;
 if not found then raise exception 'Plan unavailable'; end if;
 if not private.free_plan_for_me(p_plan) then raise exception 'This plan is not free for you'; end if;
 if private.has_plan() then raise exception 'You already have an active plan'; end if;
 select promo_id into promo from public.app_mode where id;
 if exists(select 1 from public.free_plan_claims where user_id=auth.uid() and plan_id=p_plan and promo_id=promo) then
  raise exception 'You already claimed this free plan';
 end if;
 who=private.source_of(auth.uid());
 insert into public.subscriptions(user_id,plan_id,starts_at,ends_at,source)
 values(auth.uid(),p_plan,now(),now()+make_interval(days=>pl.duration_days),'free_promo') returning * into sub;
 insert into public.free_plan_claims(user_id,plan_id,promo_id,source,subscription_id,duration_days)
 values(auth.uid(),p_plan,promo,who,sub.id,pl.duration_days);
 -- Same approval rule as a paid purchase.
 if who='organic' then
  update public.profiles set ads_access_status='pending' where id=auth.uid() and ads_access_status='none';
 end if;
 return jsonb_build_object('plan_name',pl.name,'ends_at',sub.ends_at,'duration_days',pl.duration_days);
end $$;

create or replace function private.my_status() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',p.id,'is_admin',private.is_admin(),'display_name',p.display_name,'avatar_url',p.avatar_url,'is_guest',p.is_guest,
 'source',private.source_of(p.id),'has_ads_access',private.has_ads_access(),'is_premium',private.is_premium_user(),
 'plan_name',case when private.client_free_mode() then null else(select pl.name from public.subscriptions s join public.plans pl on pl.id=s.plan_id
 where s.user_id=p.id and s.revoked_at is null and s.starts_at<=now() and s.ends_at>now() order by s.ends_at desc limit 1)end,
 'plan_ends_at',case when private.client_free_mode() then null else(select max(ends_at) from public.subscriptions where user_id=p.id and revoked_at is null and starts_at<=now() and ends_at>now())end,
 'used_bytes',p.used_bytes,'quota_bytes',private.quota_bytes(p.id),'free_mode',private.client_free_mode(),
 'paid_enabled',not private.client_free_mode(),'access_status',p.ads_access_status,'play_verified',private.play_session(),'play_billing_enabled',private.play_billing_ready(),
 'payments_available',private.payments_available() and not private.client_free_mode(),
 'free_plans_for',(select free_plans_for from public.app_mode where id),
 'web_plans',coalesce((select web_plans from public.app_mode where id),false),
 'plans_visible',private.plans_visible_for_me() and not private.client_free_mode())
 from public.profiles p where p.id=auth.uid()
$$;

create or replace function private.plan_offers() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'free_plan_ids',coalesce((select jsonb_agg(p.id order by p.position) from public.plans p where private.free_plan_for_me(p.id)),'[]'::jsonb),
  'payments_available',private.payments_available(),
  'free_plans_for',(select free_plans_for from public.app_mode where id),
  'plans_visible',private.plans_visible_for_me())
$$;
