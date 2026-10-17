-- Part C: reserved personal-cloud quota and private file access.
create table public.cloud_files(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users on delete cascade,
 parent_id uuid references public.cloud_files(id) on delete cascade,name text not null,
 is_folder boolean not null default false,storage_key text unique,mime text not null default 'application/octet-stream',
 size bigint not null default 0,ready boolean not null default false,deleting boolean not null default false,
 created_at timestamptz not null default now(),
 check(size between 0 and 52428800),
 check((is_folder and storage_key is null and size=0) or
       (not is_folder and storage_key is not null and storage_key=user_id::text||'/'||id::text)));
create index cloud_files_parent_idx on public.cloud_files(user_id,parent_id,created_at);
alter table public.cloud_files enable row level security;
revoke all on public.cloud_files from public,anon,authenticated;
grant select on public.cloud_files to authenticated;
grant update(name,parent_id) on public.cloud_files to authenticated;
grant all on public.cloud_files to service_role;
create policy cloud_files_read on public.cloud_files for select to authenticated using(user_id=(select auth.uid()));
create policy cloud_files_edit on public.cloud_files for update to authenticated using(user_id=(select auth.uid()))
 with check(user_id=(select auth.uid()));

create function private.cloud_tree_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare parent public.cloud_files;
begin
 perform 1 from public.profiles where id=new.user_id for update;
 if length(btrim(new.name)) not between 1 and 255 or new.name in ('.','..') or position('/' in new.name)>0 or position(chr(92) in new.name)>0 then raise exception 'Invalid file name'; end if;
 if TG_OP='UPDATE' and (new.id<>old.id or new.user_id<>old.user_id or new.is_folder<>old.is_folder
 or new.size<>old.size or new.storage_key is distinct from old.storage_key) then raise exception 'Protected cloud fields'; end if;
 if new.parent_id is not null then
 select * into parent from public.cloud_files where id=new.parent_id;
 if not found or parent.user_id<>new.user_id or not parent.is_folder then raise exception 'Invalid folder'; end if;
 if exists(with recursive ancestors as(
   select id,parent_id,deleting from public.cloud_files where id=new.parent_id
   union select p.id,p.parent_id,p.deleting from public.cloud_files p join ancestors a on p.id=a.parent_id
 ) select 1 from ancestors where id=new.id or deleting) then raise exception 'Invalid or deleting folder'; end if;
 end if;
 if TG_OP='UPDATE' and old.deleting and not new.deleting then raise exception 'Deletion already started'; end if;
 return new;
end $$;
revoke all on function private.cloud_tree_guard() from public,anon,authenticated;
create trigger cloud_tree_guard before insert or update on public.cloud_files for each row execute function private.cloud_tree_guard();

create function private.cloud_quota_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare used bigint; allowance bigint;
begin
 if TG_OP='INSERT' then
   if auth.uid() is distinct from new.user_id or not private.is_member() then raise exception 'Login required'; end if;
   select used_bytes into used from public.profiles where id=new.user_id for update;
   allowance=private.quota_bytes(new.user_id);
   if allowance<=0 then raise exception 'Storage access required'; end if;
   if used+new.size>allowance then raise exception 'storage quota exceeded'; end if;
   update public.profiles set used_bytes=used_bytes+new.size where id=new.user_id;
   return new;
 else
   perform 1 from public.profiles where id=old.user_id for update;
   update public.profiles set used_bytes=greatest(0,used_bytes-old.size) where id=old.user_id;
   return old;
 end if;
end $$;
revoke all on function private.cloud_quota_guard() from public,anon,authenticated;
create trigger cloud_quota_insert before insert on public.cloud_files for each row execute function private.cloud_quota_guard();
create trigger cloud_quota_delete after delete on public.cloud_files for each row execute function private.cloud_quota_guard();

create function public.cloud_reserve(name text,parent_id uuid default null,is_folder boolean default false,
 mime text default 'application/octet-stream',size bigint default 0)
