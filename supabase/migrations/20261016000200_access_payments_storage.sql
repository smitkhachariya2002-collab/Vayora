create table public.plans (
 id uuid primary key default gen_random_uuid(), code text not null unique, name text not null,
 duration_days integer not null check(duration_days>0), price_inr numeric(10,2) not null check(price_inr>0),
 perks jsonb not null default '[]', active boolean not null default true, position integer not null default 0
);
insert into public.plans(code,name,duration_days,price_inr,perks,position) values
 ('trial','Trial',7,49,'["2 TB cloud storage","Full premium videos","Fast upload & download"]',0),
 ('silver','Silver',7,129,'["2 TB cloud storage","Full premium videos","Fast upload & download"]',1),
 ('gold','Gold',30,259,'["2 TB cloud storage","Full premium videos","Fast upload & download"]',2),
 ('platinum','Platinum',180,599,'["2 TB cloud storage","Full premium videos","Fast upload & download"]',3),
 ('diamond','Diamond',365,999,'["2 TB cloud storage","Full premium videos","Fast upload & download"]',4);
create table public.payment_settings (
 id boolean primary key default true check(id), upi_id text, payee_name text, enabled boolean not null default false
);
-- Payments remain disabled until the owner enters real UPI details.
insert into public.payment_settings(id) values(true);
create table public.payment_orders (
 id uuid primary key default gen_random_uuid(), user_id uuid references auth.users on delete set null,
 plan_id uuid not null references public.plans, amount_paise bigint not null check(amount_paise>0),
 duration_days integer not null check(duration_days>0), reference text not null unique,
 status text not null default 'created' check(status in ('created','pending','success','failed','cancelled','revoked')),
 utr text unique, raw_response text, reason text, created_at timestamptz not null default now(), paid_at timestamptz
);
create index orders_user_idx on public.payment_orders(user_id,created_at desc);
create index orders_plan_idx on public.payment_orders(plan_id);
create index orders_open_idx on public.payment_orders(created_at) where status in ('created','pending');
create table public.subscriptions (
 id uuid primary key default gen_random_uuid(), user_id uuid references auth.users on delete set null,
 plan_id uuid not null references public.plans, starts_at timestamptz not null, ends_at timestamptz not null,
 source text not null check(source in ('upi_app','admin','provider_api')), order_id uuid unique references public.payment_orders,
 revoked_at timestamptz, check(ends_at>=starts_at)
);
create index subscriptions_user_idx on public.subscriptions(user_id,ends_at);
create index subscriptions_plan_idx on public.subscriptions(plan_id);
create table public.payment_events (
 id bigint generated always as identity primary key, order_id uuid not null references public.payment_orders,
 kind text not null, detail text, created_at timestamptz not null default now()
);
create index payment_events_order_idx on public.payment_events(order_id);
create table public.support_requests (
 id uuid primary key default gen_random_uuid(), user_id uuid references auth.users on delete set null,
 post_id uuid references public.posts on delete set null, channel_id uuid references public.channels on delete set null,
 kind text not null default 'content', email text, reason text not null, details text not null default '',
 status text not null default 'open' check(status in ('open','closed')), created_at timestamptz not null default now()
);
create index support_user_idx on public.support_requests(user_id);
create index support_post_idx on public.support_requests(post_id);
create index support_channel_idx on public.support_requests(channel_id);

create function public.free_mode() returns boolean language sql stable set search_path=''
as $$ select free_mode from public.app_mode where id $$;
create function private.has_plan() returns boolean language sql stable security definer set search_path=''
as $$ select auth.uid() is not null and exists(select 1 from public.subscriptions
 where user_id=auth.uid() and revoked_at is null and starts_at<=now() and ends_at>now()) $$;
-- In paid mode, organic ads access requires BOTH approval and an active plan.
create or replace function private.has_ads_access() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (private.source_of(auth.uid())='ads' or
 (exists(select 1 from public.profiles where id=auth.uid() and ads_access_status='approved')
 and (private.has_plan() or exists(select 1 from public.app_mode where id and free_mode))))
