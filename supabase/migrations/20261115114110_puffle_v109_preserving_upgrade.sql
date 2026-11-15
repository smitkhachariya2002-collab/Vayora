-- Executed atomically with the v1.0.9 schema and the data conversion.
-- Original tables, functions, data and policies are retained in private archive schemas.
set local lock_timeout = '10s';
create table private.v109_cutover_backup(kind text, name text, definition text);
alter table private.v109_cutover_backup enable row level security;
-- Save the exact grants before hiding the legacy schema; rollback must not broaden access.
insert into private.v109_cutover_backup
select 'grant',n.nspname,format('grant %s on schema %I to %s%s;',a.privilege_type,n.nspname,case when a.grantee=0 then 'public' else quote_ident(pg_get_userbyid(a.grantee)) end,case when a.is_grantable then ' with grant option' else '' end)
from pg_namespace n cross join lateral aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a where n.nspname in ('public','private');
insert into private.v109_cutover_backup
select 'grant',c.relname,format('grant %s on %s %I.%I to %s%s;',a.privilege_type,case when c.relkind='S' then 'sequence' else 'table' end,n.nspname,c.relname,case when a.grantee=0 then 'public' else quote_ident(pg_get_userbyid(a.grantee)) end,case when a.is_grantable then ' with grant option' else '' end)
from pg_class c join pg_namespace n on n.oid=c.relnamespace cross join lateral aclexplode(coalesce(c.relacl,acldefault(case when c.relkind='S' then 'S'::"char" else 'r'::"char" end,c.relowner))) a
where n.nspname in ('public','private') and c.relkind in ('r','p','v','m','S');
insert into private.v109_cutover_backup
select 'grant',p.proname,format('grant %s on function %I.%I(%s) to %s%s;',a.privilege_type,n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),case when a.grantee=0 then 'public' else quote_ident(pg_get_userbyid(a.grantee)) end,case when a.is_grantable then ' with grant option' else '' end)
from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where n.nspname in ('public','private') and p.prokind='f';
insert into private.v109_cutover_backup select 'publication',tablename,format('alter publication supabase_realtime add table %I.%I;',schemaname,tablename) from pg_publication_tables where pubname='supabase_realtime' and schemaname='public';
insert into private.v109_cutover_backup select 'bucket',id,jsonb_build_object('public',public,'file_size_limit',file_size_limit,'allowed_mime_types',allowed_mime_types)::text from storage.buckets;
insert into private.v109_cutover_backup
select 'auth_trigger',t.tgname,pg_get_triggerdef(t.oid) from pg_trigger t
join pg_proc p on p.oid=t.tgfoid join pg_namespace n on n.oid=p.pronamespace
where t.tgrelid='auth.users'::regclass and not t.tgisinternal and n.nspname in ('public','private');
insert into private.v109_cutover_backup
select 'storage_policy',policyname,format('create policy %I on %I.%I as %s for %s to %s %s %s;',policyname,schemaname,tablename,permissive,cmd,array_to_string(roles,','),case when qual is null then '' else 'using ('||qual||')' end,case when with_check is null then '' else 'with check ('||with_check||')' end)
from pg_policies where schemaname='storage' and tablename='objects';
insert into private.v109_cutover_backup select 'cron',jobname,command from cron.job where jobname like 'vayora-%' and active;
select cron.alter_job(jobid,active:=false) from cron.job where jobname like 'vayora-%';
do $$declare r record;begin
 for r in select tablename,schemaname from pg_tables where schemaname in ('public','private') loop
  execute format('lock table %I.%I in access exclusive mode',r.schemaname,r.tablename);
 end loop;
 for r in select name from private.v109_cutover_backup where kind='auth_trigger' loop
  execute format('drop trigger %I on auth.users',r.name);
 end loop;
 for r in select name from private.v109_cutover_backup where kind='storage_policy' loop
  execute format('drop policy %I on storage.objects',r.name);
 end loop;
 for r in select schemaname,tablename from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' loop
  execute format('alter publication supabase_realtime drop table %I.%I',r.schemaname,r.tablename);
 end loop;
end$$;
alter schema public rename to vayora_legacy_20261115;
alter schema private rename to vayora_legacy_private_20261115;
revoke all on schema vayora_legacy_20261115,vayora_legacy_private_20261115 from public,anon,authenticated,service_role;
revoke all on all tables in schema vayora_legacy_20261115,vayora_legacy_private_20261115 from public,anon,authenticated,service_role;
revoke all on all functions in schema vayora_legacy_20261115,vayora_legacy_private_20261115 from public,anon,authenticated,service_role;
create schema public;
create schema private;
grant usage on schema public to anon,authenticated,service_role;
grant usage on schema private to service_role;
alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
alter default privileges in schema public grant all on sequences to anon,authenticated,service_role;


-- SOURCE v1.0.9: 20261109000001_0001_core_tables.sql

create schema if not exists private;

-- ============ global config ============
create table public.app_mode (
  id int primary key default 1 check (id = 1),
  free_mode boolean not null default false,
  plans_visible_for text not null default 'everyone' check (plans_visible_for in ('everyone','ads','organic','none')),
  free_plans_for text not null default 'none' check (free_plans_for in ('none','organic','ads','everyone')),
  promo_id int not null default 0,
  updated_at timestamptz not null default now()
);
insert into public.app_mode (id) values (1);

create table public.plan_catalog (
  id int primary key default 1 check (id = 1),
  revision bigint not null default 0,
  updated_at timestamptz not null default now()
);
insert into public.plan_catalog (id) values (1);

create table public.plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z0-9][a-z0-9_-]{1,30}$'),
  name text not null check (length(trim(name)) > 0),
  price_inr integer not null check (price_inr >= 1),
  duration_days integer not null check (duration_days >= 1),
  perks text[] not null default '{}',
  badge text,
  position integer not null default 0,
  active boolean not null default true,
  free_eligible boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.payment_settings (
  id int primary key default 1 check (id = 1),
  upi_id text not null default '' check (upi_id = '' or upi_id ~ '^[A-Za-z0-9._-]{2,256}@[A-Za-z0-9]{2,64}$'),
  payee_name text not null default '',
  enabled boolean not null default true,
  activation_mode text not null default 'instant' check (activation_mode in ('instant','manual')),
  updated_at timestamptz not null default now()
);
insert into public.payment_settings (id) values (1);

create table public.play_settings (
  id int primary key default 1 check (id = 1),
  play_billing_enabled boolean not null default false,
  google_approval_confirmed boolean not null default false,
  updated_at timestamptz not null default now()
);
insert into public.play_settings (id) values (1);

-- ============ accounts ============
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  is_guest boolean not null default true,
  used_bytes bigint not null default 0 check (used_bytes >= 0),
  ads_access_status text not null default 'none' check (ads_access_status in ('none','pending','approved','rejected')),
  play_verified boolean not null default false,
  created_at timestamptz not null default now()
);

create table private.owner_bootstrap (email text primary key);
insert into private.owner_bootstrap (email) values ('perfumwala@gmail.com'); -- Original Vayora owner excluded.

create table public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','content')),
  created_at timestamptz not null default now()
);

create table public.consents (
  user_id uuid not null references auth.users(id) on delete cascade,
  policy_version text not null,
  accepted_at timestamptz not null default now(),
  primary key (user_id, policy_version)
);

-- ============ attribution ============
create table public.installs (
  install_id text primary key,
  user_id uuid references auth.users(id) on delete set null,
  source text not null check (source in ('ads','organic')),
  referrer_status text,
  raw_referrer text,
  utm_campaign text,
  install_secret text,
  created_at timestamptz not null default now()
);
create index installs_user_idx on public.installs (user_id);
create index installs_source_idx on public.installs (source, utm_campaign);

create table private.user_sources (
  user_id uuid primary key references auth.users(id) on delete cascade,
  source text not null check (source in ('ads','organic')),
  created_at timestamptz not null default now()
);

create table public.ad_clicks (
  id uuid primary key default gen_random_uuid(),
  fbclid text,
  fbc text,
  fbp text,
  ip text,
  user_agent text,
  created_at timestamptz not null default now()
);

-- ============ channels & posts ============
create table public.channels (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 80),
  description text not null default '',
  category text,
  tags text[] not null default '{}',
  icon_url text,
  audience text not null default 'all' check (audience in ('all','organic','ads')),
  status text not null default 'draft' check (status in ('draft','published','active')),
  review_status text not null default 'pending' check (review_status in ('pending','approved','rejected')),
  created_by uuid references auth.users(id) on delete set null,
  members_count integer not null default 0 check (members_count >= 0),
  hidden boolean not null default false,
  created_at timestamptz not null default now()
);
create index channels_created_by_idx on public.channels (created_by);
create index channels_review_idx on public.channels (review_status, status);

create table public.admin_channel_access (
  user_id uuid not null references auth.users(id) on delete cascade,
  channel_id uuid not null references public.channels(id) on delete cascade,
  primary key (user_id, channel_id)
);
create index admin_channel_access_channel_idx on public.admin_channel_access (channel_id);

create table public.channel_members (
  channel_id uuid not null references public.channels(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (channel_id, user_id)
);
create index channel_members_user_idx on public.channel_members (user_id);

create table public.channel_folders (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels(id) on delete cascade,
  name text not null,
  position integer not null default 0
);
create index channel_folders_channel_idx on public.channel_folders (channel_id);

create table public.posts (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels(id) on delete cascade,
  folder_id uuid references public.channel_folders(id) on delete set null,
  title text not null check (length(trim(title)) > 0),
  description text not null default '',
  audience text not null default 'all' check (audience in ('all','organic','ads')),
  status text not null default 'draft' check (status in ('draft','published','scheduled')),
  publish_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  hidden boolean not null default false,
  created_at timestamptz not null default now()
);
create index posts_channel_idx on public.posts (channel_id, created_at desc);
create index posts_folder_idx on public.posts (folder_id);
create index posts_created_by_idx on public.posts (created_by);
create index posts_feed_idx on public.posts (status, created_at desc);

create table public.post_items (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  media_key text not null,
  thumbnail_key text,
  mime text not null default 'video/mp4',
  is_premium boolean not null default false,
  duration_s integer check (duration_s is null or duration_s >= 0),
  trailer_key text,
  position integer not null default 0,
  size_bytes bigint not null default 0
);
create index post_items_post_idx on public.post_items (post_id, position);

create table public.blocked_channels (
  user_id uuid not null references auth.users(id) on delete cascade,
  channel_id uuid not null references public.channels(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, channel_id)
);
create index blocked_channels_channel_idx on public.blocked_channels (channel_id);

create table public.support_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  kind text not null check (kind in ('report','deletion','other')),
  target_type text check (target_type in ('post','channel','account')),
  target_id uuid,
  reason text,
  details text,
  email text,
  status text not null default 'open' check (status in ('open','closed')),
  created_at timestamptz not null default now()
);
create index support_requests_user_idx on public.support_requests (user_id);
create index support_requests_status_idx on public.support_requests (status, created_at desc);

-- ============ personal cloud ============
create table public.cloud_folders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  parent_id uuid references public.cloud_folders(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  created_at timestamptz not null default now()
);
create index cloud_folders_user_idx on public.cloud_folders (user_id, parent_id);
create index cloud_folders_parent_idx on public.cloud_folders (parent_id);

create table public.cloud_files (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  folder_id uuid references public.cloud_folders(id) on delete set null,
  name text not null check (length(trim(name)) > 0),
  storage_path text not null unique,
  mime text,
  size_bytes bigint not null default 0 check (size_bytes >= 0),
  created_at timestamptz not null default now()
);
create index cloud_files_user_idx on public.cloud_files (user_id, folder_id);
create index cloud_files_folder_idx on public.cloud_files (folder_id);

-- ============ subscriptions ============
create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid references public.plans(id),
  plan_code text,
  plan_name text,
  kind text not null check (kind in ('payment','free_promo','admin_grant')),
  order_id uuid unique,
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  revoked boolean not null default false,
  created_at timestamptz not null default now()
);
create index subscriptions_user_idx on public.subscriptions (user_id, ends_at desc);
create index subscriptions_plan_idx on public.subscriptions (plan_id);

-- seed plans (editable later in admin)
insert into public.plans (code, name, price_inr, duration_days, perks, badge, position) values
 ('trial','Trial',49,7,array['2 TB cloud storage','Full-length premium videos','Offline downloads'],null,1),
 ('silver','Silver',129,7,array['2 TB cloud storage','Full-length premium videos','Offline downloads'],null,2),
 ('gold','Gold',259,30,array['2 TB cloud storage','Full-length premium videos','Offline downloads','Priority support'],'Popular',3),
 ('platinum','Platinum',599,180,array['2 TB cloud storage','Full-length premium videos','Offline downloads','Priority support'],null,4),
 ('diamond','Diamond',999,365,array['2 TB cloud storage','Full-length premium videos','Offline downloads','Priority support'],'Best value',5);


-- SOURCE v1.0.9: 20261109000002_0002_core_functions_triggers.sql

-- ============ helpers (public, executable by authenticated only; see grants at end) ============
create function public.is_admin() returns boolean language sql stable security definer set search_path = '' as
$$ select exists (select 1 from public.admins where user_id = auth.uid()) $$;

create function public.is_owner() returns boolean language sql stable security definer set search_path = '' as
$$ select exists (select 1 from public.admins where user_id = auth.uid() and role = 'owner') $$;

create function public.is_member() returns boolean language sql stable security definer set search_path = '' as
$$ select auth.uid() is not null and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false $$;

create function public.source_of(p_uid uuid default auth.uid()) returns text language sql stable security definer set search_path = '' as
$$ select coalesce((select source from private.user_sources where user_id = p_uid), 'organic') $$;

create function public.is_free_mode() returns boolean language sql stable security definer set search_path = '' as
$$ select free_mode from public.app_mode where id = 1 $$;

create function public.has_plan(p_uid uuid default auth.uid()) returns boolean language sql stable security definer set search_path = '' as
$$ select exists (select 1 from public.subscriptions where user_id = p_uid and not revoked and ends_at > now()) $$;

create function public.has_ads_access(p_uid uuid default auth.uid()) returns boolean language sql stable security definer set search_path = '' as
$$
 select case
   when p_uid is null then false
   when exists (select 1 from public.admins where user_id = p_uid) then true
   when public.source_of(p_uid) = 'ads' then true
   else coalesce((select ads_access_status = 'approved' from public.profiles where id = p_uid), false)
        and ((select free_mode from public.app_mode where id = 1) or public.has_plan(p_uid))
 end
$$;

create function public.plans_visible_for_me() returns boolean language sql stable security definer set search_path = '' as
$$
 select public.is_admin() or coalesce(
   case (select plans_visible_for from public.app_mode where id = 1)
     when 'everyone' then true
     when 'none' then false
     when 'ads' then public.source_of() = 'ads'
     when 'organic' then public.source_of() = 'organic'
   end, false)
$$;

create function public.free_plan_for_me(p_plan uuid) returns boolean language sql stable security definer set search_path = '' as
$$
 select public.plans_visible_for_me()
   and not (select free_mode from public.app_mode where id = 1)
   and exists (select 1 from public.plans pl where pl.id = p_plan and pl.active and pl.free_eligible)
   and coalesce(
     case (select free_plans_for from public.app_mode where id = 1)
       when 'everyone' then true
       when 'none' then false
       when 'ads' then public.source_of() = 'ads'
       when 'organic' then public.source_of() = 'organic'
     end, false)
$$;

create function public.quota_bytes(p_uid uuid default auth.uid()) returns bigint language sql stable security definer set search_path = '' as
$$
 select case
   when p_uid is null then 0::bigint
   when coalesce((select is_guest from public.profiles where id = p_uid), true) then 0::bigint
   when public.has_plan(p_uid) then 2199023255552::bigint
   when (select free_mode from public.app_mode where id = 1)
        or coalesce((select play_verified from public.profiles where id = p_uid), false) then 16106127360::bigint
   else 0::bigint
 end
$$;

create function public.payments_available() returns boolean language sql stable security definer set search_path = '' as
$$ select exists (select 1 from public.payment_settings where enabled and coalesce(upi_id, '') <> '') $$;

create function public.can_see_audience(p_aud text) returns boolean language sql stable security definer set search_path = '' as
$$
 select public.is_admin()
     or p_aud = 'all'
     or (p_aud = 'organic' and public.source_of() = 'organic')
     or (p_aud = 'ads' and public.has_ads_access())
$$;

create function public.can_full_premium() returns boolean language sql stable security definer set search_path = '' as
$$
 select public.is_admin()
     or case when (select free_mode from public.app_mode where id = 1)
          then public.has_ads_access() else public.has_plan() end
$$;

create function public.can_manage_channel(p_channel uuid) returns boolean language sql stable security definer set search_path = '' as
$$
 select public.is_owner()
     or exists (select 1 from public.admin_channel_access a where a.user_id = auth.uid() and a.channel_id = p_channel)
$$;

create function public.can_post_to_channel(p_channel uuid) returns boolean language sql stable security definer set search_path = '' as
$$
 select public.can_manage_channel(p_channel)
     or (public.is_member() and exists (
          select 1 from public.channels c
          where c.id = p_channel and c.created_by = auth.uid()
            and c.review_status = 'approved' and c.status in ('published','active')))
$$;

create function public.can_edit_post(p_post uuid) returns boolean language sql stable security definer set search_path = '' as
$$
 select exists (select 1 from public.posts p where p.id = p_post
        and (public.can_manage_channel(p.channel_id)
             or (p.created_by = auth.uid() and public.can_post_to_channel(p.channel_id))))
$$;

create function public.has_consent() returns boolean language sql stable security definer set search_path = '' as
$$ select exists (select 1 from public.consents where user_id = auth.uid()) $$;

create function public.can_write_channel_path(p_name text) returns boolean language plpgsql stable security definer set search_path = '' as
$$
declare seg text := split_part(p_name, '/', 1);
begin
  if seg !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
  return public.can_post_to_channel(seg::uuid);
end $$;

-- ============ RPCs ============
create function public.record_install(p_install_id text, p_referrer_status text, p_raw_referrer text, p_install_secret text)
returns text language plpgsql security definer set search_path = '' as
$$
declare uid uuid := auth.uid(); norm text; src text; camp text; existing text;
begin
  if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if p_install_id is null or length(p_install_id) not between 8 and 100 then raise exception 'invalid install id'; end if;
  select source into existing from private.user_sources where user_id = uid;
  if existing is not null then return existing; end if;
  norm := replace(replace(lower(coalesce(p_raw_referrer, '')), '%3d', '='), '%26', '&');
  if norm ~ '(^|[&?])utm_source=(meta|facebook|instagram|ig)(&|$)' then src := 'ads'; else src := 'organic'; end if;
  camp := substring(norm from 'utm_campaign=([^&]+)');
  insert into public.installs (install_id, user_id, source, referrer_status, raw_referrer, utm_campaign, install_secret)
  values (p_install_id, uid, src, left(p_referrer_status, 100), left(p_raw_referrer, 1000), left(camp, 200), left(p_install_secret, 200))
  on conflict (install_id) do nothing;
  insert into private.user_sources (user_id, source) values (uid, src) on conflict (user_id) do nothing;
  return src;
end $$;

create function public.my_status() returns jsonb language plpgsql stable security definer set search_path = '' as
$$
declare
  uid uuid := auth.uid();
  pr public.profiles%rowtype;
  am public.app_mode%rowtype;
  v_plan text; v_ends timestamptz; src text; pb boolean;
begin
  if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select * into pr from public.profiles where id = uid;
  select * into am from public.app_mode where id = 1;
  select plan_name, ends_at into v_plan, v_ends from public.subscriptions
    where user_id = uid and not revoked and ends_at > now() order by ends_at desc limit 1;
  src := public.source_of(uid);
  select play_billing_enabled into pb from public.play_settings where id = 1;
  return jsonb_build_object(
    'user_id', uid,
    'is_guest', coalesce(pr.is_guest, true),
    'is_admin', public.is_admin(),
    'source', src,
    'has_ads_access', public.has_ads_access(uid),
    'is_premium', public.has_plan(uid),
    'can_play_premium', public.can_full_premium(),
    'plan_name', v_plan,
    'plan_ends_at', v_ends,
    'used_bytes', coalesce(pr.used_bytes, 0),
    'quota_bytes', public.quota_bytes(uid),
    'free_mode', am.free_mode,
    'paid_enabled', not am.free_mode,
    'access_status', case when src = 'ads' then 'approved' else coalesce(pr.ads_access_status, 'none') end,
    'payments_available', (not am.free_mode) and public.payments_available(),
    'free_plans_for', am.free_plans_for,
    'plans_visible', (not am.free_mode) and public.plans_visible_for_me(),
    'play_verified', coalesce(pr.play_verified, false),
    'play_billing_enabled', coalesce(pb, false)
  );
end $$;

create function public.request_full_access() returns text language plpgsql security definer set search_path = '' as
$$
declare uid uuid := auth.uid(); st text;
begin
  if not public.is_member() then raise exception 'login required' using errcode = '42501'; end if;
  if public.source_of(uid) <> 'organic' then raise exception 'not needed for this account'; end if;
  if not (select free_mode from public.app_mode where id = 1) then raise exception 'only available in free mode'; end if;
  update public.profiles set ads_access_status = 'pending' where id = uid and ads_access_status in ('none','rejected');
  select ads_access_status into st from public.profiles where id = uid;
  return st;
end $$;

create function public.set_ads_access(p_user uuid, p_status text) returns void language plpgsql security definer set search_path = '' as
$$
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_status not in ('none','pending','approved','rejected') then raise exception 'invalid status'; end if;
  update public.profiles set ads_access_status = p_status where id = p_user;
  if not found then raise exception 'user not found'; end if;
end $$;

create function public.grant_premium(p_user uuid, p_plan uuid) returns timestamptz language plpgsql security definer set search_path = '' as
$$
declare pl public.plans%rowtype; base timestamptz; new_end timestamptz;
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into pl from public.plans where id = p_plan;
  if not found then raise exception 'plan not found'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'user not found'; end if;
  select greatest(now(), coalesce(max(ends_at), now())) into base
    from public.subscriptions where user_id = p_user and not revoked and ends_at > now();
  new_end := base + make_interval(days => pl.duration_days);
  insert into public.subscriptions (user_id, plan_id, plan_code, plan_name, kind, starts_at, ends_at)
  values (p_user, pl.id, pl.code, pl.name, 'admin_grant', now(), new_end);
  return new_end;
end $$;

create function public.revoke_subscription(p_sub uuid) returns void language plpgsql security definer set search_path = '' as
$$
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  update public.subscriptions set revoked = true where id = p_sub;
  if not found then raise exception 'subscription not found'; end if;
end $$;

create function public.review_channel(p_channel uuid, p_approve boolean, p_audience text default null) returns void
language plpgsql security definer set search_path = '' as
$$
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_approve then
    if p_audience is null or p_audience not in ('all','organic','ads') then raise exception 'audience required'; end if;
    update public.channels set review_status = 'approved', status = 'published', audience = p_audience where id = p_channel;
  else
    update public.channels set review_status = 'rejected' where id = p_channel;
  end if;
  if not found then raise exception 'channel not found'; end if;
