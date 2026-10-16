-- Vayora foundation. Only deploy using the reviewed GitHub Actions workflow.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

create type public.audience as enum ('all','organic','ads');
create type public.access_status as enum ('none','pending','approved','rejected');
create table public.profiles (
 id uuid primary key references auth.users on delete cascade,
 display_name text not null default '', avatar_url text,
 is_guest boolean not null default true, used_bytes bigint not null default 0 check (used_bytes >= 0),
 ads_access_status public.access_status not null default 'none', created_at timestamptz not null default now()
);
create table public.admins (
 user_id uuid primary key references auth.users on delete cascade,
 role text not null check (role in ('owner','content'))
);
create table public.installs (
 install_id uuid primary key, referrer_status text not null, raw_referrer text not null default '',
 utm_source text, utm_medium text, utm_campaign text, utm_content text, utm_term text,
 source text not null check (source in ('organic','ads')),
 user_id uuid references auth.users on delete set null, client_ip inet, user_agent text,
 ad_click_id uuid, created_at timestamptz not null default now()
);
create index installs_user_idx on public.installs(user_id);
create table private.install_claims (
 install_id uuid primary key references public.installs on delete cascade, secret_hash bytea not null
);
create table private.user_sources (
 user_id uuid primary key references auth.users on delete cascade,
 source text not null check (source in ('organic','ads')), created_at timestamptz not null default now()
);
create table public.channels (
 id uuid primary key default gen_random_uuid(), name text not null check (length(name) between 1 and 120),
 description text not null default '', category text not null default '', icon_url text,
 audience public.audience not null default 'all', status text not null default 'active' check(status in ('active','hidden')),
 review_status text not null default 'pending' check(review_status in ('pending','approved','rejected')),
 created_by uuid not null references auth.users, members_count bigint not null default 0,
 created_at timestamptz not null default now()
);
create index channels_creator_idx on public.channels(created_by);
create table public.admin_channel_access (
 user_id uuid not null references public.admins on delete cascade,
 channel_id uuid not null references public.channels on delete cascade, primary key(user_id,channel_id)
);
create index admin_channel_access_channel_idx on public.admin_channel_access(channel_id);
create table public.channel_folders (
 id uuid primary key default gen_random_uuid(), channel_id uuid not null references public.channels on delete cascade,
 name text not null
);
create index channel_folders_channel_idx on public.channel_folders(channel_id);
create table public.channel_members (
 user_id uuid not null references auth.users on delete cascade,
 channel_id uuid not null references public.channels on delete cascade, created_at timestamptz not null default now(),
 primary key(user_id,channel_id)
);
create index channel_members_channel_idx on public.channel_members(channel_id);
create table public.posts (
 id uuid primary key default gen_random_uuid(), channel_id uuid not null references public.channels on delete cascade,
 title text not null, description text not null default '', audience public.audience not null default 'all',
 status text not null default 'draft' check(status in ('draft','scheduled','published')), publish_at timestamptz,
 created_by uuid not null references auth.users, view_count bigint not null default 0,
 created_at timestamptz not null default now()
);
create index posts_channel_idx on public.posts(channel_id);
create index posts_creator_idx on public.posts(created_by);
create index posts_published_idx on public.posts(status,publish_at);
create table public.post_items (
 id uuid primary key default gen_random_uuid(), post_id uuid not null references public.posts on delete cascade,
 media_key text not null unique, thumbnail_key text, trailer_key text unique,
 mime text not null default 'video/mp4', duration_s integer check(duration_s >= 0),
 is_premium boolean not null default false, position integer not null default 0,
 check (trailer_key is null or trailer_key <> media_key)
);
create index post_items_post_idx on public.post_items(post_id);
create table public.consents (
 user_id uuid not null references auth.users on delete cascade, policy_version text not null,
 accepted_at timestamptz not null default now(), primary key(user_id,policy_version)
);
create table public.audit_logs (
 id bigint generated always as identity primary key, actor_id uuid references auth.users on delete set null,
 action text not null, target_id text, created_at timestamptz not null default now()
);
create index audit_actor_idx on public.audit_logs(actor_id);
create table public.app_mode (
 id boolean primary key default true check(id), free_mode boolean not null default false,
 free_access_enabled boolean not null default true, paid_enabled boolean not null default true
);
-- Hybrid launch: free access AND upgrades. free_mode is a separate exclusive-free override.
insert into public.app_mode(id,free_mode,free_access_enabled,paid_enabled) values(true,false,true,true);

