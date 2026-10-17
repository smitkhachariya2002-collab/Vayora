-- Part A: creator gates, persisted names, server search and counted views.
create extension if not exists pg_trgm with schema extensions;
create index if not exists posts_title_trgm on public.posts using gin(title extensions.gin_trgm_ops);
create index if not exists channels_name_trgm on public.channels using gin(name extensions.gin_trgm_ops);
create index if not exists channels_category_idx on public.channels(category);

create or replace function private.sync_profile() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,is_guest,display_name)
 values(new.id,coalesce(new.is_anonymous,false),'User-'||substr(replace(new.id::text,'-',''),1,8))
 on conflict(id) do update set is_guest=excluded.is_guest;
 return new;
end $$;
update public.profiles set display_name='User-'||substr(replace(id::text,'-',''),1,8) where btrim(display_name)='';

create function private.creator_write_allowed(p_channel uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.is_member() and exists(
 select 1 from public.channels c where c.id=p_channel and
 ((private.is_admin() and private.manage_channel(c.id)) or
 (c.created_by=auth.uid() and c.review_status='approved' and c.status='active')))
$$;
revoke all on function private.creator_write_allowed(uuid) from public,anon;
grant execute on function private.creator_write_allowed(uuid) to authenticated,service_role;

drop policy posts_create on public.posts;
drop policy posts_edit on public.posts;
create policy posts_create on public.posts for insert to authenticated
 with check(created_by=(select auth.uid()) and private.creator_write_allowed(channel_id));
create policy posts_edit on public.posts for update to authenticated
 using(private.creator_write_allowed(channel_id)) with check(private.creator_write_allowed(channel_id));
drop policy items_create on public.post_items;
drop policy items_edit on public.post_items;
create policy items_create on public.post_items for insert to authenticated with check(
 exists(select 1 from public.posts p where p.id=post_id and private.creator_write_allowed(p.channel_id)));
create policy items_edit on public.post_items for update to authenticated using(
 exists(select 1 from public.posts p where p.id=post_id and private.creator_write_allowed(p.channel_id)))
 with check(exists(select 1 from public.posts p where p.id=post_id and private.creator_write_allowed(p.channel_id)));
create or replace function private.manage_media(p_key text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.posts p where
 split_part(p_key,'/',1)=p.created_by::text and split_part(p_key,'/',2)=p.id::text
 and private.creator_write_allowed(p.channel_id))
$$;

-- Clients cannot edit counters. The server counter function can.
revoke update on public.posts from authenticated;
grant update(channel_id,title,description,audience,status,publish_at) on public.posts to authenticated;
create or replace function private.post_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='INSERT' then
   if new.created_by<>auth.uid() and auth.uid() is not null then raise exception 'Invalid creator'; end if;
   new.view_count=0;
 elsif new.created_by<>old.created_by or new.id<>old.id then raise exception 'Protected post fields';
 end if;
 return new;
end $$;

create table private.post_views(
 user_id uuid not null references auth.users on delete cascade,
 post_id uuid not null references public.posts on delete cascade,
 last_viewed_at timestamptz not null default now(), primary key(user_id,post_id));
alter table private.post_views enable row level security;
revoke all on private.post_views from public,anon,authenticated;
create function private.increment_view(p_post uuid) returns bigint
language plpgsql security definer set search_path='' as $$
declare counted integer; total bigint;
begin
 if auth.uid() is null or not private.visible_post(p_post) then raise exception 'Post unavailable'; end if;
 insert into private.post_views(user_id,post_id) values(auth.uid(),p_post)
 on conflict(user_id,post_id) do update set last_viewed_at=excluded.last_viewed_at
 where private.post_views.last_viewed_at<=now()-interval '30 minutes'
 returning 1 into counted;
 if counted=1 then
   update public.posts set view_count=view_count+1 where id=p_post returning view_count into total;
 else select view_count into total from public.posts where id=p_post;
 end if;
 return total;
end $$;
create function public.increment_view(post_id uuid) returns bigint language sql set search_path=''
as $$ select private.increment_view(post_id) $$;
revoke all on function private.increment_view(uuid),public.increment_view(uuid) from public,anon;
grant execute on function private.increment_view(uuid),public.increment_view(uuid) to authenticated;

-- SECURITY INVOKER deliberately preserves channels/posts/items RLS.
create function public.search_posts(query_text text default '',category_filter text default null,
 channel_filter uuid default null,creator_filter uuid default null,joined_only boolean default false,
 page_offset integer default 0,page_size integer default 20)
returns setof jsonb language sql stable security invoker set search_path='' as $$
 select to_jsonb(p)||jsonb_build_object('channels',to_jsonb(c),'post_items',
   coalesce((select jsonb_agg(to_jsonb(i) order by i.position) from public.post_items i where i.post_id=p.id),'[]'::jsonb))
 from public.posts p join public.channels c on c.id=p.channel_id
 where (coalesce(query_text,'')='' or p.title ilike '%'||left(query_text,160)||'%' or c.name ilike '%'||left(query_text,160)||'%')
 and (category_filter is null or lower(c.category)=lower(category_filter) or exists(
 select 1 from unnest(c.tags) tag where lower(tag)=lower(category_filter)))
 and (channel_filter is null or p.channel_id=channel_filter)
 and (creator_filter is null or p.created_by=creator_filter)
 and (not joined_only or exists(select 1 from public.channel_members m where m.user_id=auth.uid() and m.channel_id=p.channel_id))
 order by p.created_at desc,p.id
 limit least(greatest(page_size,1),50) offset greatest(page_offset,0)
$$;
revoke all on function public.search_posts(text,text,uuid,uuid,boolean,integer,integer) from public,anon;
grant execute on function public.search_posts(text,text,uuid,uuid,boolean,integer,integer) to authenticated;

-- Serialize ownership transfer before destructive cleanup, including concurrent deletes.
create function private.prepare_account_deletion() returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.is_member() then raise exception 'Member account required'; end if;
 perform pg_advisory_xact_lock(2026101604);
 if exists(select 1 from public.admins where user_id=auth.uid() and role='owner') then
   if (select count(*) from public.admins where role='owner')<=1 then
     raise exception 'Transfer ownership before deleting this account';
   end if;
   delete from public.admins where user_id=auth.uid();
   insert into public.audit_logs(actor_id,action,target_id) values(auth.uid(),'owner_account_deletion_prepared',auth.uid()::text);
 end if;
end $$;
create function public.prepare_account_deletion() returns void language sql set search_path=''
as $$ select private.prepare_account_deletion() $$;
revoke all on function private.prepare_account_deletion(),public.prepare_account_deletion() from public,anon;
grant execute on function private.prepare_account_deletion(),public.prepare_account_deletion() to authenticated;
create function private.keep_last_owner() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(2026101604);
 if exists(select 1 from public.admins where user_id=old.id and role='owner')
 and (select count(*) from public.admins where role='owner')<=1 then
   raise exception 'Transfer ownership before deleting this account';
 end if;
 return old;
end $$;
revoke all on function private.keep_last_owner() from public,anon,authenticated;
create trigger preserve_last_owner before delete on auth.users for each row execute function private.keep_last_owner();

update public.plans set perks='["Full premium videos","2 TB cloud storage","Download to your phone"]'::jsonb
 where perks in ('["2 TB cloud storage","Full premium videos","Fast upload & download"]'::jsonb,'[]'::jsonb);