end $$;

create function public.set_content_hidden(p_type text, p_id uuid, p_hidden boolean) returns void
language plpgsql security definer set search_path = '' as
$$
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_type = 'post' then update public.posts set hidden = p_hidden where id = p_id;
  elsif p_type = 'channel' then update public.channels set hidden = p_hidden where id = p_id;
  else raise exception 'invalid type'; end if;
end $$;

create function public.report_content(p_target_type text, p_target_id uuid, p_reason text, p_details text default null) returns uuid
language plpgsql security definer set search_path = '' as
$$
declare uid uuid := auth.uid(); rid uuid;
begin
  if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if p_target_type not in ('post','channel') then raise exception 'invalid target'; end if;
  if p_reason not in ('Sexual/nude','Violence','Hate/harassment','Copyright','Spam/scam','Other') then raise exception 'invalid reason'; end if;
  if p_target_type = 'post' and not exists (select 1 from public.posts where id = p_target_id) then raise exception 'not found'; end if;
  if p_target_type = 'channel' and not exists (select 1 from public.channels where id = p_target_id) then raise exception 'not found'; end if;
  if (select count(*) from public.support_requests where user_id = uid and kind = 'report' and created_at > now() - interval '1 day') >= 20 then
    raise exception 'too many reports';
  end if;
  insert into public.support_requests (user_id, kind, target_type, target_id, reason, details)
  values (uid, 'report', p_target_type, p_target_id, p_reason, left(p_details, 2000)) returning id into rid;
  return rid;
end $$;

create function public.accept_consent(p_policy text) returns void language plpgsql security definer set search_path = '' as
$$
begin
  if not public.is_member() then raise exception 'login required' using errcode = '42501'; end if;
  insert into public.consents (user_id, policy_version) values (auth.uid(), left(p_policy, 50)) on conflict do nothing;
end $$;

-- ============ trigger functions (private) ============
create function private.touch_updated_at() returns trigger language plpgsql set search_path = '' as
$$ begin new.updated_at := now(); return new; end $$;

create function private.lock_plan_code() returns trigger language plpgsql set search_path = '' as
$$ begin if new.code is distinct from old.code then raise exception 'plan code cannot be changed'; end if; return new; end $$;

create function private.bump_catalog() returns trigger language plpgsql security definer set search_path = '' as
$$ begin update public.plan_catalog set revision = revision + 1, updated_at = now() where id = 1; return null; end $$;

create function private.promo_counter() returns trigger language plpgsql set search_path = '' as
$$
begin
  if old.free_plans_for = 'none' and new.free_plans_for <> 'none' then new.promo_id := old.promo_id + 1; end if;
  return new;
end $$;

create function private.user_sources_immutable() returns trigger language plpgsql set search_path = '' as
$$
begin
  if tg_op = 'UPDATE' then raise exception 'user source is immutable' using errcode = '42501'; end if;
  if tg_op = 'DELETE' and pg_trigger_depth() < 2 then raise exception 'user source is immutable' using errcode = '42501'; end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;

create function private.maybe_make_owner(p_id uuid, p_email text, p_confirmed timestamptz, p_anon boolean) returns void
language plpgsql security definer set search_path = '' as
$$
begin
  if p_confirmed is not null and not coalesce(p_anon, false) and p_email is not null
     and exists (select 1 from private.owner_bootstrap where lower(email) = lower(p_email)) then
    insert into public.admins (user_id, role) values (p_id, 'owner') on conflict (user_id) do nothing;
  end if;
end $$;

create function private.handle_new_user() returns trigger language plpgsql security definer set search_path = '' as
$$
begin
  insert into public.profiles (id, is_guest, display_name)
  values (new.id, coalesce(new.is_anonymous, false), nullif(split_part(coalesce(new.email, ''), '@', 1), ''))
  on conflict (id) do nothing;
  perform private.maybe_make_owner(new.id, new.email, new.email_confirmed_at, new.is_anonymous);
  return new;
end $$;

create function private.handle_user_updated() returns trigger language plpgsql security definer set search_path = '' as
$$
begin
  update public.profiles
     set is_guest = coalesce(new.is_anonymous, false),
         display_name = coalesce(display_name, nullif(split_part(coalesce(new.email, ''), '@', 1), ''))
   where id = new.id;
  perform private.maybe_make_owner(new.id, new.email, new.email_confirmed_at, new.is_anonymous);
  return new;
end $$;

create function private.guard_profiles() returns trigger language plpgsql set search_path = '' as
$$
begin
  if current_user in ('authenticated','anon') then
    if new.id is distinct from old.id or new.is_guest is distinct from old.is_guest
       or new.used_bytes is distinct from old.used_bytes
       or new.ads_access_status is distinct from old.ads_access_status
       or new.play_verified is distinct from old.play_verified
       or new.created_at is distinct from old.created_at then
      raise exception 'protected profile fields' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

create function private.guard_channels() returns trigger language plpgsql set search_path = '' as
$$
begin
  if tg_op = 'INSERT' then
    if current_user in ('authenticated','anon') then
      if public.is_owner() then
        new.review_status := 'approved';
        new.created_by := coalesce(new.created_by, auth.uid());
        new.members_count := 0;
      else
        new.created_by := auth.uid(); new.review_status := 'pending'; new.status := 'draft';
        new.members_count := 0; new.hidden := false; new.audience := 'all';
      end if;
    end if;
    return new;
  end if;
  if current_user in ('authenticated','anon') and not public.is_owner() then
    if new.created_by is distinct from old.created_by or new.review_status is distinct from old.review_status
       or new.members_count is distinct from old.members_count or new.hidden is distinct from old.hidden then
      raise exception 'protected channel fields' using errcode = '42501';
    end if;
    if not public.can_manage_channel(old.id) then
      if new.audience is distinct from old.audience or new.status is distinct from old.status then
        raise exception 'protected channel fields' using errcode = '42501';
      end if;
      if new.name is distinct from old.name or new.description is distinct from old.description
         or new.category is distinct from old.category or new.tags is distinct from old.tags
         or new.icon_url is distinct from old.icon_url then
        new.review_status := 'pending';
      end if;
    end if;
  end if;
  return new;
end $$;

create function private.guard_posts() returns trigger language plpgsql set search_path = '' as
$$
declare ch_aud text;
begin
  if current_user not in ('authenticated','anon') then return new; end if;
  if tg_op = 'INSERT' then
    if public.can_manage_channel(new.channel_id) then
      new.created_by := coalesce(new.created_by, auth.uid());
    else
      select audience into ch_aud from public.channels where id = new.channel_id;
      new.created_by := auth.uid(); new.hidden := false; new.audience := coalesce(ch_aud, 'all');
    end if;
    return new;
  end if;
  if new.channel_id is distinct from old.channel_id or new.created_by is distinct from old.created_by then
    raise exception 'protected post fields' using errcode = '42501';
  end if;
  if not public.is_owner() then
    if new.hidden is distinct from old.hidden then raise exception 'protected post fields' using errcode = '42501'; end if;
    if not public.can_manage_channel(old.channel_id) and new.audience is distinct from old.audience then
      raise exception 'protected post fields' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

create function private.sync_members_count() returns trigger language plpgsql security definer set search_path = '' as
$$
declare cid uuid := coalesce(new.channel_id, old.channel_id);
begin
  update public.channels set members_count = (select count(*) from public.channel_members where channel_id = cid) where id = cid;
  return null;
end $$;

create function private.sync_used_bytes() returns trigger language plpgsql security definer set search_path = '' as
$$
begin
  if tg_op = 'INSERT' then
    update public.profiles set used_bytes = used_bytes + new.size_bytes where id = new.user_id;
  elsif tg_op = 'DELETE' then
    update public.profiles set used_bytes = greatest(0, used_bytes - old.size_bytes) where id = old.user_id;
  else
    update public.profiles set used_bytes = greatest(0, used_bytes + new.size_bytes - old.size_bytes) where id = new.user_id;
  end if;
  return null;
end $$;

create function private.protect_last_owner() returns trigger language plpgsql security definer set search_path = '' as
$$
begin
  if (tg_op = 'DELETE' and old.role = 'owner') or (tg_op = 'UPDATE' and old.role = 'owner' and new.role <> 'owner') then
    if not exists (select 1 from public.admins where role = 'owner' and user_id <> old.user_id) then
      raise exception 'cannot remove the last owner';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;

-- ============ triggers ============
create trigger plans_touch before update on public.plans for each row execute function private.touch_updated_at();
create trigger plans_lock_code before update on public.plans for each row execute function private.lock_plan_code();
create trigger payment_settings_touch before update on public.payment_settings for each row execute function private.touch_updated_at();
create trigger app_mode_touch before update on public.app_mode for each row execute function private.touch_updated_at();
create trigger app_mode_promo before update on public.app_mode for each row execute function private.promo_counter();
create trigger play_settings_touch before update on public.play_settings for each row execute function private.touch_updated_at();

create trigger plans_bump after insert or update or delete on public.plans for each statement execute function private.bump_catalog();
create trigger app_mode_bump after update on public.app_mode for each statement execute function private.bump_catalog();
create trigger payment_settings_bump after update on public.payment_settings for each statement execute function private.bump_catalog();

create trigger user_sources_immutable before update or delete on private.user_sources for each row execute function private.user_sources_immutable();
create trigger profiles_guard before update on public.profiles for each row execute function private.guard_profiles();
create trigger channels_guard before insert or update on public.channels for each row execute function private.guard_channels();
create trigger posts_guard before insert or update on public.posts for each row execute function private.guard_posts();
create trigger members_count_sync after insert or delete on public.channel_members for each row execute function private.sync_members_count();
create trigger cloud_files_used after insert or delete or update of size_bytes on public.cloud_files for each row execute function private.sync_used_bytes();
create trigger admins_last_owner before update or delete on public.admins for each row execute function private.protect_last_owner();

create trigger on_auth_user_created after insert on auth.users for each row execute function private.handle_new_user();
create trigger on_auth_user_updated after update of is_anonymous, email, email_confirmed_at on auth.users for each row execute function private.handle_user_updated();

-- ============ grants: functions callable only by signed-in users ============
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prokind = 'f' loop
    execute format('revoke execute on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated, service_role', r.sig);
  end loop;
end $$;
alter default privileges in schema public revoke execute on functions from public, anon;


-- SOURCE v1.0.9: 20261109000003_0003_rls_storage_realtime.sql

alter table public.app_mode enable row level security;
alter table public.plan_catalog enable row level security;
alter table public.plans enable row level security;
alter table public.payment_settings enable row level security;
alter table public.play_settings enable row level security;
alter table public.profiles enable row level security;
alter table public.admins enable row level security;
alter table public.admin_channel_access enable row level security;
alter table public.consents enable row level security;
alter table public.installs enable row level security;
alter table public.ad_clicks enable row level security;
alter table public.channels enable row level security;
alter table public.channel_members enable row level security;
alter table public.channel_folders enable row level security;
alter table public.posts enable row level security;
alter table public.post_items enable row level security;
alter table public.blocked_channels enable row level security;
alter table public.support_requests enable row level security;
alter table public.cloud_folders enable row level security;
alter table public.cloud_files enable row level security;
alter table public.subscriptions enable row level security;

-- config
create policy app_mode_read on public.app_mode for select to anon, authenticated using (true);
create policy app_mode_owner_update on public.app_mode for update to authenticated using ((select public.is_owner())) with check ((select public.is_owner()));
create policy plan_catalog_read on public.plan_catalog for select to anon, authenticated using (true);
create policy plans_read on public.plans for select to anon, authenticated using (active or (select public.is_admin()));
create policy plans_owner_insert on public.plans for insert to authenticated with check ((select public.is_owner()));
create policy plans_owner_update on public.plans for update to authenticated using ((select public.is_owner())) with check ((select public.is_owner()));
create policy payment_settings_owner_read on public.payment_settings for select to authenticated using ((select public.is_owner()));
create policy payment_settings_owner_update on public.payment_settings for update to authenticated using ((select public.is_owner())) with check ((select public.is_owner()));
create policy play_settings_owner_read on public.play_settings for select to authenticated using ((select public.is_owner()));
create policy play_settings_owner_update on public.play_settings for update to authenticated using ((select public.is_owner())) with check ((select public.is_owner()));

-- accounts
create policy profiles_read on public.profiles for select to authenticated using (id = (select auth.uid()) or (select public.is_admin()));
create policy profiles_update_own on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy admins_read on public.admins for select to authenticated using (user_id = (select auth.uid()) or (select public.is_owner()));
create policy admins_owner_write on public.admins for all to authenticated using ((select public.is_owner())) with check ((select public.is_owner()));
create policy admin_access_read on public.admin_channel_access for select to authenticated using (user_id = (select auth.uid()) or (select public.is_owner()));
create policy admin_access_owner_write on public.admin_channel_access for all to authenticated using ((select public.is_owner())) with check ((select public.is_owner()));
create policy consents_read on public.consents for select to authenticated using (user_id = (select auth.uid()));
create policy consents_insert on public.consents for insert to authenticated with check (user_id = (select auth.uid()) and (select public.is_member()));
create policy subscriptions_read on public.subscriptions for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));

-- channels
create policy channels_select on public.channels for select to authenticated using (
  (select public.is_admin())
  or created_by = (select auth.uid())
  or (review_status = 'approved' and not hidden and status in ('published','active') and (select public.can_see_audience(audience)))
);
create policy channels_insert on public.channels for insert to authenticated with check (
  (select public.is_owner()) or ((select public.is_member()) and created_by = (select auth.uid()))
);
create policy channels_update on public.channels for update to authenticated
  using ((select public.can_manage_channel(id)) or created_by = (select auth.uid()))
  with check ((select public.can_manage_channel(id)) or created_by = (select auth.uid()));
create policy channels_delete on public.channels for delete to authenticated using ((select public.is_owner()));

create policy channel_members_select on public.channel_members for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy channel_members_insert on public.channel_members for insert to authenticated with check (
  user_id = (select auth.uid()) and (select public.is_member()) and exists (select 1 from public.channels c where c.id = channel_id)
);
create policy channel_members_delete on public.channel_members for delete to authenticated using (user_id = (select auth.uid()));

create policy channel_folders_select on public.channel_folders for select to authenticated using (exists (select 1 from public.channels c where c.id = channel_id));
create policy channel_folders_write on public.channel_folders for all to authenticated
  using ((select public.can_manage_channel(channel_id))) with check ((select public.can_manage_channel(channel_id)));

create policy posts_select on public.posts for select to authenticated using (
  (select public.is_admin())
  or created_by = (select auth.uid())
  or (not hidden
      and (status = 'published' or (status = 'scheduled' and publish_at <= now()))
      and (select public.can_see_audience(audience))
      and exists (select 1 from public.channels c where c.id = posts.channel_id))
);
create policy posts_insert on public.posts for insert to authenticated with check (
  (select public.can_post_to_channel(channel_id))
  and ((select public.can_manage_channel(channel_id)) or (select public.has_consent()))
);
create policy posts_update on public.posts for update to authenticated
  using ((select public.can_edit_post(id))) with check ((select public.can_post_to_channel(channel_id)));
create policy posts_delete on public.posts for delete to authenticated using ((select public.can_edit_post(id)));

create policy post_items_select on public.post_items for select to authenticated using (exists (select 1 from public.posts p where p.id = post_items.post_id));
create policy post_items_write on public.post_items for all to authenticated
  using ((select public.can_edit_post(post_id))) with check ((select public.can_edit_post(post_id)));

create policy blocked_own on public.blocked_channels for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy support_owner_read on public.support_requests for select to authenticated using ((select public.is_owner()));
create policy support_owner_update on public.support_requests for update to authenticated using ((select public.is_owner())) with check ((select public.is_owner()));

-- personal cloud
create policy cloud_folders_own on public.cloud_folders for all to authenticated
  using (user_id = (select auth.uid()) and (select public.is_member()))
  with check (user_id = (select auth.uid()) and (select public.is_member()));
create policy cloud_files_select on public.cloud_files for select to authenticated using (user_id = (select auth.uid()));
create policy cloud_files_insert on public.cloud_files for insert to authenticated with check (
  user_id = (select auth.uid()) and (select public.is_member())
  and (coalesce((select used_bytes from public.profiles where id = (select auth.uid())), 0) + size_bytes) <= (select public.quota_bytes())
);
create policy cloud_files_update on public.cloud_files for update to authenticated
  using (user_id = (select auth.uid()) and (select public.is_member()))
  with check (user_id = (select auth.uid()) and size_bytes = (select f.size_bytes from public.cloud_files f where f.id = cloud_files.id));
create policy cloud_files_delete on public.cloud_files for delete to authenticated using (user_id = (select auth.uid()));

-- ============ storage ============
insert into storage.buckets (id, name, public) values
  ('media','media',false), ('cloud','cloud',false), ('avatars','avatars',false),
  ('channel-icons','channel-icons',false), ('downloads','downloads',true)
on conflict (id) do nothing;

create policy media_select on storage.objects for select to authenticated using (
  bucket_id = 'media' and (
    (select public.is_admin())
    or exists (select 1 from public.post_items i
               where i.thumbnail_key = name or i.trailer_key = name
                  or (i.media_key = name and (not i.is_premium or (select public.can_full_premium()))))
  )
);
create policy media_insert on storage.objects for insert to authenticated with check (bucket_id = 'media' and (select public.can_write_channel_path(name)));
create policy media_update on storage.objects for update to authenticated using (bucket_id = 'media' and (select public.can_write_channel_path(name)));
create policy media_delete on storage.objects for delete to authenticated using (bucket_id = 'media' and (select public.can_write_channel_path(name)));

create policy icons_select on storage.objects for select to authenticated using (
  bucket_id = 'channel-icons' and ((select public.is_admin()) or (select public.can_write_channel_path(name))
    or exists (select 1 from public.channels c where c.icon_url = name))
);
create policy icons_insert on storage.objects for insert to authenticated with check (bucket_id = 'channel-icons' and (select public.can_write_channel_path(name)));
create policy icons_update on storage.objects for update to authenticated using (bucket_id = 'channel-icons' and (select public.can_write_channel_path(name)));
create policy icons_delete on storage.objects for delete to authenticated using (bucket_id = 'channel-icons' and (select public.can_write_channel_path(name)));

create policy cloud_obj_select on storage.objects for select to authenticated using (
  bucket_id = 'cloud' and (storage.foldername(name))[1] = (select auth.uid())::text and (select public.is_member()));
create policy cloud_obj_insert on storage.objects for insert to authenticated with check (
  bucket_id = 'cloud' and (storage.foldername(name))[1] = (select auth.uid())::text and (select public.is_member())
  and exists (select 1 from public.cloud_files f where f.user_id = (select auth.uid()) and f.storage_path = name));
create policy cloud_obj_update on storage.objects for update to authenticated using (
  bucket_id = 'cloud' and (storage.foldername(name))[1] = (select auth.uid())::text and (select public.is_member()));
