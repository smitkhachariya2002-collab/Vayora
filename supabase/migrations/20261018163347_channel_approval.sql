-- Channel review is server-authoritative. App inserts, including admins, always wait.
alter table public.channels add column reviewed_by uuid references auth.users(id) on delete set null;
alter table public.channels add column reviewed_at timestamptz;
create index channels_reviewed_by_idx on public.channels(reviewed_by);
alter table public.channels drop constraint channels_status_check;
-- Legacy 'active' remains readable for installed clients; new approval writes 'published'.
alter table public.channels add constraint channels_status_check check(status in ('draft','published','hidden','active'));
alter table public.channels alter column status set default 'draft';
create index channels_pending_creator_idx on public.channels(created_by) where review_status='pending';
create index channels_pending_review_idx on public.channels(created_at) where review_status='pending';

-- A private, transaction-scoped capability: unlike a client-settable GUC/header,
-- only the authenticated, role-checked functions below can create this row.
create table private.channel_operations (
 transaction_id bigint not null, channel_id uuid not null, actor_id uuid not null,
 operation text not null check(operation in ('save','review')),
 primary key(transaction_id,channel_id)
);
alter table private.channel_operations enable row level security;
revoke all on private.channel_operations from public,anon,authenticated,service_role;

create or replace function private.channel_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare privileged boolean;
begin
 -- Trusted migrations/service operations have no end-user identity. API roles
 -- cannot INSERT/UPDATE without auth.uid() due to grants and RLS.
 if auth.uid() is null then return new; end if;
 select exists(select 1 from private.channel_operations o
 where o.transaction_id=txid_current() and o.channel_id=new.id and o.actor_id=auth.uid())
 into privileged;
 if TG_OP='INSERT' then
   if not private.is_member() then raise insufficient_privilege using message='Log in to create a channel'; end if;
   new.created_by=auth.uid();
   new.created_at=now();
   new.members_count=0;
   if privileged then
     new.review_status='approved'; new.status='published';
     new.reviewed_by=auth.uid(); new.reviewed_at=now();
   else
     -- Serialize the count per creator, including concurrent app requests.
     perform pg_advisory_xact_lock(hashtextextended('channel-request:'||auth.uid()::text,0));
     if (select count(*) from public.channels where created_by=auth.uid() and review_status='pending')>=3 then
       raise exception 'you already have 3 channels waiting for approval';
     end if;
     new.review_status='pending'; new.status='draft'; new.audience='all';
     new.reviewed_by=null; new.reviewed_at=null;
   end if;
 elsif not privileged and
   (to_jsonb(new)-array['name','description','category','tags','icon_url'])
   is distinct from (to_jsonb(old)-array['name','description','category','tags','icon_url']) then
   raise exception 'Protected channel fields';
 end if;
 return new;
end $$;

-- Preserve existing approved communities; do not expose pending/rejected rows.
update public.channels set status=case when review_status<>'approved' then 'draft'
 when status='active' then 'published' else status end;
alter table public.channels add constraint channels_name_minimum check(length(btrim(name)) between 3 and 120) not valid;

create or replace function private.visible_channel(p_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.channels c where c.id=p_id and
 (private.is_admin() or c.created_by=auth.uid() or
 (c.status in ('published','active') and c.review_status='approved' and public.can_see(c.audience))))
$$;
create or replace function private.visible_post(p_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.posts p join public.channels c on c.id=p.channel_id
 where p.id=p_id and (private.is_admin() or p.created_by=auth.uid() or
 (c.status in ('published','active') and c.review_status='approved'
 and public.can_see(c.audience) and public.can_see(p.audience)
 and (p.status='published' or (p.status='scheduled' and p.publish_at<=now())))))
