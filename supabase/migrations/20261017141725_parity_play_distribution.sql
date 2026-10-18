-- Play distribution: effective free mode is bound to a verified Auth session.
create table private.play_settings(id boolean primary key default true check(id),
 play_billing_enabled boolean not null default false,google_approval_confirmed boolean not null default false);
insert into private.play_settings(id)values(true);
create table private.play_sessions(session_id uuid primary key,user_id uuid not null references auth.users on delete cascade,
 verified_until timestamptz not null,created_at timestamptz not null default now());
create index play_sessions_user_idx on private.play_sessions(user_id);
create table private.play_challenges(nonce text primary key,user_id uuid not null references auth.users on delete cascade,
 session_id uuid not null,expires_at timestamptz not null,consumed boolean not null default false,created_at timestamptz not null default now());
create index play_challenges_user_idx on private.play_challenges(user_id,created_at);
create table public.play_products(product_id text not null,base_plan_id text not null,plan_id uuid not null references public.plans,
 active boolean not null default true,primary key(product_id,base_plan_id));
create table private.play_purchases(token_hash text primary key,user_id uuid not null references auth.users on delete cascade,
 product_id text not null,base_plan_id text not null,subscription_id uuid unique references public.subscriptions on delete set null,
 verified_until timestamptz not null,updated_at timestamptz not null default now());
alter table private.play_settings enable row level security;
alter table private.play_sessions enable row level security;
alter table private.play_challenges enable row level security;
alter table private.play_purchases enable row level security;
alter table public.play_products enable row level security;
revoke all on private.play_settings,private.play_sessions,private.play_challenges,private.play_purchases,public.play_products from public,anon,authenticated;
grant select,insert,update,delete on public.play_products to authenticated;
grant all on public.play_products to service_role;
create function private.play_session() returns boolean language sql stable security definer set search_path='' as $$
 select private.is_member() and exists(select 1 from private.play_sessions where session_id=nullif(auth.jwt()->>'session_id','')::uuid
 and user_id=auth.uid() and verified_until>now())
$$;
revoke all on function private.play_session() from public,anon;
grant execute on function private.play_session() to authenticated;
create function private.play_billing_ready() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.play_settings where id and play_billing_enabled and google_approval_confirmed)
$$;
revoke all on function private.play_billing_ready() from public,anon;
grant execute on function private.play_billing_ready() to authenticated;
create function private.client_free_mode() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.app_mode where id and free_mode) or (private.play_session() and not private.play_billing_ready())
$$;
revoke all on function private.client_free_mode() from public,anon;
grant execute on function private.client_free_mode() to authenticated;
create policy play_products_read on public.play_products for select to authenticated using(private.is_owner() or (active and private.play_billing_ready() and private.play_session()));
create policy play_products_insert on public.play_products for insert to authenticated with check(private.is_owner());
create policy play_products_update on public.play_products for update to authenticated using(private.is_owner()) with check(private.is_owner());
create policy play_products_delete on public.play_products for delete to authenticated using(private.is_owner());
create or replace function public.free_mode() returns boolean language sql stable set search_path='' as $$select private.client_free_mode()$$;
create or replace function private.is_premium_user() returns boolean language sql stable security definer set search_path='' as $$
 select private.is_member() and case when private.client_free_mode() then private.has_ads_access() else private.has_plan() end
$$;
create or replace function private.quota_bytes(p_user uuid) returns bigint language sql stable security definer set search_path='' as $$
 select case when p_user is distinct from auth.uid() or not private.is_member() then 0::bigint
 when private.client_free_mode() then 16106127360::bigint when private.has_plan() then 2199023255552::bigint else 0::bigint end
$$;
create or replace function private.my_status() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',p.id,'is_admin',private.is_admin(),'display_name',p.display_name,'avatar_url',p.avatar_url,'is_guest',p.is_guest,
 'source',private.source_of(p.id),'has_ads_access',private.has_ads_access(),'is_premium',private.is_premium_user(),
 'plan_name',case when private.client_free_mode() then null else(select pl.name from public.subscriptions s join public.plans pl on pl.id=s.plan_id
 where s.user_id=p.id and s.revoked_at is null and s.starts_at<=now() and s.ends_at>now() order by s.ends_at desc limit 1)end,
 'plan_ends_at',case when private.client_free_mode() then null else(select max(ends_at) from public.subscriptions where user_id=p.id and revoked_at is null and starts_at<=now() and ends_at>now())end,
 'used_bytes',p.used_bytes,'quota_bytes',private.quota_bytes(p.id),'free_mode',private.client_free_mode(),
 'paid_enabled',not private.client_free_mode(),'access_status',p.ads_access_status,'play_verified',private.play_session(),'play_billing_enabled',private.play_billing_ready())
 from public.profiles p where p.id=auth.uid()