create function private.is_owner() returns boolean language sql stable security definer set search_path=''
as $$ select auth.uid() is not null and exists(select 1 from public.admins where user_id=auth.uid() and role='owner') $$;
create function public.is_owner() returns boolean language sql stable set search_path=''
as $$ select private.is_owner() $$;
create function private.is_admin() returns boolean language sql stable security definer set search_path=''
as $$ select auth.uid() is not null and exists(select 1 from public.admins where user_id=auth.uid()) $$;
create function public.is_admin() returns boolean language sql stable set search_path=''
as $$ select private.is_admin() $$;
create function private.is_member() returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from auth.users where id=auth.uid() and not coalesce(is_anonymous,false) and deleted_at is null) $$;
create function private.source_of(p_user uuid) returns text language sql stable security definer set search_path=''
as $$ select case when p_user=auth.uid() or private.is_owner()
 then coalesce((select source from private.user_sources where user_id=p_user),'organic') else null end $$;
create function public.source_of(user_id uuid) returns text language sql stable set search_path=''
as $$ select private.source_of(user_id) $$;
create function private.has_ads_access() returns boolean language sql stable security definer set search_path=''
as $$ select auth.uid() is not null and
 (private.source_of(auth.uid())='ads' or exists(select 1 from public.profiles where id=auth.uid() and ads_access_status='approved')) $$;
create function public.has_ads_access() returns boolean language sql stable set search_path=''
as $$ select private.has_ads_access() $$;
create function public.can_see(audience public.audience) returns boolean language sql stable set search_path=''
as $$ select auth.uid() is not null and (private.is_admin() or audience='all'
 or (audience='organic' and private.source_of(auth.uid())='organic')
 or (audience='ads' and private.has_ads_access())) $$;
create function private.manage_channel(p_id uuid) returns boolean language sql stable security definer set search_path=''
as $$ select auth.uid() is not null and (private.is_owner() or exists(
 select 1 from public.channels c where c.id=p_id and (c.created_by=auth.uid() or
 (private.is_admin() and exists(select 1 from public.admin_channel_access a where a.user_id=auth.uid() and a.channel_id=c.id))))) $$;
create function private.visible_channel(p_id uuid) returns boolean language sql stable security definer set search_path=''
as $$ select auth.uid() is not null and exists(select 1 from public.channels c where c.id=p_id and
 (private.is_admin() or c.created_by=auth.uid() or (c.status='active' and c.review_status='approved' and public.can_see(c.audience)))) $$;
create function private.visible_post(p_id uuid) returns boolean language sql stable security definer set search_path=''
as $$ select auth.uid() is not null and exists(select 1 from public.posts p join public.channels c on c.id=p.channel_id where p.id=p_id and
 (private.is_admin() or p.created_by=auth.uid() or
 (c.status='active' and c.review_status='approved' and public.can_see(c.audience) and public.can_see(p.audience)
 and (p.status='published' or (p.status='scheduled' and p.publish_at<=now()))))) $$;

create function private.sync_profile() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,is_guest) values(new.id,coalesce(new.is_anonymous,false))
 on conflict(id) do update set is_guest=excluded.is_guest;
 return new;
end $$;
create trigger auth_profile after insert or update of is_anonymous on auth.users for each row execute function private.sync_profile();

create function private.query_param(raw text,k text) returns text language sql immutable set search_path=''
as $$ select split_part(x,'=',2) from unnest(string_to_array(ltrim(raw,'?'),'&')) x where split_part(x,'=',1)=k limit 1 $$;
-- Parse percent-encoded referrer values, including '+' spaces.
create function private.url_decode(v text) returns text language plpgsql immutable set search_path='' as $$
declare result bytea=''; i integer=1; ch text;
begin
 if v is null then return null; end if;
 while i<=length(v) loop
 ch=substr(v,i,1);
 if ch='%' and substr(v,i+1,2) ~ '^[0-9A-Fa-f]{2}$' then
 result=result || decode(substr(v,i+1,2),'hex'); i=i+3;
 else result=result || convert_to(case when ch='+' then ' ' else ch end,'UTF8'); i=i+1; end if;
 end loop;
 return convert_from(result,'UTF8');
