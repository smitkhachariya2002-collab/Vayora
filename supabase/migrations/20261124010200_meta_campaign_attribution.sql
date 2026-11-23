-- Vayora 1.0.12, additive to the existing Play-referrer v2 migrations.
-- No changes to private.user_sources or existing acquisition labels.
alter table public.ad_clicks
 add column if not exists event_id uuid unique,
 add column if not exists utm_source text,
 add column if not exists utm_medium text,
 add column if not exists utm_campaign text,
 add column if not exists utm_content text,
 add column if not exists page_url text;

alter table private.user_attribution
 add column if not exists first_touch_source text,
 add column if not exists first_touch_medium text,
 add column if not exists first_touch_campaign text,
 add column if not exists first_touch_content text,
 add column if not exists first_touch_install_id text,
 add column if not exists first_touch_at timestamptz,
 add column if not exists last_touch_source text,
 add column if not exists last_touch_medium text,
 add column if not exists last_touch_campaign text,
 add column if not exists last_touch_content text,
 add column if not exists last_touch_install_id text,
 add column if not exists last_touch_at timestamptz;

-- Creative and keyword details remain private and never authorize content.
alter table private.install_attribution
 add column if not exists utm_content text,
 add column if not exists utm_term text;

-- A public website click is only logged if the existing consent/URL/rate
-- validation RPC also queues its deduplicated server-side Lead event.
create or replace function public.record_web_ad_click(
 p_event_id uuid,p_consent boolean,p_fbclid text default '',
 p_fbc text default '',p_fbp text default '',p_url text default '',
 p_utm_source text default '',p_utm_medium text default '',
 p_utm_campaign text default '',p_utm_content text default ''
) returns boolean language plpgsql security definer set search_path = ''
as $$
declare ok boolean;
begin
 if p_event_id is null then return false; end if;
 ok:=public.record_web_measurement('Lead',p_event_id,p_consent,p_fbclid,p_fbc,p_fbp,p_url);
 if not ok then return false; end if;
 insert into public.ad_clicks(event_id,fbclid,fbc,fbp,ip,user_agent,
  utm_source,utm_medium,utm_campaign,utm_content,page_url)
 values(p_event_id,left(p_fbclid,500),left(p_fbc,600),left(p_fbp,200),
  private.req_ip(),left(private.req_header('user-agent'),400),
  left(p_utm_source,100),left(p_utm_medium,100),
  left(p_utm_campaign,200),left(p_utm_content,200),left(p_url,500))
 on conflict(event_id) do nothing;
 return true;
end
$$;
revoke all on function public.record_web_ad_click(uuid,boolean,text,text,text,text,text,text,text,text)
 from public;
grant execute on function public.record_web_ad_click(uuid,boolean,text,text,text,text,text,text,text,text)
 to anon,authenticated;

-- Preserve the existing install-identity and source_of rules. A local
-- install_secret proves the session possesses the original installation.
-- Existing organic accounts keep organic first-touch even when signing in
-- after a Meta ad install; last-touch still records the Meta campaign.
create or replace function public.link_install_touch_v2(
 p_install_id text,p_install_secret text,p_details jsonb default '{}'::jsonb
) returns text language plpgsql security definer set search_path = ''
as $$
declare uid uuid:=auth.uid(); i public.installs%rowtype;
 a private.install_attribution%rowtype; first_src text;
 same_source boolean; content_ text; term_ text; touch_at timestamptz;
begin
 if uid is null then raise exception 'session required' using errcode='42501'; end if;
 if jsonb_typeof(p_details)<>'object' or octet_length(p_details::text)>1024 then
  raise exception 'invalid campaign details';
 end if;
 select * into i from public.installs where install_id=p_install_id;
 if not found or i.install_secret is distinct from p_install_secret then
  raise exception 'invalid install credentials' using errcode='42501';
 end if;
 select * into a from private.install_attribution where install_id=p_install_id;
 if not found or a.confidence=0 then return private.source_of(uid); end if;
 content_:=nullif(left(trim(coalesce(p_details->>'utm_content','')),200),'');
 term_:=nullif(left(trim(coalesce(p_details->>'utm_term','')),200),'');
 update private.install_attribution set
  utm_content=coalesce(utm_content,content_),
  utm_term=coalesce(utm_term,term_)
 where install_id=p_install_id;
 select * into a from private.install_attribution where install_id=p_install_id;
 first_src:=case when private.source_of(uid)='ads' then 'meta' else 'organic' end;
 same_source:=(first_src='meta' and a.classification='meta')
    or (first_src='organic' and a.classification<>'meta');
 touch_at:=case when a.install_timestamp between 946684800 and 4102444800
   then to_timestamp(a.install_timestamp) else i.created_at end;
 insert into private.user_attribution as ua(
  user_id,first_touch_source,first_touch_medium,first_touch_campaign,
  first_touch_content,first_touch_install_id,first_touch_at,
  last_touch_source,last_touch_medium,last_touch_campaign,
  last_touch_content,last_touch_install_id,last_touch_at)
 values(uid,first_src,
  case when same_source then a.utm_medium end,
  case when same_source then a.utm_campaign end,
  case when same_source then a.utm_content end,
  p_install_id,touch_at,
  a.classification,a.utm_medium,a.utm_campaign,a.utm_content,p_install_id,touch_at)
 on conflict(user_id) do update set
  first_touch_source=coalesce(ua.first_touch_source,excluded.first_touch_source),
  first_touch_medium=coalesce(ua.first_touch_medium,excluded.first_touch_medium),
  first_touch_campaign=coalesce(ua.first_touch_campaign,excluded.first_touch_campaign),
  first_touch_content=coalesce(ua.first_touch_content,excluded.first_touch_content),
  first_touch_install_id=coalesce(ua.first_touch_install_id,excluded.first_touch_install_id),
  first_touch_at=coalesce(ua.first_touch_at,excluded.first_touch_at),
  last_touch_source=case when ua.last_touch_at is null or excluded.last_touch_at>=ua.last_touch_at then excluded.last_touch_source else ua.last_touch_source end,
  last_touch_medium=case when ua.last_touch_at is null or excluded.last_touch_at>=ua.last_touch_at then excluded.last_touch_medium else ua.last_touch_medium end,
  last_touch_campaign=case when ua.last_touch_at is null or excluded.last_touch_at>=ua.last_touch_at then excluded.last_touch_campaign else ua.last_touch_campaign end,
  last_touch_content=case when ua.last_touch_at is null or excluded.last_touch_at>=ua.last_touch_at then excluded.last_touch_content else ua.last_touch_content end,
  last_touch_install_id=case when ua.last_touch_at is null or excluded.last_touch_at>=ua.last_touch_at then excluded.last_touch_install_id else ua.last_touch_install_id end,
  last_touch_at=greatest(coalesce(ua.last_touch_at,'-infinity'::timestamptz),excluded.last_touch_at),
  updated_at=now();
 return private.source_of(uid);
end
$$;
revoke all on function public.link_install_touch_v2(text,text,jsonb) from public,anon;
grant execute on function public.link_install_touch_v2(text,text,jsonb) to authenticated;