$$;
drop policy plans_read on public.plans;
create policy plans_read on public.plans for select to authenticated using(private.is_owner() or (active and not private.client_free_mode()));
create function public.play_integrity_challenge() returns text language plpgsql security definer set search_path='' as $$
declare session uuid; key text;
begin
 if not private.is_member() then raise exception 'Login required'; end if;
 session=nullif(auth.jwt()->>'session_id','')::uuid;
 if session is null then raise exception 'Session required'; end if;
 if (select count(*) from private.play_challenges where user_id=auth.uid() and created_at>now()-interval '1 hour')>=10 then raise exception 'Try again later'; end if;
 key=translate(rtrim(encode(extensions.gen_random_bytes(32),'base64'),'='),'+/','-_');
 insert into private.play_challenges(nonce,user_id,session_id,expires_at) values(key,auth.uid(),session,now()+interval '5 minutes');
 delete from private.play_challenges where expires_at<now()-interval '1 day';
 return key;
end $$;
revoke all on function public.play_integrity_challenge() from public,anon;
grant execute on function public.play_integrity_challenge() to authenticated;
create function public.enable_play_free_cloud(user_id uuid,session_id uuid,nonce text) returns void language plpgsql security definer set search_path='' as $$
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 update private.play_challenges c set consumed=true where c.nonce=enable_play_free_cloud.nonce and c.user_id=enable_play_free_cloud.user_id
 and c.session_id=enable_play_free_cloud.session_id and not consumed and expires_at>now();
 if not found then raise exception 'Challenge expired or already used'; end if;
 insert into private.play_sessions(session_id,user_id,verified_until)values(session_id,user_id,now()+interval '30 days')
 on conflict on constraint play_sessions_pkey do update set verified_until=excluded.verified_until where private.play_sessions.user_id=excluded.user_id;