exception when character_not_in_repertoire then return v;
end $$;
create function private.record_install(p_id uuid,p_status text,p_raw text,p_secret text) returns text
language plpgsql security definer set search_path='' as $$
declare src text; headers jsonb; existing bytea;
begin
 if auth.uid() is null or length(coalesce(p_secret,''))<32 then raise exception 'Authentication and install secret required'; end if;
 if length(coalesce(p_raw,''))>4096 then raise exception 'Referrer too long'; end if;
 headers=coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}');
 src=case when lower(private.url_decode(private.query_param(coalesce(p_raw,''),'utm_source'))) in ('meta','facebook','instagram','fb','ig') then 'ads' else 'organic' end;
 insert into public.installs(install_id,referrer_status,raw_referrer,utm_source,utm_medium,utm_campaign,utm_content,utm_term,source,user_id,user_agent)
 values(p_id,left(p_status,80),coalesce(p_raw,''),private.url_decode(private.query_param(p_raw,'utm_source')),
 private.url_decode(private.query_param(p_raw,'utm_medium')),private.url_decode(private.query_param(p_raw,'utm_campaign')),
 private.url_decode(private.query_param(p_raw,'utm_content')),private.url_decode(private.query_param(p_raw,'utm_term')),src,auth.uid(),headers->>'user-agent')
 on conflict(install_id) do nothing;
 insert into private.install_claims(install_id,secret_hash) values(p_id,extensions.digest(p_secret,'sha256')) on conflict do nothing;
 select secret_hash into existing from private.install_claims where install_id=p_id;
 if existing<>extensions.digest(p_secret,'sha256') then raise exception 'Invalid install secret'; end if;
 select source into src from public.installs where install_id=p_id;
 insert into private.user_sources(user_id,source) values(auth.uid(),src) on conflict(user_id) do nothing;
 return src;
end $$;
create function public.record_install(install_id uuid,referrer_status text,raw_referrer text,install_secret text)
returns text language sql set search_path='' as $$ select private.record_install(install_id,referrer_status,raw_referrer,install_secret) $$;
create function private.attribute_user(p_id uuid,p_secret text) returns void language plpgsql security definer set search_path='' as $$
declare src text;
begin
 if auth.uid() is null or not exists(select 1 from private.install_claims where install_id=p_id and secret_hash=extensions.digest(p_secret,'sha256')) then raise exception 'Invalid install claim'; end if;
 select source into src from public.installs where install_id=p_id for update;
 insert into private.user_sources(user_id,source) values(auth.uid(),src) on conflict(user_id) do nothing;
 update public.installs set user_id=auth.uid() where install_id=p_id;
end $$;
create function public.attribute_user(install_id uuid,install_secret text) returns void language sql set search_path=''
as $$ select private.attribute_user(install_id,install_secret) $$;

create function private.channel_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='INSERT' then
 if new.created_by<>auth.uid() and auth.uid() is not null then raise exception 'Invalid creator'; end if;
 new.review_status=case when private.is_admin() then 'approved' else 'pending' end;
 new.members_count=0;
 elsif not private.is_owner() then
 if new.id<>old.id or new.created_by<>old.created_by or new.review_status<>old.review_status or new.members_count<>old.members_count then
 raise exception 'Protected channel fields'; end if;
 end if;
 return new;
end $$;
create trigger channel_guard before insert or update on public.channels for each row execute function private.channel_guard();
create function private.post_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='INSERT' then
 if new.created_by<>auth.uid() and auth.uid() is not null then raise exception 'Invalid creator'; end if;
 new.view_count=0;
 elsif new.created_by<>old.created_by or new.id<>old.id or new.view_count<>old.view_count then raise exception 'Protected post fields'; end if;
 return new;
end $$;
create trigger post_guard before insert or update on public.posts for each row execute function private.post_guard();