create policy cloud_obj_delete on storage.objects for delete to authenticated using (
  bucket_id = 'cloud' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy avatars_own on storage.objects for all to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy downloads_owner_write on storage.objects for all to authenticated
  using (bucket_id = 'downloads' and (select public.is_owner()))
  with check (bucket_id = 'downloads' and (select public.is_owner()));

-- ============ realtime ============
alter publication supabase_realtime add table public.app_mode, public.plans, public.plan_catalog, public.profiles;


-- SOURCE v1.0.9: 20261109000004_0004_hide_uid_param_helpers.sql

alter function public.source_of(uuid) set schema private;
alter function public.has_plan(uuid) set schema private;
alter function public.has_ads_access(uuid) set schema private;
alter function public.quota_bytes(uuid) set schema private;

create or replace function private.has_ads_access(p_uid uuid default null) returns boolean language sql stable security definer set search_path = '' as
$$
 select case
   when p_uid is null then false
   when exists (select 1 from public.admins where user_id = p_uid) then true
   when private.source_of(p_uid) = 'ads' then true
   else coalesce((select ads_access_status = 'approved' from public.profiles where id = p_uid), false)
        and ((select free_mode from public.app_mode where id = 1) or private.has_plan(p_uid))
 end
$$;

create or replace function private.quota_bytes(p_uid uuid default null) returns bigint language sql stable security definer set search_path = '' as
$$
 select case
   when p_uid is null then 0::bigint
   when coalesce((select is_guest from public.profiles where id = p_uid), true) then 0::bigint
   when private.has_plan(p_uid) then 2199023255552::bigint
   when (select free_mode from public.app_mode where id = 1)
        or coalesce((select play_verified from public.profiles where id = p_uid), false) then 16106127360::bigint
   else 0::bigint
 end
$$;

create function public.source_of() returns text language sql stable security definer set search_path = '' as $$ select private.source_of(auth.uid()) $$;
create function public.has_plan() returns boolean language sql stable security definer set search_path = '' as $$ select private.has_plan(auth.uid()) $$;
create function public.has_ads_access() returns boolean language sql stable security definer set search_path = '' as $$ select private.has_ads_access(auth.uid()) $$;
create function public.quota_bytes() returns bigint language sql stable security definer set search_path = '' as $$ select private.quota_bytes(auth.uid()) $$;

create or replace function public.my_status() returns jsonb language plpgsql stable security definer set search_path = '' as
$$
declare
  uid uuid := auth.uid();
  pr public.profiles%rowtype;
  am public.app_mode%rowtype;
  v_plan text; v_ends timestamptz; src text; pb boolean;
begin
  if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select * into pr from public.profiles where id = uid;
  select * into am from public.app_mode where id = 1;
  select plan_name, ends_at into v_plan, v_ends from public.subscriptions
    where user_id = uid and not revoked and ends_at > now() order by ends_at desc limit 1;
  src := private.source_of(uid);
  select play_billing_enabled into pb from public.play_settings where id = 1;
  return jsonb_build_object(
    'user_id', uid,
    'is_guest', coalesce(pr.is_guest, true),
    'is_admin', public.is_admin(),
    'source', src,
    'has_ads_access', private.has_ads_access(uid),
    'is_premium', private.has_plan(uid),
    'can_play_premium', public.can_full_premium(),
    'plan_name', v_plan,
    'plan_ends_at', v_ends,
    'used_bytes', coalesce(pr.used_bytes, 0),
    'quota_bytes', private.quota_bytes(uid),
    'free_mode', am.free_mode,
    'paid_enabled', not am.free_mode,
    'access_status', case when src = 'ads' then 'approved' else coalesce(pr.ads_access_status, 'none') end,
    'payments_available', (not am.free_mode) and public.payments_available(),
    'free_plans_for', am.free_plans_for,
    'plans_visible', (not am.free_mode) and public.plans_visible_for_me(),
    'play_verified', coalesce(pr.play_verified, false),
    'play_billing_enabled', coalesce(pb, false)
  );
end $$;

create or replace function public.request_full_access() returns text language plpgsql security definer set search_path = '' as
$$
declare uid uuid := auth.uid(); st text;
begin
  if not public.is_member() then raise exception 'login required' using errcode = '42501'; end if;
  if private.source_of(uid) <> 'organic' then raise exception 'not needed for this account'; end if;
  if not (select free_mode from public.app_mode where id = 1) then raise exception 'only available in free mode'; end if;
  update public.profiles set ads_access_status = 'pending' where id = uid and ads_access_status in ('none','rejected');
  select ads_access_status into st from public.profiles where id = uid;
  return st;
end $$;

revoke execute on function public.source_of(), public.has_plan(), public.has_ads_access(), public.quota_bytes() from public, anon;
grant execute on function public.source_of(), public.has_plan(), public.has_ads_access(), public.quota_bytes() to authenticated, service_role;

do $$ begin
  revoke execute on function public.rls_auto_enable() from authenticated, anon, public;
exception when others then raise notice 'rls_auto_enable not changed: %', sqlerrm;
end $$;


-- SOURCE v1.0.9: 20261109000005_0005_fix_cloud_insert_policy.sql

drop policy cloud_files_insert on public.cloud_files;
create policy cloud_files_insert on public.cloud_files for insert to authenticated with check (
  user_id = (select auth.uid()) and (select public.is_member())
  and (coalesce((select used_bytes from public.profiles where id = (select auth.uid())), 0) + size_bytes) <= (select public.quota_bytes())
);


-- SOURCE v1.0.9: 20261109000006_0006_payments_core.sql

alter table public.payment_settings drop constraint if exists payment_settings_upi_id_check;
alter table public.payment_settings add constraint payment_settings_upi_id_check
  check (upi_id = '' or upi_id ~ '^[A-Za-z0-9._-]{2,100}@[A-Za-z0-9]{2,64}$');

create table public.payment_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid not null references public.plans(id),
  plan_code text, plan_name text,
  amount_paise bigint not null default 0 check (amount_paise >= 0),
  duration_days integer not null default 0,
  reference text unique,
  upi_id_used text, payee_used text,
  status text not null default 'pending' check (status in ('pending','submitted','review','paid','failed','cancelled','rejected','revoked')),
  raw_result text, txn_id text, approval_ref text, utr text,
  success_reported boolean not null default false,
  reported_at timestamptz, activated_at timestamptz,
  activation_kind text check (activation_kind in ('auto','manual','webhook')),
  bank_verified boolean not null default false, bank_verified_at timestamptz,
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index payment_orders_user_idx on public.payment_orders (user_id, created_at desc);
create index payment_orders_status_idx on public.payment_orders (status, created_at desc);
create index payment_orders_plan_idx on public.payment_orders (plan_id);

alter table public.subscriptions add constraint subscriptions_order_fk foreign key (order_id) references public.payment_orders(id);

create table private.used_payment_utrs (
  txn_id text primary key,
  order_id uuid,
  created_at timestamptz not null default now()
);

create table public.free_plan_claims (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id uuid not null references public.plans(id),
  promo_id integer not null,
  subscription_id uuid references public.subscriptions(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (user_id, plan_id, promo_id)
);
create index free_plan_claims_plan_idx on public.free_plan_claims (plan_id);
create index free_plan_claims_sub_idx on public.free_plan_claims (subscription_id);

create table public.settings_audit (
  id bigint generated always as identity primary key,
  table_name text not null, row_key text, field text not null,
  old_value text, new_value text,
  changed_by uuid, changed_at timestamptz not null default now()
);
create index settings_audit_time_idx on public.settings_audit (changed_at desc);

create table public.meta_settings (
  id int primary key default 1 check (id = 1),
  pixel_id text not null default '',
  capi_token text not null default '',
  test_event_code text not null default '',
  enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
insert into public.meta_settings (id) values (1);

create table public.meta_events (
  id bigint generated always as identity primary key,
  event_name text not null check (event_name in ('Lead','CompleteRegistration','Purchase')),
  event_id text not null unique,
  user_id uuid references auth.users(id) on delete set null,
  order_id uuid,
  value_inr numeric,
  status text not null default 'pending' check (status in ('pending','sent','failed')),
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
create index meta_events_status_idx on public.meta_events (status, created_at);
create index meta_events_user_idx on public.meta_events (user_id);

alter table public.payment_orders enable row level security;
alter table public.free_plan_claims enable row level security;
alter table public.settings_audit enable row level security;
alter table public.meta_settings enable row level security;
alter table public.meta_events enable row level security;

create policy orders_read on public.payment_orders for select to authenticated using (user_id = (select auth.uid()) or (select public.is_owner()));
create policy claims_owner_read on public.free_plan_claims for select to authenticated using ((select public.is_owner()));
create policy audit_owner_read on public.settings_audit for select to authenticated using ((select public.is_owner()));
create policy meta_settings_owner on public.meta_settings for all to authenticated using ((select public.is_owner())) with check ((select public.is_owner()));
create policy meta_events_owner_read on public.meta_events for select to authenticated using ((select public.is_owner()));

create function private.upi_param(p_raw text, p_key text) returns text language sql immutable set search_path = '' as
$$ select substring(coalesce(p_raw,'') from '(?i)(?:^|[?&;,\s])' || p_key || '=([^&;,\s]*)') $$;

create function private.enqueue_meta(p_event text, p_user uuid, p_order uuid, p_value numeric) returns void
language plpgsql security definer set search_path = '' as
$$
begin
  if not exists (select 1 from public.meta_settings where enabled and pixel_id <> '' and capi_token <> '') then return; end if;
  insert into public.meta_events (event_name, event_id, user_id, order_id, value_inr)
  values (p_event,
          case p_event when 'Purchase' then 'purchase-' || p_order::text when 'Lead' then 'lead-' || p_user::text else 'reg-' || p_user::text end,
          p_user, p_order, p_value)
  on conflict (event_id) do nothing;
end $$;

create function private.order_json(p_order uuid) returns jsonb language sql stable security definer set search_path = '' as
$$
 select jsonb_build_object(
   'order_id', o.id, 'status', o.status, 'reference', o.reference, 'plan_name', o.plan_name,
   'amount_paise', o.amount_paise, 'amount_inr', o.amount_paise / 100,
   'txn_id', o.txn_id, 'activated_at', o.activated_at,
   'ends_at', (select s.ends_at from public.subscriptions s where s.order_id = o.id))
 from public.payment_orders o where o.id = p_order
$$;

create function private.activate_order(p_order uuid, p_kind text) returns void
language plpgsql security definer set search_path = '' as
$$
declare o public.payment_orders%rowtype; base timestamptz; new_end timestamptz;
begin
  select * into o from public.payment_orders where id = p_order for update;
  if not found then raise exception 'order not found'; end if;
  if exists (select 1 from public.subscriptions where order_id = o.id) then
    update public.payment_orders set status = 'paid', updated_at = now() where id = o.id and status <> 'paid';
    return;
  end if;
  select greatest(now(), coalesce(max(ends_at), now())) into base
    from public.subscriptions where user_id = o.user_id and not revoked and ends_at > now();
  new_end := base + make_interval(days => o.duration_days);
  insert into public.subscriptions (user_id, plan_id, plan_code, plan_name, kind, order_id, starts_at, ends_at)
  values (o.user_id, o.plan_id, o.plan_code, o.plan_name, 'payment', o.id, base, new_end);
  update public.payment_orders set status = 'paid', activated_at = now(), activation_kind = p_kind, updated_at = now() where id = o.id;
  if private.source_of(o.user_id) = 'organic' then
    update public.profiles set ads_access_status = 'pending' where id = o.user_id and ads_access_status in ('none','rejected');
  end if;
  perform private.enqueue_meta('Purchase', o.user_id, o.id, o.amount_paise / 100.0);
end $$;

create function private.order_snapshot() returns trigger language plpgsql security definer set search_path = '' as
$$
declare pl public.plans%rowtype; ps public.payment_settings%rowtype;
begin
  select * into pl from public.plans where id = new.plan_id;
  if not found then raise exception 'plan not found'; end if;
  select * into ps from public.payment_settings where id = 1;
  new.plan_code := pl.code; new.plan_name := pl.name;
  new.amount_paise := pl.price_inr::bigint * 100;
  new.duration_days := pl.duration_days;
  new.upi_id_used := ps.upi_id; new.payee_used := ps.payee_name;
  new.reference := 'OB' || to_char(now() at time zone 'Asia/Kolkata', 'YYMMDD') || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  new.status := 'pending'; new.success_reported := false; new.raw_result := null;
  new.txn_id := null; new.utr := null; new.activated_at := null; new.activation_kind := null;
  return new;
end $$;
create trigger payment_orders_snapshot before insert on public.payment_orders for each row execute function private.order_snapshot();
create trigger payment_orders_touch before update on public.payment_orders for each row execute function private.touch_updated_at();

create function private.audit_changes() returns trigger language plpgsql security definer set search_path = '' as
$$
declare k text; o jsonb; n jsonb; rk text;
begin
  n := to_jsonb(new);
  rk := coalesce(n ->> 'code', n ->> 'id');
  if tg_op = 'INSERT' then
    insert into public.settings_audit (table_name, row_key, field, old_value, new_value, changed_by)
    values (tg_table_name, rk, 'created', null, coalesce(n ->> 'name', rk), auth.uid());
    return new;
  end if;
  o := to_jsonb(old);
  for k in select jsonb_object_keys(n) loop
    if k = 'updated_at' then continue; end if;
    if (o -> k) is distinct from (n -> k) then
      insert into public.settings_audit (table_name, row_key, field, old_value, new_value, changed_by)
      values (tg_table_name, rk, k, o ->> k, n ->> k, auth.uid());
    end if;
  end loop;
  return new;
end $$;
create trigger plans_audit after insert or update on public.plans for each row execute function private.audit_changes();
create trigger payment_settings_audit after update on public.payment_settings for each row execute function private.audit_changes();
create trigger app_mode_audit after update on public.app_mode for each row execute function private.audit_changes();

create function private.registration_event() returns trigger language plpgsql security definer set search_path = '' as
$$
begin
  if (tg_op = 'INSERT' and not new.is_guest) or (tg_op = 'UPDATE' and old.is_guest and not new.is_guest) then
    perform private.enqueue_meta('CompleteRegistration', new.id, null, null);
  end if;
  return new;
end $$;
create trigger profiles_registration after insert or update of is_guest on public.profiles for each row execute function private.registration_event();

create function public.create_order(p_plan uuid) returns jsonb language plpgsql security definer set search_path = '' as
$$
declare uid uuid := auth.uid(); pl public.plans%rowtype; ps public.payment_settings%rowtype; o public.payment_orders%rowtype;
begin
  if not public.is_member() then raise exception 'login required' using errcode = '42501'; end if;
  if (select free_mode from public.app_mode where id = 1) then raise exception 'payments are off in free mode'; end if;
  if not public.plans_visible_for_me() then raise exception 'plans are not available for this account'; end if;
  select * into pl from public.plans where id = p_plan and active;
  if not found then raise exception 'This plan is no longer available.'; end if;
  if public.free_plan_for_me(p_plan) then raise exception 'this plan is free for you'; end if;
  if not public.payments_available() then raise exception 'payments are not available'; end if;
  select * into ps from public.payment_settings where id = 1;

  update public.payment_orders set status = 'cancelled'
   where user_id = uid and status = 'pending' and not success_reported
     and (created_at < now() - interval '2 hours' or plan_id <> p_plan
          or amount_paise <> pl.price_inr::bigint * 100 or coalesce(upi_id_used, '') <> ps.upi_id);

  select * into o from public.payment_orders
   where user_id = uid and plan_id = p_plan and status = 'pending' and not success_reported
   order by created_at desc limit 1;
  if not found then
    insert into public.payment_orders (user_id, plan_id) values (uid, p_plan) returning * into o;
    perform private.enqueue_meta('Lead', uid, o.id, null);
  end if;
  return jsonb_build_object('order_id', o.id, 'reference', o.reference, 'amount_paise', o.amount_paise,
    'amount_inr', o.amount_paise / 100, 'plan_name', o.plan_name, 'status', o.status, 'created_at', o.created_at,
    'upi_id', o.upi_id_used, 'payee_name', o.payee_used);
end $$;

create function public.report_result(p_order uuid, p_raw text) returns jsonb language plpgsql security definer set search_path = '' as
$$
declare uid uuid := auth.uid(); o public.payment_orders%rowtype; raw text := coalesce(p_raw, '');
        st text; txn text; ref text; apr text; mode text; recent int; got boolean;
begin
  select * into o from public.payment_orders where id = p_order and user_id = uid for update;
  if not found then raise exception 'order not found'; end if;
  if o.status not in ('pending','submitted') then return private.order_json(o.id); end if;

  update public.payment_orders set raw_result = left(raw, 4000), reported_at = now() where id = o.id;

  st := upper(coalesce(private.upi_param(raw, 'Status'), ''));
  apr := nullif(private.upi_param(raw, 'ApprovalRefNo'), '');
  txn := coalesce(nullif(private.upi_param(raw, 'txnId'), ''), apr);
  ref := private.upi_param(raw, 'txnRef');

  if st in ('FAILURE','FAILED') then
    update public.payment_orders set status = 'failed' where id = o.id;
  elsif st = 'SUCCESS' then
    update public.payment_orders set success_reported = true where id = o.id;
    if lower(coalesce(ref, '')) = lower(o.reference)
       and txn ~ '^[A-Za-z0-9]{6,40}$'
       and o.created_at > now() - interval '2 hours' then
      insert into private.used_payment_utrs (txn_id, order_id) values (upper(txn), o.id) on conflict (txn_id) do nothing;
      get diagnostics recent = row_count;
      got := recent = 1;
      if got then
        update public.payment_orders set txn_id = txn, approval_ref = apr where id = o.id;
        select activation_mode into mode from public.payment_settings where id = 1;
        select count(*) into recent from public.payment_orders
         where user_id = uid and status = 'paid' and activation_kind = 'auto' and activated_at > now() - interval '24 hours';
        if mode = 'manual' or recent >= 3 then
          update public.payment_orders set status = 'review' where id = o.id;
        else
          perform private.activate_order(o.id, 'auto');
        end if;
      end if;
    end if;
  end if;
  return private.order_json(o.id);
end $$;

create function public.claim_free_plan(p_plan uuid) returns timestamptz language plpgsql security definer set search_path = '' as
$$
declare uid uuid := auth.uid(); pl public.plans%rowtype; promo int; new_end timestamptz; sub_id uuid;
begin
  if not public.is_member() then raise exception 'login required' using errcode = '42501'; end if;
  if not public.plans_visible_for_me() then raise exception 'plans are not available for this account'; end if;
  if not public.free_plan_for_me(p_plan) then raise exception 'this plan is not free for you'; end if;
  if public.has_plan() then raise exception 'you already have an active plan'; end if;
  select * into pl from public.plans where id = p_plan;
  select promo_id into promo from public.app_mode where id = 1;
  if exists (select 1 from public.free_plan_claims where user_id = uid and plan_id = p_plan and promo_id = promo) then
    raise exception 'already claimed';
  end if;
  new_end := now() + make_interval(days => pl.duration_days);
  insert into public.subscriptions (user_id, plan_id, plan_code, plan_name, kind, starts_at, ends_at)
  values (uid, pl.id, pl.code, pl.name, 'free_promo', now(), new_end) returning id into sub_id;
  insert into public.free_plan_claims (user_id, plan_id, promo_id, subscription_id) values (uid, p_plan, promo, sub_id);
  if private.source_of(uid) = 'organic' then
    update public.profiles set ads_access_status = 'pending' where id = uid and ads_access_status in ('none','rejected');
  end if;
  return new_end;
end $$;

create function public.plan_offers() returns jsonb language plpgsql stable security definer set search_path = '' as
$$
declare fm boolean; ids uuid[];
begin
  select a.free_mode into fm from public.app_mode a where a.id = 1;
  select coalesce(array_agg(p.id), '{}') into ids from public.plans p where p.active and public.free_plan_for_me(p.id);
  return jsonb_build_object(
    'free_plan_ids', to_jsonb(ids),
    'payments_available', (not fm) and public.payments_available(),
    'plans_visible', (not fm) and public.plans_visible_for_me());
end $$;

create function public.provider_payment_update(p_reference text, p_txn text, p_status text, p_amount_paise bigint) returns jsonb
language plpgsql security definer set search_path = '' as
$$
declare o public.payment_orders%rowtype; got int;
begin
  select * into o from public.payment_orders where reference = p_reference for update;
  if not found then return jsonb_build_object('result', 'unknown_reference'); end if;
  if o.status in ('paid','revoked') then return private.order_json(o.id); end if;
  if upper(p_status) in ('FAILURE','FAILED') then
    update public.payment_orders set status = 'failed' where id = o.id and status in ('pending','submitted','review');
    return private.order_json(o.id);
  end if;
  if upper(p_status) <> 'SUCCESS' then return private.order_json(o.id); end if;
  if p_amount_paise is distinct from o.amount_paise then
    update public.payment_orders set status = 'review', admin_note = 'webhook amount mismatch' where id = o.id;
    return private.order_json(o.id);
  end if;
  if p_txn is null or p_txn !~ '^[A-Za-z0-9]{6,40}$' then return private.order_json(o.id); end if;
  insert into private.used_payment_utrs (txn_id, order_id) values (upper(p_txn), o.id) on conflict (txn_id) do nothing;
  get diagnostics got = row_count;
  if got = 0 and not exists (select 1 from private.used_payment_utrs where txn_id = upper(p_txn) and order_id = o.id) then
    return jsonb_build_object('result', 'txn_reused');
  end if;
  update public.payment_orders set txn_id = p_txn, success_reported = true, bank_verified = true, bank_verified_at = now() where id = o.id;
  perform private.activate_order(o.id, 'webhook');
  return private.order_json(o.id);
end $$;

update public.payment_settings set upi_id = '2728412a@bandhan', payee_name = 'As Enterprice', enabled = true, activation_mode = 'manual' where id = 1;

do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prokind = 'f' and p.proname <> 'rls_auto_enable' loop
    execute format('revoke execute on function %s from public, anon', r.sig);
    if r.proname = 'provider_payment_update' then
      execute format('revoke execute on function %s from authenticated', r.sig);
      execute format('grant execute on function %s to service_role', r.sig);
    else
      execute format('grant execute on function %s to authenticated, service_role', r.sig);
    end if;
  end loop;
end $$;


-- SOURCE v1.0.9: 20261109000007_0007_admin_rpcs.sql

create function public.admin_mark_paid(p_order uuid, p_utr text) returns jsonb language plpgsql security definer set search_path = '' as
$$
declare o public.payment_orders%rowtype; got int;
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_utr is null or p_utr !~ '^[0-9]{12}$' then raise exception 'UTR must be exactly 12 digits'; end if;
  select * into o from public.payment_orders where id = p_order for update;
  if not found then raise exception 'order not found'; end if;
  if o.status in ('paid','revoked') then raise exception 'order is already %', o.status; end if;
  insert into private.used_payment_utrs (txn_id, order_id) values (upper(p_utr), o.id) on conflict (txn_id) do nothing;
  get diagnostics got = row_count;
  if got = 0 and not exists (select 1 from private.used_payment_utrs where txn_id = upper(p_utr) and order_id = o.id) then
    raise exception 'this UTR was already used for another order';
  end if;
  update public.payment_orders set utr = p_utr, success_reported = true, bank_verified = true, bank_verified_at = now() where id = o.id;
  perform private.activate_order(o.id, 'manual');
  return private.order_json(o.id);
end $$;

create function public.admin_confirm_bank(p_order uuid) returns jsonb language plpgsql security definer set search_path = '' as
$$
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  update public.payment_orders set bank_verified = true, bank_verified_at = now() where id = p_order and status = 'paid';
  if not found then raise exception 'only paid orders can be bank-verified'; end if;
  return private.order_json(p_order);
end $$;

create function public.admin_reject_order(p_order uuid, p_note text default null) returns jsonb language plpgsql security definer set search_path = '' as
$$
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  update public.payment_orders set status = 'rejected', admin_note = left(p_note, 500)
   where id = p_order and status in ('pending','submitted','review','failed');
  if not found then raise exception 'order cannot be rejected in its current status'; end if;
  return private.order_json(p_order);
end $$;

create function public.admin_revoke_order(p_order uuid, p_note text default null) returns jsonb language plpgsql security definer set search_path = '' as
$$
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  update public.payment_orders set status = 'revoked', admin_note = left(p_note, 500) where id = p_order and status = 'paid';
  if not found then raise exception 'only paid orders can be revoked'; end if;
  update public.subscriptions set revoked = true where order_id = p_order;
  return private.order_json(p_order);
end $$;

create function public.admin_dashboard() returns jsonb language plpgsql stable security definer set search_path = '' as
$$
declare res jsonb; today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  res := jsonb_build_object(
    'channels', (select count(*) from public.channels where review_status = 'approved'),
    'posts', (select count(*) from public.posts));
  if not public.is_owner() then return res; end if;
  return res || jsonb_build_object(
    'ads_installs', (select count(*) from public.installs where source = 'ads'),
    'organic_installs', (select count(*) from public.installs where source = 'organic'),
    'users', (select count(*) from public.profiles),
    'logged_in', (select count(*) from public.profiles where not is_guest),
    'premium_users', (select count(distinct user_id) from public.subscriptions where not revoked and ends_at > now()),
    'revenue_today', coalesce((select sum(amount_paise) from public.payment_orders where status = 'paid' and (activated_at at time zone 'Asia/Kolkata')::date = today), 0) / 100,
    'revenue_month', coalesce((select sum(amount_paise) from public.payment_orders where status = 'paid' and date_trunc('month', activated_at at time zone 'Asia/Kolkata') = date_trunc('month', now() at time zone 'Asia/Kolkata')), 0) / 100,
    'free_claims', (select count(*) from public.free_plan_claims),
    'alerts', jsonb_build_object(
      'channel_requests', (select count(*) from public.channels where review_status = 'pending'),
      'organic_buyers_waiting', (select count(*) from public.profiles where ads_access_status = 'pending'),
      'payments_to_verify', (select count(*) from public.payment_orders
          where status = 'review' or (status = 'paid' and activation_kind = 'auto' and not bank_verified
                and (activated_at at time zone 'Asia/Kolkata')::date = today)),
      'open_requests', (select count(*) from public.support_requests where status = 'open')),
    'installs_by_campaign', coalesce((select jsonb_agg(x) from (
        select source, coalesce(utm_campaign, '(none)') as campaign, count(*) as installs
        from public.installs group by 1, 2 order by 3 desc limit 50) x), '[]'::jsonb));
end $$;

create function public.admin_payment_stats() returns jsonb language plpgsql stable security definer set search_path = '' as
$$
declare today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  return jsonb_build_object(
    'paid_orders', (select count(*) from public.payment_orders where status = 'paid'),
    'revenue_total', coalesce((select sum(amount_paise) from public.payment_orders where status = 'paid'), 0) / 100,
    'revenue_today', coalesce((select sum(amount_paise) from public.payment_orders where status = 'paid' and (activated_at at time zone 'Asia/Kolkata')::date = today), 0) / 100,
    'to_verify', (select count(*) from public.payment_orders where status = 'review' or (status = 'paid' and activation_kind = 'auto' and not bank_verified and (activated_at at time zone 'Asia/Kolkata')::date = today)),
    'pending_orders', (select count(*) from public.payment_orders where status in ('pending','submitted')),
    'failed_orders', (select count(*) from public.payment_orders where status in ('failed','rejected')),
    'sales_per_plan', coalesce((select jsonb_agg(x) from (
        select plan_name, count(*) as orders, sum(amount_paise) / 100 as revenue
        from public.payment_orders where status = 'paid' group by plan_name order by 3 desc) x), '[]'::jsonb),
    'repeat_buyers', coalesce((select jsonb_agg(x) from (
        select u.email, count(*) as paid_orders, sum(o.amount_paise) / 100 as spent
        from public.payment_orders o join auth.users u on u.id = o.user_id
        where o.status = 'paid' group by u.email having count(*) >= 2 order by 2 desc limit 50) x), '[]'::jsonb));
end $$;

create function public.admin_orders(p_status text default null, p_verify_today boolean default false, p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = '' as
$$
declare today date := (now() at time zone 'Asia/Kolkata')::date; res jsonb;
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb) into res from (
    select o.id, o.created_at, u.email, o.user_id, o.plan_name, o.amount_paise / 100 as amount_inr, o.reference,
           coalesce(o.utr, o.txn_id) as txn, o.upi_id_used, o.status, o.activation_kind, o.bank_verified, o.raw_result, o.admin_note
    from public.payment_orders o join auth.users u on u.id = o.user_id
    where (coalesce(p_status, '') = '' or o.status = p_status)
      and (not p_verify_today or (o.status = 'paid' and o.activation_kind = 'auto' and not o.bank_verified
                                   and (o.activated_at at time zone 'Asia/Kolkata')::date = today))
    order by o.created_at desc limit least(greatest(p_limit, 1), 200) offset greatest(p_offset, 0)) x;
  return res;
end $$;

create function public.admin_users(p_search text default null, p_source text default null, p_plan text default null,
                                   p_guest boolean default null, p_access text default null, p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = '' as
$$
declare res jsonb;
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  with base as (
    select pr.id, u.email, pr.display_name, pr.is_guest, private.source_of(pr.id) as source, pr.ads_access_status, pr.used_bytes, pr.created_at,
      (select s.plan_name from public.subscriptions s where s.user_id = pr.id and not s.revoked and s.ends_at > now() order by s.ends_at desc limit 1) as plan_name,
      (select max(s.ends_at) from public.subscriptions s where s.user_id = pr.id and not s.revoked and s.ends_at > now()) as plan_ends_at
    from public.profiles pr join auth.users u on u.id = pr.id
    where (coalesce(p_search, '') = '' or u.email ilike '%' || p_search || '%' or pr.display_name ilike '%' || p_search || '%')
      and (coalesce(p_source, '') = '' or private.source_of(pr.id) = p_source)
      and (p_guest is null or pr.is_guest = p_guest)
      and (coalesce(p_access, '') = '' or pr.ads_access_status = p_access)),
  filtered as (
    select * from base
    where (coalesce(p_plan, '') = '') or (p_plan = 'active' and plan_name is not null) or (p_plan = 'none' and plan_name is null))
  select jsonb_build_object('total', (select count(*) from filtered),
    'rows', coalesce((select jsonb_agg(to_jsonb(f) order by f.created_at desc) from (
        select * from filtered order by created_at desc limit least(greatest(p_limit, 1), 200) offset greatest(p_offset, 0)) f), '[]'::jsonb))
  into res;
  return res;
end $$;

create function public.admin_channel_requests() returns jsonb language plpgsql stable security definer set search_path = '' as
$$
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from (
    select c.id, c.name, c.description, c.category, c.tags, c.icon_url, c.created_at,
           u.email as creator_email, p.display_name as creator_name, private.source_of(c.created_by) as creator_source
    from public.channels c left join auth.users u on u.id = c.created_by left join public.profiles p on p.id = c.created_by
    where c.review_status = 'pending') x), '[]'::jsonb);
end $$;

create function public.admin_requests(p_status text default 'open') returns jsonb language plpgsql stable security definer set search_path = '' as
$$
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
    select r.id, r.kind, r.target_type, r.target_id, r.reason, r.details, r.status, r.created_at, r.email as contact_email,
           u.email as user_email, r.user_id,
           case r.target_type when 'post' then (select title from public.posts where id = r.target_id)
                              when 'channel' then (select name from public.channels where id = r.target_id) end as target_title
    from public.support_requests r left join auth.users u on u.id = r.user_id
    where p_status is null or r.status = p_status
    order by r.created_at desc limit 200) x), '[]'::jsonb);
