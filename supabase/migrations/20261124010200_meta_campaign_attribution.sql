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
create or replace function public.link_install_touch_v2(p_install_id text,p_install_secret text)
returns text language plpgsql security definer set search_path = ''
as $$
declare uid uuid:=auth.uid(); i public.installs%rowtype;
 a private.install_attribution%rowtype; first_src text;
begin
 if uid is null then raise exception 'session required' using errcode='42501'; end if;
 select * into i from public.installs where install_id=p_install_id;
 if not found or i.install_secret is distinct from p_install_secret then
  raise exception 'invalid install credentials' using errcode='42501';
 end if;
 select * into a from private.install_attribution where install_id=p_install_id;
 if not found or a.confidence=0 then return private.source_of(uid); end if;
 first_src:=case when private.source_of(uid)='ads' then 'meta' else 'organic' end;
 insert into private.user_attribution as ua(
  user_id,first_touch_source,first_touch_medium,first_touch_campaign,
  first_touch_content,first_touch_install_id,first_touch_at,
  last_touch_source,last_touch_medium,last_touch_campaign,
  last_touch_content,last_touch_install_id,last_touch_at)
 values(uid,first_src,
  case when first_src='meta' then a.utm_medium end,
  case when first_src='meta' then a.utm_campaign end,
  null,p_install_id,now(),
  a.classification,a.utm_medium,a.utm_campaign,null,p_install_id,now())
 on conflict(user_id) do update set
  first_touch_source=coalesce(ua.first_touch_source,excluded.first_touch_source),
  first_touch_medium=coalesce(ua.first_touch_medium,excluded.first_touch_medium),
  first_touch_campaign=coalesce(ua.first_touch_campaign,excluded.first_touch_campaign),
  first_touch_content=coalesce(ua.first_touch_content,excluded.first_touch_content),
  first_touch_install_id=coalesce(ua.first_touch_install_id,excluded.first_touch_install_id),
  first_touch_at=coalesce(ua.first_touch_at,excluded.first_touch_at),
  last_touch_source=excluded.last_touch_source,
  last_touch_medium=excluded.last_touch_medium,
  last_touch_campaign=excluded.last_touch_campaign,
  last_touch_content=excluded.last_touch_content,
  last_touch_install_id=excluded.last_touch_install_id,
  last_touch_at=now(),updated_at=now();
 return private.source_of(uid);
end
$$;
revoke all on function public.link_install_touch_v2(text,text) from public,anon;
grant execute on function public.link_install_touch_v2(text,text) to authenticated;
