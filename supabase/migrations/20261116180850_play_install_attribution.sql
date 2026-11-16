-- Additive attribution only: existing accounts, plans and source-based access remain unchanged.
create table private.install_attribution (
 install_id text primary key references public.installs(install_id) on delete cascade,
 classification text not null check(classification in ('meta','organic','direct','other','unknown')),
 confidence integer not null check(confidence in (0,20,40,100)),
 referrer_status text not null,
 utm_source text, utm_medium text, utm_campaign text,
 click_timestamp bigint, install_timestamp bigint,
 installer text, updated_at timestamptz not null default now()
);
alter table private.install_attribution enable row level security;
revoke all on private.install_attribution from public, anon, authenticated;

create or replace function public.record_install_v2(p_install_id text, p_install_secret text, p_attribution jsonb)
returns text language plpgsql security definer set search_path='' as $$
declare
 uid uuid:=auth.uid(); src text; existing public.installs; params jsonb;
 classification text; confidence integer; status text; source text; medium text;
begin
 if uid is null then raise exception 'not authenticated' using errcode='28000'; end if;
 if p_install_id is null or length(p_install_id) not between 8 and 100
  or p_install_secret is null or length(p_install_secret) not between 16 and 200
  or jsonb_typeof(p_attribution)<>'object' or octet_length(p_attribution::text)>16384
 then raise exception 'invalid install attribution'; end if;
 params:=coalesce(p_attribution->'params','{}'::jsonb);
 source:=lower(left(coalesce(params->>'utm_source',''),200));
 medium:=lower(left(coalesce(params->>'utm_medium',''),200));
 status:=case when p_attribution->>'status' in ('play_referrer','apk_define') then p_attribution->>'status' else 'unavailable' end;
 classification:=case when source in ('meta','facebook','instagram','ig','fb') then 'meta'
  when medium='organic' or source in ('organic','google-play') then 'organic'
  when source='direct' then 'direct' when source<>'' then 'other' else 'unknown' end;
 confidence:=case when status='play_referrer' then 100 when status='apk_define' then 40 when classification='organic' then 20 else 0 end;
 -- Client referrers are useful attribution evidence, never proof of a purchase.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_install_id,0));
 select * into existing from public.installs where install_id=p_install_id for update;
 if found and existing.install_secret is distinct from p_install_secret then raise exception 'install secret mismatch' using errcode='42501'; end if;
 src:=case when classification='meta' then 'ads' else 'organic' end;
 if existing.install_id is not null and confidence=0 then src:=existing.source; end if;
 insert into private.user_sources(user_id,source) values(uid,src) on conflict(user_id) do nothing;
 src:=private.source_of(uid);
 insert into public.installs(install_id,user_id,source,referrer_status,raw_referrer,utm_campaign,install_secret)
 values(p_install_id,uid,src,status,case when classification='meta' then 'utm_source=meta' else '' end,left(params->>'utm_campaign',300),p_install_secret)
 on conflict(install_id) do nothing;
 insert into private.install_attribution(install_id,classification,confidence,referrer_status,utm_source,utm_medium,utm_campaign,click_timestamp,install_timestamp,installer)
 values(p_install_id,classification,confidence,status,source,medium,left(params->>'utm_campaign',300),
  case when p_attribution->>'click_timestamp' ~ '^[0-9]{1,12}$' then (p_attribution->>'click_timestamp')::bigint end,
  case when p_attribution->>'install_timestamp' ~ '^[0-9]{1,12}$' then (p_attribution->>'install_timestamp')::bigint end,left(p_attribution->>'installer',200))
 on conflict(install_id) do update set classification=excluded.classification,confidence=excluded.confidence,referrer_status=excluded.referrer_status,
  utm_source=excluded.utm_source,utm_medium=excluded.utm_medium,utm_campaign=excluded.utm_campaign,
  click_timestamp=excluded.click_timestamp,install_timestamp=excluded.install_timestamp,installer=excluded.installer,updated_at=now()
 where excluded.confidence>private.install_attribution.confidence;
 return src;
end $$;
revoke all on function public.record_install_v2(text,text,jsonb) from public,anon;
grant execute on function public.record_install_v2(text,text,jsonb) to authenticated;