$$;
create function private.is_premium_user() returns boolean language sql stable security definer set search_path='' as $$
 select private.is_member() and case when exists(select 1 from public.app_mode where id and free_mode)
 then private.has_ads_access() else private.has_plan() end
$$;
create function public.is_premium_user() returns boolean language sql stable set search_path='' as $$ select private.is_premium_user() $$;
create function private.quota_bytes(p_user uuid) returns bigint language sql stable security definer set search_path='' as $$
 select case when p_user<>auth.uid() or not private.is_member() then 0::bigint
 when exists(select 1 from public.app_mode where id and free_mode) then 16106127360::bigint
 when private.has_plan() then 2199023255552::bigint else 0::bigint end
$$;
create function public.quota_bytes(user_id uuid) returns bigint language sql stable set search_path='' as $$ select private.quota_bytes(user_id) $$;

create function private.request_full_access() returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.is_member() then raise exception 'Login required'; end if;
 if not exists(select 1 from public.app_mode where id and free_mode) then raise exception 'Full access requests require free mode'; end if;
 update public.profiles set ads_access_status='pending' where id=auth.uid() and ads_access_status in ('none','rejected');
end $$;
create function public.request_full_access() returns void language sql set search_path='' as $$ select private.request_full_access() $$;
create function private.set_ads_access(p_user uuid,p_status public.access_status) returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 update public.profiles set ads_access_status=p_status where id=p_user;
 insert into public.audit_logs(actor_id,action,target_id) values(auth.uid(),'ads_access:'||p_status::text,p_user::text);
end $$;
create function public.set_ads_access(user_id uuid,status public.access_status) returns void language sql set search_path=''
as $$ select private.set_ads_access(user_id,status) $$;

