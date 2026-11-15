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