end $$;

create function public.admin_close_request(p_id uuid) returns void language plpgsql security definer set search_path = '' as
$$
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  update public.support_requests set status = 'closed' where id = p_id;
end $$;

create function public.admin_list_admins() returns jsonb language plpgsql stable security definer set search_path = '' as
$$
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from (
    select a.user_id, a.role, a.created_at, u.email,
           coalesce((select jsonb_agg(c.name) from public.admin_channel_access ac join public.channels c on c.id = ac.channel_id where ac.user_id = a.user_id), '[]'::jsonb) as channels
    from public.admins a join auth.users u on u.id = a.user_id) x), '[]'::jsonb);
end $$;

-- public website needs a safe, minimal view of one shareable post (service role only)
create function public.public_post_preview(p_id uuid) returns jsonb language sql stable security definer set search_path = '' as
$$
 select jsonb_build_object('id', p.id, 'title', p.title, 'description', left(p.description, 300), 'channel', c.name)
 from public.posts p join public.channels c on c.id = p.channel_id
 where p.id = p_id and not p.hidden and p.audience = 'all' and p.status = 'published'
   and c.audience = 'all' and c.review_status = 'approved' and not c.hidden
$$;
revoke execute on function public.public_post_preview(uuid) from public, anon, authenticated;
grant execute on function public.public_post_preview(uuid) to service_role;

do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prokind = 'f' and p.proname like 'admin\_%' loop
    execute format('revoke execute on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated, service_role', r.sig);
  end loop;
end $$;


-- SOURCE v1.0.9: 20261109000008_0008_cron_cancel_stale_orders.sql

create extension if not exists pg_cron;

create function private.cancel_stale_orders() returns void language sql security definer set search_path = '' as
$$
  update public.payment_orders set status = 'cancelled'
   where status = 'pending' and not success_reported and created_at < now() - interval '24 hours'
$$;

select cron.schedule('cancel-stale-orders', '*/30 * * * *', 'select private.cancel_stale_orders()');


-- SOURCE v1.0.9: 20261109000009_0009_retention_and_play.sql

-- keep payment records (anonymised) when an account is deleted: legal/tax retention
alter table public.payment_orders alter column user_id drop not null;
alter table public.payment_orders drop constraint payment_orders_user_id_fkey;
alter table public.payment_orders add constraint payment_orders_user_id_fkey foreign key (user_id) references auth.users(id) on delete set null;
alter table public.payment_orders add column email_at_purchase text;

create or replace function private.order_snapshot() returns trigger language plpgsql security definer set search_path = '' as
$$
declare pl public.plans%rowtype; ps public.payment_settings%rowtype;
begin
  select * into pl from public.plans where id = new.plan_id;
  if not found then raise exception 'plan not found'; end if;
  select * into ps from public.payment_settings where id = 1;
  new.plan_code := pl.code; new.plan_name := pl.name;
  new.amount_paise := pl.price_inr::bigint * 100;
  new.duration_days := pl.duration_days;
  new.upi_id_used := ps.upi_id; new.payee_used := ps.payee_name;
  select email into new.email_at_purchase from auth.users where id = new.user_id;
  new.reference := 'OB' || to_char(now() at time zone 'Asia/Kolkata', 'YYMMDD') || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  new.status := 'pending'; new.success_reported := false; new.raw_result := null;
  new.txn_id := null; new.utr := null; new.activated_at := null; new.activation_kind := null;
  return new;
end $$;

create or replace function public.admin_orders(p_status text default null, p_verify_today boolean default false, p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = '' as
$$
declare today date := (now() at time zone 'Asia/Kolkata')::date; res jsonb;
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb) into res from (
    select o.id, o.created_at, coalesce(u.email, o.email_at_purchase) as email, o.user_id, o.plan_name, o.amount_paise / 100 as amount_inr, o.reference,
           coalesce(o.utr, o.txn_id) as txn, o.upi_id_used, o.status, o.activation_kind, o.bank_verified, o.raw_result, o.admin_note
    from public.payment_orders o left join auth.users u on u.id = o.user_id
    where (coalesce(p_status, '') = '' or o.status = p_status)
      and (not p_verify_today or (o.status = 'paid' and o.activation_kind = 'auto' and not o.bank_verified
                                   and (o.activated_at at time zone 'Asia/Kolkata')::date = today))
    order by o.created_at desc limit least(greatest(p_limit, 1), 200) offset greatest(p_offset, 0)) x;
  return res;
end $$;

create or replace function public.admin_payment_stats() returns jsonb language plpgsql stable security definer set search_path = '' as
$$
declare today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  return jsonb_build_object(
    'paid_orders', (select count(*) from public.payment_orders where status = 'paid'),
    'revenue_total', coalesce((select sum(amount_paise) from public.payment_orders where status = 'paid'), 0) / 100,
    'revenue_today', coalesce((select sum(amount_paise) from public.payment_orders where status = 'paid' and (activated_at at time zone 'Asia/Kolkata')::date = today), 0) / 100,
    'to_verify', (select count(*) from public.payment_orders where status = 'review' or (status = 'paid' and activation_kind = 'auto' and not bank_verified and (activated_at at time zone 'Asia/Kolkata')::date = today)),
    'pending_orders', (select count(*) from public.payment_orders where status in ('pending','submitted')),
    'failed_orders', (select count(*) from public.payment_orders where status in ('failed','rejected')),
    'sales_per_plan', coalesce((select jsonb_agg(x) from (
        select plan_name, count(*) as orders, sum(amount_paise) / 100 as revenue
        from public.payment_orders where status = 'paid' group by plan_name order by 3 desc) x), '[]'::jsonb),
    'repeat_buyers', coalesce((select jsonb_agg(x) from (
        select coalesce(u.email, o.email_at_purchase) as email, count(*) as paid_orders, sum(o.amount_paise) / 100 as spent
        from public.payment_orders o left join auth.users u on u.id = o.user_id
        where o.status = 'paid' group by coalesce(u.email, o.email_at_purchase) having count(*) >= 2 order by 2 desc limit 50) x), '[]'::jsonb));
end $$;

-- Play Integrity (free 15 GB cloud for verified Play installs)
create table private.play_challenges (
  nonce text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  used boolean not null default false,
  created_at timestamptz not null default now()
);
create index play_challenges_user_idx on private.play_challenges (user_id, created_at desc);

create function public.play_integrity_challenge() returns text language plpgsql security definer set search_path = '' as
$$
declare uid uuid := auth.uid(); n text;
begin
  if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if (select count(*) from private.play_challenges where user_id = uid and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'too many requests';
  end if;
  n := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into private.play_challenges (nonce, user_id, expires_at) values (n, uid, now() + interval '10 minutes');
  return n;
end $$;

create function public.enable_play_free_cloud(p_user uuid, p_nonce text) returns boolean language plpgsql security definer set search_path = '' as
$$
begin
  update private.play_challenges set used = true
   where nonce = p_nonce and user_id = p_user and not used and expires_at > now();
  if not found then return false; end if;
  update public.profiles set play_verified = true where id = p_user;
  return true;
end $$;
revoke execute on function public.enable_play_free_cloud(uuid, text) from public, anon, authenticated;
grant execute on function public.enable_play_free_cloud(uuid, text) to service_role;
revoke execute on function public.play_integrity_challenge() from public, anon;
grant execute on function public.play_integrity_challenge() to authenticated, service_role;

-- Google Play billing scaffold (stays OFF until play_settings flags are enabled; see docs/play-billing.md)
create table public.play_products (
  id uuid primary key default gen_random_uuid(),
  play_product_id text not null,
  base_plan_id text,
  plan_id uuid references public.plans(id),
  created_at timestamptz not null default now(),
  unique (play_product_id, base_plan_id)
);
create index play_products_plan_idx on public.play_products (plan_id);

create table public.play_purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  product_id uuid references public.play_products(id),
  purchase_token text not null unique,
  status text not null default 'pending' check (status in ('pending','verified','reported','failed')),
  verified_at timestamptz, reported_at timestamptz,
  external_transaction_id text, last_error text,
  created_at timestamptz not null default now()
);
create index play_purchases_user_idx on public.play_purchases (user_id);
create index play_purchases_product_idx on public.play_purchases (product_id);

alter table public.play_products enable row level security;
alter table public.play_purchases enable row level security;
create policy play_products_owner on public.play_products for all to authenticated using ((select public.is_owner())) with check ((select public.is_owner()));
create policy play_purchases_owner_read on public.play_purchases for select to authenticated using ((select public.is_owner()));


-- SOURCE v1.0.9: 20261109000010_0010_split_overlapping_policies.sql

drop policy admins_owner_write on public.admins;
create policy admins_owner_insert on public.admins for insert to authenticated with check ((select public.is_owner()));
create policy admins_owner_update on public.admins for update to authenticated using ((select public.is_owner())) with check ((select public.is_owner()));
create policy admins_owner_delete on public.admins for delete to authenticated using ((select public.is_owner()));

drop policy admin_access_owner_write on public.admin_channel_access;
create policy admin_access_owner_insert on public.admin_channel_access for insert to authenticated with check ((select public.is_owner()));
create policy admin_access_owner_update on public.admin_channel_access for update to authenticated using ((select public.is_owner())) with check ((select public.is_owner()));
create policy admin_access_owner_delete on public.admin_channel_access for delete to authenticated using ((select public.is_owner()));

drop policy channel_folders_write on public.channel_folders;
create policy channel_folders_insert on public.channel_folders for insert to authenticated with check ((select public.can_manage_channel(channel_id)));
create policy channel_folders_update on public.channel_folders for update to authenticated using ((select public.can_manage_channel(channel_id))) with check ((select public.can_manage_channel(channel_id)));
create policy channel_folders_delete on public.channel_folders for delete to authenticated using ((select public.can_manage_channel(channel_id)));

drop policy post_items_write on public.post_items;
create policy post_items_insert on public.post_items for insert to authenticated with check ((select public.can_edit_post(post_id)));
create policy post_items_update on public.post_items for update to authenticated using ((select public.can_edit_post(post_id))) with check ((select public.can_edit_post(post_id)));
create policy post_items_delete on public.post_items for delete to authenticated using ((select public.can_edit_post(post_id)));


-- SOURCE v1.0.9: 20261109000011_0011_public_plans.sql

create or replace function public.public_plans()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'code', code, 'name', name, 'price_inr', price_inr,
    'duration_days', duration_days, 'perks', perks, 'badge', badge, 'position', position
  ) order by position), '[]'::jsonb)
  from public.plans where active;
$$;
revoke all on function public.public_plans() from public;
grant execute on function public.public_plans() to anon, authenticated, service_role;


-- SOURCE v1.0.9: 20261109000012_0012_guest_status_fallback.sql
create or replace function public.guest_status() returns jsonb language sql stable security definer set search_path = '' as
$$
 select jsonb_build_object(
   'is_guest', true, 'is_premium', false, 'can_play_premium', false,
   'free_mode', am.free_mode,
   'plans_visible', (not am.free_mode) and am.plans_visible_for = 'everyone',
   'quota_bytes', 0, 'used_bytes', 0)
 from public.app_mode am where am.id = 1
$$;
revoke all on function public.guest_status() from public;
grant execute on function public.guest_status() to anon, authenticated;


-- SOURCE v1.0.9: 20261109000013_0013_guest_status_payments.sql
create or replace function public.guest_status() returns jsonb language sql stable security definer set search_path = '' as
$$
 select jsonb_build_object(
   'is_guest', true, 'is_premium', false, 'can_play_premium', false,
   'free_mode', am.free_mode,
   'plans_visible', (not am.free_mode) and am.plans_visible_for = 'everyone',
   'payments_available', (not am.free_mode) and public.payments_available(),
   'quota_bytes', 0, 'used_bytes', 0)
 from public.app_mode am where am.id = 1
$$;


-- SOURCE v1.0.9: 20261109000014_0014_instant_activation.sql
-- Owner request: plans activate automatically when the UPI app reports a successful payment.
update public.payment_settings set activation_mode = 'instant' where id = 1;


-- SOURCE v1.0.9: 20261110000015_0015_hourly_plans.sql
-- Hourly plans: duration_hours > 0 overrides duration_days (days stays >= 1 as a placeholder).
alter table public.plans add column if not exists duration_hours integer not null default 0 check (duration_hours >= 0);
alter table public.payment_orders add column if not exists duration_hours integer not null default 0;

create or replace function private.plan_interval(p_days int, p_hours int) returns interval
language sql immutable set search_path = '' as
$$ select case when coalesce(p_hours, 0) > 0 then make_interval(hours => p_hours) else make_interval(days => p_days) end $$;

create or replace function public.public_plans()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'code', code, 'name', name, 'price_inr', price_inr,
    'duration_days', duration_days, 'duration_hours', duration_hours, 'perks', perks, 'badge', badge, 'position', position
  ) order by position), '[]'::jsonb)
  from public.plans where active;
$$;

create or replace function private.order_snapshot() returns trigger language plpgsql security definer set search_path = '' as
$$
declare pl public.plans%rowtype; ps public.payment_settings%rowtype;
begin
  select * into pl from public.plans where id = new.plan_id;
  if not found then raise exception 'plan not found'; end if;
  select * into ps from public.payment_settings where id = 1;
  new.plan_code := pl.code; new.plan_name := pl.name;
  new.amount_paise := pl.price_inr::bigint * 100;
  new.duration_days := pl.duration_days; new.duration_hours := pl.duration_hours;
  new.upi_id_used := ps.upi_id; new.payee_used := ps.payee_name;
  select email into new.email_at_purchase from auth.users where id = new.user_id;
  new.reference := 'OB' || to_char(now() at time zone 'Asia/Kolkata', 'YYMMDD') || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  new.status := 'pending'; new.success_reported := false; new.raw_result := null;
  new.txn_id := null; new.utr := null; new.activated_at := null; new.activation_kind := null;
  return new;
end $$;

create or replace function private.activate_order(p_order uuid, p_kind text) returns void
language plpgsql security definer set search_path = '' as
$$
declare o public.payment_orders%rowtype; base timestamptz; new_end timestamptz;
begin
  select * into o from public.payment_orders where id = p_order for update;
  if not found then raise exception 'order not found'; end if;
  if exists (select 1 from public.subscriptions where order_id = o.id) then
    update public.payment_orders set status = 'paid', updated_at = now() where id = o.id and status <> 'paid';
    return;
  end if;
  select greatest(now(), coalesce(max(ends_at), now())) into base
    from public.subscriptions where user_id = o.user_id and not revoked and ends_at > now();
  new_end := base + private.plan_interval(o.duration_days, o.duration_hours);
  insert into public.subscriptions (user_id, plan_id, plan_code, plan_name, kind, order_id, starts_at, ends_at)
  values (o.user_id, o.plan_id, o.plan_code, o.plan_name, 'payment', o.id, base, new_end);
  update public.payment_orders set status = 'paid', activated_at = now(), activation_kind = p_kind, updated_at = now() where id = o.id;
  if private.source_of(o.user_id) = 'organic' then
    update public.profiles set ads_access_status = 'pending' where id = o.user_id and ads_access_status in ('none','rejected');
  end if;
  perform private.enqueue_meta('Purchase', o.user_id, o.id, o.amount_paise / 100.0);
end $$;

create or replace function public.claim_free_plan(p_plan uuid) returns timestamptz language plpgsql security definer set search_path = '' as
$$
declare uid uuid := auth.uid(); pl public.plans%rowtype; promo int; new_end timestamptz; sub_id uuid;
begin
  if not public.is_member() then raise exception 'login required' using errcode = '42501'; end if;
  if not public.plans_visible_for_me() then raise exception 'plans are not available for this account'; end if;
  if not public.free_plan_for_me(p_plan) then raise exception 'this plan is not free for you'; end if;
  if public.has_plan() then raise exception 'you already have an active plan'; end if;
  select * into pl from public.plans where id = p_plan;
  select promo_id into promo from public.app_mode where id = 1;
  if exists (select 1 from public.free_plan_claims where user_id = uid and plan_id = p_plan and promo_id = promo) then
    raise exception 'already claimed';
  end if;
  new_end := now() + private.plan_interval(pl.duration_days, pl.duration_hours);
  insert into public.subscriptions (user_id, plan_id, plan_code, plan_name, kind, starts_at, ends_at)
  values (uid, pl.id, pl.code, pl.name, 'free_promo', now(), new_end) returning id into sub_id;
  insert into public.free_plan_claims (user_id, plan_id, promo_id, subscription_id) values (uid, p_plan, promo, sub_id);
  if private.source_of(uid) = 'organic' then
    update public.profiles set ads_access_status = 'pending' where id = uid and ads_access_status in ('none','rejected');
  end if;
  return new_end;
end $$;

create or replace function public.grant_premium(p_user uuid, p_plan uuid) returns timestamptz language plpgsql security definer set search_path = '' as
$$
declare pl public.plans%rowtype; base timestamptz; new_end timestamptz;
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into pl from public.plans where id = p_plan;
  if not found then raise exception 'plan not found'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'user not found'; end if;
  select greatest(now(), coalesce(max(ends_at), now())) into base
    from public.subscriptions where user_id = p_user and not revoked and ends_at > now();
  new_end := base + private.plan_interval(pl.duration_days, pl.duration_hours);
  insert into public.subscriptions (user_id, plan_id, plan_code, plan_name, kind, starts_at, ends_at)
  values (p_user, pl.id, pl.code, pl.name, 'admin_grant', now(), new_end);
  return new_end;
end $$;


