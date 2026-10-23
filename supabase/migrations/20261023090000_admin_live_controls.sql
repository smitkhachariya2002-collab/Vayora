-- Admin live controls: free plans by user type, UPI used per order, change history.
-- Paid checkout validation and activation rules are unchanged.

-- Free plans: who gets them (none/organic/ads/everyone) and which plans qualify.
alter table public.app_mode add column free_plans_for text not null default 'none'
 check(free_plans_for in ('none','organic','ads','everyone'));
alter table public.app_mode add column promo_id uuid not null default gen_random_uuid();
alter table public.plans add column free_eligible boolean not null default true;
-- Website plans page inside the direct/ads app (never used by the Play build).
alter table public.app_mode add column web_plans boolean not null default false;

-- Each time free plans are switched on, a new promotion starts (one claim per plan per promotion).
create function private.app_mode_promo() returns trigger language plpgsql set search_path='' as $$
begin
 if new.free_plans_for<>'none' and old.free_plans_for='none' then new.promo_id=gen_random_uuid(); end if;
 return new;
end $$;
revoke all on function private.app_mode_promo() from public,anon,authenticated;
create trigger app_mode_promo before update on public.app_mode for each row execute function private.app_mode_promo();

alter table public.subscriptions drop constraint subscriptions_source_check;
alter table public.subscriptions add constraint subscriptions_source_check
 check(source in ('upi_app','admin','provider_api','bank_credit','google_play','free_promo'));

create table public.free_plan_claims(
 id uuid primary key default gen_random_uuid(),
 user_id uuid references auth.users on delete set null,
 plan_id uuid not null references public.plans,
 promo_id uuid not null,
 source text not null check(source in ('ads','organic')),
 subscription_id uuid unique references public.subscriptions on delete set null,
 duration_days integer not null check(duration_days>0),
 created_at timestamptz not null default now(),
 unique(user_id,plan_id,promo_id)
);
create index free_plan_claims_plan_idx on public.free_plan_claims(plan_id);
create index free_plan_claims_promo_idx on public.free_plan_claims(promo_id);
alter table public.free_plan_claims enable row level security;
revoke all on public.free_plan_claims from public,anon,authenticated;
grant select on public.free_plan_claims to authenticated;
create policy free_plan_claims_read on public.free_plan_claims for select to authenticated using((select private.is_owner()));

-- The UPI ID and payee each order was created with.
alter table public.payment_orders add column upi_id_used text;
alter table public.payment_orders add column payee_used text;

-- Change history for plans, UPI settings and modes (owner read only).
create table public.settings_audit(
 id bigint generated always as identity primary key,
 table_name text not null, record_id text not null, field text not null,
 old_value text, new_value text,
 changed_by uuid references auth.users on delete set null,
 changed_at timestamptz not null default now()
);
create index settings_audit_time_idx on public.settings_audit(changed_at desc);
alter table public.settings_audit enable row level security;
revoke all on public.settings_audit from public,anon,authenticated;
grant select on public.settings_audit to authenticated;
create policy settings_audit_read on public.settings_audit for select to authenticated using((select private.is_owner()));

create function private.audit_settings() returns trigger language plpgsql security definer set search_path='' as $$
declare old_row jsonb=case when TG_OP='UPDATE' then to_jsonb(old) else '{}'::jsonb end; new_row jsonb=to_jsonb(new); k text;
 skip text[]=array['updated_at','created_at','promo_id'];
begin
 for k in select jsonb_object_keys(new_row) loop
  if k=any(skip) then continue; end if;
  if old_row->k is distinct from new_row->k then
   insert into public.settings_audit(table_name,record_id,field,old_value,new_value,changed_by)
   values(TG_TABLE_NAME,coalesce(new_row->>'code',new_row->>'id'),k,old_row->>k,new_row->>k,auth.uid());
  end if;
 end loop;
 return null;
end $$;
revoke all on function private.audit_settings() from public,anon,authenticated;
create trigger audit_settings after insert or update on public.plans for each row execute function private.audit_settings();
create trigger audit_settings after update on public.payment_settings for each row execute function private.audit_settings();
create trigger audit_settings after update on public.app_mode for each row execute function private.audit_settings();

