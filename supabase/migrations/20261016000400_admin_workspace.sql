-- Additive admin RPCs only. Existing entitlement and payment rules are unchanged.
create table private.admin_meta_settings (
 id boolean primary key default true check(id),
 pixel_id text not null default '', api_token text, test_code text not null default '',
 website text not null default '', enabled boolean not null default false,
 updated_at timestamptz not null default now()
);
alter table private.admin_meta_settings enable row level security;
revoke all on private.admin_meta_settings from public,anon,authenticated;
insert into private.admin_meta_settings(id) values(true);
create function public.admin_meta() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 return (select jsonb_build_object('pixel_id',pixel_id,'has_token',api_token is not null,
 'test_code',test_code,'website',website,'enabled',enabled,'updated_at',updated_at,
 'delivery_connected',false) from private.admin_meta_settings where id);
end $$;
create function public.admin_save_meta(pixel_id text,api_token text,test_code text,website text,enabled boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 if length(pixel_id)>100 or length(api_token)>4096 or length(test_code)>100 or length(website)>2048 then raise exception 'Value too long'; end if;
 if website<>'' and website !~ '^https://' then raise exception 'Use an HTTPS website URL'; end if;
 update private.admin_meta_settings s set pixel_id=admin_save_meta.pixel_id,
 api_token=coalesce(nullif(admin_save_meta.api_token,''),s.api_token),
 test_code=admin_save_meta.test_code,website=admin_save_meta.website,enabled=admin_save_meta.enabled,updated_at=now() where id;
 insert into public.audit_logs(actor_id,action) values(auth.uid(),'meta_settings_saved');
end $$;
create function public.admin_directory() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from (
 select a.user_id,a.role,u.email,coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name))
 from public.admin_channel_access g join public.channels c on c.id=g.channel_id where g.user_id=a.user_id),'[]') as channels
 from public.admins a join auth.users u on u.id=a.user_id order by u.created_at desc) x),'[]');
end $$;
create function public.admin_manage_member(target_email text,target_role text,channel_ids uuid[],remove_member boolean default false)
returns void language plpgsql security definer set search_path='' as $$
declare target uuid; previous text; owners integer;
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 -- Serialize owner changes to prevent concurrent removal of the last owner.
 perform pg_advisory_xact_lock(2026101604);
 select id into target from auth.users where lower(email)=lower(trim(target_email))
 and email_confirmed_at is not null and not coalesce(is_anonymous,false) and deleted_at is null;
 if target is null then raise exception 'User must register and confirm this email first'; end if;
 if target_role not in ('owner','content') then raise exception 'Invalid role'; end if;
 select role into previous from public.admins where user_id=target;
 select count(*) into owners from public.admins where role='owner';
 if previous='owner' and (remove_member or target_role<>'owner') and owners<=1 then raise exception 'Cannot remove the last owner'; end if;
 if remove_member then delete from public.admins where user_id=target;
 else
 if exists(select 1 from unnest(coalesce(channel_ids,'{}')) g where not exists(select 1 from public.channels c where c.id=g)) then raise exception 'Unknown channel'; end if;
 insert into public.admins(user_id,role) values(target,target_role) on conflict(user_id) do update set role=excluded.role;
 delete from public.admin_channel_access where user_id=target;
 insert into public.admin_channel_access(user_id,channel_id) select target,g from unnest(coalesce(channel_ids,'{}')) g on conflict do nothing;
 end if;
 insert into public.audit_logs(actor_id,action,target_id) values(auth.uid(),case when remove_member then 'admin_removed' else 'admin_saved' end,target::text);
end $$;
create function public.admin_metrics() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'Admin required'; end if;
 if not private.is_owner() then return jsonb_build_object(
 'channels',(select count(*) from public.channels c where private.manage_channel(c.id)),
 'posts',(select count(*) from public.posts p where private.manage_channel(p.channel_id) and p.status='published'));
 end if;
 return jsonb_build_object(
 'ads',(select count(*) from public.installs where source='ads'),
 'organic',(select count(*) from public.installs where source='organic'),
 'users',(select count(*) from public.profiles),
 'members',(select count(*) from auth.users where not coalesce(is_anonymous,false) and deleted_at is null),
 'premium',(select count(distinct user_id) from public.subscriptions where revoked_at is null and starts_at<=now() and ends_at>now()),
 'channels',(select count(*) from public.channels),
 'posts',(select count(*) from public.posts where status='published'),
 'campaigns',coalesce((select jsonb_agg(to_jsonb(x)) from (
 select i.source,coalesce(i.utm_campaign,'Direct / no campaign') as campaign,count(*) as installs,
 count(distinct i.user_id) filter(where not coalesce(u.is_anonymous,true)) as registrations,
 count(distinct i.user_id) filter(where exists(select 1 from public.payment_orders o where o.user_id=i.user_id and o.status='success')) as buyers
 from public.installs i left join auth.users u on u.id=i.user_id group by i.source,i.utm_campaign order by count(*) desc) x),'[]'));
end $$;
revoke all on function public.admin_meta(),public.admin_save_meta(text,text,text,text,boolean),public.admin_directory(),public.admin_manage_member(text,text,uuid[],boolean),public.admin_metrics() from public,anon;
grant execute on function public.admin_meta(),public.admin_save_meta(text,text,text,text,boolean),public.admin_directory(),public.admin_manage_member(text,text,uuid[],boolean),public.admin_metrics() to authenticated;

create function public.admin_reorder_post_items(post_id uuid,item_ids uuid[]) returns void
language plpgsql security definer set search_path='' as $$
declare channel uuid; actual uuid[];
begin
 if not private.is_admin() then raise exception 'Admin required'; end if;
 select channel_id into channel from public.posts p where p.id=post_id for update;
 if channel is null or not private.manage_channel(channel) then raise exception 'Channel access required'; end if;
 select array_agg(id order by id) into actual from public.post_items i where i.post_id=admin_reorder_post_items.post_id;
 if coalesce(actual,'{}')<>coalesce((select array_agg(v order by v) from unnest(item_ids) v),'{}') then raise exception 'Media list changed; refresh and try again'; end if;
 update public.post_items i set position=x.n-1 from unnest(item_ids) with ordinality x(id,n) where i.id=x.id;
end $$;
revoke all on function public.admin_reorder_post_items(uuid,uuid[]) from public,anon;
grant execute on function public.admin_reorder_post_items(uuid,uuid[]) to authenticated;

create function public.admin_payment_summary() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 return (select jsonb_build_object(
 'today',coalesce(sum(amount_paise) filter(where status='success' and (paid_at at time zone 'Asia/Kolkata')::date=(now() at time zone 'Asia/Kolkata')::date),0),
 'month',coalesce(sum(amount_paise) filter(where status='success' and date_trunc('month',paid_at at time zone 'Asia/Kolkata')=date_trunc('month',now() at time zone 'Asia/Kolkata')),0),
 'success',count(*) filter(where status='success'),
 'pending',count(*) filter(where status in ('created','pending'))) from public.payment_orders);
end $$;
create function public.admin_user_plans() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from (
 select distinct on(s.user_id) s.user_id,p.name,s.ends_at from public.subscriptions s join public.plans p on p.id=s.plan_id
 where s.revoked_at is null and s.starts_at<=now() and s.ends_at>now() order by s.user_id,s.ends_at desc) x),'[]');
end $$;
revoke all on function public.admin_payment_summary(),public.admin_user_plans() from public,anon;
grant execute on function public.admin_payment_summary(),public.admin_user_plans() to authenticated;