end $$;
revoke all on function public.enable_play_free_cloud(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.enable_play_free_cloud(uuid,uuid,text) to service_role;

create or replace function private.create_payment_order(p_plan uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare pl public.plans; settings public.payment_settings; ord public.payment_orders;
begin
 if not private.is_member() then raise exception 'Login required'; end if;
 if private.client_free_mode() then raise exception 'Payments unavailable in free mode'; end if;
 select * into settings from public.payment_settings where id and enabled and length(btrim(upi_id))>2 and length(btrim(payee_name))>0;
 if not found then raise exception 'Payments are not available right now'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 select * into pl from public.plans where id=p_plan and active;
 if not found then raise exception 'Plan unavailable'; end if;
 update public.payment_orders set status='cancelled',reason='Replaced or expired'
 where user_id=auth.uid() and status in ('initiated','pending') and (plan_id<>p_plan or created_at<=now()-interval '24 hours');
 select * into ord from public.payment_orders where user_id=auth.uid() and plan_id=p_plan and status in ('initiated','pending')
 and created_at>now()-interval '24 hours' order by created_at desc limit 1 for update;
 if not found then
 insert into public.payment_orders(user_id,plan_id,amount_paise,duration_days,reference)
 values(auth.uid(),p_plan,(pl.price_inr*100)::bigint,pl.duration_days,'VY'||to_char(now(),'YYMMDD')||encode(extensions.gen_random_bytes(6),'hex'))
 returning * into ord;
 end if;
 return to_jsonb(ord)||jsonb_build_object('upi_id',settings.upi_id,'payee_name',settings.payee_name);
end $$;

create or replace function private.request_full_access() returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.is_member() then raise exception 'Login required'; end if;
 if not private.client_free_mode() then raise exception 'Full access requests require free mode'; end if;
 update public.profiles set ads_access_status='pending' where id=auth.uid() and ads_access_status in ('none','rejected');
end $$;

-- Direct checkout cannot be used by a verified Play session; Play must supply Google's choice token.
alter function private.create_payment_order(uuid) rename to direct_payment_order;
create function private.create_payment_order(p_plan uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if private.play_session() then raise exception 'Use Google Play billing choice'; end if;
 return private.direct_payment_order(p_plan);
end $$;
revoke all on function private.direct_payment_order(uuid),private.create_payment_order(uuid) from public,anon;
grant execute on function private.create_payment_order(uuid) to authenticated;
revoke all on function private.direct_payment_order(uuid) from authenticated;

alter table private.play_settings add column tax_rate_bps integer check(tax_rate_bps between 0 and 10000);
create or replace function private.play_billing_ready() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.play_settings where id and play_billing_enabled and google_approval_confirmed and tax_rate_bps is not null)
$$;
create table private.play_external_orders(order_id uuid primary key references public.payment_orders,
 external_token text not null unique,administrative_area text not null,report_status text not null default 'pending' check(report_status in('pending','sending','sent','failed')),
 attempts integer not null default 0,last_attempt_at timestamptz,reported_at timestamptz,response text);
alter table private.play_external_orders enable row level security;
revoke all on private.play_external_orders from public,anon,authenticated;
create function public.create_play_upi_order(plan_id uuid,external_transaction_token text,administrative_area text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare ord jsonb;
begin
 if not private.is_member() or not private.play_session() or not private.play_billing_ready() then raise exception 'Play billing is disabled'; end if;
 if length(coalesce(external_transaction_token,'')) not between 16 and 4096 then raise exception 'Google billing choice required'; end if;
 if administrative_area not in ('ANDAMAN AND NICOBAR ISLANDS','ANDHRA PRADESH','ARUNACHAL PRADESH','ASSAM','BIHAR','CHANDIGARH','CHHATTISGARH','DADRA AND NAGAR HAVELI','DADRA AND NAGAR HAVELI AND DAMAN AND DIU','DAMAN AND DIU','DELHI','GOA','GUJARAT','HARYANA','HIMACHAL PRADESH','JAMMU AND KASHMIR','JHARKHAND','KARNATAKA','KERALA','LADAKH','LAKSHADWEEP','MADHYA PRADESH','MAHARASHTRA','MANIPUR','MEGHALAYA','MIZORAM','NAGALAND','ODISHA','PUDUCHERRY','PUNJAB','RAJASTHAN','SIKKIM','TAMIL NADU','TELANGANA','TRIPURA','UTTAR PRADESH','UTTARAKHAND','WEST BENGAL') or administrative_area is null then raise exception 'Billing state required'; end if;
 ord=private.direct_payment_order(plan_id);
 insert into private.play_external_orders(order_id,external_token,administrative_area)values((ord->>'id')::uuid,external_transaction_token,administrative_area)
 on conflict(order_id) do update set external_token=excluded.external_token,administrative_area=excluded.administrative_area where private.play_external_orders.report_status<>'sent';
 return ord;
end $$;
revoke all on function public.create_play_upi_order(uuid,text,text) from public,anon;
grant execute on function public.create_play_upi_order(uuid,text,text) to authenticated;

alter table public.subscriptions drop constraint subscriptions_source_check;
alter table public.subscriptions add constraint subscriptions_source_check check(source in('upi_app','admin','provider_api','google_play'));
create function public.activate_play_purchase(user_id uuid,token_hash text,product_id text,base_plan_id text,verified_ends_at timestamptz) returns void
language plpgsql security definer set search_path='' as $$
declare mapping public.play_products; receipt private.play_purchases; sub uuid;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 if not private.play_billing_ready() then raise exception 'Play billing is disabled'; end if;
 if verified_ends_at<=now() then raise exception 'Purchase expired'; end if;
 select * into mapping from public.play_products p where p.product_id=activate_play_purchase.product_id and p.base_plan_id=activate_play_purchase.base_plan_id and active;
 if not found then raise exception 'Product not mapped'; end if;
 perform pg_advisory_xact_lock(hashtextextended(token_hash,0));
 select * into receipt from private.play_purchases p where p.token_hash=activate_play_purchase.token_hash for update;
 if found and receipt.user_id<>activate_play_purchase.user_id then raise exception 'Purchase belongs to another account'; end if;
 perform 1 from public.profiles where id=user_id and not is_guest for update;
 if not found then raise exception 'Member account required'; end if;
 if receipt.subscription_id is null then
 insert into public.subscriptions(user_id,plan_id,starts_at,ends_at,source)
 values(user_id,mapping.plan_id,now(),verified_ends_at,'google_play')returning id into sub;
 else
 sub=receipt.subscription_id;
 update public.subscriptions set ends_at=verified_ends_at,revoked_at=null where id=sub;
 end if;
 insert into private.play_purchases(token_hash,user_id,product_id,base_plan_id,subscription_id,verified_until)
 values(token_hash,user_id,product_id,base_plan_id,sub,verified_ends_at)
 on conflict on constraint play_purchases_pkey do update set verified_until=excluded.verified_until,updated_at=now();
 if coalesce((select s.source from private.user_sources s where s.user_id=activate_play_purchase.user_id),'organic')='organic' then
 update public.profiles set ads_access_status='pending' where id=user_id and ads_access_status='none'; end if;
end $$;
revoke all on function public.activate_play_purchase(uuid,text,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.activate_play_purchase(uuid,text,text,text,timestamptz) to service_role;

create table private.play_report_config(id boolean primary key default true check(id),secret text not null);
insert into private.play_report_config values(true,encode(extensions.gen_random_bytes(32),'hex'));
alter table private.play_report_config enable row level security;
revoke all on private.play_report_config from public,anon,authenticated;
create function public.authorize_play_report(secret text)returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.play_report_config c where c.secret=authorize_play_report.secret)
$$;
revoke all on function public.authorize_play_report(text) from public,anon,authenticated;
grant execute on function public.authorize_play_report(text) to service_role;
create function public.claim_play_reports()returns jsonb language plpgsql security definer set search_path='' as $$
declare jobs jsonb;
begin
 if coalesce(auth.role(),'')<>'service_role' or not private.play_billing_ready() then raise exception 'Play billing is disabled'; end if;
 update private.play_external_orders set report_status='failed',response='Worker interrupted'
 where report_status='sending' and last_attempt_at<now()-interval '10 minutes';
 with eligible as(select x.order_id from private.play_external_orders x join public.payment_orders o on o.id=x.order_id
 where x.report_status in('pending','failed') and o.status='success' and (last_attempt_at is null or last_attempt_at<now()-interval '5 minutes')
 order by o.paid_at limit 20 for update of x skip locked),
 claimed as(update private.play_external_orders x set report_status='sending',attempts=attempts+1,last_attempt_at=now()
 from eligible e where x.order_id=e.order_id returning x.*)
 select coalesce(jsonb_agg(jsonb_build_object('id',x.order_id,'token',x.external_token,'amount_paise',o.amount_paise,'paid_at',o.paid_at,
 'administrative_area',x.administrative_area,'tax_rate_bps',(select tax_rate_bps from private.play_settings where id))),'[]')into jobs from claimed x join public.payment_orders o on o.id=x.order_id;
 return jobs;
end $$;
revoke all on function public.claim_play_reports() from public,anon,authenticated;
grant execute on function public.claim_play_reports() to service_role;
create function public.finish_play_report(order_id uuid,succeeded boolean,response text)returns void language plpgsql security definer set search_path='' as $$
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 update private.play_external_orders x set report_status=case when succeeded then 'sent' else 'failed' end,
 reported_at=case when succeeded then now()end,response=left(finish_play_report.response,2000) where x.order_id=finish_play_report.order_id;
end $$;
revoke all on function public.finish_play_report(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.finish_play_report(uuid,boolean,text) to service_role;
create function private.play_report_dispatch()returns void language plpgsql security definer set search_path='' as $$
begin
 if private.play_billing_ready() and exists(select 1 from private.play_external_orders x join public.payment_orders o on o.id=x.order_id where x.report_status<>'sent' and o.status='success')then
 perform net.http_post(url:='https://fzloulsjhkdxwagonsgt.supabase.co/functions/v1/play-report',body:='{}',
 headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select secret from private.play_report_config where id)),timeout_milliseconds:=10000);
 end if;
end $$;
revoke all on function private.play_report_dispatch() from public,anon,authenticated;
select cron.schedule('vayora-play-report','*/15 * * * *','select private.play_report_dispatch()');

-- Refresh the invoker wrapper after the internal function rename, including warm RPC plans.
create or replace function public.create_payment_order(plan_id uuid) returns jsonb language sql set search_path='' as $$
 select private.create_payment_order(plan_id)
$$;
revoke all on function public.create_payment_order(uuid) from public,anon;
grant execute on function public.create_payment_order(uuid) to authenticated;
