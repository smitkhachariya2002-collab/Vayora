-- Additive upgrade. Legacy Supabase objects and all existing entitlements remain valid.
alter table public.post_items add column bunny_video_id uuid;
alter table public.post_items add column trailer_bunny_video_id uuid;
alter table public.post_items add column processing_status text not null default 'ready' check(processing_status in ('uploading','processing','ready','failed'));
alter table public.post_items add column trailer_processing_status text not null default 'ready' check(trailer_processing_status in ('uploading','processing','ready','failed'));
alter table public.channels add column display_followers bigint not null default 0 check(display_followers>=0);
alter table public.plans add column recommended boolean not null default false;
alter table public.plans add column recommendation_label text not null default 'MOST POPULAR' check(recommendation_label in ('MOST POPULAR','BEST VALUE'));
create unique index plans_one_recommended on public.plans(recommended) where recommended and active;
alter table public.payment_orders add column is_test boolean not null default false;
alter table public.payment_orders add column utr_submitted_at timestamptz;
alter table public.cloud_files add column storage_provider text not null default 'supabase' check(storage_provider in ('supabase','bunny'));
alter table public.cloud_files add column upload_status text not null default 'ready' check(upload_status in ('uploading','ready','failed'));

create table public.bunny_assets(
 video_id uuid primary key, item_id uuid references public.post_items(id) on delete set null,
 slot text not null check(slot in ('main','trailer')), uploaded_by uuid references auth.users(id) on delete set null,
 status text not null default 'uploading', bytes bigint not null default 0,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(item_id,slot)
);
alter table public.bunny_assets enable row level security;
revoke all on public.bunny_assets from public,anon,authenticated;
grant all on public.bunny_assets to service_role;
create index bunny_assets_status on public.bunny_assets(status,created_at);

create function private.guard_bunny_media() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user not in ('postgres','supabase_admin','service_role') then
  if (tg_op='INSERT' and (new.bunny_video_id is not null or new.trailer_bunny_video_id is not null or new.processing_status<>'ready'))
   or (tg_op='UPDATE' and (new.bunny_video_id is distinct from old.bunny_video_id or new.trailer_bunny_video_id is distinct from old.trailer_bunny_video_id or new.processing_status is distinct from old.processing_status or new.trailer_processing_status is distinct from old.trailer_processing_status))
  then raise exception 'Provider metadata is server controlled' using errcode='42501'; end if;
 end if;
 return new;
end $$;
create trigger bunny_provider_metadata before insert or update on public.post_items for each row execute function private.guard_bunny_media();

create function private.set_publication_time() returns trigger language plpgsql set search_path='' as $$
begin
 if new.status='published' and new.publish_at is null then new.publish_at:=now(); end if;
 return new;
end $$;
create trigger posts_publication_time before insert or update of status,publish_at on public.posts for each row execute function private.set_publication_time();

create or replace function private.cancel_stale_orders() returns void language sql security definer set search_path='' as $$
 update public.payment_orders set status='cancelled' where status='pending' and not success_reported and created_at<now()-interval '72 hours'
$$;

create function public.submit_payment_utr(p_order uuid,p_utr text) returns jsonb language plpgsql security definer set search_path='' as $$
declare order_ public.payment_orders;
begin
 if auth.uid() is null or coalesce(p_utr,'') !~ '^[0-9]{12}$' then raise exception 'Enter the 12-digit bank reference'; end if;
 select * into order_ from public.payment_orders where id=p_order and user_id=auth.uid() for update;
 if not found then raise exception 'order not found'; end if;
 if order_.status in ('paid','revoked','rejected') then return private.order_json(order_.id); end if;
 update public.payment_orders set utr=p_utr,utr_submitted_at=now(),status='review' where id=order_.id;
 return private.order_json(order_.id);
end $$;
revoke all on function public.submit_payment_utr(uuid,text) from public,anon;
grant execute on function public.submit_payment_utr(uuid,text) to authenticated;