-- SOURCE v1.0.9: 20261110000016_0016_guest_purchase.sql
-- Guests (anonymous sessions) may buy a plan; they can add an email later (updateUser keeps the same user id).
create or replace function public.create_order(p_plan uuid) returns jsonb language plpgsql security definer set search_path = '' as
$$
declare uid uuid := auth.uid(); pl public.plans%rowtype; ps public.payment_settings%rowtype; o public.payment_orders%rowtype;
begin
  if uid is null then raise exception 'session required' using errcode = '42501'; end if;
  if (select free_mode from public.app_mode where id = 1) then raise exception 'payments are off in free mode'; end if;
  if not public.plans_visible_for_me() then raise exception 'plans are not available for this account'; end if;
  select * into pl from public.plans where id = p_plan and active;
  if not found then raise exception 'This plan is no longer available.'; end if;
  if public.free_plan_for_me(p_plan) then raise exception 'this plan is free for you'; end if;
  if not public.payments_available() then raise exception 'payments are not available'; end if;
  select * into ps from public.payment_settings where id = 1;

  update public.payment_orders set status = 'cancelled'
   where user_id = uid and status = 'pending' and not success_reported
     and (created_at < now() - interval '2 hours' or plan_id <> p_plan
          or amount_paise <> pl.price_inr::bigint * 100 or coalesce(upi_id_used, '') <> ps.upi_id);

  select * into o from public.payment_orders
   where user_id = uid and plan_id = p_plan and status = 'pending' and not success_reported
   order by created_at desc limit 1;
  if not found then
    insert into public.payment_orders (user_id, plan_id) values (uid, p_plan) returning * into o;
    perform private.enqueue_meta('Lead', uid, o.id, null);
  end if;
  return jsonb_build_object('order_id', o.id, 'reference', o.reference, 'amount_paise', o.amount_paise,
    'amount_inr', o.amount_paise / 100, 'plan_name', o.plan_name, 'status', o.status, 'created_at', o.created_at,
    'upi_id', o.upi_id_used, 'payee_name', o.payee_used);
end $$;


-- SOURCE v1.0.9: 20261110000017_0017_admin_panel_rpcs.sql
-- Admin panel v2: counters, campaign table, payment filters, approvals, plan impact, audit trail.
-- Every function re-checks the role in the database; the UI is never the only guard.

create or replace function public.admin_role() returns text language sql stable security definer set search_path = '' as
$$ select role from public.admins where user_id = auth.uid() $$;

create or replace function public.admin_nav_counts() returns jsonb language plpgsql stable security definer set search_path = '' as
$$
declare today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if not public.is_owner() then return '{}'::jsonb; end if;
  return jsonb_build_object(
    'channels', (select count(*) from public.channels where review_status = 'pending'),
    'approvals', (select count(*) from public.profiles where ads_access_status = 'pending'),
    'payments', (select count(*) from public.payment_orders
        where status = 'review' or (status = 'paid' and activation_kind = 'auto' and not bank_verified
              and (activated_at at time zone 'Asia/Kolkata')::date = today)),
    'requests', (select count(*) from public.support_requests where status = 'open'));
end $$;

create or replace function public.admin_campaigns() returns jsonb language plpgsql stable security definer set search_path = '' as
$$
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x)) from (
    select i.source, coalesce(i.utm_campaign, '(none)') as campaign, count(*) as installs,
           count(*) filter (where exists (select 1 from public.profiles p where p.id = i.user_id and not p.is_guest)) as registrations,
           count(distinct i.user_id) filter (where exists (select 1 from public.payment_orders o where o.user_id = i.user_id and o.status = 'paid')) as buyers
    from public.installs i group by 1, 2 order by 3 desc limit 100) x), '[]'::jsonb);
end $$;

create or replace function public.admin_payments(
  p_status text default null, p_plan text default null, p_from date default null, p_to date default null,
  p_search text default null, p_sort text default 'newest', p_verify text default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = '' as
$$
declare today date := (now() at time zone 'Asia/Kolkata')::date; q text := nullif(trim(coalesce(p_search, '')), '');
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x)) from (
    select o.id, o.created_at, o.updated_at, coalesce(u.email, o.email_at_purchase) as email, o.user_id,
           (u.id is not null and coalesce(u.is_anonymous, false)) as guest,
           o.plan_code, o.plan_name, o.amount_paise / 100 as amount_inr, o.reference, o.utr, o.txn_id, o.upi_id_used,
           o.status, o.activation_kind, o.activated_at, o.bank_verified, o.bank_verified_at, o.admin_note, o.raw_result
    from public.payment_orders o left join auth.users u on u.id = o.user_id
    where (coalesce(p_status, '') = '' or o.status = p_status)
      and (coalesce(p_plan, '') = '' or o.plan_code = p_plan)
      and (p_from is null or (o.created_at at time zone 'Asia/Kolkata')::date >= p_from)
      and (p_to is null or (o.created_at at time zone 'Asia/Kolkata')::date <= p_to)
      and (q is null or o.reference ilike '%' || q || '%' or o.utr ilike '%' || q || '%' or o.txn_id ilike '%' || q || '%'
           or coalesce(u.email, o.email_at_purchase) ilike '%' || q || '%' or o.user_id::text = q)
      and (coalesce(p_verify, '') = ''
           or (p_verify = 'today' and (o.status = 'review' or (o.status = 'paid' and o.activation_kind = 'auto' and not o.bank_verified
                                        and (o.activated_at at time zone 'Asia/Kolkata')::date = today)))
           or (p_verify = 'all' and (o.status = 'review' or (o.status = 'paid' and o.activation_kind = 'auto' and not o.bank_verified))))
    order by case when p_sort = 'highest' then o.amount_paise end desc nulls last, o.created_at desc
    limit least(greatest(p_limit, 1), 500)) x), '[]'::jsonb);
end $$;

create or replace function public.admin_approvals(p_status text default 'pending') returns jsonb language plpgsql stable security definer set search_path = '' as
$$
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_status not in ('pending','approved','rejected') then raise exception 'invalid status'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x)) from (
    select pr.id, u.email, coalesce(u.is_anonymous, false) as guest, private.source_of(pr.id) as source,
           (select i.utm_campaign from public.installs i where i.user_id = pr.id order by i.created_at limit 1) as campaign,
           (select s.plan_name from public.subscriptions s where s.user_id = pr.id and not s.revoked and s.ends_at > now() order by s.ends_at desc limit 1) as plan_name,
           pr.ads_access_status as status, pr.created_at
    from public.profiles pr join auth.users u on u.id = pr.id
    where pr.ads_access_status = p_status
    order by pr.created_at desc limit 300) x), '[]'::jsonb);
end $$;

create or replace function public.admin_plan_impact() returns jsonb language plpgsql stable security definer set search_path = '' as
$$
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  return coalesce((select jsonb_object_agg(pl.id, jsonb_build_object(
      'subscribers', (select count(distinct s.user_id) from public.subscriptions s where s.plan_id = pl.id and not s.revoked and s.ends_at > now()),
      'orders', (select count(*) from public.payment_orders o where o.plan_id = pl.id and o.status = 'paid')))
    from public.plans pl), '{}'::jsonb);
end $$;

create or replace function public.admin_free_plan_claims() returns jsonb language plpgsql stable security definer set search_path = '' as
$$
declare promo int;
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  select promo_id into promo from public.app_mode where id = 1;
  return jsonb_build_object(
    'organic', (select count(*) from public.free_plan_claims c where c.promo_id = promo and private.source_of(c.user_id) = 'organic'),
    'ads', (select count(*) from public.free_plan_claims c where c.promo_id = promo and private.source_of(c.user_id) = 'ads'));
end $$;

create or replace function public.admin_audit(p_limit int default 100) returns jsonb language plpgsql stable security definer set search_path = '' as
$$
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x)) from (
    select a.table_name, a.row_key, a.field, a.old_value, a.new_value, u.email as changed_by, a.changed_at
    from public.settings_audit a left join auth.users u on u.id = a.changed_by
    order by a.changed_at desc limit least(greatest(p_limit, 1), 500)) x), '[]'::jsonb);
end $$;