-- UPI ID format check; an empty ID is allowed and means payments are off.
create function private.guard_payment_settings() returns trigger language plpgsql set search_path='' as $$
begin
 new.upi_id=nullif(btrim(coalesce(new.upi_id,'')),'');
 new.payee_name=nullif(btrim(coalesce(new.payee_name,'')),'');
 if new.upi_id is not null and new.upi_id !~ '^[A-Za-z0-9._-]{2,128}@[A-Za-z][A-Za-z0-9.-]{1,63}$' then
  raise exception 'Enter a valid UPI ID, for example name@bank' using errcode='23514';
 end if;
 if new.upi_id is null then new.enabled=false; end if;
 if new.enabled and new.payee_name is null then raise exception 'Payee name is required' using errcode='23514'; end if;
 return new;
end $$;
revoke all on function private.guard_payment_settings() from public,anon,authenticated;
create trigger guard_payment_settings before update on public.payment_settings for each row execute function private.guard_payment_settings();

-- Changes to UPI settings or modes ping the app's plan list so it refetches immediately.
create trigger notify_plan_catalog after update on public.payment_settings for each row execute function private.notify_plan_catalog();
create trigger notify_plan_catalog after update on public.app_mode for each row execute function private.notify_plan_catalog();

create function private.payments_available() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.payment_settings where id and enabled and length(btrim(coalesce(upi_id,'')))>2
 and length(btrim(coalesce(payee_name,'')))>0)
$$;
revoke all on function private.payments_available() from public,anon;

create function private.free_plan_for_me(p_plan uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not private.client_free_mode() and exists(
  select 1 from public.plans p cross join public.app_mode m
  where p.id=p_plan and p.active and p.free_eligible and m.id
  and (m.free_plans_for='everyone' or m.free_plans_for=private.source_of(auth.uid())))
$$;
revoke all on function private.free_plan_for_me(uuid) from public,anon;

-- What the Premium screen needs besides the plan rows.
create function private.plan_offers() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'free_plan_ids',coalesce((select jsonb_agg(p.id order by p.position) from public.plans p where private.free_plan_for_me(p.id)),'[]'::jsonb),
  'payments_available',private.payments_available(),
  'free_plans_for',(select free_plans_for from public.app_mode where id))
$$;
revoke all on function private.plan_offers() from public,anon;
grant execute on function private.plan_offers() to authenticated;
create function public.plan_offers() returns jsonb language sql stable set search_path='' as $$select private.plan_offers()$$;
revoke all on function public.plan_offers() from public,anon;
grant execute on function public.plan_offers() to authenticated;

create function private.claim_free_plan(p_plan uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare pl public.plans; promo uuid; who text; sub public.subscriptions;
begin
 if not private.is_member() then raise exception 'Login required'; end if;
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
revoke all on function private.claim_free_plan(uuid) from public,anon;
grant execute on function private.claim_free_plan(uuid) to authenticated;
create function public.claim_free_plan(plan_id uuid) returns jsonb language sql set search_path='' as $$select private.claim_free_plan(plan_id)$$;
revoke all on function public.claim_free_plan(uuid) from public,anon;
grant execute on function public.claim_free_plan(uuid) to authenticated;

-- Latest checkout (from upi_checkout_window) plus: free plans are claimed, not bought,
-- and every new order records the UPI ID it was sent to.
create or replace function private.direct_payment_order(p_plan uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare pl public.plans; settings public.payment_settings; ord public.payment_orders;
begin
 if not private.is_member() then raise exception 'Login required'; end if;
 if private.client_free_mode() then raise exception 'Payments unavailable in free mode'; end if;
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

-- my_status: add free plan and payment availability flags (existing keys unchanged).
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
 'web_plans',coalesce((select web_plans from public.app_mode where id),false))
 from public.profiles p where p.id=auth.uid()
$$;

-- Admin: free plan claims per plan and source for the current promotion.
create function public.admin_free_plan_claims() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required' using errcode='42501'; end if;
 return jsonb_build_object(
  'organic',(select count(*) from public.free_plan_claims c join public.app_mode m on m.id and c.promo_id=m.promo_id where c.source='organic'),
  'ads',(select count(*) from public.free_plan_claims c join public.app_mode m on m.id and c.promo_id=m.promo_id where c.source='ads'),
  'total',(select count(*) from public.free_plan_claims));
end $$;
revoke all on function public.admin_free_plan_claims() from public,anon;
grant execute on function public.admin_free_plan_claims() to authenticated;
