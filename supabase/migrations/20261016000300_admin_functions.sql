create function private.admin_users() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from (
 select p.*,u.email,coalesce(s.source,'organic') as source,
 (select max(ends_at) from public.subscriptions where user_id=p.id and revoked_at is null and ends_at>now()) as plan_ends_at,
 (select utm_campaign from public.installs where user_id=p.id order by created_at limit 1) as campaign
 from public.profiles p join auth.users u on u.id=p.id left join private.user_sources s on s.user_id=p.id
 order by p.created_at desc limit 500) x),'[]');
end $$;
create function public.admin_users() returns jsonb language sql stable set search_path='' as $$ select private.admin_users() $$;
create function private.grant_premium(p_user uuid,p_plan uuid) returns void language plpgsql security definer set search_path='' as $$
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
 update public.profiles set ads_access_status='pending' where id=p_user and ads_access_status='none'; end if;
 insert into public.audit_logs(actor_id,action,target_id) values(auth.uid(),'grant_premium',p_user::text);
end $$;
create function public.grant_premium(user_id uuid,plan_id uuid) returns void language sql set search_path='' as $$ select private.grant_premium(user_id,plan_id) $$;
create function private.admin_plan_sales() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from (
 select p.name,count(o.id) as sales,coalesce(sum(o.amount_paise),0) as amount_paise from public.plans p
 left join public.payment_orders o on o.plan_id=p.id and o.status='success' group by p.id) x),'[]');
end $$;
create function public.admin_plan_sales() returns jsonb language sql stable set search_path='' as $$ select private.admin_plan_sales() $$;
create function private.admin_buyers() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from (
 select user_id,count(*) as purchases,sum(amount_paise) as total_paise from public.payment_orders
 where status='success' group by user_id having count(*)>1) x),'[]');
end $$;
create function public.admin_buyers() returns jsonb language sql stable set search_path='' as $$ select private.admin_buyers() $$;
revoke execute on function private.admin_users(),private.grant_premium(uuid,uuid),private.admin_plan_sales(),private.admin_buyers() from public,anon;
revoke execute on function public.admin_users(),public.grant_premium(uuid,uuid),public.admin_plan_sales(),public.admin_buyers() from public,anon;
grant execute on function private.admin_users(),private.grant_premium(uuid,uuid),private.admin_plan_sales(),private.admin_buyers(),
 public.admin_users(),public.grant_premium(uuid,uuid),public.admin_plan_sales(),public.admin_buyers() to authenticated;