returns public.cloud_files language plpgsql security definer set search_path='' as $$
declare entry public.cloud_files; key uuid=gen_random_uuid();
begin
 if not private.is_member() then raise exception 'Login required'; end if;
 if size<0 or size>52428800 then raise exception '50 MB maximum per file'; end if;
 if length(mime)>160 then raise exception 'Invalid file type'; end if;
 insert into public.cloud_files(id,user_id,parent_id,name,is_folder,storage_key,mime,size,ready)
 values(key,auth.uid(),parent_id,btrim(name),is_folder,case when is_folder then null else auth.uid()::text||'/'||key::text end,
 mime,case when is_folder then 0 else size end,is_folder) returning * into entry;
 return entry;
end $$;
revoke all on function public.cloud_reserve(text,uuid,boolean,text,bigint) from public,anon;
grant execute on function public.cloud_reserve(text,uuid,boolean,text,bigint) to authenticated;

create function public.cloud_finish_upload(user_id uuid,entry_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare entry public.cloud_files; actual bigint;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 perform 1 from public.profiles where id=user_id for update;
 select * into entry from public.cloud_files f where f.id=entry_id and f.user_id=cloud_finish_upload.user_id for update;
 if not found or entry.is_folder or entry.deleting then raise exception 'Upload unavailable'; end if;
 if exists(with recursive ancestors as(select id,parent_id,deleting from public.cloud_files where id=entry.parent_id
 union select p.id,p.parent_id,p.deleting from public.cloud_files p join ancestors a on p.id=a.parent_id)
 select 1 from ancestors where deleting) then raise exception 'Folder deleting'; end if;
 select (metadata->>'size')::bigint into actual from storage.objects where bucket_id='cloud' and name=entry.storage_key;
 if actual is null or actual<>entry.size then raise exception 'Uploaded size mismatch'; end if;
 update public.cloud_files set ready=true where id=entry.id;
end $$;
revoke all on function public.cloud_finish_upload(uuid,uuid) from public,anon,authenticated;
grant execute on function public.cloud_finish_upload(uuid,uuid) to service_role;

create function public.cloud_folder_keys(entry_id uuid) returns setof text language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_member() or not exists(select 1 from public.cloud_files where id=entry_id and user_id=auth.uid()) then raise exception 'File unavailable'; end if;
 return query with recursive descendants as(
 select id,storage_key from public.cloud_files where id=entry_id and user_id=auth.uid()
 union all select f.id,f.storage_key from public.cloud_files f join descendants d on f.parent_id=d.id where f.user_id=auth.uid())
 select storage_key from descendants where storage_key is not null;
end $$;
revoke all on function public.cloud_folder_keys(uuid) from public,anon;
grant execute on function public.cloud_folder_keys(uuid) to authenticated;
create function public.cloud_begin_delete(entry_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare keys jsonb;
begin
 if not private.is_member() then raise exception 'Login required'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 update public.cloud_files set deleting=true where id=entry_id and user_id=auth.uid();
 if not found then raise exception 'File unavailable'; end if;
 select coalesce(jsonb_agg(k),'[]') into keys from public.cloud_folder_keys(entry_id) k;
 return jsonb_build_object('id',entry_id,'keys',keys);
end $$;
revoke all on function public.cloud_begin_delete(uuid) from public,anon;
grant execute on function public.cloud_begin_delete(uuid) to authenticated;
create function public.cloud_finish_delete(user_id uuid,entry_id uuid,upload_finished boolean default false) returns void language plpgsql security definer set search_path='' as $$
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 perform 1 from public.profiles where id=user_id for update;
 if not exists(select 1 from public.cloud_files f where f.id=entry_id and f.user_id=cloud_finish_delete.user_id and f.deleting) then raise exception 'Deletion unavailable'; end if;
 -- A user deletion must not free a reservation while its Edge upload may still be in flight.
 -- Hosted Edge requests terminate before this ten-minute recovery interval.
 if not upload_finished and exists(with recursive descendants as(
 select * from public.cloud_files where id=entry_id and user_id=cloud_finish_delete.user_id
 union all select f.* from public.cloud_files f join descendants d on f.parent_id=d.id)
 select 1 from descendants where not is_folder and not ready and created_at>now()-interval '10 minutes') then raise exception 'Upload still finishing. Retry deletion shortly'; end if;
 if exists(with recursive descendants as(
 select id,storage_key from public.cloud_files where id=entry_id and user_id=cloud_finish_delete.user_id
 union all select f.id,f.storage_key from public.cloud_files f join descendants d on f.parent_id=d.id)
 select 1 from descendants d join storage.objects o on o.bucket_id='cloud' and o.name=d.storage_key) then raise exception 'Storage cleanup required'; end if;
 delete from public.cloud_files where id=entry_id;
end $$;
revoke all on function public.cloud_finish_delete(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.cloud_finish_delete(uuid,uuid,boolean) to service_role;

create function private.cloud_read_allowed(p_key text) returns boolean language sql stable security definer set search_path='' as $$
 select private.is_member() and private.quota_bytes(auth.uid())>0 and exists(
 select 1 from public.cloud_files f where f.storage_key=p_key and f.user_id=auth.uid() and f.ready and not f.deleting
 and not exists(with recursive ancestors as(select id,parent_id,deleting from public.cloud_files where id=f.parent_id
 union select p.id,p.parent_id,p.deleting from public.cloud_files p join ancestors a on p.id=a.parent_id) select 1 from ancestors where deleting))
$$;
revoke all on function private.cloud_read_allowed(text) from public,anon;
grant execute on function private.cloud_read_allowed(text) to authenticated,service_role;
drop policy cloud_read on storage.objects;
create policy cloud_read on storage.objects for select to authenticated using(bucket_id='cloud' and private.cloud_read_allowed(name));

create or replace function private.report_content(p_post uuid,p_channel uuid,p_reason text,p_details text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or length(coalesce(p_details,''))>500 or p_reason not in (
 'Sexual or nude content','Violence or dangerous content','Hate speech or harassment',
 'Copyright — this is my content','Spam, scam or misleading','Other') then raise exception 'Invalid report'; end if;
 if p_post is null and p_channel is null then raise exception 'Report target required'; end if;
 insert into public.support_requests(user_id,post_id,channel_id,reason,details) values(auth.uid(),p_post,p_channel,p_reason,coalesce(p_details,''));
end $$;

revoke delete on public.posts from authenticated;
create function public.prepare_post_delete(post_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.posts; files jsonb;
begin
 select * into p from public.posts where id=post_id for update;
 if not found or not private.is_member() or not(p.created_by=auth.uid() or (private.is_admin() and private.manage_channel(p.channel_id))) then raise exception 'Post unavailable'; end if;
 update public.posts set status='draft' where id=p.id;
 select coalesce(jsonb_agg(jsonb_build_object('bucket',bucket,'key',key)),'[]') into files from(
 select 'media'::text bucket,media_key key from public.post_items i where i.post_id=p.id
 union all select 'media',trailer_key from public.post_items i where i.post_id=p.id and trailer_key is not null
 union all select 'public',thumbnail_key from public.post_items i where i.post_id=p.id and thumbnail_key is not null) q;
 return jsonb_build_object('id',p.id,'files',files);
end $$;
revoke all on function public.prepare_post_delete(uuid) from public,anon;
grant execute on function public.prepare_post_delete(uuid) to authenticated;
create function public.finish_post_delete(post_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 if exists(select 1 from public.post_items i join storage.objects o on
 (o.bucket_id='media' and o.name in(i.media_key,i.trailer_key)) or (o.bucket_id='public' and o.name=i.thumbnail_key)
 where i.post_id=finish_post_delete.post_id) then raise exception 'Storage cleanup required'; end if;
 delete from public.posts where id=post_id;
end $$;
revoke all on function public.finish_post_delete(uuid) from public,anon,authenticated;
grant execute on function public.finish_post_delete(uuid) to service_role;
alter table public.posts add constraint post_title_length check(length(btrim(title)) between 1 and 160) not valid;
alter table public.posts add constraint post_description_length check(length(description)<=2000) not valid;

create or replace function private.item_keys_guard() returns trigger language plpgsql set search_path='' as $$
declare owner_id uuid; prefix text;
begin
 select created_by into owner_id from public.posts where id=new.post_id;
 prefix=owner_id::text||'/'||new.post_id::text||'/';
 if new.media_key not like prefix||'%' or (new.trailer_key is not null and new.trailer_key not like prefix||'%')
 or (new.thumbnail_key is not null and new.thumbnail_key not like prefix||'%') then raise exception 'Media must use the creator/post path'; end if;
 return new;
end $$;

-- Meta deliveries stay disabled until the owner supplies credentials and enables them.
create extension if not exists pg_net with schema extensions;
alter table private.admin_meta_settings add column api_version text not null default 'v26.0' check(api_version ~ '^v[0-9]+[.][0-9]+$');
create table private.ad_clicks(
 id uuid primary key default gen_random_uuid(),fbclid text,fbc text,fbp text,client_ip inet,user_agent text,
 campaign text,created_at timestamptz not null default now(),used_install uuid unique references public.installs on delete set null);
create index ad_click_ip_time_idx on private.ad_clicks(client_ip,created_at desc) where used_install is null;
create table private.meta_events(
 id uuid primary key default gen_random_uuid(),event_id text not null unique,event_name text not null,
 user_id uuid references auth.users on delete cascade,install_id uuid references public.installs on delete cascade,
 custom_data jsonb not null default '{}',client_ip inet,user_agent text,fbc text,fbp text,
 status text not null default 'queued' check(status in('queued','sending','sent','failed')),
 attempts integer not null default 0,request_id bigint,last_attempt_at timestamptz,sent_at timestamptz,
 response text,created_at timestamptz not null default now());
create index meta_dispatch_idx on private.meta_events(status,created_at);
alter table private.ad_clicks enable row level security;
alter table private.meta_events enable row level security;
revoke all on private.ad_clicks,private.meta_events from public,anon,authenticated;
create function public.record_ad_click(fbclid text,fbp text,client_ip text,user_agent text,campaign text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare key uuid; ip inet;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 if length(coalesce(fbclid,''))>512 or length(coalesce(fbp,''))>200 or length(coalesce(user_agent,''))>1000 or length(coalesce(campaign,''))>200 then raise exception 'Click fields too long'; end if;
 begin ip=nullif(client_ip,'')::inet; exception when invalid_text_representation then ip=null; end;
 -- Coarse server-side abuse limit; the HTTP route also validates origin and bounded JSON.
 if (select count(*) from private.ad_clicks c where c.client_ip=ip and c.created_at>now()-interval '1 hour')>=60 then raise exception 'Click limit reached'; end if;
 insert into private.ad_clicks(fbclid,fbc,fbp,client_ip,user_agent,campaign)
 values(nullif(fbclid,''),case when nullif(fbclid,'') is not null then 'fb.1.'||floor(extract(epoch from now())*1000)::bigint||'.'||fbclid end,
 nullif(fbp,''),ip,user_agent,campaign) returning id into key;
 return key;
end $$;
revoke all on function public.record_ad_click(text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.record_ad_click(text,text,text,text,text) to service_role;

create function private.capture_install_click() returns trigger language plpgsql security definer set search_path='' as $$
declare headers jsonb; click private.ad_clicks;
begin
 headers=coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}');
 begin new.client_ip=nullif(split_part(coalesce(headers->>'x-forwarded-for',headers->>'x-real-ip',''),',',1),'')::inet;
 exception when invalid_text_representation then new.client_ip=null; end;
 new.user_agent=left(coalesce(headers->>'user-agent',new.user_agent),1000);
 select * into click from private.ad_clicks c where c.client_ip=new.client_ip and c.used_install is null
 and c.created_at>now()-interval '48 hours' order by c.created_at desc limit 1 for update skip locked;
 if found then new.ad_click_id=click.id; end if;
 -- Source is already classified by record_install; click matching never changes first touch.
 return new;
end $$;
revoke all on function private.capture_install_click() from public,anon,authenticated;
create trigger capture_install_click before insert on public.installs for each row execute function private.capture_install_click();

create function private.enqueue_install_event() returns trigger language plpgsql security definer set search_path='' as $$
declare c private.ad_clicks;
begin
 if new.ad_click_id is not null then
   update private.ad_clicks set used_install=new.install_id where id=new.ad_click_id and used_install is null returning * into c;
 end if;
 insert into private.meta_events(event_id,event_name,user_id,install_id,custom_data,client_ip,user_agent,fbc,fbp)
 values('install:'||new.install_id,'Install',new.user_id,new.install_id,
 jsonb_strip_nulls(jsonb_build_object('source',new.source,'campaign',coalesce(nullif(new.utm_campaign,''),c.campaign))),
 new.client_ip,new.user_agent,c.fbc,c.fbp) on conflict(event_id) do nothing;
 return new;
end $$;
revoke all on function private.enqueue_install_event() from public,anon,authenticated;
create trigger enqueue_install_event after insert on public.installs for each row execute function private.enqueue_install_event();

create function private.enqueue_meta(p_name text,p_id text,p_user uuid,p_custom jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare i public.installs; c private.ad_clicks;
begin
 select * into i from public.installs where user_id=p_user order by created_at limit 1;
 select * into c from private.ad_clicks where id=i.ad_click_id;
 insert into private.meta_events(event_id,event_name,user_id,install_id,custom_data,client_ip,user_agent,fbc,fbp)
 values(p_id,p_name,p_user,i.install_id,p_custom,i.client_ip,i.user_agent,c.fbc,c.fbp) on conflict(event_id) do nothing;
end $$;
revoke all on function private.enqueue_meta(text,text,uuid,jsonb) from public,anon,authenticated;
create or replace function private.attribute_user(p_id uuid,p_secret text) returns void language plpgsql security definer set search_path='' as $$
declare src text;
begin
 if auth.uid() is null or not exists(select 1 from private.install_claims where install_id=p_id and secret_hash=extensions.digest(p_secret,'sha256')) then raise exception 'Invalid install claim'; end if;
 select source into src from public.installs where install_id=p_id for update;
 insert into private.user_sources(user_id,source) values(auth.uid(),src) on conflict(user_id) do nothing;
 update public.installs set user_id=auth.uid() where install_id=p_id;
 if private.is_member() then perform private.enqueue_meta('CompleteRegistration','registration:'||auth.uid(),auth.uid(),'{}'); end if;
end $$;
create function private.enqueue_purchase_event() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='success' and old.status is distinct from 'success' then
 perform private.enqueue_meta('Purchase',new.id::text,new.user_id,jsonb_build_object('value',new.amount_paise/100.0,'currency','INR','plan',
 (select name from public.plans where id=new.plan_id))); end if;
 return new;
end $$;
revoke all on function private.enqueue_purchase_event() from public,anon,authenticated;
create trigger enqueue_purchase_event after update of status on public.payment_orders for each row execute function private.enqueue_purchase_event();

create function private.meta_dispatch() returns void language plpgsql security definer set search_path='' as $$
declare settings private.admin_meta_settings; event private.meta_events; delivery record; payload jsonb; userdata jsonb; email text; req bigint;
begin
 if not pg_try_advisory_xact_lock(2026101707) then return; end if;
 -- pg_net only sends after commit; consume responses in the next minute.
 for delivery in select e.id,r.status_code,r.timed_out,r.error_msg,r.content
 from private.meta_events e join net._http_response r on r.id=e.request_id where e.status='sending' loop
   update private.meta_events set status=case when delivery.status_code between 200 and 299 and not coalesce(delivery.timed_out,false)
     and coalesce(delivery.content,'') like '%events_received%' then 'sent' else 'failed' end,
     sent_at=case when delivery.status_code between 200 and 299 and coalesce(delivery.content,'') like '%events_received%' then now() end,
     response=left(coalesce(delivery.error_msg,delivery.content,'No response'),2000) where id=delivery.id;
 end loop;
 update private.meta_events set status='failed',response='Delivery timed out' where status='sending' and last_attempt_at<now()-interval '5 minutes';
 select * into settings from private.admin_meta_settings where id;
 if not settings.enabled or settings.pixel_id!~'^[0-9]+$' or coalesce(settings.api_token,'')='' then return; end if;
 for event in select e.* from private.meta_events e where e.status in('queued','failed') and e.attempts<5
 and (e.last_attempt_at is null or e.last_attempt_at<now()-interval '5 minutes')
 and e.created_at>now()-interval '7 days'
 and (e.user_id is null or exists(select 1 from public.consents c where c.user_id=e.user_id and c.policy_version='v1'))
 order by e.created_at limit 25 for update skip locked loop
   select lower(btrim(u.email)) into email from auth.users u where u.id=event.user_id and not coalesce(u.is_anonymous,true);
   userdata=jsonb_strip_nulls(jsonb_build_object(
   'em',case when email<>'' then jsonb_build_array(encode(extensions.digest(email,'sha256'),'hex')) end,
   'external_id',jsonb_build_array(encode(extensions.digest(coalesce(event.user_id::text,event.event_id),'sha256'),'hex')),
   'client_ip_address',host(event.client_ip),'client_user_agent',event.user_agent,'fbc',event.fbc,'fbp',event.fbp));
   payload=jsonb_build_object('data',jsonb_build_array(jsonb_build_object(
     'event_name',event.event_name,'event_id',event.event_id,'event_time',floor(extract(epoch from event.created_at))::bigint,
     'action_source','other','user_data',userdata,'custom_data',event.custom_data)));
   if settings.test_code<>'' then payload=payload||jsonb_build_object('test_event_code',settings.test_code); end if;
   req=net.http_post(url:='https://graph.facebook.com/'||settings.api_version||'/'||settings.pixel_id||'/events',
     body:=payload,headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||settings.api_token),timeout_milliseconds:=10000);
   update private.meta_events set status='sending',attempts=attempts+1,request_id=req,last_attempt_at=now() where id=event.id;
 end loop;
 -- Minimize unmatched click retention.
 delete from private.ad_clicks where used_install is null and created_at<now()-interval '7 days';
end $$;
revoke all on function private.meta_dispatch() from public,anon,authenticated;
select cron.schedule('vayora-meta-dispatch','* * * * *','select private.meta_dispatch()');

create or replace function public.admin_meta() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 return (select jsonb_build_object('pixel_id',pixel_id,'has_token',api_token is not null,'test_code',test_code,
 'website',website,'enabled',enabled,'api_version',api_version,'updated_at',updated_at,'delivery_connected',true,
 'last_sent',(select max(sent_at) from private.meta_events),'queued',(select count(*) from private.meta_events where status in('queued','sending')),
 'failures_24h',(select count(*) from private.meta_events where status='failed' and last_attempt_at>now()-interval '24 hours'),
 'recent',(select coalesce(jsonb_agg(x),'[]') from(select event_name,status,attempts,response,sent_at,created_at from private.meta_events order by created_at desc limit 20)x))
 from private.admin_meta_settings where id);
end $$;
create function public.admin_meta_test() returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required'; end if;
 if not exists(select 1 from private.admin_meta_settings where id and enabled and test_code<>'' and api_token is not null) then raise exception 'Enable Meta with a test event code first'; end if;
 -- Test data only; no real customer data is sent by this action.
 insert into private.meta_events(event_name,event_id,custom_data) values('ViewContent','owner-test:'||gen_random_uuid(),jsonb_build_object('content_name','Vayora owner test'));
end $$;
revoke all on function public.admin_meta_test() from public,anon;
grant execute on function public.admin_meta_test() to authenticated;
create function public.download_meta_config() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('pixel_id',case when enabled then pixel_id else '' end) from private.admin_meta_settings where id
$$;
revoke all on function public.download_meta_config() from public;
grant execute on function public.download_meta_config() to anon,authenticated;
