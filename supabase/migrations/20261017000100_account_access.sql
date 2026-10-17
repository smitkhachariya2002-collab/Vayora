-- Account/access contract: audience approval and paid entitlement are independent.
create or replace function private.has_ads_access() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (private.source_of(auth.uid())='ads' or
 exists(select 1 from public.profiles where id=auth.uid() and ads_access_status='approved'))
$$;

create or replace function private.is_premium_user() returns boolean
language sql stable security definer set search_path='' as $$
 select private.is_member() and case
 when exists(select 1 from public.app_mode where id and free_mode)
 then private.has_ads_access() else private.has_plan() end
$$;

create or replace function private.my_status() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',p.id,'is_admin',private.is_admin(),'display_name',p.display_name,'avatar_url',p.avatar_url,'is_guest',p.is_guest,
 'source',private.source_of(p.id),'has_ads_access',private.has_ads_access(),'is_premium',private.is_premium_user(),
 'plan_name',case when m.free_mode then null else (select pl.name from public.subscriptions s join public.plans pl on pl.id=s.plan_id where s.user_id=p.id and s.revoked_at is null and s.starts_at<=now() and s.ends_at>now() order by s.ends_at desc limit 1) end,
 'plan_ends_at',case when m.free_mode then null else (select max(ends_at) from public.subscriptions where user_id=p.id and revoked_at is null and starts_at<=now() and ends_at>now()) end,
 'used_bytes',p.used_bytes,'quota_bytes',private.quota_bytes(p.id),'free_mode',m.free_mode,
 'paid_enabled',not m.free_mode,'access_status',p.ads_access_status)
 from public.profiles p cross join public.app_mode m where p.id=auth.uid()
$$;

-- Rejected/revoked organic buyers may re-enter the review queue on a new
-- activation; retain an existing approval and preserve payment verification.
create or replace function private.activate_payment(p_order uuid,p_amount bigint,p_utr text,p_source text) returns void language plpgsql security definer set search_path='' as $$
declare ord public.payment_orders; end_time timestamptz;
begin
 select * into ord from public.payment_orders where id=p_order for update;
 if not found or ord.user_id is null then raise exception 'Order unavailable'; end if;
 if ord.status='success' then return; end if;
 if ord.status='revoked' then raise exception 'Order revoked'; end if;
 if p_amount<>ord.amount_paise then raise exception 'Amount mismatch'; end if;
 if p_utr !~ '^[A-Za-z0-9]{6,40}$' or p_utr is null then raise exception 'Valid UTR required'; end if;
 if exists(select 1 from public.payment_orders where utr=p_utr and id<>p_order) then raise exception 'UTR already used'; end if;
 perform 1 from public.profiles where id=ord.user_id for update;
 select greatest(now(),coalesce(max(ends_at),now())) into end_time from public.subscriptions
 where user_id=ord.user_id and revoked_at is null and ends_at>now();
 update public.payment_orders set status='success',utr=p_utr,paid_at=now(),reason=null where id=p_order;
 insert into public.subscriptions(user_id,plan_id,starts_at,ends_at,source,order_id)
 values(ord.user_id,ord.plan_id,now(),end_time+make_interval(days=>ord.duration_days),p_source,p_order);
 if coalesce((select source from private.user_sources where user_id=ord.user_id),'organic')='organic' then
 update public.profiles set ads_access_status='pending' where id=ord.user_id and ads_access_status in ('none','rejected');
 end if;
 insert into public.payment_events(order_id,kind) values(p_order,'activated');
end $$;

-- Replacements retain their existing grants. Explicitly close privileged
-- activation to all client roles; only the owner-checked payment RPC invokes it.
revoke all on function private.activate_payment(uuid,bigint,text,text) from public,anon,authenticated;
revoke all on function private.has_ads_access(),private.is_premium_user(),private.my_status() from public,anon;
grant execute on function private.has_ads_access(),private.is_premium_user(),private.my_status() to authenticated;

-- Attribution is immutable even through privileged table edits.
create function private.keep_first_touch() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.source is distinct from old.source then
   raise exception 'First-touch source is immutable';
 end if;
 return new;
end $$;
revoke all on function private.keep_first_touch() from public,anon,authenticated;
create trigger installs_first_touch before update of source on public.installs
 for each row execute function private.keep_first_touch();
create trigger accounts_first_touch before update of source on private.user_sources
 for each row execute function private.keep_first_touch();

create or replace function private.grant_premium(p_user uuid,p_plan uuid) returns void language plpgsql security definer set search_path='' as $$
declare days integer; end_time timestamptz;
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 select duration_days into days from public.plans where id=p_plan;
 if days is null then raise exception 'Plan unavailable'; end if;
 perform 1 from public.profiles where id=p_user for update;
 if not found then raise exception 'User unavailable'; end if;
 select greatest(now(),coalesce(max(ends_at),now())) into end_time from public.subscriptions where user_id=p_user and revoked_at is null;
 insert into public.subscriptions(user_id,plan_id,starts_at,ends_at,source) values(p_user,p_plan,now(),end_time+make_interval(days=>days),'admin');
 if coalesce((select source from private.user_sources where user_id=p_user),'organic')='organic' then
 update public.profiles set ads_access_status='pending' where id=p_user and ads_access_status in ('none','rejected'); end if;
 insert into public.audit_logs(actor_id,action,target_id) values(auth.uid(),'grant_premium',p_user::text);
end $$;