-- users list: add the install campaign and allow the latest 500
create or replace function public.admin_users(p_search text default null, p_source text default null, p_plan text default null,
                                   p_guest boolean default null, p_access text default null, p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = '' as
$$
declare res jsonb;
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  with base as (
    select pr.id, u.email, pr.display_name, pr.is_guest, private.source_of(pr.id) as source, pr.ads_access_status, pr.used_bytes, pr.created_at,
      (select i.utm_campaign from public.installs i where i.user_id = pr.id order by i.created_at limit 1) as campaign,
      (select s.plan_name from public.subscriptions s where s.user_id = pr.id and not s.revoked and s.ends_at > now() order by s.ends_at desc limit 1) as plan_name,
      (select max(s.ends_at) from public.subscriptions s where s.user_id = pr.id and not s.revoked and s.ends_at > now()) as plan_ends_at
    from public.profiles pr join auth.users u on u.id = pr.id
    where (coalesce(p_search, '') = '' or u.email ilike '%' || p_search || '%' or pr.display_name ilike '%' || p_search || '%')
      and (coalesce(p_source, '') = '' or private.source_of(pr.id) = p_source)
      and (p_guest is null or pr.is_guest = p_guest)
      and (coalesce(p_access, '') = '' or pr.ads_access_status = p_access)),
  filtered as (
    select * from base
    where (coalesce(p_plan, '') = '') or (p_plan = 'active' and plan_name is not null) or (p_plan = 'none' and plan_name is null))
  select jsonb_build_object('total', (select count(*) from filtered),
    'rows', coalesce((select jsonb_agg(to_jsonb(f) order by f.created_at desc) from (
        select * from filtered order by created_at desc limit least(greatest(p_limit, 1), 500) offset greatest(p_offset, 0)) f), '[]'::jsonb))
  into res;
  return res;
end $$;

do $$
declare f text;
begin
  foreach f in array array['admin_role()','admin_nav_counts()','admin_campaigns()',
    'admin_payments(text,text,date,date,text,text,text,int)','admin_approvals(text)','admin_plan_impact()',
    'admin_free_plan_claims()','admin_audit(int)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
end $$;


-- SOURCE v1.0.9: 20261110000018_0018_meta_tracking.sql
-- Meta tracking v2: full funnel (Lead -> AppInstall -> CompleteRegistration -> InitiateCheckout -> Purchase),
-- ad-click matching (fbc / fbp / IP / user agent) so Purchase value can be attributed for ROAS,
-- automatic sending (no button needed), and a public pixel id so the website follows the admin setting.
create extension if not exists pg_net with schema extensions;

alter table public.meta_events drop constraint if exists meta_events_event_name_check;
alter table public.meta_events add constraint meta_events_event_name_check
  check (event_name in ('Lead','AppInstall','CompleteRegistration','InitiateCheckout','Purchase'));
alter table public.meta_events
  add column if not exists fbc text,
  add column if not exists fbp text,
  add column if not exists client_ip text,
  add column if not exists client_ua text,
  add column if not exists source_url text,
  add column if not exists content_name text;
create index if not exists ad_clicks_ip_idx on public.ad_clicks (ip, created_at desc);

create table if not exists private.user_attribution (
  user_id uuid primary key references auth.users(id) on delete cascade,
  click_id uuid,
  fbc text,
  fbp text,
  ip text,          -- browser IP at the ad click
  ua text,          -- browser user agent at the ad click
  last_ip text,     -- most recent app IP
  last_ua text,
  updated_at timestamptz not null default now()
);

create table if not exists private.meta_cron (
  id int primary key default 1 check (id = 1),
  key text not null default encode(extensions.gen_random_bytes(24), 'hex'),
  url text not null default ''   -- https://<project>.supabase.co/functions/v1/meta-send (set once per project)
);
insert into private.meta_cron (id) values (1) on conflict do nothing;

create or replace function private.req_header(p_name text) returns text language plpgsql stable set search_path = '' as
$$
declare h text := current_setting('request.headers', true);
begin
  if h is null or h = '' then return null; end if;
  return nullif(h::json ->> p_name, '');
exception when others then return null;
end $$;

create or replace function private.req_ip() returns text language sql stable set search_path = '' as
$$ select nullif(trim(split_part(coalesce(private.req_header('x-forwarded-for'), ''), ',', 1)), '') $$;

create or replace function private.touch_attribution(p_user uuid) returns void language plpgsql security definer set search_path = '' as
$$
declare v_ip text := private.req_ip(); v_ua text := left(private.req_header('user-agent'), 400);
begin
  if p_user is null or v_ip is null then return; end if;
  insert into private.user_attribution (user_id, last_ip, last_ua) values (p_user, v_ip, v_ua)
  on conflict (user_id) do update set last_ip = excluded.last_ip, last_ua = excluded.last_ua, updated_at = now();
end $$;

create or replace function private.meta_ready() returns boolean language sql stable security definer set search_path = '' as
$$ select exists (select 1 from public.meta_settings where enabled and pixel_id <> '' and capi_token <> '') $$;

create or replace function private.enqueue_meta(p_event text, p_user uuid, p_order uuid, p_value numeric) returns void
language plpgsql security definer set search_path = '' as
$$
declare a private.user_attribution%rowtype; v_name text;
begin
  if not private.meta_ready() then return; end if;
  select * into a from private.user_attribution where user_id = p_user;
  if p_order is not null then select plan_name into v_name from public.payment_orders where id = p_order; end if;
  insert into public.meta_events (event_name, event_id, user_id, order_id, value_inr, fbc, fbp, client_ip, client_ua, content_name)
  values (p_event,
          case p_event when 'Purchase' then 'purchase-' || p_order::text
                       when 'InitiateCheckout' then 'checkout-' || p_order::text
                       when 'AppInstall' then 'install-' || p_user::text
                       when 'Lead' then 'lead-' || p_user::text
                       else 'reg-' || p_user::text end,
          p_user, p_order, p_value, a.fbc, a.fbp, coalesce(a.last_ip, a.ip), coalesce(a.ua, a.last_ua), v_name)
  on conflict (event_id) do nothing;
end $$;

-- Website: remembers an ad click (and optionally queues the Lead for the download tap). Called from the browser,
-- so the IP and user agent are the visitor's own.
create or replace function public.record_ad_click(p_fbclid text, p_fbc text, p_fbp text, p_url text, p_lead_event_id text default null)
returns uuid language plpgsql security definer set search_path = '' as
$$
declare v_ip text := private.req_ip(); v_ua text := left(private.req_header('user-agent'), 400); v_fbc text; v_id uuid;
begin
  if v_ip is null then return null; end if;
  if (select count(*) from public.ad_clicks where ip = v_ip and created_at > now() - interval '1 hour') >= 30 then return null; end if;
  p_fbclid := nullif(left(p_fbclid, 500), '');
  v_fbc := coalesce(nullif(left(p_fbc, 600), ''),
                    case when p_fbclid is not null then 'fb.1.' || (extract(epoch from now()) * 1000)::bigint || '.' || p_fbclid end);
  insert into public.ad_clicks (fbclid, fbc, fbp, ip, user_agent)
  values (p_fbclid, v_fbc, nullif(left(p_fbp, 200), ''), v_ip, v_ua) returning id into v_id;
  if p_lead_event_id ~ '^lead-[0-9a-f-]{36}$' and private.meta_ready() then
    insert into public.meta_events (event_name, event_id, fbc, fbp, client_ip, client_ua, source_url, content_name)
    values ('Lead', p_lead_event_id, v_fbc, nullif(left(p_fbp, 200), ''), v_ip, v_ua, left(p_url, 500), 'apk_download')
    on conflict (event_id) do nothing;
  end if;
  return v_id;
end $$;
revoke all on function public.record_ad_click(text, text, text, text, text) from public;
grant execute on function public.record_ad_click(text, text, text, text, text) to anon, authenticated;

-- The website reads the pixel id from here, so changing it in the admin panel changes it everywhere.
create or replace function public.meta_public() returns jsonb language sql stable security definer set search_path = '' as
$$ select coalesce((select jsonb_build_object('pixel_id', pixel_id) from public.meta_settings where id = 1 and enabled and pixel_id <> ''), '{}'::jsonb) $$;
revoke all on function public.meta_public() from public;
grant execute on function public.meta_public() to anon, authenticated;

create or replace function public.record_install(p_install_id text, p_referrer_status text, p_raw_referrer text, p_install_secret text)
returns text language plpgsql security definer set search_path = '' as
$$
declare uid uuid := auth.uid(); norm text; src text; camp text; existing text; v_ip text := private.req_ip(); c public.ad_clicks%rowtype;
begin
  if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if p_install_id is null or length(p_install_id) not between 8 and 100 then raise exception 'invalid install id'; end if;
  select source into existing from private.user_sources where user_id = uid;
  if existing is not null then return existing; end if;
  norm := replace(replace(lower(coalesce(p_raw_referrer, '')), '%3d', '='), '%26', '&');
  if norm ~ '(^|[&?])utm_source=(meta|facebook|instagram|ig)(&|$)' then src := 'ads'; else src := 'organic'; end if;
  camp := substring(norm from 'utm_campaign=([^&]+)');
  insert into public.installs (install_id, user_id, source, referrer_status, raw_referrer, utm_campaign, install_secret)
  values (p_install_id, uid, src, left(p_referrer_status, 100), left(p_raw_referrer, 1000), left(camp, 200), left(p_install_secret, 200))
  on conflict (install_id) do nothing;
  insert into private.user_sources (user_id, source) values (uid, src) on conflict (user_id) do nothing;

  -- Link this install to the most recent ad click from the same network (last 7 days).
  if v_ip is not null then
    select * into c from public.ad_clicks where ip = v_ip and created_at > now() - interval '7 days' order by created_at desc limit 1;
  end if;
  insert into private.user_attribution (user_id, click_id, fbc, fbp, ip, ua, last_ip, last_ua)
  values (uid, c.id, c.fbc, c.fbp, c.ip, c.user_agent, v_ip, left(private.req_header('user-agent'), 400))
  on conflict (user_id) do nothing;
  perform private.enqueue_meta('AppInstall', uid, null, null);
  return src;
end $$;

create or replace function public.create_order(p_plan uuid) returns jsonb language plpgsql security definer set search_path = '' as
$$
declare uid uuid := auth.uid(); pl public.plans%rowtype; ps public.payment_settings%rowtype; o public.payment_orders%rowtype;
begin
  if uid is null then raise exception 'session required' using errcode = '42501'; end if;
  if (select free_mode from public.app_mode where id = 1) then raise exception 'payments are off in free mode'; end if;
  if not public.plans_visible_for_me() then raise exception 'plans are not available for this account'; end if;
  select * into pl from public.plans where id = p_plan and active;
  if not found then raise exception 'This plan is no longer available.'; end if;
  if public.free_plan_for_me(p_plan) then raise exception 'this plan is free for you'; end if;
  if not public.payments_available() then raise exception 'payments are not available'; end if;
  select * into ps from public.payment_settings where id = 1;

  update public.payment_orders set status = 'cancelled'
   where user_id = uid and status = 'pending' and not success_reported
     and (created_at < now() - interval '2 hours' or plan_id <> p_plan
          or amount_paise <> pl.price_inr::bigint * 100 or coalesce(upi_id_used, '') <> ps.upi_id);

  select * into o from public.payment_orders
   where user_id = uid and plan_id = p_plan and status = 'pending' and not success_reported
   order by created_at desc limit 1;
  if not found then
    insert into public.payment_orders (user_id, plan_id) values (uid, p_plan) returning * into o;
    perform private.touch_attribution(uid);
    perform private.enqueue_meta('InitiateCheckout', uid, o.id, o.amount_paise / 100.0);
  end if;
  return jsonb_build_object('order_id', o.id, 'reference', o.reference, 'amount_paise', o.amount_paise,
    'amount_inr', o.amount_paise / 100, 'plan_name', o.plan_name, 'status', o.status, 'created_at', o.created_at,
    'upi_id', o.upi_id_used, 'payee_name', o.payee_used);
end $$;

-- ---------- automatic sending ----------
create or replace function public.meta_cron_ok(p_key text) returns boolean language sql stable security definer set search_path = '' as
$$ select coalesce(p_key, '') <> '' and exists (select 1 from private.meta_cron where id = 1 and key = p_key) $$;
revoke all on function public.meta_cron_ok(text) from public, anon, authenticated;
grant execute on function public.meta_cron_ok(text) to service_role;

create or replace function private.meta_kick() returns void language plpgsql security definer set search_path = '' as
$$
declare c private.meta_cron%rowtype;
begin
  select * into c from private.meta_cron where id = 1;
  if c.url is null or c.url = '' or not private.meta_ready() then return; end if;
  if not exists (select 1 from public.meta_events where status = 'pending' and attempts < 5) then return; end if;
  perform net.http_post(url := c.url, body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-key', c.key));
exception when others then null; -- tracking must never break a payment or a sign-up
end $$;

create or replace function private.meta_kick_trg() returns trigger language plpgsql security definer set search_path = '' as
$$ begin perform private.meta_kick(); return null; end $$;
create or replace trigger meta_events_kick after insert on public.meta_events for each statement execute function private.meta_kick_trg();

select cron.schedule('meta-send', '*/5 * * * *', 'select private.meta_kick()');

-- ---------- admin ----------
create or replace function public.admin_meta_overview() returns jsonb language plpgsql stable security definer set search_path = '' as
$$
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  return jsonb_build_object(
    'funnel', coalesce((select jsonb_agg(row_to_json(f)) from (
        select n.event_name,
               count(e.id) filter (where e.created_at > now() - interval '1 day') as d1,
               count(e.id) filter (where e.created_at > now() - interval '7 days') as d7,
               count(e.id) as d30,
               count(e.id) filter (where e.status = 'sent') as sent,
               count(e.id) filter (where e.status = 'failed') as failed,
               count(e.id) filter (where e.fbc is not null) as with_click,
               coalesce(sum(e.value_inr) filter (where n.event_name = 'Purchase' and e.created_at > now() - interval '7 days'), 0) as value_d7,
               coalesce(sum(e.value_inr) filter (where n.event_name = 'Purchase'), 0) as value_d30
          from unnest(array['Lead','AppInstall','CompleteRegistration','InitiateCheckout','Purchase']) with ordinality as n(event_name, ord)
          left join public.meta_events e on e.event_name = n.event_name and e.created_at > now() - interval '30 days'
         group by n.event_name, n.ord order by n.ord) f), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(row_to_json(r)) from (
        select id, event_name, status, value_inr, content_name, attempts, last_error, created_at, sent_at,
               (fbc is not null) as has_click, (client_ip is not null) as has_ip
          from public.meta_events order by created_at desc limit 40) r), '[]'::jsonb),
    'clicks_7d', (select count(*) from public.ad_clicks where created_at > now() - interval '7 days'),
    'matched_installs_7d', (select count(*) from private.user_attribution where click_id is not null and updated_at > now() - interval '7 days'),
    'auto_send', (select url <> '' from private.meta_cron where id = 1));
end $$;
revoke all on function public.admin_meta_overview() from public, anon;
grant execute on function public.admin_meta_overview() to authenticated, service_role;

create or replace function public.admin_meta_retry() returns integer language plpgsql security definer set search_path = '' as
$$
declare n integer;
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode = '42501'; end if;
  update public.meta_events set status = 'pending', attempts = 0
   where status = 'failed' and created_at > now() - interval '6 days';
  get diagnostics n = row_count;
  perform private.meta_kick();
  return n;
end $$;
revoke all on function public.admin_meta_retry() from public, anon;
grant execute on function public.admin_meta_retry() to authenticated, service_role;


-- SOURCE v1.0.9: 20261110000019_0019_install_event_ads_only.sql
-- AppInstall goes to Meta only for installs that came from an ad. Organic and Play-store installs send nothing,
-- which keeps the Play data-safety answers accurate.
create or replace function public.record_install(p_install_id text, p_referrer_status text, p_raw_referrer text, p_install_secret text)
returns text language plpgsql security definer set search_path = '' as
$$
declare uid uuid := auth.uid(); norm text; src text; camp text; existing text; v_ip text := private.req_ip(); c public.ad_clicks%rowtype;
begin
  if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if p_install_id is null or length(p_install_id) not between 8 and 100 then raise exception 'invalid install id'; end if;
  select source into existing from private.user_sources where user_id = uid;
  if existing is not null then return existing; end if;
  norm := replace(replace(lower(coalesce(p_raw_referrer, '')), '%3d', '='), '%26', '&');
  if norm ~ '(^|[&?])utm_source=(meta|facebook|instagram|ig)(&|$)' then src := 'ads'; else src := 'organic'; end if;
  camp := substring(norm from 'utm_campaign=([^&]+)');
  insert into public.installs (install_id, user_id, source, referrer_status, raw_referrer, utm_campaign, install_secret)
  values (p_install_id, uid, src, left(p_referrer_status, 100), left(p_raw_referrer, 1000), left(camp, 200), left(p_install_secret, 200))
  on conflict (install_id) do nothing;
  insert into private.user_sources (user_id, source) values (uid, src) on conflict (user_id) do nothing;

  if src = 'ads' then
    if v_ip is not null then
      select * into c from public.ad_clicks where ip = v_ip and created_at > now() - interval '7 days' order by created_at desc limit 1;
    end if;
    insert into private.user_attribution (user_id, click_id, fbc, fbp, ip, ua, last_ip, last_ua)
    values (uid, c.id, c.fbc, c.fbp, c.ip, c.user_agent, v_ip, left(private.req_header('user-agent'), 400))
    on conflict (user_id) do nothing;
    perform private.enqueue_meta('AppInstall', uid, null, null);
  end if;
  return src;
end $$;


-- SOURCE v1.0.9: 20261114105455_require_video_approval.sql
create or replace function private.guard_posts() returns trigger language plpgsql set search_path = '' as $$
declare ch_aud text;
begin
  if current_user not in ('authenticated','anon') then return new; end if;
  if tg_op = 'INSERT' then
    if public.can_manage_channel(new.channel_id) then
      new.created_by := coalesce(new.created_by, auth.uid());
    else
      select audience into ch_aud from public.channels where id = new.channel_id;
      new.created_by := auth.uid(); new.hidden := false; new.audience := coalesce(ch_aud, 'all');
      new.status := 'draft'; new.publish_at := null;
    end if;
    return new;
  end if;
  if new.channel_id is distinct from old.channel_id or new.created_by is distinct from old.created_by then
    raise exception 'protected post fields' using errcode = '42501';
  end if;
  if not public.is_owner() then
    if new.hidden is distinct from old.hidden then raise exception 'protected post fields' using errcode = '42501'; end if;
    if not public.can_manage_channel(old.channel_id) then
      if new.audience is distinct from old.audience then raise exception 'protected post fields' using errcode = '42501'; end if;
      new.status := 'draft'; new.publish_at := null;
    end if;
  end if;
  return new;
end $$;

-- SOURCE v1.0.9: 20261114121008_premium_channel_creation.sql
alter policy channels_insert on public.channels with check (
  (select public.is_owner()) or (
    (select public.is_member()) and (select public.has_plan()) and created_by = (select auth.uid())
  )
);

-- SOURCE v1.0.9: 20261114152156_require_organic_login_for_media.sql
alter policy media_select on storage.objects using (
  bucket_id = 'media' and (
    (select public.is_admin()) or exists (
      select 1 from public.post_items i
      where i.thumbnail_key = objects.name
         or (
           ((select public.is_member()) or (select public.source_of()) = 'ads')
           and (
             i.trailer_key = objects.name
             or (i.media_key = objects.name and (not i.is_premium or (select public.can_full_premium())))
           )
         )
    )
  )
);

-- SOURCE v1.0.9: 20261114160500_use_saved_account_status_after_guest_upgrade.sql
-- Account upgrades must take effect immediately even while an older guest JWT is still valid.
-- Keep the existing SECURITY DEFINER lookup, fixed search path and execution grants.
create or replace function public.is_member()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from auth.users u
    where u.id = auth.uid() and u.is_anonymous = false
  )
$$;


-- SOURCE v1.0.9: 20261114162028_keep_media_references_inside_parent_channel.sql
-- Keep each media reference within its parent channel so a post cannot expose another channel's files.
create or replace function private.guard_media_channel_paths()
returns trigger language plpgsql set search_path = '' as $$
declare channel_id_ uuid; path_key text;
begin
  select p.channel_id into channel_id_ from public.posts p where p.id = new.post_id;
  if channel_id_ is null then
    raise exception 'Post is not available for this media item' using errcode = '42501';
  end if;
  foreach path_key in array array[new.media_key,new.thumbnail_key,new.trailer_key] loop
    if path_key is not null and split_part(path_key,'/',1) <> channel_id_::text then
      raise exception 'Video, thumbnail and trailer must belong to this channel' using errcode = '42501';
    end if;
  end loop;
  return new;
end;
$$;
create trigger post_items_channel_paths before insert or update of post_id,media_key,thumbnail_key,trailer_key
on public.post_items for each row execute function private.guard_media_channel_paths();


-- SOURCE v1.0.9: 20261114173724_consent_aware_app_measurement.sql

-- Consent-aware measurement. No advertising SDK, advertising ID, private content or client-supplied purchase amounts.
create table public.measurement_preferences(
 user_id uuid primary key references auth.users(id) on delete cascade,
 analytics boolean not null default false, advertising boolean not null default false,
 policy_version text not null default '2026-11-14', advertising_since timestamptz, updated_at timestamptz not null default now()
);
alter table public.measurement_preferences enable row level security;
create policy measurement_preferences_read on public.measurement_preferences for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.measurement_preferences from anon,authenticated;
grant select on public.measurement_preferences to authenticated;
create table private.app_measurement_context(
 user_id uuid primary key references auth.users(id) on delete cascade,
 install_id text not null, app_data jsonb not null, updated_at timestamptz not null default now()
);
create table private.app_activity(
 event_id uuid primary key,user_id uuid not null references auth.users(id) on delete cascade,
 session_id uuid not null,event_name text not null,properties jsonb not null default '{}',
 occurred_at timestamptz not null,received_at timestamptz not null default now()
);
create index app_activity_user_time on private.app_activity(user_id,occurred_at desc);
create index app_activity_time on private.app_activity(occurred_at desc);
alter table private.app_measurement_context enable row level security;
alter table private.app_activity enable row level security;
alter table public.meta_settings add column revision bigint not null default 1;
alter table public.meta_events
 add column action_source text not null default 'app',
 add column app_data jsonb,
 add column anon_id text,
 add column custom_data jsonb not null default '{}',
 add column advertising_consent boolean not null default false,
 add column config_revision bigint not null default 1,
 add column lease_until timestamptz,
 add column next_attempt_at timestamptz not null default now(),
 add column meta_trace_id text;
alter table public.meta_events drop constraint if exists meta_events_event_name_check;
alter table public.meta_events drop constraint if exists meta_events_status_check;
alter table public.meta_events add constraint meta_events_status_check check(status in('pending','processing','sent','test_sent','failed','suppressed'));
alter table public.meta_events add constraint meta_events_action_source_check check(action_source in('website','app'));
create index meta_events_due on public.meta_events(next_attempt_at,created_at) where status in('pending','processing');
create or replace function private.meta_revision() returns trigger language plpgsql set search_path='' as $$
begin
 if new.pixel_id is distinct from old.pixel_id then
  new.revision:=old.revision+1;
  update public.meta_events set status='suppressed',last_error='Dataset changed; old events are not replayed to the new dataset'
   where status in('pending','processing');
 else new.revision:=old.revision;
 end if;
 return new;
end $$;
create trigger meta_settings_revision before update on public.meta_settings for each row execute function private.meta_revision();

create or replace function private.enqueue_meta(p_event text,p_user uuid,p_order uuid,p_value numeric) returns void
language plpgsql security definer set search_path='' as $$
declare pref public.measurement_preferences%rowtype; ctx private.app_measurement_context%rowtype;
 a private.user_attribution%rowtype; o public.payment_orders%rowtype; event_time_ timestamptz:=now(); key_ text; value_ numeric; name_ text;
begin
 if not private.meta_ready() then return; end if;
 select * into pref from public.measurement_preferences where user_id=p_user;
 if not coalesce(pref.advertising,false) then return; end if;
 select * into ctx from private.app_measurement_context where user_id=p_user;
 if ctx.user_id is null then return; end if;
 select * into a from private.user_attribution where user_id=p_user;
 if p_event in('Purchase','InitiateCheckout') then
  select * into o from public.payment_orders where id=p_order and user_id=p_user;
  if o.id is null then return; end if;
  if p_event='Purchase' and (o.status<>'paid' or not o.bank_verified) then return; end if;
  value_:=o.amount_paise/100.0; name_:=o.plan_name;
  event_time_:=case when p_event='Purchase' then o.activated_at else o.created_at end;
  if event_time_ is null or event_time_<coalesce(pref.advertising_since,pref.updated_at) or event_time_<now()-interval '7 days' then return; end if;
  key_:=case when p_event='Purchase' then 'purchase-' else 'checkout-' end||p_order::text;
 elsif p_event='AppInstall' then
  select created_at into event_time_ from public.installs where user_id=p_user and install_id=ctx.install_id;
  if event_time_ is null or event_time_<now()-interval '1 day' then return; end if;
  key_:='install-'||ctx.install_id;
 elsif p_event='CompleteRegistration' then key_:='reg-'||p_user::text;
 else return;
 end if;
 insert into public.meta_events(event_name,event_id,user_id,order_id,value_inr,fbc,fbp,client_ip,client_ua,content_name,created_at,
  action_source,app_data,anon_id,advertising_consent,config_revision,custom_data)
 values(case when p_event='AppInstall' then 'MobileAppInstall' else p_event end,key_,p_user,p_order,value_,a.fbc,a.fbp,
  private.req_ip(),left(private.req_header('user-agent'),400),name_,event_time_,
  'app',ctx.app_data,ctx.install_id,true,(select revision from public.meta_settings where id=1),
  case when p_order is null then '{}'::jsonb else jsonb_build_object('order_id',p_order::text) end)
 on conflict(event_id) do nothing;
end $$;

create or replace function public.set_measurement_preferences(p_analytics boolean,p_advertising boolean,p_context jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); ext jsonb; install_ text; old_ads boolean; i int; was_recorded boolean;
begin
 if uid is null then raise exception 'session required' using errcode='42501'; end if;
 select advertising into old_ads from public.measurement_preferences where user_id=uid;
 was_recorded:=found;
 insert into public.measurement_preferences(user_id,analytics,advertising,advertising_since) values(uid,p_analytics,p_advertising,case when p_advertising then now() end)
 on conflict(user_id) do update set analytics=excluded.analytics,advertising=excluded.advertising,policy_version='2026-11-14',updated_at=now(),
 advertising_since=case when not excluded.advertising then null when measurement_preferences.advertising then measurement_preferences.advertising_since else now() end;
 if p_advertising then
  ext:=p_context->'extinfo'; install_:=p_context->>'install_id';
  if jsonb_typeof(ext)<>'array' or jsonb_array_length(ext)<>16 or ext->>0<>'a2' or ext->>1<>'com.vayora.app'
     or coalesce(ext->>4,'')='' or coalesce(install_,'')!~'^[0-9a-f-]{36}$' then raise exception 'valid Android app context required'; end if;
  for i in 0..15 loop
   if jsonb_typeof(ext->i)<>'string' or length(ext->>i)>120 then raise exception 'invalid app context'; end if;
  end loop;
  insert into private.app_measurement_context(user_id,install_id,app_data)
  values(uid,install_,jsonb_build_object('advertiser_tracking_enabled',1,'application_tracking_enabled',1,'extinfo',ext))
  on conflict(user_id) do update set install_id=excluded.install_id,app_data=excluded.app_data,updated_at=now();
  if not coalesce(old_ads,false) then perform private.enqueue_meta('AppInstall',uid,null,null); end if;
 else
  update public.meta_events set status='suppressed',last_error='Advertising sharing disabled by the user',fbc=null,fbp=null,client_ip=null,client_ua=null,app_data=null,anon_id=null
   where user_id=uid and status in('pending','processing','failed');
  delete from private.app_measurement_context where user_id=uid;
  delete from private.user_attribution where user_id=uid;
 end if;
 return jsonb_build_object('analytics',p_analytics,'advertising',p_advertising,'policy_version','2026-11-14');
end $$;
revoke all on function public.set_measurement_preferences(boolean,boolean,jsonb) from public,anon;
grant execute on function public.set_measurement_preferences(boolean,boolean,jsonb) to authenticated;

create or replace function public.record_activity(p_event_id uuid,p_name text,p_session_id uuid,p_properties jsonb default '{}',p_occurred_at timestamptz default now())
returns boolean language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); pref public.measurement_preferences%rowtype; ctx private.app_measurement_context%rowtype; props jsonb; at_ timestamptz;
begin
 if uid is null then raise exception 'session required' using errcode='42501'; end if;
 if p_name not in('AppOpen','ScreenView','Login','ViewContent','VideoStart','VideoProgress','PreviewComplete','SearchUsed','ChannelCreated','ChannelJoined','VideoUploaded','CloudUploaded','CloudDeleted','PlanViewed','SubscriptionPrompt') then
  raise exception 'event is not permitted'; end if;
 select * into pref from public.measurement_preferences where user_id=uid;
 if not coalesce(pref.analytics,false) and not coalesce(pref.advertising,false) then return false; end if;
 if (select count(*) from private.app_activity where user_id=uid and received_at>now()-interval '1 day')>=5000 then return false; end if;
 at_:=greatest(now()-interval '1 day',least(coalesce(p_occurred_at,now()),now()));
 props:=jsonb_strip_nulls(jsonb_build_object(
 'screen',case when p_properties->>'screen' in('Cloud','Home','Explore','Channel','Profile','Premium','Post','Safety') then p_properties->>'screen' end,
 'media_type',case when p_properties->>'media_type' in('video','image','file') then p_properties->>'media_type' end,
 'progress',case when p_properties->>'progress' in('25','50','75','100') then (p_properties->>'progress')::int end,
 'preview',case when jsonb_typeof(p_properties->'preview')='boolean' then p_properties->'preview' end,
 'premium',case when jsonb_typeof(p_properties->'premium')='boolean' then p_properties->'premium' end));
 -- Store one minimal activity row for deduplication/consented analytics, never arbitrary text or content identifiers.
 insert into private.app_activity(event_id,user_id,session_id,event_name,properties,occurred_at) values(p_event_id,uid,p_session_id,p_name,props,at_)
 on conflict(event_id) do nothing;
 if not found then return false; end if;
 if pref.advertising and private.meta_ready() then
  select * into ctx from private.app_measurement_context where user_id=uid;
  if ctx.user_id is not null then
   insert into public.meta_events(event_name,event_id,user_id,created_at,action_source,app_data,anon_id,advertising_consent,config_revision,custom_data,client_ip,client_ua)
   values(p_name,'activity-'||p_event_id::text,uid,at_,'app',ctx.app_data,ctx.install_id,true,
    (select revision from public.meta_settings where id=1),props,private.req_ip(),left(private.req_header('user-agent'),400)) on conflict(event_id) do nothing;
  end if;
 end if;
 return true;
end $$;
revoke all on function public.record_activity(uuid,text,uuid,jsonb,timestamptz) from public,anon;
grant execute on function public.record_activity(uuid,text,uuid,jsonb,timestamptz) to authenticated;

-- Preserve install classification and content access; remove the unreliable same-IP ad-click guess.
create or replace function public.record_install(p_install_id text,p_referrer_status text,p_raw_referrer text,p_install_secret text)
returns text language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); norm text; src text; existing text;
begin
 if uid is null then raise exception 'not authenticated' using errcode='28000'; end if;
 if p_install_id is null or length(p_install_id) not between 8 and 100 then raise exception 'invalid install id'; end if;
 select source into existing from private.user_sources where user_id=uid;
 if existing is not null then return existing; end if;
 norm:=replace(replace(lower(coalesce(p_raw_referrer,'')),'%3d','='),'%26','&');
 src:=case when norm~'(^|[&?])utm_source=(meta|facebook|instagram|ig)(&|$)' then 'ads' else 'organic' end;
 insert into public.installs(install_id,user_id,source,referrer_status,raw_referrer,utm_campaign,install_secret)
 values(p_install_id,uid,src,left(p_referrer_status,100),
  case when src='ads' then 'utm_source=meta' else '' end,null,left(p_install_secret,200)) on conflict(install_id) do nothing;
 insert into private.user_sources(user_id,source) values(uid,src) on conflict(user_id) do nothing;
 return src;
end $$;
create or replace function private.touch_attribution(p_user uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.measurement_preferences where user_id=p_user and advertising) then
  insert into private.user_attribution(user_id,last_ip,last_ua) values(p_user,private.req_ip(),left(private.req_header('user-agent'),400))
  on conflict(user_id) do update set last_ip=excluded.last_ip,last_ua=excluded.last_ua,updated_at=now();
 end if;
end $$;
-- A successful UPI app reply keeps its existing activation flow; Meta Purchase waits for bank/provider verification.
create or replace function private.verified_purchase_event() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='paid' and new.bank_verified and (old.status is distinct from new.status or not old.bank_verified) then
  perform private.enqueue_meta('Purchase',new.user_id,new.id,new.amount_paise/100.0);
 end if;
 if new.status in('revoked','rejected','failed','cancelled') then
  update public.meta_events set status='suppressed',last_error='Order is no longer a paid verified purchase'
   where order_id=new.id and event_name='Purchase' and status in('pending','processing','failed');
 end if;
 return new;
end $$;
create trigger verified_purchase_measurement after update on public.payment_orders for each row execute function private.verified_purchase_event();

-- Old public website calls cannot share advertising data without the updated consent flow.
create or replace function public.record_ad_click(p_fbclid text,p_fbc text,p_fbp text,p_url text,p_lead_event_id text default null)
returns uuid language sql set search_path='' as $$ select null::uuid $$;
create or replace function public.record_web_measurement(p_event text,p_event_id uuid,p_consent boolean,p_fbclid text default '',p_fbc text default '',p_fbp text default '',p_url text default '')
returns boolean language plpgsql security definer set search_path='' as $$
declare ip_ text:=private.req_ip(); fbc_ text; rev bigint;
begin
 if not p_consent or not private.meta_ready() or ip_ is null then return false; end if;
 if p_event not in('PageView','Lead','PlanViewed') then raise exception 'event is not permitted'; end if;
 if p_url!~'^https://vayora-eta[.]vercel[.]app(/[^?#]*)?$' then return false; end if;
 if (select count(*) from public.meta_events where client_ip=ip_ and action_source='website' and created_at>now()-interval '1 hour')>=120 then return false; end if;
 fbc_:=coalesce(nullif(left(p_fbc,600),''),case when coalesce(p_fbclid,'')<>'' then 'fb.1.'||(extract(epoch from now())*1000)::bigint||'.'||left(p_fbclid,500) end);
 select revision into rev from public.meta_settings where id=1;
 insert into public.meta_events(event_name,event_id,action_source,advertising_consent,config_revision,fbc,fbp,client_ip,client_ua,source_url,custom_data)
 values(p_event,'web-'||p_event_id::text,'website',true,rev,fbc_,nullif(left(p_fbp,200),''),ip_,left(private.req_header('user-agent'),400),left(p_url,500),
 case when p_event='Lead' then '{"content_name":"apk_download"}'::jsonb else '{}'::jsonb end) on conflict(event_id) do nothing;
 return found;
end $$;
revoke all on function public.record_web_measurement(text,uuid,boolean,text,text,text,text) from public;
grant execute on function public.record_web_measurement(text,uuid,boolean,text,text,text,text) to anon,authenticated;
-- Atomic leasing prevents the cron and an admin-triggered flush from delivering the same batch concurrently.
create or replace function public.meta_claim_batch(p_limit int default 50) returns setof public.meta_events
language plpgsql security definer set search_path='' as $$
begin
 update public.meta_events e set status='suppressed',last_error='Consent withdrawn, configuration changed, or event expired'
 where e.status in('pending','processing') and (
  not e.advertising_consent or e.config_revision<>(select revision from public.meta_settings where id=1)
  or e.created_at<now()-interval '7 days'
  or(e.user_id is not null and not exists(select 1 from public.measurement_preferences p where p.user_id=e.user_id and p.advertising)));
 return query with picked as(
  select e.id from public.meta_events e where
   ((e.status='pending' and e.next_attempt_at<=now()) or(e.status='processing' and e.lease_until<now()))
   and e.attempts<8 order by e.created_at for update skip locked limit least(greatest(p_limit,1),100))
 update public.meta_events e set status='processing',lease_until=now()+interval '5 minutes',attempts=e.attempts+1
 from picked p where e.id=p.id returning e.*;
end $$;
revoke all on function public.meta_claim_batch(int) from public,anon,authenticated;
grant execute on function public.meta_claim_batch(int) to service_role;
select cron.schedule('measurement-retention','17 3 * * *',$job$
 delete from private.app_activity where received_at<now()-interval '90 days';
 delete from public.meta_events where created_at<now()-interval '90 days';
 delete from public.ad_clicks where created_at<now()-interval '30 days';
 update private.user_attribution set fbc=null,fbp=null,ip=null,ua=null,last_ip=null,last_ua=null,click_id=null where updated_at<now()-interval '30 days';
$job$);



-- SOURCE v1.0.9: 20261114173854_owner_date_range_analytics_and_sorting.sql