do $$ declare t text; begin
 foreach t in array array['profiles','admins','installs','channels','admin_channel_access','channel_folders','channel_members','posts','post_items','consents','audit_logs','app_mode'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon, authenticated',t);
 execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;
alter table private.install_claims enable row level security;
alter table private.user_sources enable row level security;
grant select on public.profiles,public.admins,public.installs,public.channels,public.admin_channel_access,public.channel_folders,
 public.channel_members,public.posts,public.post_items,public.consents,public.audit_logs,public.app_mode to authenticated;
grant update(display_name,avatar_url) on public.profiles to authenticated;
grant insert,update,delete on public.channels,public.channel_folders,public.posts,public.post_items to authenticated;
grant insert,delete on public.channel_members to authenticated;
grant insert on public.consents to authenticated;
grant update on public.app_mode to authenticated;
create policy profiles_read on public.profiles for select to authenticated using(id=(select auth.uid()) or (select private.is_owner()));
create policy profiles_edit on public.profiles for update to authenticated using(id=(select auth.uid())) with check(id=(select auth.uid()));
create policy admins_read on public.admins for select to authenticated using(user_id=(select auth.uid()) or (select private.is_owner()));
create policy installs_read on public.installs for select to authenticated using((select private.is_owner()));
create policy channels_read on public.channels for select to authenticated using(private.visible_channel(id));
create policy channels_create on public.channels for insert to authenticated with check((select private.is_member()) and created_by=(select auth.uid()));
create policy channels_edit on public.channels for update to authenticated using(private.manage_channel(id)) with check(private.manage_channel(id));
create policy channels_delete on public.channels for delete to authenticated using(private.manage_channel(id));
create policy channel_access_read on public.admin_channel_access for select to authenticated using(user_id=(select auth.uid()) or (select private.is_owner()));
create policy folders_read on public.channel_folders for select to authenticated using(private.visible_channel(channel_id));
create policy folders_create on public.channel_folders for insert to authenticated with check(private.manage_channel(channel_id));
create policy folders_edit on public.channel_folders for update to authenticated using(private.manage_channel(channel_id)) with check(private.manage_channel(channel_id));
create policy folders_delete on public.channel_folders for delete to authenticated using(private.manage_channel(channel_id));
create policy members_read on public.channel_members for select to authenticated using(user_id=(select auth.uid()) or private.manage_channel(channel_id));
create policy members_join on public.channel_members for insert to authenticated with check(user_id=(select auth.uid()) and (select private.is_member()) and private.visible_channel(channel_id));
create policy members_leave on public.channel_members for delete to authenticated using(user_id=(select auth.uid()));
create policy posts_read on public.posts for select to authenticated using(private.visible_post(id));
create policy posts_create on public.posts for insert to authenticated with check((select private.is_member()) and created_by=(select auth.uid()) and private.manage_channel(channel_id));
create policy posts_edit on public.posts for update to authenticated using(private.manage_channel(channel_id)) with check(private.manage_channel(channel_id));
create policy posts_delete on public.posts for delete to authenticated using(private.manage_channel(channel_id));
create policy items_read on public.post_items for select to authenticated using(private.visible_post(post_id));
create policy items_create on public.post_items for insert to authenticated with check(exists(select 1 from public.posts p where p.id=post_id and private.manage_channel(p.channel_id)));
create policy items_edit on public.post_items for update to authenticated using(exists(select 1 from public.posts p where p.id=post_id and private.manage_channel(p.channel_id)))
 with check(exists(select 1 from public.posts p where p.id=post_id and private.manage_channel(p.channel_id)));
create policy items_delete on public.post_items for delete to authenticated using(exists(select 1 from public.posts p where p.id=post_id and private.manage_channel(p.channel_id)));
create policy consents_read on public.consents for select to authenticated using(user_id=(select auth.uid()));
create policy consents_accept on public.consents for insert to authenticated with check(user_id=(select auth.uid()) and policy_version='v1');
create policy audit_read on public.audit_logs for select to authenticated using((select private.is_owner()));
create policy mode_read on public.app_mode for select to authenticated using(true);
create policy mode_edit on public.app_mode for update to authenticated using((select private.is_owner())) with check((select private.is_owner()));

-- Helpers in private are not API endpoints; expose only narrow invoker wrappers.
revoke execute on all functions in schema private from public,anon,authenticated;
grant execute on function private.is_owner(),private.is_admin(),private.is_member(),private.source_of(uuid),private.has_ads_access(),
 private.manage_channel(uuid),private.visible_channel(uuid),private.visible_post(uuid),private.record_install(uuid,text,text,text),private.attribute_user(uuid,text) to authenticated;
revoke execute on all functions in schema public from public,anon;
grant execute on function public.is_owner(),public.is_admin(),public.source_of(uuid),public.has_ads_access(),public.can_see(public.audience),
 public.record_install(uuid,text,text,text),public.attribute_user(uuid,text) to authenticated;