-- Preserve the deployed payment parser and activation rules; narrowly extend supported references.
do $$declare definition text; begin
 definition:=pg_get_functiondef('public.report_result(uuid,text)'::regprocedure);
 if position('lower(coalesce(ref, '''')) = lower(o.reference)' in definition)=0 then raise exception 'Unexpected payment reference validator'; end if;
 definition:=replace(definition,'lower(coalesce(ref, '''')) = lower(o.reference)','(lower(coalesce(ref, '''')) = lower(o.reference) or ref ~ ''^[0-9]{12}$'')');
 definition:=replace(definition,'if st in (''FAILURE'',''FAILED'') then','if st in (''FAILURE'',''FAILED'') and not o.success_reported and o.status<>''submitted'' then');
 definition:=replace(definition,'elsif st = ''SUCCESS'' then','elsif st = ''SUBMITTED'' then' || E'\n' || '    update public.payment_orders set status=''submitted'',success_reported=true where id=o.id;' || E'\n' || '  elsif st = ''SUCCESS'' then');
 execute definition;
end $$;

create table public.integration_public_config(
 id integer primary key default 1 check(id=1), firebase_options jsonb,
 meta_app_id text not null default '', meta_client_token text not null default '',
 updated_at timestamptz not null default now()
);
alter table public.integration_public_config enable row level security;
insert into public.integration_public_config(id) values(1);
create policy integration_config_read on public.integration_public_config for select to authenticated using(true);
create policy integration_config_owner on public.integration_public_config for update to authenticated using((select public.admin_role())='owner') with check((select public.admin_role())='owner');
grant select,update on public.integration_public_config to authenticated;
revoke all on public.integration_public_config from anon;

create table public.push_tokens(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,
 token text not null unique check(length(token) between 20 and 4096),install_id text not null,
 allowed boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table public.push_tokens enable row level security;
revoke all on public.push_tokens from public,anon,authenticated;
grant all on public.push_tokens to service_role;
create index push_tokens_user on public.push_tokens(user_id) where allowed;

create table public.push_messages(
 id uuid primary key default gen_random_uuid(),title text not null check(length(title) between 1 and 150),
 body text not null check(length(body) between 1 and 2000),image_url text,
 target jsonb not null default '{"type":"explore"}',audience jsonb not null default '{}',
 status text not null default 'draft' check(status in ('draft','scheduled','sending','sent','failed','cancelled')),
 automatic_key text,scheduled_at timestamptz,created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),last_error text
);
create table public.push_deliveries(
 id uuid primary key default gen_random_uuid(),message_id uuid not null references public.push_messages(id) on delete cascade,
 token_id uuid references public.push_tokens(id) on delete cascade,user_id uuid not null references auth.users(id) on delete cascade,
 status text not null default 'pending' check(status in ('pending','processing','sent','failed','skipped')),
 attempts integer not null default 0,lease_until timestamptz, next_attempt_at timestamptz not null default now(),
 sent_at timestamptz,tapped_at timestamptz,last_error text,created_at timestamptz not null default now(),unique(message_id,token_id)
);
alter table public.push_messages enable row level security;
alter table public.push_deliveries enable row level security;
create policy push_messages_owner on public.push_messages for all to authenticated using((select public.admin_role())='owner') with check((select public.admin_role())='owner');
create policy push_deliveries_owner on public.push_deliveries for select to authenticated using((select public.admin_role())='owner');
grant select,insert,update on public.push_messages to authenticated;
grant select on public.push_deliveries to authenticated;
grant all on public.push_messages,public.push_deliveries to service_role;
create index push_deliveries_pending on public.push_deliveries(status,next_attempt_at);
create index push_deliveries_user_time on public.push_deliveries(user_id,sent_at);
create index push_messages_schedule on public.push_messages(status,scheduled_at);

create table public.push_automations(
 key text primary key,enabled boolean not null default false,title text not null,body text not null,
 delay_hours integer not null default 0,updated_at timestamptz not null default now()
);
alter table public.push_automations enable row level security;
create policy push_automation_owner on public.push_automations for all to authenticated using((select public.admin_role())='owner') with check((select public.admin_role())='owner');
grant select,update on public.push_automations to authenticated;
grant all on public.push_automations to service_role;
insert into public.push_automations(key,title,body,delay_hours) values
 ('payment_reminder_1','Finish your payment','Your selected plan is waiting.',1),
 ('payment_reminder_2','Your plan is waiting','Open Vayora to finish your payment.',24),
 ('payment_failed','Payment not completed','Try again or contact support.',0),
 ('payment_approved','Your plan is active','Enjoy your Vayora benefits.',0),
 ('plan_ending','Your plan ends tomorrow','Open Vayora to see your options.',24),
 ('plan_ended','Your plan has ended','Choose a plan to continue.',0),
 ('plan_ended_3d','Ready to return?','Explore current plans in Vayora.',72),
 ('welcome_video','Discover something new','Watch a video selected for you.',3),
 ('return_4d','New in Vayora','Come back and discover the latest videos.',96),
 ('return_7d','See what is new','Your next video is waiting.',168),
 ('return_14d','Welcome back','Explore new videos and channels.',336),
 ('channel_new_video','New video','A channel you joined has a new release.',0),
 ('daily_unpaid','Discover Vayora','Open Vayora for videos and current offers.',0);

create function public.register_push_token(p_token text,p_install_id text,p_allowed boolean default true) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or length(p_token) not between 20 and 4096 or p_install_id !~ '^[0-9a-f-]{36}$' then raise exception 'invalid push registration'; end if;
 -- Rotation/reassignment requires the same device install secret, checked separately by register-device endpoint.
 if exists(select 1 from public.push_tokens where token=p_token and user_id<>auth.uid()) then raise exception 'token already owned' using errcode='42501'; end if;
 insert into public.push_tokens(user_id,token,install_id,allowed) values(auth.uid(),p_token,p_install_id,p_allowed)
 on conflict(token) do update set allowed=excluded.allowed,updated_at=now();
end $$;
revoke all on function public.register_push_token(text,text,boolean) from public,anon;
grant execute on function public.register_push_token(text,text,boolean) to authenticated;
create function public.record_push_tap(p_delivery uuid) returns void language sql security definer set search_path='' as $$
 update public.push_deliveries set tapped_at=coalesce(tapped_at,now()) where id=p_delivery and user_id=auth.uid() and status='sent'
$$;
revoke all on function public.record_push_tap(uuid) from public,anon;
grant execute on function public.record_push_tap(uuid) to authenticated;

create function public.register_push_token_v2(p_token text,p_install_id text,p_allowed boolean,p_secret text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or length(p_token) not between 20 and 4096 or p_install_id !~ '^[0-9a-f-]{36}$' then raise exception 'invalid push registration'; end if;
 if not exists(select 1 from public.installs where install_id=p_install_id and install_secret=p_secret) then raise exception 'device proof required' using errcode='42501'; end if;
 if exists(select 1 from public.push_tokens where token=p_token and install_id<>p_install_id) then raise exception 'different device owns this token' using errcode='42501'; end if;
 insert into public.push_tokens(user_id,token,install_id,allowed) values(auth.uid(),p_token,p_install_id,p_allowed)
 on conflict(token) do update set user_id=excluded.user_id,allowed=excluded.allowed,updated_at=now();
end $$;
revoke all on function public.register_push_token_v2(text,text,boolean,text) from public,anon;
grant execute on function public.register_push_token_v2(text,text,boolean,text) to authenticated;

create function public.set_recommended_plan(p_plan uuid,p_label text) returns void language plpgsql security definer set search_path='' as $$
begin
 if public.admin_role()<>'owner' or public.admin_role() is null then raise exception 'owner required' using errcode='42501'; end if;
 if p_label not in ('MOST POPULAR','BEST VALUE') then raise exception 'invalid label'; end if;
 perform pg_advisory_xact_lock(812442);
 if not exists(select 1 from public.plans where id=p_plan and active) then raise exception 'active plan required'; end if;
 update public.plans set recommended=false where recommended;
 update public.plans set recommended=true,recommendation_label=p_label where id=p_plan;
end $$;
revoke all on function public.set_recommended_plan(uuid,text) from public,anon;
grant execute on function public.set_recommended_plan(uuid,text) to authenticated;
create or replace function public.public_plans() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'price_inr',price_inr,'duration_days',duration_days,'duration_hours',duration_hours,'perks',perks,'badge',badge,'position',position,'recommended',recommended,'recommendation_label',recommendation_label) order by position),'[]'::jsonb) from public.plans where active
$$;

create function public.prepare_push_message(p_message uuid) returns integer language plpgsql security definer set search_path='' as $$
declare m public.push_messages; inserted integer; local_ timestamp:=now() at time zone 'Asia/Kolkata';
begin
 select * into m from public.push_messages where id=p_message for update;
 if not found or m.status not in ('scheduled','sending') or m.scheduled_at>now() then return 0; end if;
 if m.automatic_key is not null and extract(hour from local_)>=3 and extract(hour from local_)<9 then
  update public.push_messages set scheduled_at=(date_trunc('day',local_)+interval '9 hours') at time zone 'Asia/Kolkata' where id=m.id;return 0;
 end if;
 insert into public.push_deliveries(message_id,token_id,user_id)
 select m.id,t.id,t.user_id from public.push_tokens t join auth.users u on u.id=t.user_id
 where t.allowed
  and (not(m.audience?'source') or m.audience->>'source'=private.source_of(t.user_id))
  and (not(m.audience?'guest') or (m.audience->>'guest')::boolean=u.is_anonymous)
  and (not(m.audience?'premium') or (m.audience->>'premium')::boolean=exists(select 1 from public.subscriptions s where s.user_id=t.user_id and not s.revoked and s.starts_at<=now() and s.ends_at>now()))
  and (not(m.audience?'user_ids') or t.user_id::text in (select jsonb_array_elements_text(m.audience->'user_ids')))
  and (not(m.audience?'channel_ids') or exists(select 1 from public.channel_members c where c.user_id=t.user_id and c.channel_id::text in (select jsonb_array_elements_text(m.audience->'channel_ids'))))
 on conflict(message_id,token_id) do nothing;
 get diagnostics inserted=row_count;
 update public.push_messages set status='sending' where id=m.id;
 return inserted;
end $$;
revoke all on function public.prepare_push_message(uuid) from public,anon,authenticated;
grant execute on function public.prepare_push_message(uuid) to service_role;

create function public.claim_push_deliveries(p_limit integer default 30) returns jsonb language plpgsql security definer set search_path='' as $$
declare rows_ jsonb;
begin
 update public.push_deliveries set status='failed',lease_until=null,last_error='Delivery retry limit reached' where status='processing' and lease_until<now() and attempts>=5;
 update public.push_deliveries set status='pending',lease_until=null where status='processing' and lease_until<now() and attempts<5;
 -- Suppress held acquisition/payment reminders as soon as any real purchase activates.
 update public.push_deliveries d set status='skipped',last_error='User has paid'
 from public.push_messages m where m.id=d.message_id and d.status='pending'
 and m.automatic_key in ('payment_reminder_1','payment_reminder_2','payment_failed','daily_unpaid')
 and exists(select 1 from public.payment_orders o where o.user_id=d.user_id and o.status='paid' and not o.is_test);
 -- During quiet hours all automatic deliveries wait, including previously queued batches.
 update public.push_deliveries d set next_attempt_at=(date_trunc('day',now() at time zone 'Asia/Kolkata')+interval '9 hours') at time zone 'Asia/Kolkata'
 from public.push_messages m where d.message_id=m.id and m.automatic_key is not null and d.status='pending'
 and extract(hour from now() at time zone 'Asia/Kolkata')>=3 and extract(hour from now() at time zone 'Asia/Kolkata')<9;
 -- Discard older automatic messages waiting for the same person.
 update public.push_deliveries old set status='skipped',last_error='Newer automatic message queued'
 from public.push_messages om where old.message_id=om.id and old.status='pending' and om.automatic_key is not null
 and exists(select 1 from public.push_deliveries newer join public.push_messages nm on nm.id=newer.message_id where newer.user_id=old.user_id and newer.status in ('pending','sent') and nm.automatic_key is not null and (nm.created_at,nm.id)>(om.created_at,om.id));
 with selected as (
  select d.id from public.push_deliveries d join public.push_messages m on m.id=d.message_id
  join public.push_tokens t on t.id=d.token_id
  where d.status='pending' and d.next_attempt_at<=now() and d.attempts<5 and t.allowed and t.user_id=d.user_id and m.status='sending'
  and (m.automatic_key is null or not exists(select 1 from public.push_deliveries recent join public.push_messages rm on rm.id=recent.message_id where recent.user_id=d.user_id and recent.status='sent' and recent.sent_at>now()-interval '2 hours' and rm.automatic_key is not null))
  order by d.created_at limit greatest(1,least(p_limit,50)) for update of d skip locked
 ), claimed as (
  update public.push_deliveries d set status='processing',attempts=attempts+1,lease_until=now()+interval '3 minutes' from selected where d.id=selected.id returning d.*
 ) select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('token',t.token,'title',m.title,'body',m.body,'image_url',m.image_url,'target',m.target)),'[]'::jsonb) into rows_
 from claimed c join public.push_tokens t on t.id=c.token_id join public.push_messages m on m.id=c.message_id;
 return rows_;
end $$;
revoke all on function public.claim_push_deliveries(integer) from public,anon,authenticated;
grant execute on function public.claim_push_deliveries(integer) to service_role;

create function private.guard_cloud_provider() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user not in ('postgres','supabase_admin','service_role') then
  if (tg_op='INSERT' and (new.storage_provider<>'supabase' or new.upload_status<>'ready'))
   or (tg_op='UPDATE' and (new.storage_provider is distinct from old.storage_provider or new.upload_status is distinct from old.upload_status))
  then raise exception 'Storage provider is server controlled' using errcode='42501'; end if;
 end if;
 return new;
end $$;
create trigger cloud_provider_guard before insert or update on public.cloud_files for each row execute function private.guard_cloud_provider();

alter table public.push_messages add column automatic_event text unique;
create function private.queue_automatic_push(p_user uuid,p_key text,p_event text,p_title text default null,p_body text default null,p_target jsonb default '{"type":"premium"}') returns void
language plpgsql security definer set search_path='' as $$
declare template public.push_automations;
begin
 select * into template from public.push_automations where key=p_key and enabled;
 if not found or not exists(select 1 from public.push_tokens where user_id=p_user and allowed) then return; end if;
 insert into public.push_messages(title,body,target,audience,status,automatic_key,automatic_event,scheduled_at)
 values(coalesce(p_title,template.title),coalesce(p_body,template.body),p_target,jsonb_build_object('user_ids',jsonb_build_array(p_user::text)),'scheduled',p_key,p_key||':'||p_user||':'||p_event,now())
 on conflict(automatic_event) do nothing;
end $$;

create function public.schedule_push_automations() returns integer language plpgsql security definer set search_path='' as $$
declare person record; order_ record; subscription_ record; last_seen timestamptz; watched boolean; chosen record;
 elapsed interval; day_ date:=(now() at time zone 'Asia/Kolkata')::date; hour_ integer:=extract(hour from now() at time zone 'Asia/Kolkata');
 cheapest text; count_ integer:=0; source_ text; rotation integer; destination jsonb;
begin
 if hour_>=3 and hour_<9 then return 0; end if;
 select 'Plans from ₹'||min(price_inr)::text into cheapest from public.plans where active;
 for person in select distinct t.user_id from public.push_tokens t where t.allowed loop
  source_:=private.source_of(person.user_id);
  select max(coalesce(a.occurred_at,a.received_at)) into last_seen from private.app_activity a where a.user_id=person.user_id;
  select coalesce(last_seen,min(i.created_at),min(u.created_at)) into last_seen from auth.users u left join public.installs i on i.user_id=u.id where u.id=person.user_id;
  elapsed:=now()-coalesce(last_seen,now());
  for order_ in select * from public.payment_orders where user_id=person.user_id and not is_test and created_at>now()-interval '72 hours' loop
   if order_.status in ('pending','submitted','review') then
    if order_.created_at<=now()-interval '24 hours' then perform private.queue_automatic_push(person.user_id,'payment_reminder_2',order_.id::text);
    elsif order_.created_at<=now()-interval '1 hour' then perform private.queue_automatic_push(person.user_id,'payment_reminder_1',order_.id::text);end if;
   elsif order_.status='failed' and coalesce(order_.reported_at,order_.created_at)>now()-interval '2 hours' then perform private.queue_automatic_push(person.user_id,'payment_failed',date_trunc('hour',now())::text);
   elsif order_.status='paid' and order_.activated_at>now()-interval '24 hours' then perform private.queue_automatic_push(person.user_id,'payment_approved',order_.id::text);end if;
  end loop;
  select * into subscription_ from public.subscriptions where user_id=person.user_id and not revoked order by ends_at desc limit 1;
  if found then
   if subscription_.ends_at between now() and now()+interval '24 hours' then perform private.queue_automatic_push(person.user_id,'plan_ending',subscription_.id::text);
   elsif subscription_.ends_at between now()-interval '24 hours' and now() then perform private.queue_automatic_push(person.user_id,'plan_ended',subscription_.id::text,null,'Your plan has ended. '||coalesce(cheapest,'Open Vayora for current plans.'));
   elsif subscription_.ends_at between now()-interval '4 days' and now()-interval '3 days' then perform private.queue_automatic_push(person.user_id,'plan_ended_3d',subscription_.id::text,null,'Return to Vayora. '||coalesce(cheapest,'See current plans.'));end if;
  end if;
  select p.id,p.title into chosen from public.posts p join public.channels c on c.id=p.channel_id
   where p.status='published' and not p.hidden and coalesce(p.publish_at,p.created_at)<=now() and not c.hidden and c.review_status='approved' and c.status in ('published','active')
   and (p.audience='all' or p.audience=source_) and (c.audience='all' or c.audience=source_)
   order by p.created_at desc limit 1;
  destination:=case when chosen.id is not null then jsonb_build_object('type','video','id',chosen.id::text) else '{"type":"explore"}'::jsonb end;
  select exists(select 1 from private.app_activity where user_id=person.user_id and event_name in ('VideoStart','ViewContent')) into watched;
  if not watched and exists(select 1 from public.installs where user_id=person.user_id and created_at between now()-interval '24 hours' and now()-interval '3 hours') and chosen.id is not null then
   perform private.queue_automatic_push(person.user_id,'welcome_video',day_::text,'Watch '||left(chosen.title,135),'Discover this video in Vayora.',destination);
  end if;
  if elapsed>=interval '14 days' then perform private.queue_automatic_push(person.user_id,'return_14d',coalesce(last_seen::text,day_::text),null,coalesce('Watch '||chosen.title,'Discover the latest videos.'),destination);
  elsif elapsed>=interval '7 days' then perform private.queue_automatic_push(person.user_id,'return_7d',coalesce(last_seen::text,day_::text),null,coalesce('Watch '||chosen.title,'Discover the latest videos.'),destination);
  elsif elapsed>=interval '4 days' then perform private.queue_automatic_push(person.user_id,'return_4d',coalesce(last_seen::text,day_::text),null,coalesce('Watch '||chosen.title,'Discover the latest videos.'),destination);end if;
  if hour_ in (0,9,14,19) and not exists(select 1 from public.payment_orders where user_id=person.user_id and status='paid' and not is_test)
   and exists(select 1 from public.installs where user_id=person.user_id and created_at>now()-interval '14 days') then
   rotation:=(extract(doy from day_)::integer*4+case hour_ when 0 then 0 when 9 then 1 when 14 then 2 else 3 end)%8;
   perform private.queue_automatic_push(person.user_id,'daily_unpaid',day_::text||':'||hour_,
    case rotation when 0 then 'Trending in Vayora' when 1 then 'Try Vayora today' when 2 then 'Your newest video' when 3 then coalesce(cheapest,'Explore current plans') when 4 then 'Unlock more videos' when 5 then 'Find your best-value plan' when 6 then 'Continue exploring' else 'Discover a channel' end,
    case when rotation in (0,2,6,7) then coalesce(chosen.title,'Explore new videos and channels.') else coalesce(cheapest,'Open Vayora for current offers.') end,
    case when rotation in (0,2,6,7) then destination else '{"type":"premium"}'::jsonb end);
  end if;
  if chosen.id is not null and exists(select 1 from public.posts p join public.channel_members cm on cm.channel_id=p.channel_id where p.id=chosen.id and cm.user_id=person.user_id and p.created_at>now()-interval '24 hours') then
   perform private.queue_automatic_push(person.user_id,'channel_new_video',chosen.id::text,'New video: '||left(chosen.title,135),null,destination);
  end if;
  count_:=count_+1;
 end loop;
 return count_;
end $$;
revoke all on function public.schedule_push_automations() from public,anon,authenticated;
grant execute on function public.schedule_push_automations() to service_role;

-- Encoding readiness is additional to existing review/audience rules.
alter table public.posts add column bunny_publish_requested boolean not null default false;
create function private.hold_unready_bunny_posts() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('authenticated','anon') and (
  (tg_op='INSERT' and new.bunny_publish_requested) or
  (tg_op='UPDATE' and new.bunny_publish_requested is distinct from old.bunny_publish_requested)
 ) then raise exception 'Publication queue is server controlled' using errcode='42501'; end if;
 if new.status in ('published','scheduled') and exists(select 1 from public.post_items i where i.post_id=new.id and
  ((i.bunny_video_id is not null and i.processing_status<>'ready') or (i.trailer_bunny_video_id is not null and i.trailer_processing_status<>'ready')))
 then new.status:='draft'; new.bunny_publish_requested:=true;
 elsif tg_op='UPDATE' and new.status='draft' and current_user in ('authenticated','anon') then new.bunny_publish_requested:=false;
 end if;
 if new.status='published' and (tg_op='INSERT' or old.status<>'published') then new.publish_at:=now(); end if;
 return new;
end $$;
create trigger zz_bunny_publication_guard before insert or update on public.posts for each row execute function private.hold_unready_bunny_posts();
create function private.queue_removed_bunny_media() returns trigger language plpgsql security definer set search_path='' as $$
begin
 update public.bunny_assets set item_id=null,status='cleanup_queued',updated_at=now() where item_id=old.id;
 return old;
end $$;
create trigger bunny_removed_media before delete on public.post_items for each row execute function private.queue_removed_bunny_media();
do $$declare definition text; begin
 definition:=pg_get_functiondef('public.create_order(uuid)'::regprocedure);
 definition:=replace(definition,'created_at < now() - interval ''2 hours''','created_at < now() - interval ''72 hours''');
 execute definition;
end $$;

-- Reuse the private server cron authentication; it is never returned to a browser.
create function public.activate_bunny_processing() returns void language plpgsql security definer set search_path='' as $$
declare config record; command text; job bigint;
begin
 select * into config from private.meta_cron limit 1;
 if config is null then raise exception 'Server scheduler is not configured'; end if;
 command:=format('select net.http_post(url := %L, headers := %L::jsonb, body := %L::jsonb, timeout_milliseconds := 55000)',replace(config.url,'/meta-send','/bunny-sync'),jsonb_build_object('Content-Type','application/json','x-cron-key',config.key)::text,'{}');
 select jobid into job from cron.job where jobname='bunny-processing';
 if job is null then perform cron.schedule('bunny-processing','* * * * *',command);
 else perform cron.alter_job(job,command:=command,active:=true);end if;
end $$;
revoke all on function public.activate_bunny_processing() from public,anon,authenticated;
grant execute on function public.activate_bunny_processing() to service_role;