create or replace function public.admin_users_filtered(p_search text default null,p_source text default null,p_plan text default null,p_guest boolean default null,p_access text default null,p_from date default null,p_to date default null,p_customer text default null,p_sort text default 'newest',p_limit int default 50,p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result_ jsonb;
begin
 if not public.is_owner() then raise exception 'forbidden' using errcode='42501'; end if;
 if p_from is not null and p_to is not null and p_from>p_to then raise exception 'Start date must not follow end date'; end if;
 with spending as (
  select user_id,count(*) as paid_orders,sum(amount_paise)/100.0 as spent,
  coalesce(sum(amount_paise) filter(where bank_verified),0)/100.0 as verified_spent
  from public.payment_orders where status='paid' group by user_id),
 activity as(select user_id,max(occurred_at) as last_seen,count(distinct session_id) as sessions from private.app_activity group by user_id),
 base as(
  select pr.id,u.email,pr.display_name,pr.is_guest,coalesce(us.source,'organic') as source,pr.ads_access_status,pr.used_bytes,pr.created_at,
  current_plan.plan_name,current_plan.plan_ends_at,coalesce(s.paid_orders,0) as paid_orders,coalesce(s.spent,0) as spent,
  coalesce(s.verified_spent,0) as verified_spent,a.last_seen,coalesce(a.sessions,0) as sessions
  from public.profiles pr join auth.users u on u.id=pr.id left join private.user_sources us on us.user_id=pr.id
  left join spending s on s.user_id=pr.id left join activity a on a.user_id=pr.id
  left join lateral(select plan_name,ends_at as plan_ends_at from public.subscriptions where user_id=pr.id and not revoked and ends_at>now() order by ends_at desc limit 1) current_plan on true
  where (nullif(p_search,'') is null or u.email ilike '%'||left(p_search,200)||'%' or pr.display_name ilike '%'||left(p_search,200)||'%' or pr.id::text=p_search)
  and(nullif(p_source,'') is null or coalesce(us.source,'organic')=p_source)
  and(p_guest is null or pr.is_guest=p_guest)
  and(nullif(p_access,'') is null or pr.ads_access_status=p_access)
  and(p_from is null or pr.created_at>=p_from::timestamp at time zone 'Asia/Kolkata')
  and(p_to is null or pr.created_at<(p_to+1)::timestamp at time zone 'Asia/Kolkata')),
 filtered as(select * from base where
  (nullif(p_plan,'') is null or(p_plan='active' and plan_name is not null) or(p_plan='none' and plan_name is null))
  and(nullif(p_customer,'') is null or(p_customer='repeat' and paid_orders>=2) or(p_customer='first' and paid_orders=1) or(p_customer='never' and paid_orders=0) or(p_customer='returning' and sessions>=2))),
 sorted as(select * from filtered order by
  case when p_sort='oldest' then created_at end asc nulls last,
  case when p_sort='spent_high' then spent end desc nulls last,
  case when p_sort='spent_low' then spent end asc nulls last,
  case when p_sort='recently_active' then last_seen end desc nulls last,
  case when p_sort='repeat' then paid_orders end desc nulls last,
  created_at desc,id
  limit least(greatest(p_limit,1),200) offset greatest(p_offset,0))
 select jsonb_build_object('total',(select count(*) from filtered),'rows',coalesce((select jsonb_agg(to_jsonb(s)) from sorted s),'[]'::jsonb)) into result_;
 return result_;
end $$;
revoke all on function public.admin_users_filtered(text,text,text,boolean,text,date,date,text,text,int,int) from public,anon;
grant execute on function public.admin_users_filtered(text,text,text,boolean,text,date,date,text,text,int,int) to authenticated;

create or replace function public.admin_payments_filtered(p_status text default null,p_plan text default null,p_from date default null,p_to date default null,p_search text default null,p_sort text default 'newest',p_verify text default null,p_source text default null,p_customer text default null,p_date_basis text default 'created',p_limit int default 100,p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare today date:=(now() at time zone 'Asia/Kolkata')::date; result_ jsonb;
begin
 if not public.is_owner() then raise exception 'forbidden' using errcode='42501'; end if;
 if p_from is not null and p_to is not null and p_from>p_to then raise exception 'Start date must not follow end date'; end if;
 with paid as(select user_id,count(*) as paid_orders from public.payment_orders where status='paid' group by user_id),
 base as(
 select o.id,o.created_at,o.updated_at,coalesce(u.email,o.email_at_purchase) as email,o.user_id,
 coalesce(u.is_anonymous,false) as guest,o.plan_code,o.plan_name,o.amount_paise/100.0 as amount_inr,o.reference,o.utr,o.txn_id,o.upi_id_used,
 o.status,o.activation_kind,o.activated_at,o.bank_verified,o.bank_verified_at,o.admin_note,o.raw_result,
 coalesce(us.source,'organic') as source,coalesce(pd.paid_orders,0) as paid_orders,
 case when p_date_basis='activated' then o.activated_at else o.created_at end as date_basis
 from public.payment_orders o left join auth.users u on u.id=o.user_id left join private.user_sources us on us.user_id=o.user_id left join paid pd on pd.user_id=o.user_id
 where(nullif(p_status,'') is null or o.status=p_status)
 and(nullif(p_plan,'') is null or o.plan_code=p_plan)
 and(nullif(p_source,'') is null or coalesce(us.source,'organic')=p_source)
 and(nullif(p_search,'') is null or o.reference ilike '%'||left(p_search,200)||'%' or o.utr ilike '%'||left(p_search,200)||'%' or o.txn_id ilike '%'||left(p_search,200)||'%' or coalesce(u.email,o.email_at_purchase) ilike '%'||left(p_search,200)||'%' or o.user_id::text=p_search)
 and(nullif(p_verify,'') is null or(p_verify='verified' and o.bank_verified) or(p_verify='unverified' and not o.bank_verified)
  or(p_verify='all' and(o.status='review' or(o.status='paid' and not o.bank_verified)))
  or(p_verify='today' and(o.status='review' or(o.status='paid' and not o.bank_verified and(o.activated_at at time zone 'Asia/Kolkata')::date=today))))),
 filtered as(select * from base where
 (p_from is null or date_basis>=p_from::timestamp at time zone 'Asia/Kolkata')
 and(p_to is null or date_basis<(p_to+1)::timestamp at time zone 'Asia/Kolkata')
 and(nullif(p_customer,'') is null or(p_customer='repeat' and paid_orders>=2) or(p_customer='first' and paid_orders=1))),
 sorted as(select * from filtered order by
  case when p_sort='oldest' then created_at end asc nulls last,
  case when p_sort='highest' then amount_inr end desc nulls last,
  case when p_sort='lowest' then amount_inr end asc nulls last,
  case when p_sort='activated' then activated_at end desc nulls last,
  created_at desc,id limit least(greatest(p_limit,1),200) offset greatest(p_offset,0))
 select jsonb_build_object('total',(select count(*) from filtered),'rows',coalesce((select jsonb_agg(to_jsonb(s)) from sorted s),'[]'::jsonb)) into result_;
 return result_;
end $$;
revoke all on function public.admin_payments_filtered(text,text,date,date,text,text,text,text,text,text,int,int) from public,anon;
grant execute on function public.admin_payments_filtered(text,text,date,date,text,text,text,text,text,text,int,int) to authenticated;

create or replace function public.admin_analytics(p_from date default null,p_to date default null,p_source text default null,p_plan text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result_ jsonb; lo timestamptz:=coalesce(p_from::timestamp at time zone 'Asia/Kolkata','-infinity'::timestamptz); hi timestamptz:=coalesce((p_to+1)::timestamp at time zone 'Asia/Kolkata','infinity'::timestamptz);
begin
 if not public.is_owner() then raise exception 'forbidden' using errcode='42501'; end if;
 if p_from is not null and p_to is not null and p_from>p_to then raise exception 'Start date must not follow end date'; end if;
 with users_ as(
 select p.id,p.created_at,p.is_guest,coalesce(s.source,'organic') as source from public.profiles p left join private.user_sources s on s.user_id=p.id
 where(nullif(p_source,'') is null or coalesce(s.source,'organic')=p_source)),
 orders_ as(
 select o.*,u.source from public.payment_orders o join users_ u on u.id=o.user_id
 where o.status='paid' and(nullif(p_plan,'') is null or o.plan_code=p_plan)),
 selected_orders as(select * from orders_ where activated_at>=lo and activated_at<hi),
 totals as(select user_id,count(*) as paid_orders from public.payment_orders where status='paid' group by user_id),
 activity as(
 select a.* from private.app_activity a join users_ u on u.id=a.user_id join public.measurement_preferences pref on pref.user_id=a.user_id and pref.analytics
 where a.occurred_at>=lo and a.occurred_at<hi),
 daily as(
 select (activated_at at time zone 'Asia/Kolkata')::date as day,count(*) as orders,sum(amount_paise)/100.0 as activated_revenue,
 coalesce(sum(amount_paise) filter(where bank_verified),0)/100.0 as verified_revenue from selected_orders group by 1 order by 1),
 plans_ as(select plan_code,plan_name,count(*) as orders,sum(amount_paise)/100.0 as revenue,
 coalesce(sum(amount_paise) filter(where bank_verified),0)/100.0 as verified_revenue from selected_orders group by 1,2 order by verified_revenue desc,orders desc),
 repeat_ as(select o.user_id,coalesce(u.email,'Guest') as email,count(*) as orders_in_range,max(t.paid_orders) as lifetime_paid_orders,sum(o.amount_paise)/100.0 as spent
 from selected_orders o join totals t on t.user_id=o.user_id left join auth.users u on u.id=o.user_id
 where t.paid_orders>=2 group by o.user_id,u.email order by spent desc limit 100),
 sources_ as(select u.source,count(*) as new_users from users_ u where created_at>=lo and created_at<hi group by u.source),
 events_ as(select event_name,count(*) as events,count(distinct user_id) as users from activity group by event_name order by events desc)
 select jsonb_build_object(
 'from',p_from,'to',p_to,'timezone','Asia/Kolkata',
 'activated_revenue',coalesce((select sum(amount_paise)/100.0 from selected_orders),0),
 'verified_revenue',coalesce((select sum(amount_paise)/100.0 from selected_orders where bank_verified),0),
 'unverified_revenue',coalesce((select sum(amount_paise)/100.0 from selected_orders where not bank_verified),0),
 'paid_orders',(select count(*) from selected_orders),
 'paying_users',(select count(distinct user_id) from selected_orders),
 'repeat_buyers',(select count(distinct o.user_id) from selected_orders o join totals t on t.user_id=o.user_id where t.paid_orders>=2),
 'new_users',(select count(*) from users_ where created_at>=lo and created_at<hi),
 'new_registrations',(select count(*) from users_ u join auth.users a on a.id=u.id where a.email_confirmed_at>=lo and a.email_confirmed_at<hi and not u.is_guest),
 'active_users',(select count(distinct user_id) from activity),
 'returning_users',(select count(distinct a.user_id) from activity a where exists(select 1 from private.app_activity earlier where earlier.user_id=a.user_id and earlier.occurred_at<lo)),
 'sessions',(select count(distinct(user_id,session_id)) from activity),
 'daily',coalesce((select jsonb_agg(to_jsonb(d)) from daily d),'[]'::jsonb),
 'plans',coalesce((select jsonb_agg(to_jsonb(p)) from plans_ p),'[]'::jsonb),
 'repeat_customers',coalesce((select jsonb_agg(to_jsonb(r)) from repeat_ r),'[]'::jsonb),
 'sources',coalesce((select jsonb_agg(to_jsonb(s)) from sources_ s),'[]'::jsonb),
 'events',coalesce((select jsonb_agg(to_jsonb(e)) from events_ e),'[]'::jsonb)
 ) into result_;
 return result_;
end $$;
revoke all on function public.admin_analytics(date,date,text,text) from public,anon;
grant execute on function public.admin_analytics(date,date,text,text) to authenticated;



-- SOURCE v1.0.9: 20261114174241_keep_conversion_context_on_the_purchasing_device.sql
create or replace function private.enqueue_meta(p_event text,p_user uuid,p_order uuid,p_value numeric) returns void
language plpgsql security definer set search_path='' as $$
declare pref public.measurement_preferences%rowtype; ctx private.app_measurement_context%rowtype;
 a private.user_attribution%rowtype; o public.payment_orders%rowtype; event_time_ timestamptz:=now(); key_ text; value_ numeric; name_ text;
begin
 if not private.meta_ready() then return; end if;
 select * into pref from public.measurement_preferences where user_id=p_user;
 if not coalesce(pref.advertising,false) then return; end if;
 select * into ctx from private.app_measurement_context where user_id=p_user;
 if ctx.user_id is null then return; end if;
 select * into a from private.user_attribution where user_id=p_user;
 if p_event in('Purchase','InitiateCheckout') then
  select * into o from public.payment_orders where id=p_order and user_id=p_user;
  if o.id is null then return; end if;
  if p_event='Purchase' and (o.status<>'paid' or not o.bank_verified) then return; end if;
  value_:=o.amount_paise/100.0; name_:=o.plan_name;
  event_time_:=case when p_event='Purchase' then o.activated_at else o.created_at end;
  if event_time_ is null or event_time_<coalesce(pref.advertising_since,pref.updated_at) or event_time_<now()-interval '7 days' then return; end if;
  key_:=case when p_event='Purchase' then 'purchase-' else 'checkout-' end||p_order::text;
 elsif p_event='AppInstall' then
  select created_at into event_time_ from public.installs where user_id=p_user and install_id=ctx.install_id;
  if event_time_ is null or event_time_<now()-interval '1 day' then return; end if;
  key_:='install-'||ctx.install_id;
 elsif p_event='CompleteRegistration' then key_:='reg-'||p_user::text;
 else return;
 end if;
 insert into public.meta_events(event_name,event_id,user_id,order_id,value_inr,fbc,fbp,client_ip,client_ua,content_name,created_at,
  action_source,app_data,anon_id,advertising_consent,config_revision,custom_data)
 values(case when p_event='AppInstall' then 'MobileAppInstall' else p_event end,key_,p_user,p_order,value_,a.fbc,a.fbp,
  coalesce(a.last_ip,a.ip),coalesce(a.last_ua,a.ua),name_,event_time_,
  'app',ctx.app_data,ctx.install_id,true,(select revision from public.meta_settings where id=1),
  case when p_order is null then '{}'::jsonb else jsonb_build_object('order_id',p_order::text) end)
 on conflict(event_id) do nothing;
end $$;
create or replace function public.set_measurement_preferences(p_analytics boolean,p_advertising boolean,p_context jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); ext jsonb; install_ text; old_ads boolean; i int; was_recorded boolean;
begin
 if uid is null then raise exception 'session required' using errcode='42501'; end if;
 select advertising into old_ads from public.measurement_preferences where user_id=uid;
 was_recorded:=found;
 insert into public.measurement_preferences(user_id,analytics,advertising,advertising_since) values(uid,p_analytics,p_advertising,case when p_advertising then now() end)
 on conflict(user_id) do update set analytics=excluded.analytics,advertising=excluded.advertising,policy_version='2026-11-14',updated_at=now(),
 advertising_since=case when not excluded.advertising then null when measurement_preferences.advertising then measurement_preferences.advertising_since else now() end;
 if p_advertising then
  ext:=p_context->'extinfo'; install_:=p_context->>'install_id';
  if jsonb_typeof(ext)<>'array' or jsonb_array_length(ext)<>16 or ext->>0<>'a2' or ext->>1<>'com.vayora.app'
     or coalesce(ext->>4,'')='' or coalesce(install_,'')!~'^[0-9a-f-]{36}$' then raise exception 'valid Android app context required'; end if;
  for i in 0..15 loop
   if jsonb_typeof(ext->i)<>'string' or length(ext->>i)>120 then raise exception 'invalid app context'; end if;
  end loop;
  insert into private.app_measurement_context(user_id,install_id,app_data)
  values(uid,install_,jsonb_build_object('advertiser_tracking_enabled',1,'application_tracking_enabled',1,'extinfo',ext))
  on conflict(user_id) do update set install_id=excluded.install_id,app_data=excluded.app_data,updated_at=now();
  perform private.touch_attribution(uid);
  if not coalesce(old_ads,false) then perform private.enqueue_meta('AppInstall',uid,null,null); end if;
 else
  update public.meta_events set status='suppressed',last_error='Advertising sharing disabled by the user',fbc=null,fbp=null,client_ip=null,client_ua=null,app_data=null,anon_id=null
   where user_id=uid and status in('pending','processing','failed');
  delete from private.app_measurement_context where user_id=uid;
  delete from private.user_attribution where user_id=uid;
  if not p_analytics then delete from private.app_activity where user_id=uid; end if;
 end if;
 return jsonb_build_object('analytics',p_analytics,'advertising',p_advertising,'policy_version','2026-11-14');
end $$;
create or replace function public.record_activity(p_event_id uuid,p_name text,p_session_id uuid,p_properties jsonb default '{}',p_occurred_at timestamptz default now())
returns boolean language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); pref public.measurement_preferences%rowtype; ctx private.app_measurement_context%rowtype; props jsonb; at_ timestamptz;
begin
 if uid is null then raise exception 'session required' using errcode='42501'; end if;
 if p_name not in('AppOpen','ScreenView','Login','ViewContent','VideoStart','VideoProgress','PreviewComplete','SearchUsed','ChannelCreated','ChannelJoined','VideoUploaded','CloudUploaded','CloudDeleted','PlanViewed','SubscriptionPrompt') then
  raise exception 'event is not permitted'; end if;
 select * into pref from public.measurement_preferences where user_id=uid;
 if not coalesce(pref.analytics,false) and not coalesce(pref.advertising,false) then return false; end if;
 if (select count(*) from private.app_activity where user_id=uid and received_at>now()-interval '1 day')>=5000 then return false; end if;
 at_:=greatest(now()-interval '1 day',least(coalesce(p_occurred_at,now()),now()));
 props:=jsonb_strip_nulls(jsonb_build_object(
 'screen',case when p_properties->>'screen' in('Cloud','Home','Explore','Channel','Profile','Premium','Post','Safety') then p_properties->>'screen' end,
 'media_type',case when p_properties->>'media_type' in('video','image','file') then p_properties->>'media_type' end,
 'progress',case when p_properties->>'progress' in('25','50','75','100') then (p_properties->>'progress')::int end,
 'preview',case when jsonb_typeof(p_properties->'preview')='boolean' then p_properties->'preview' end,
 'premium',case when jsonb_typeof(p_properties->'premium')='boolean' then p_properties->'premium' end));
 -- Store one minimal activity row for deduplication/consented analytics, never arbitrary text or content identifiers.
 insert into private.app_activity(event_id,user_id,session_id,event_name,properties,occurred_at) values(p_event_id,uid,p_session_id,p_name,props,at_)
 on conflict(event_id) do nothing;
 if not found then return false; end if;
 if pref.advertising then perform private.touch_attribution(uid); end if;
 if pref.advertising and private.meta_ready() then
  select * into ctx from private.app_measurement_context where user_id=uid;
  if ctx.user_id is not null then
   insert into public.meta_events(event_name,event_id,user_id,created_at,action_source,app_data,anon_id,advertising_consent,config_revision,custom_data,client_ip,client_ua)
   values(p_name,'activity-'||p_event_id::text,uid,at_,'app',ctx.app_data,ctx.install_id,true,
    (select revision from public.meta_settings where id=1),props,private.req_ip(),left(private.req_header('user-agent'),400)) on conflict(event_id) do nothing;
  end if;
 end if;
 return true;
end $$;


-- SOURCE v1.0.9: 20261114180508_returning_sessions_across_report_ranges.sql
create or replace function public.admin_analytics(p_from date default null,p_to date default null,p_source text default null,p_plan text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result_ jsonb; lo timestamptz:=coalesce(p_from::timestamp at time zone 'Asia/Kolkata','-infinity'::timestamptz); hi timestamptz:=coalesce((p_to+1)::timestamp at time zone 'Asia/Kolkata','infinity'::timestamptz);
begin
 if not public.is_owner() then raise exception 'forbidden' using errcode='42501'; end if;
 if p_from is not null and p_to is not null and p_from>p_to then raise exception 'Start date must not follow end date'; end if;
 with users_ as(
 select p.id,p.created_at,p.is_guest,coalesce(s.source,'organic') as source from public.profiles p left join private.user_sources s on s.user_id=p.id
 where(nullif(p_source,'') is null or coalesce(s.source,'organic')=p_source)),
 orders_ as(
 select o.*,u.source from public.payment_orders o join users_ u on u.id=o.user_id
 where o.status='paid' and(nullif(p_plan,'') is null or o.plan_code=p_plan)),
 selected_orders as(select * from orders_ where activated_at>=lo and activated_at<hi),
 totals as(select user_id,count(*) as paid_orders from public.payment_orders where status='paid' group by user_id),
 activity as(
 select a.* from private.app_activity a join users_ u on u.id=a.user_id join public.measurement_preferences pref on pref.user_id=a.user_id and pref.analytics
 where a.occurred_at>=lo and a.occurred_at<hi),
 daily as(
 select (activated_at at time zone 'Asia/Kolkata')::date as day,count(*) as orders,sum(amount_paise)/100.0 as activated_revenue,
 coalesce(sum(amount_paise) filter(where bank_verified),0)/100.0 as verified_revenue from selected_orders group by 1 order by 1),
 plans_ as(select plan_code,plan_name,count(*) as orders,sum(amount_paise)/100.0 as revenue,
 coalesce(sum(amount_paise) filter(where bank_verified),0)/100.0 as verified_revenue from selected_orders group by 1,2 order by verified_revenue desc,orders desc),
 repeat_ as(select o.user_id,coalesce(u.email,'Guest') as email,count(*) as orders_in_range,max(t.paid_orders) as lifetime_paid_orders,sum(o.amount_paise)/100.0 as spent
 from selected_orders o join totals t on t.user_id=o.user_id left join auth.users u on u.id=o.user_id
 where t.paid_orders>=2 group by o.user_id,u.email order by spent desc limit 100),
 sources_ as(select u.source,count(*) as new_users from users_ u where created_at>=lo and created_at<hi group by u.source),
 events_ as(select event_name,count(*) as events,count(distinct user_id) as users from activity group by event_name order by events desc)
 select jsonb_build_object(
 'from',p_from,'to',p_to,'timezone','Asia/Kolkata',
 'activated_revenue',coalesce((select sum(amount_paise)/100.0 from selected_orders),0),
 'verified_revenue',coalesce((select sum(amount_paise)/100.0 from selected_orders where bank_verified),0),
 'unverified_revenue',coalesce((select sum(amount_paise)/100.0 from selected_orders where not bank_verified),0),
 'paid_orders',(select count(*) from selected_orders),
 'paying_users',(select count(distinct user_id) from selected_orders),
 'repeat_buyers',(select count(distinct o.user_id) from selected_orders o join totals t on t.user_id=o.user_id where t.paid_orders>=2),
 'new_users',(select count(*) from users_ where created_at>=lo and created_at<hi),
 'new_registrations',(select count(*) from users_ u join auth.users a on a.id=u.id where a.email_confirmed_at>=lo and a.email_confirmed_at<hi and not u.is_guest),
 'active_users',(select count(distinct user_id) from activity),
 'returning_users',(select count(distinct a.user_id) from activity a where exists(select 1 from private.app_activity earlier where earlier.user_id=a.user_id and earlier.session_id<>a.session_id and earlier.occurred_at<a.occurred_at)),
 'sessions',(select count(distinct(user_id,session_id)) from activity),
 'daily',coalesce((select jsonb_agg(to_jsonb(d)) from daily d),'[]'::jsonb),
 'plans',coalesce((select jsonb_agg(to_jsonb(p)) from plans_ p),'[]'::jsonb),
 'repeat_customers',coalesce((select jsonb_agg(to_jsonb(r)) from repeat_ r),'[]'::jsonb),
 'sources',coalesce((select jsonb_agg(to_jsonb(s)) from sources_ s),'[]'::jsonb),
 'events',coalesce((select jsonb_agg(to_jsonb(e)) from events_ e),'[]'::jsonb)
 ) into result_;
 return result_;
end $$;
revoke all on function public.admin_analytics(date,date,text,text) from public,anon;
grant execute on function public.admin_analytics(date,date,text,text) to authenticated;



-- SOURCE v1.0.9: 20261114181113_accurate_delivery_reporting_and_strict_device_context.sql
create or replace function public.admin_meta_overview() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_owner() then raise exception 'forbidden' using errcode='42501'; end if;
 return jsonb_build_object(
 'funnel',coalesce((select jsonb_agg(to_jsonb(r)) from(
 select e.event_name,count(*) filter(where created_at>now()-interval '1 day') as d1,count(*) filter(where created_at>now()-interval '7 days') as d7,count(*) as d30,
 count(*) filter(where status='sent') as sent,count(*) filter(where status='test_sent') as test_sent,count(*) filter(where status='failed') as failed,
 count(*) filter(where fbc is not null) as with_click,
 coalesce(sum(value_inr) filter(where event_name='Purchase' and status='sent' and created_at>now()-interval '7 days'),0) as value_d7,
 coalesce(sum(value_inr) filter(where event_name='Purchase' and status='sent'),0) as value_d30
 from public.meta_events e where created_at>now()-interval '30 days' group by event_name order by event_name)r),'[]'::jsonb),
 'recent',coalesce((select jsonb_agg(to_jsonb(r)) from(select id,event_name,status,value_inr,content_name,attempts,last_error,created_at,sent_at,action_source,meta_trace_id,
 (fbc is not null) as has_click from public.meta_events order by created_at desc limit 60)r),'[]'::jsonb),
 'clicks_7d',(select count(*) from public.ad_clicks where created_at>now()-interval '7 days'),
 'matched_installs_7d',0,'auto_send',(select url<>'' from private.meta_cron where id=1));
end $$;
create or replace function public.admin_meta_retry() returns integer language plpgsql security definer set search_path='' as $$
declare n integer;begin
 if not public.is_owner() then raise exception 'forbidden' using errcode='42501'; end if;
 update public.meta_events e set status='pending',attempts=0,next_attempt_at=now(),lease_until=null
 where e.status='failed' and e.created_at>now()-interval '6 days' and e.advertising_consent
 and e.config_revision=(select revision from public.meta_settings where id=1)
 and(e.user_id is null or exists(select 1 from public.measurement_preferences p where p.user_id=e.user_id and p.advertising));
 get diagnostics n=row_count;perform private.meta_kick();return n;end $$;
create or replace function public.set_measurement_preferences(p_analytics boolean,p_advertising boolean,p_context jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); ext jsonb; install_ text; old_ads boolean; i int; was_recorded boolean;
begin
 if uid is null then raise exception 'session required' using errcode='42501'; end if;
 select advertising into old_ads from public.measurement_preferences where user_id=uid;
 was_recorded:=found;
 insert into public.measurement_preferences(user_id,analytics,advertising,advertising_since) values(uid,p_analytics,p_advertising,case when p_advertising then now() end)
 on conflict(user_id) do update set analytics=excluded.analytics,advertising=excluded.advertising,policy_version='2026-11-14',updated_at=now(),
 advertising_since=case when not excluded.advertising then null when measurement_preferences.advertising then measurement_preferences.advertising_since else now() end;
 if p_advertising then
  ext:=p_context->'extinfo'; install_:=p_context->>'install_id';
  if coalesce(jsonb_typeof(ext),'')<>'array' or jsonb_array_length(ext)<>16 or ext->>0<>'a2' or ext->>1<>'com.vayora.app'
     or coalesce(ext->>4,'')='' or coalesce(install_,'')!~'^[0-9a-f-]{36}$' then raise exception 'valid Android app context required'; end if;
  for i in 0..15 loop
   if coalesce(jsonb_typeof(ext->i),'')<>'string' or length(ext->>i)>120 then raise exception 'invalid app context'; end if;
  end loop;
  insert into private.app_measurement_context(user_id,install_id,app_data)
  values(uid,install_,jsonb_build_object('advertiser_tracking_enabled',1,'application_tracking_enabled',1,'extinfo',ext))
  on conflict(user_id) do update set install_id=excluded.install_id,app_data=excluded.app_data,updated_at=now();
  perform private.touch_attribution(uid);
  if not coalesce(old_ads,false) then perform private.enqueue_meta('AppInstall',uid,null,null); end if;
 else
  update public.meta_events set status='suppressed',last_error='Advertising sharing disabled by the user',fbc=null,fbp=null,client_ip=null,client_ua=null,app_data=null,anon_id=null
   where user_id=uid and status in('pending','processing','failed');
  delete from private.app_measurement_context where user_id=uid;
  delete from private.user_attribution where user_id=uid;
  if not p_analytics then delete from private.app_activity where user_id=uid; end if;
 end if;
 return jsonb_build_object('analytics',p_analytics,'advertising',p_advertising,'policy_version','2026-11-14');
end $$;



-- SOURCE v1.0.9: 20261114181824_respect_independent_analytics_choices_for_retained_activity.sql
CREATE OR REPLACE FUNCTION public.admin_users_filtered(p_search text DEFAULT NULL::text, p_source text DEFAULT NULL::text, p_plan text DEFAULT NULL::text, p_guest boolean DEFAULT NULL::boolean, p_access text DEFAULT NULL::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_customer text DEFAULT NULL::text, p_sort text DEFAULT 'newest'::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result_ jsonb;
begin
 if not public.is_owner() then raise exception 'forbidden' using errcode='42501'; end if;
 if p_from is not null and p_to is not null and p_from>p_to then raise exception 'Start date must not follow end date'; end if;
 with spending as (
  select user_id,count(*) as paid_orders,sum(amount_paise)/100.0 as spent,
  coalesce(sum(amount_paise) filter(where bank_verified),0)/100.0 as verified_spent
  from public.payment_orders where status='paid' group by user_id),
 activity as(select user_id,max(occurred_at) as last_seen,count(distinct session_id) as sessions from private.app_activity a join public.measurement_preferences pref using(user_id) where pref.analytics group by user_id),
 base as(
  select pr.id,u.email,pr.display_name,pr.is_guest,coalesce(us.source,'organic') as source,pr.ads_access_status,pr.used_bytes,pr.created_at,
  current_plan.plan_name,current_plan.plan_ends_at,coalesce(s.paid_orders,0) as paid_orders,coalesce(s.spent,0) as spent,
  coalesce(s.verified_spent,0) as verified_spent,a.last_seen,coalesce(a.sessions,0) as sessions
  from public.profiles pr join auth.users u on u.id=pr.id left join private.user_sources us on us.user_id=pr.id
  left join spending s on s.user_id=pr.id left join activity a on a.user_id=pr.id
  left join lateral(select plan_name,ends_at as plan_ends_at from public.subscriptions where user_id=pr.id and not revoked and ends_at>now() order by ends_at desc limit 1) current_plan on true
  where (nullif(p_search,'') is null or u.email ilike '%'||left(p_search,200)||'%' or pr.display_name ilike '%'||left(p_search,200)||'%' or pr.id::text=p_search)
  and(nullif(p_source,'') is null or coalesce(us.source,'organic')=p_source)
  and(p_guest is null or pr.is_guest=p_guest)
  and(nullif(p_access,'') is null or pr.ads_access_status=p_access)
  and(p_from is null or pr.created_at>=p_from::timestamp at time zone 'Asia/Kolkata')
  and(p_to is null or pr.created_at<(p_to+1)::timestamp at time zone 'Asia/Kolkata')),
 filtered as(select * from base where
  (nullif(p_plan,'') is null or(p_plan='active' and plan_name is not null) or(p_plan='none' and plan_name is null))
  and(nullif(p_customer,'') is null or(p_customer='repeat' and paid_orders>=2) or(p_customer='first' and paid_orders=1) or(p_customer='never' and paid_orders=0) or(p_customer='returning' and sessions>=2))),
 sorted as(select * from filtered order by
  case when p_sort='oldest' then created_at end asc nulls last,
  case when p_sort='spent_high' then spent end desc nulls last,
  case when p_sort='spent_low' then spent end asc nulls last,
  case when p_sort='recently_active' then last_seen end desc nulls last,
  case when p_sort='repeat' then paid_orders end desc nulls last,
  created_at desc,id
  limit least(greatest(p_limit,1),200) offset greatest(p_offset,0))
 select jsonb_build_object('total',(select count(*) from filtered),'rows',coalesce((select jsonb_agg(to_jsonb(s)) from sorted s),'[]'::jsonb)) into result_;
 return result_;
end $function$;

CREATE OR REPLACE FUNCTION public.record_activity(p_event_id uuid, p_name text, p_session_id uuid, p_properties jsonb DEFAULT '{}'::jsonb, p_occurred_at timestamp with time zone DEFAULT now())
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=auth.uid(); pref public.measurement_preferences%rowtype; ctx private.app_measurement_context%rowtype; props jsonb; at_ timestamptz;
begin
 if uid is null then raise exception 'session required' using errcode='42501'; end if;
 if p_name not in('AppOpen','ScreenView','Login','ViewContent','VideoStart','VideoProgress','PreviewComplete','SearchUsed','ChannelCreated','ChannelJoined','VideoUploaded','CloudUploaded','CloudDeleted','PlanViewed','SubscriptionPrompt') then
  raise exception 'event is not permitted'; end if;
 select * into pref from public.measurement_preferences where user_id=uid;
 if not coalesce(pref.analytics,false) and not coalesce(pref.advertising,false) then return false; end if;
 if (select count(*) from private.app_activity where user_id=uid and received_at>now()-interval '1 day')>=5000 then return false; end if;
 at_:=greatest(now()-interval '1 day',least(coalesce(p_occurred_at,now()),now()));
 props:=jsonb_strip_nulls(jsonb_build_object(
 'screen',case when p_properties->>'screen' in('Cloud','Home','Explore','Channel','Profile','Premium','Post','Safety') then p_properties->>'screen' end,
 'media_type',case when p_properties->>'media_type' in('video','image','file') then p_properties->>'media_type' end,
 'progress',case when p_properties->>'progress' in('25','50','75','100') then (p_properties->>'progress')::int end,
 'preview',case when jsonb_typeof(p_properties->'preview')='boolean' then p_properties->'preview' end,
 'premium',case when jsonb_typeof(p_properties->'premium')='boolean' then p_properties->'premium' end));
 -- Store one minimal activity row for deduplication/consented analytics, never arbitrary text or content identifiers.
 insert into private.app_activity(event_id,user_id,session_id,event_name,properties,occurred_at) values(p_event_id,uid,p_session_id,p_name,props,at_)
 on conflict(event_id) do nothing;
 if not found then return false; end if;
 if pref.advertising then perform private.touch_attribution(uid); end if;
 if pref.advertising and at_>=coalesce(pref.advertising_since,pref.updated_at) and private.meta_ready() then
  select * into ctx from private.app_measurement_context where user_id=uid;
  if ctx.user_id is not null then
   insert into public.meta_events(event_name,event_id,user_id,created_at,action_source,app_data,anon_id,advertising_consent,config_revision,custom_data,client_ip,client_ua)
   values(p_name,'activity-'||p_event_id::text,uid,at_,'app',ctx.app_data,ctx.install_id,true,
    (select revision from public.meta_settings where id=1),props,private.req_ip(),left(private.req_header('user-agent'),400)) on conflict(event_id) do nothing;
  end if;
 end if;
 return true;
end $function$;


-- SOURCE v1.0.9: 20261114215818_admin_customer_purchase_history.sql
-- Purchase history is for the owner admin only. No repeat-buyer labels enter advertising payloads.
create or replace function public.admin_customer_purchases(p_user uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result_ jsonb;
begin
 if not public.is_owner() then raise exception 'forbidden' using errcode='42501';end if;
 with paid as(select id,plan_code,plan_name,amount_paise,activated_at,bank_verified,reference,
 lag(plan_code) over(order by activated_at,id) as previous_code,
 lag(plan_name) over(order by activated_at,id) as previous_plan,
 lag(amount_paise) over(order by activated_at,id) as previous_amount
 from public.payment_orders where user_id=p_user and status='paid'),
 history as(select id,plan_code,plan_name,amount_paise/100.0 as amount_inr,activated_at,bank_verified,reference,previous_plan,previous_amount/100.0 as previous_amount_inr,
 case when previous_code is null then 'First purchase' when plan_code=previous_code then 'Same plan' when amount_paise>previous_amount then 'Higher-priced plan' when amount_paise<previous_amount then 'Lower-priced plan' else 'Different plan, same price' end as change
 from paid order by activated_at desc,id desc limit 200)
 select jsonb_build_object('user_id',p_user,'email',(select email from auth.users where id=p_user),'paid_orders',(select count(*) from paid),
 'spent',coalesce((select sum(amount_paise)/100.0 from paid),0),'history',coalesce((select jsonb_agg(to_jsonb(h)) from history h),'[]'::jsonb)) into result_;
 return result_;
end $$;
revoke all on function public.admin_customer_purchases(uuid) from public,anon;grant execute on function public.admin_customer_purchases(uuid) to authenticated;

-- Preserve old records under their original IDs. Auth users and storage objects never move.
-- Disable only application triggers while importing, leaving foreign keys active.
do $$declare r record;begin
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  execute format('alter table %I.%I disable trigger user',r.schemaname,r.tablename);
 end loop;
end$$;
delete from public.plans; -- only the new empty schema's sample plans
delete from public.settings_audit; -- discard seed-configuration audit rows before restoring history
insert into public.profiles(id,display_name,avatar_url,is_guest,used_bytes,ads_access_status,created_at)
select id,display_name,avatar_url,is_guest,used_bytes,ads_access_status::text,created_at from vayora_legacy_20261115.profiles;
insert into public.admins(user_id,role) select user_id,role from vayora_legacy_20261115.admins;
insert into public.plans(id,code,name,duration_days,price_inr,perks,active,position,badge,created_at,updated_at,free_eligible)
select id,code,name,duration_days,price_inr,perks,active,position,badge,created_at,updated_at,free_eligible from vayora_legacy_20261115.plans;
-- UUID promo identifiers receive a stable one-to-one integer mapping.
create table private.legacy_promo_map(old_id uuid primary key,new_id integer generated always as identity unique);
alter table private.legacy_promo_map enable row level security;
insert into private.legacy_promo_map(old_id)
select promo_id from vayora_legacy_20261115.app_mode union select promo_id from vayora_legacy_20261115.free_plan_claims;
update public.app_mode n set free_mode=o.free_mode,free_plans_for=o.free_plans_for,plans_visible_for=o.plans_visible_for,promo_id=m.new_id
from vayora_legacy_20261115.app_mode o join private.legacy_promo_map m on m.old_id=o.promo_id where n.id=1;
update public.payment_settings n set upi_id=coalesce(o.upi_id,''),payee_name=coalesce(o.payee_name,''),enabled=o.enabled,activation_mode=o.activation_mode
from vayora_legacy_20261115.payment_settings o where n.id=1;
update public.plan_catalog n set revision=o.revision from vayora_legacy_20261115.plan_catalog o where n.id=1;
insert into private.user_sources(user_id,source,created_at) select user_id,source,created_at from vayora_legacy_private_20261115.user_sources;
insert into public.installs(install_id,user_id,source,referrer_status,raw_referrer,utm_campaign,created_at)
select install_id::text,user_id,source,referrer_status,raw_referrer,utm_campaign,created_at from vayora_legacy_20261115.installs;
insert into public.consents(user_id,policy_version,accepted_at) select user_id,policy_version,accepted_at from vayora_legacy_20261115.consents;
insert into public.channels(id,name,description,category,tags,icon_url,audience,status,review_status,created_by,members_count,hidden,created_at)
select id,name,description,category,tags,icon_url,audience::text,case when status in ('published','active') then 'published' else 'draft' end,review_status,created_by,members_count,status='hidden',created_at from vayora_legacy_20261115.channels;
insert into public.admin_channel_access select * from vayora_legacy_20261115.admin_channel_access;
insert into public.channel_members(channel_id,user_id,joined_at) select channel_id,user_id,created_at from vayora_legacy_20261115.channel_members;
insert into public.channel_folders(id,channel_id,name) select id,channel_id,name from vayora_legacy_20261115.channel_folders;
insert into public.posts(id,channel_id,title,description,audience,status,publish_at,created_by,hidden,created_at)
select id,channel_id,title,description,audience::text,case when status in ('published','scheduled') then status else 'draft' end,publish_at,created_by,status='hidden',created_at from vayora_legacy_20261115.posts;
insert into public.post_items(id,post_id,media_key,thumbnail_key,trailer_key,mime,duration_s,is_premium,position)
select id,post_id,media_key,thumbnail_key,trailer_key,mime,duration_s,is_premium,position from vayora_legacy_20261115.post_items;
-- Keep historical payments even after account deletion, just as Vayora did before.
alter table public.payment_orders alter column user_id drop not null;
alter table public.subscriptions alter column user_id drop not null;
alter table public.payment_orders drop constraint payment_orders_user_id_fkey;
alter table public.payment_orders add constraint payment_orders_user_id_fkey foreign key(user_id) references auth.users(id) on delete set null;
alter table public.subscriptions drop constraint subscriptions_user_id_fkey;
alter table public.subscriptions add constraint subscriptions_user_id_fkey foreign key(user_id) references auth.users(id) on delete set null;
insert into public.payment_orders(id,user_id,plan_id,plan_code,plan_name,amount_paise,duration_days,reference,upi_id_used,payee_used,status,raw_result,txn_id,utr,success_reported,activated_at,activation_kind,bank_verified,bank_verified_at,admin_note,created_at,updated_at)
select o.id,o.user_id,o.plan_id,p.code,p.name,o.amount_paise,o.duration_days,o.reference,o.upi_id_used,o.payee_used,o.status,o.raw_response,o.txn_id,o.utr,coalesce(upper(o.client_status)='SUCCESS',o.status='paid'),o.paid_at,
case when o.paid_at is null then null when o.auto_activated then 'auto' when o.verification_source in ('provider_api','bank_credit') then 'webhook' else 'manual' end,
o.bank_verified_at is not null,o.bank_verified_at,coalesce(o.reason,o.result_note),o.created_at,o.updated_at
from vayora_legacy_20261115.payment_orders o join public.plans p on p.id=o.plan_id;
insert into public.subscriptions(id,user_id,plan_id,plan_code,plan_name,kind,order_id,starts_at,ends_at,revoked,created_at)
select s.id,s.user_id,s.plan_id,p.code,p.name,
case when exists(select 1 from vayora_legacy_20261115.free_plan_claims f where f.subscription_id=s.id) then 'free_promo' when s.order_id is null then 'admin_grant' else 'payment' end,
s.order_id,s.starts_at,s.ends_at,s.revoked_at is not null,s.starts_at
from vayora_legacy_20261115.subscriptions s join public.plans p on p.id=s.plan_id;
insert into private.used_payment_utrs(txn_id,order_id,created_at) select utr,order_id,created_at from vayora_legacy_private_20261115.used_payment_utrs;
insert into public.free_plan_claims(id,user_id,plan_id,promo_id,subscription_id,created_at)
select f.id,f.user_id,f.plan_id,m.new_id,f.subscription_id,f.created_at from vayora_legacy_20261115.free_plan_claims f join private.legacy_promo_map m on m.old_id=f.promo_id;
insert into public.support_requests(id,user_id,kind,target_type,target_id,reason,details,email,status,created_at)
select id,user_id,case when kind='deletion' then 'deletion' when kind='content' then 'report' else 'other' end,
case when post_id is not null then 'post' when channel_id is not null then 'channel' else 'account' end,coalesce(post_id,channel_id,user_id),reason,details,email,status,created_at from vayora_legacy_20261115.support_requests;
insert into public.settings_audit(id,table_name,row_key,field,old_value,new_value,changed_by,changed_at) overriding system value
select id,table_name,record_id,field,old_value,new_value,changed_by,changed_at from vayora_legacy_20261115.settings_audit;
select setval(pg_get_serial_sequence('public.settings_audit','id'),greatest(coalesce((select max(id) from public.settings_audit),0),1),exists(select 1 from public.settings_audit));
insert into public.cloud_folders(id,user_id,parent_id,name,created_at)
select id,user_id,parent_id,name,created_at from vayora_legacy_20261115.cloud_files where is_folder;
insert into public.cloud_files(id,user_id,folder_id,name,storage_path,mime,size_bytes,created_at)
select id,user_id,parent_id,name,storage_key,mime,size,created_at from vayora_legacy_20261115.cloud_files where not is_folder and ready and not deleting;
update public.meta_settings n set pixel_id=o.pixel_id,capi_token=coalesce(o.api_token,''),test_event_code=o.test_code,enabled=o.enabled
from vayora_legacy_private_20261115.admin_meta_settings o where n.id=1;
update private.meta_cron set url='https://fzloulsjhkdxwagonsgt.supabase.co/functions/v1/meta-send' where id=1;
-- Legacy delivery logs remain archived; do not replay events without new consent.
insert into public.ad_clicks(id,fbclid,fbc,fbp,ip,user_agent,created_at)
select id,fbclid,fbc,fbp,client_ip::text,user_agent,created_at from vayora_legacy_private_20261115.ad_clicks;
do $$declare r record;begin
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  execute format('alter table %I.%I enable trigger user',r.schemaname,r.tablename);
 end loop;
end$$;
-- Fail the whole transaction if any account, financial record or content ID is lost.
do $$declare name text;before_count bigint;after_count bigint;begin
 foreach name in array array['profiles','admins','plans','installs','consents','channels','posts','post_items','payment_orders','subscriptions','support_requests','free_plan_claims','settings_audit'] loop
  execute format('select count(*) from vayora_legacy_20261115.%I',name) into before_count;
  execute format('select count(*) from public.%I',name) into after_count;
  if before_count<>after_count then raise exception 'Migration row count mismatch: %',name;end if;
 end loop;
 if exists(select 1 from vayora_legacy_20261115.payment_orders o left join public.payment_orders n using(id) where n.id is null or n.amount_paise<>o.amount_paise or n.status<>o.status or n.user_id is distinct from o.user_id) then raise exception 'Payment preservation failed';end if;
 if exists(select 1 from vayora_legacy_20261115.subscriptions o left join public.subscriptions n using(id) where n.id is null or n.ends_at<>o.ends_at or n.starts_at<>o.starts_at or n.user_id is distinct from o.user_id or n.revoked<>(o.revoked_at is not null)) then raise exception 'Subscription preservation failed';end if;
 if exists(select 1 from vayora_legacy_20261115.cloud_files where not is_folder and (not ready or deleting)) then raise exception 'Finish pending cloud operations before migration';end if;
end$$;
notify pgrst,'reload schema';