$$;
create or replace function private.creator_write_allowed(p_channel uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.is_member() and exists(
 select 1 from public.channels c where c.id=p_channel and c.review_status='approved'
 and c.status in ('published','active') and
 (c.created_by=auth.uid() or (private.is_admin() and private.manage_channel(c.id))))
$$;

-- Direct row predicates also authorize INSERT ... RETURNING before a row lookup
-- can see that new row; the same policy remains creator/admin-only for drafts.
drop policy channels_read on public.channels;
create policy channels_read on public.channels for select to authenticated
 using(created_by=(select auth.uid()) or (select private.is_admin()) or
 (review_status='approved' and status in ('published','active') and public.can_see(audience)));

drop policy channels_edit on public.channels;
create policy channels_edit on public.channels for update to authenticated
 using(created_by=(select auth.uid()) and (select private.is_member()))
 with check(created_by=(select auth.uid()) and (select private.is_member()));
drop policy channels_delete on public.channels;
create policy channels_delete on public.channels for delete to authenticated
 using(created_by=(select auth.uid()) and review_status<>'approved' and (select private.is_member()));
drop policy members_join on public.channel_members;
create policy members_join on public.channel_members for insert to authenticated
 with check(user_id=(select auth.uid()) and (select private.is_member()) and exists(
 select 1 from public.channels c where c.id=channel_id and c.review_status='approved'
 and c.status in ('published','active') and private.visible_channel(c.id)));

create function private.review_channel(p_channel uuid,p_approve boolean,p_audience public.audience) returns void
language plpgsql security definer set search_path='' as $$
declare creator uuid;
begin
 if auth.uid() is null or not private.is_owner() then raise exception 'Owner required'; end if;
 if p_approve is null or p_audience is null then raise exception 'Review decision and audience required'; end if;
 select created_by into creator from public.channels where id=p_channel for update;
 if not found then raise exception 'Channel unavailable'; end if;
 insert into private.channel_operations values(txid_current(),p_channel,auth.uid(),'review');
 if p_approve then
   insert into public.channel_members(user_id,channel_id) values(creator,p_channel) on conflict do nothing;
 end if;
 update public.channels set review_status=case when p_approve then 'approved' else 'rejected' end,
 status=case when p_approve then 'published' else 'draft' end,
 audience=case when p_approve then p_audience else audience end,
 reviewed_by=auth.uid(),reviewed_at=now(),
 members_count=(select count(*) from public.channel_members where channel_id=p_channel)
 where id=p_channel;
 delete from private.channel_operations where transaction_id=txid_current() and channel_id=p_channel;
 insert into public.audit_logs(actor_id,action,target_id)
 values(auth.uid(),case when p_approve then 'channel_approved' else 'channel_rejected' end,p_channel::text);
end $$;
create function public.review_channel(channel_id uuid,approve boolean,audience public.audience default 'all')
returns void language sql security invoker set search_path=''
as $$ select private.review_channel(channel_id,approve,audience) $$;

create function private.admin_save_channel(p_id uuid,p_name text,p_description text,p_category text,
 p_icon text,p_audience public.audience,p_status text,p_tags text[]) returns uuid
language plpgsql security definer set search_path='' as $$
declare target uuid=coalesce(p_id,gen_random_uuid()); existing public.channels;
begin
 if auth.uid() is null or not private.is_admin() or not private.is_member() then raise exception 'Admin required'; end if;
 if p_audience is null or p_status not in ('published','hidden') then raise exception 'Invalid channel settings'; end if;
 if p_id is not null then
   select * into existing from public.channels where id=target for update;
   if not found or not private.manage_channel(target) then raise exception 'Channel access required'; end if;
   if not private.is_owner() and (p_audience<>existing.audience or
       (existing.review_status='approved' and p_status<>case when existing.status='active' then 'published' else existing.status end)) then
     raise exception 'Owner required';
   end if;
 end if;
 insert into private.channel_operations values(txid_current(),target,auth.uid(),'save');
 if p_id is null then
   insert into public.channels(id,name,description,category,icon_url,audience,tags,created_by)
   values(target,btrim(p_name),coalesce(p_description,''),coalesce(p_category,''),p_icon,p_audience,
     coalesce(p_tags,'{}'),auth.uid());
   insert into public.channel_members(user_id,channel_id) values(auth.uid(),target) on conflict do nothing;
   update public.channels set members_count=1,status=p_status where id=target;
 else
   update public.channels set name=btrim(p_name),description=coalesce(p_description,''),
   category=coalesce(p_category,''),icon_url=p_icon,audience=p_audience,tags=coalesce(p_tags,'{}'),
   status=case when existing.review_status='approved' then p_status else 'draft' end where id=target;
 end if;
 delete from private.channel_operations where transaction_id=txid_current() and channel_id=target;
 return target;
end $$;
create function public.admin_save_channel(channel_id uuid,channel_name text,description text default '',
 category text default '',icon_url text default null,audience public.audience default 'all',
 status text default 'published',tags text[] default '{}') returns uuid
language sql security invoker set search_path='' as $$
 select private.admin_save_channel(channel_id,channel_name,description,category,icon_url,audience,status,tags)
$$;

-- No 500-user directory limit: each pending request gets its creator identity.
create function private.channel_requests() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.is_owner() then raise exception 'Owner required'; end if;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from (
 select c.*,p.display_name as creator_name,u.email as creator_email,
 coalesce(s.source,'organic') as creator_source
 from public.channels c join public.profiles p on p.id=c.created_by
 join auth.users u on u.id=c.created_by left join private.user_sources s on s.user_id=c.created_by
 where c.review_status='pending')x),'[]'::jsonb);
end $$;
create function public.channel_requests() returns jsonb language sql security invoker set search_path=''
as $$ select private.channel_requests() $$;

revoke all on function private.review_channel(uuid,boolean,public.audience),
 public.review_channel(uuid,boolean,public.audience),
 private.admin_save_channel(uuid,text,text,text,text,public.audience,text,text[]),
 public.admin_save_channel(uuid,text,text,text,text,public.audience,text,text[]),
 private.channel_requests(),public.channel_requests(),private.channel_guard() from public,anon,authenticated;
grant execute on function private.review_channel(uuid,boolean,public.audience),
 public.review_channel(uuid,boolean,public.audience),
 private.admin_save_channel(uuid,text,text,text,text,public.audience,text,text[]),
 public.admin_save_channel(uuid,text,text,text,text,public.audience,text,text[]),
 private.channel_requests(),public.channel_requests() to authenticated;

-- Dedicated icon bucket enforces <5 MiB on the server without shrinking media uploads.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('channel-icons','channel-icons',true,5242879,array['image/jpeg','image/png','image/webp']);
create policy channel_icons_read on storage.objects for select to authenticated using(bucket_id='channel-icons');
create policy channel_icons_create on storage.objects for insert to authenticated
 with check(bucket_id='channel-icons' and (storage.foldername(name))[1]=(select auth.uid())::text and (select private.is_member()));
create policy channel_icons_update on storage.objects for update to authenticated
 using(bucket_id='channel-icons' and (storage.foldername(name))[1]=(select auth.uid())::text and (select private.is_member()))
 with check(bucket_id='channel-icons' and (storage.foldername(name))[1]=(select auth.uid())::text and (select private.is_member()));
create policy channel_icons_delete on storage.objects for delete to authenticated
 using(bucket_id='channel-icons' and (storage.foldername(name))[1]=(select auth.uid())::text and (select private.is_member()));