create function private.create_payment_order(p_plan uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare pl public.plans; settings public.payment_settings; ord public.payment_orders;
begin
 if not private.is_member() then raise exception 'Login required'; end if;
 if not exists(select 1 from public.app_mode where id and not free_mode) then raise exception 'Payments unavailable in free mode'; end if;
 select * into settings from public.payment_settings where id and enabled and length(upi_id)>2 and length(payee_name)>0;
 if not found then raise exception 'Payments are not configured yet'; end if;
 -- Serialize all orders for this user, including different plans.
 perform 1 from public.profiles where id=auth.uid() for update;
 select * into pl from public.plans where id=p_plan and active;
 if not found then raise exception 'Plan unavailable'; end if;
 update public.payment_orders set status='cancelled',reason='Replaced or expired'
 where user_id=auth.uid() and status in ('created','pending') and (plan_id<>p_plan or created_at<=now()-interval '24 hours');
 select * into ord from public.payment_orders where user_id=auth.uid() and plan_id=p_plan
 and status in ('created','pending') and created_at>now()-interval '24 hours' order by created_at desc limit 1 for update;
 if not found then
 insert into public.payment_orders(user_id,plan_id,amount_paise,duration_days,reference)
 values(auth.uid(),p_plan,(pl.price_inr*100)::bigint,pl.duration_days,
 'VY'||to_char(now(),'YYMMDD')||encode(extensions.gen_random_bytes(6),'hex')) returning * into ord;
 end if;
 return to_jsonb(ord)||jsonb_build_object('upi_id',settings.upi_id,'payee_name',settings.payee_name);
end $$;
create function public.create_payment_order(plan_id uuid) returns jsonb language sql set search_path='' as $$ select private.create_payment_order(plan_id) $$;

-- Only trusted owner/provider paths call this. No mobile response can authenticate a bank transfer.
create function private.activate_payment(p_order uuid,p_amount bigint,p_utr text,p_source text) returns void language plpgsql security definer set search_path='' as $$
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
 update public.profiles set ads_access_status='pending' where id=ord.user_id and ads_access_status='none';
 end if;
 insert into public.payment_events(order_id,kind) values(p_order,'activated');
end $$;
create function private.report_payment_result(p_order uuid,p_raw text) returns text language plpgsql security definer set search_path='' as $$
declare ord public.payment_orders; st text; ref text; tx text; why text;
begin
 if auth.uid() is null then raise exception 'Login required'; end if;
 if length(p_raw)>8192 then raise exception 'Response too long'; end if;
 select * into ord from public.payment_orders where id=p_order and user_id=auth.uid() for update;
 if not found then raise exception 'Order unavailable'; end if;
 if ord.status not in ('created','pending') then return ord.status; end if;
 st=upper(coalesce(private.url_decode(private.query_param(p_raw,'Status')),private.url_decode(private.query_param(p_raw,'status')),''));
 ref=coalesce(private.url_decode(private.query_param(p_raw,'txnRef')),private.url_decode(private.query_param(p_raw,'txnref')));
 tx=coalesce(nullif(private.url_decode(private.query_param(p_raw,'ApprovalRefNo')),''),private.url_decode(private.query_param(p_raw,'txnId')));
 why=case when ref is not null and ref<>ord.reference then 'Reference mismatch'
 when tx is null or tx !~ '^[A-Za-z0-9]{6,40}$' then 'Missing or invalid transaction ID'
 when exists(select 1 from public.payment_orders where utr=tx) then 'Transaction already used'
 when ord.created_at<=now()-interval '2 hours' then 'Late response'
 else 'Awaiting bank verification by owner' end;
 update public.payment_orders set status=case when st in ('FAILURE','FAILED') then 'failed' else 'pending' end,
 raw_response=p_raw,reason=why where id=p_order returning * into ord;
 insert into public.payment_events(order_id,kind,detail) values(p_order,'client_response',why);
 return ord.status;
end $$;
create function public.report_payment_result(order_id uuid,raw text) returns text language sql set search_path='' as $$ select private.report_payment_result(order_id,raw) $$;
create function private.admin_mark_payment_paid(p_order uuid,p_utr text) returns void language plpgsql security definer set search_path='' as $$
declare amount bigint;
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 select amount_paise into amount from public.payment_orders where id=p_order;
 perform private.activate_payment(p_order,amount,p_utr,'admin');
 insert into public.audit_logs(actor_id,action,target_id) values(auth.uid(),'mark_payment_paid',p_order::text);
end $$;
create function public.admin_mark_payment_paid(order_id uuid,utr text) returns void language sql set search_path='' as $$ select private.admin_mark_payment_paid(order_id,utr) $$;
create function private.admin_revoke_payment(p_order uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.is_owner() or length(trim(p_reason))=0 then raise exception 'Owner and reason required'; end if;
 perform 1 from public.payment_orders where id=p_order and status='success' for update;
 if not found then raise exception 'Successful order required'; end if;
 update public.payment_orders set status='revoked',reason=p_reason where id=p_order;
 update public.subscriptions set revoked_at=now() where order_id=p_order;
 insert into public.audit_logs(actor_id,action,target_id) values(auth.uid(),'revoke_payment:'||p_reason,p_order::text);
end $$;
create function public.admin_revoke_payment(order_id uuid,reason text) returns void language sql set search_path='' as $$ select private.admin_revoke_payment(order_id,reason) $$;
create function private.cancel_stale_payment_orders() returns void language sql security definer set search_path='' as $$
 update public.payment_orders set status='cancelled',reason='Expired after 24 hours' where status in ('created','pending') and created_at<now()-interval '24 hours'
$$;
select cron.schedule('vayora-cancel-orders','*/30 * * * *','select private.cancel_stale_payment_orders()');

create function private.can_read_media(p_key text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.post_items i join public.posts p on p.id=i.post_id
 where (i.media_key=p_key or i.trailer_key=p_key) and
 (private.is_admin() or p.created_by=auth.uid() or
 (private.visible_post(p.id) and
 ((i.media_key=p_key and private.is_member() and (not i.is_premium or private.is_premium_user()))
 or (i.trailer_key=p_key and private.has_ads_access())))))
$$;
create function public.can_read_media(key text) returns boolean language sql stable set search_path='' as $$ select private.can_read_media(key) $$;
create function private.manage_media(p_key text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.posts p where
 split_part(p_key,'/',1)=p.created_by::text and split_part(p_key,'/',2)=p.id::text and private.manage_channel(p.channel_id))
$$;
create function private.item_keys_guard() returns trigger language plpgsql set search_path='' as $$
declare owner_id uuid;
begin
 select created_by into owner_id from public.posts where id=new.post_id;
 if new.media_key not like owner_id::text||'/'||new.post_id::text||'/%'
 or (new.trailer_key is not null and new.trailer_key not like owner_id::text||'/'||new.post_id::text||'/%') then
 raise exception 'Media must use the creator/post path'; end if;
 return new;
end $$;
create trigger item_keys_guard before insert or update on public.post_items for each row execute function private.item_keys_guard();

create function private.my_status() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',p.id,'display_name',p.display_name,'avatar_url',p.avatar_url,'is_guest',p.is_guest,
 'source',private.source_of(p.id),'has_ads_access',private.has_ads_access(),'is_premium',private.is_premium_user(),
 'plan_name',(select pl.name from public.subscriptions s join public.plans pl on pl.id=s.plan_id where s.user_id=p.id and s.revoked_at is null and s.starts_at<=now() and s.ends_at>now() order by s.ends_at desc limit 1),
 'plan_ends_at',(select max(ends_at) from public.subscriptions where user_id=p.id and revoked_at is null and starts_at<=now() and ends_at>now()),
 'used_bytes',p.used_bytes,'quota_bytes',private.quota_bytes(p.id),'free_mode',m.free_mode,
 'paid_enabled',not m.free_mode,'access_status',p.ads_access_status)
 from public.profiles p cross join public.app_mode m where p.id=auth.uid()
$$;
create function public.my_status() returns jsonb language sql stable set search_path='' as $$ select private.my_status() $$;
create function private.report_content(p_post uuid,p_channel uuid,p_reason text,p_details text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or length(trim(p_reason))=0 or length(p_details)>4000 then raise exception 'Invalid report'; end if;
 if p_post is null and p_channel is null then raise exception 'Report target required'; end if;
 insert into public.support_requests(user_id,post_id,channel_id,reason,details) values(auth.uid(),p_post,p_channel,left(p_reason,200),p_details);
end $$;
create function public.report_content_in_app(post_id uuid,channel_id uuid,reason text,details text) returns void language sql set search_path=''
as $$ select private.report_content(post_id,channel_id,reason,details) $$;

do $$ declare t text; begin
 foreach t in array array['plans','payment_settings','payment_orders','subscriptions','payment_events','support_requests'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;
grant select on public.plans,public.payment_settings,public.payment_orders,public.subscriptions,public.payment_events,public.support_requests to authenticated;
grant insert,update,delete on public.plans to authenticated;
grant update on public.payment_settings,public.support_requests to authenticated;
create policy plans_read on public.plans for select to authenticated using((select private.is_owner()) or
 (active and exists(select 1 from public.app_mode where not free_mode)));
create policy plans_create on public.plans for insert to authenticated with check((select private.is_owner()));
create policy plans_edit on public.plans for update to authenticated using((select private.is_owner())) with check((select private.is_owner()));
create policy plans_delete on public.plans for delete to authenticated using((select private.is_owner()));
create policy payment_settings_read on public.payment_settings for select to authenticated using((select private.is_owner()));
create policy payment_settings_edit on public.payment_settings for update to authenticated using((select private.is_owner())) with check((select private.is_owner()));
create policy orders_read on public.payment_orders for select to authenticated using(user_id=(select auth.uid()) or (select private.is_owner()));
create policy subscriptions_read on public.subscriptions for select to authenticated using(user_id=(select auth.uid()) or (select private.is_owner()));
create policy events_read on public.payment_events for select to authenticated using((select private.is_owner()));
create policy support_read on public.support_requests for select to authenticated using(user_id=(select auth.uid()) or (select private.is_owner()));
create policy support_edit on public.support_requests for update to authenticated using((select private.is_owner())) with check((select private.is_owner()));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('media','media',false,52428800,null),
 ('public','public',true,52428800,array['image/jpeg','image/png','image/webp']),
 ('cloud','cloud',false,52428800,null),
 ('downloads','downloads',true,52428800,array['application/vnd.android.package-archive','application/octet-stream'])
on conflict(id) do nothing;
create policy media_read on storage.objects for select to authenticated using(bucket_id='media' and private.can_read_media(name));
create policy media_upload on storage.objects for insert to authenticated with check(bucket_id='media' and private.manage_media(name) and (select private.is_member()));
create policy media_update on storage.objects for update to authenticated using(bucket_id='media' and private.manage_media(name))
 with check(bucket_id='media' and private.manage_media(name));
create policy media_delete on storage.objects for delete to authenticated using(bucket_id='media' and private.manage_media(name));
create policy public_images_read on storage.objects for select to authenticated using(bucket_id='public');
create policy public_images_upload on storage.objects for insert to authenticated with check(bucket_id='public' and (storage.foldername(name))[1]=(select auth.uid())::text and (select private.is_member()));
create policy public_images_edit on storage.objects for update to authenticated using(bucket_id='public' and (storage.foldername(name))[1]=(select auth.uid())::text)
 with check(bucket_id='public' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy public_images_delete on storage.objects for delete to authenticated using(bucket_id='public' and (storage.foldername(name))[1]=(select auth.uid())::text);
-- Cloud writes stay closed until atomic quota reservations/upload finalization are implemented.
create policy cloud_read on storage.objects for select to authenticated using(bucket_id='cloud' and (storage.foldername(name))[1]=(select auth.uid())::text and (select private.is_member()));
create policy downloads_read on storage.objects for select to anon,authenticated using(bucket_id='downloads');
create policy downloads_upload on storage.objects for insert to authenticated with check(bucket_id='downloads' and (select private.is_owner()));
create policy downloads_edit on storage.objects for update to authenticated using(bucket_id='downloads' and (select private.is_owner())) with check(bucket_id='downloads' and (select private.is_owner()));
create policy downloads_delete on storage.objects for delete to authenticated using(bucket_id='downloads' and (select private.is_owner()));

revoke execute on all functions in schema private from public,anon,authenticated;
grant execute on function private.is_owner(),private.is_admin(),private.is_member(),private.source_of(uuid),private.has_ads_access(),
 private.manage_channel(uuid),private.visible_channel(uuid),private.visible_post(uuid),private.record_install(uuid,text,text,text),private.attribute_user(uuid,text),
 private.is_premium_user(),private.quota_bytes(uuid),private.request_full_access(),private.set_ads_access(uuid,public.access_status),
 private.create_payment_order(uuid),private.report_payment_result(uuid,text),private.admin_mark_payment_paid(uuid,text),private.admin_revoke_payment(uuid,text),
 private.can_read_media(text),private.manage_media(text),private.my_status(),private.report_content(uuid,uuid,text,text) to authenticated;
revoke execute on all functions in schema public from public,anon;
grant execute on function public.free_mode(),public.is_premium_user(),public.quota_bytes(uuid),public.request_full_access(),public.set_ads_access(uuid,public.access_status),
 public.create_payment_order(uuid),public.report_payment_result(uuid,text),public.admin_mark_payment_paid(uuid,text),public.admin_revoke_payment(uuid,text),
 public.can_read_media(text),public.my_status(),public.report_content_in_app(uuid,uuid,text,text) to authenticated;
