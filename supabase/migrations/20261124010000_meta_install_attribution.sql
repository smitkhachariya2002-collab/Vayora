-- Vayora 1.0.12: first-install attribution, preserving the 1.0.11 schema.
-- Review and run on a disposable Supabase database before production.
-- No backfill changes existing users' immutable source labels.
alter table public.installs
  add column if not exists utm_source text,
  add column if not exists utm_medium text,
  add column if not exists utm_content text,
  add column if not exists utm_term text,
  add column if not exists click_ts timestamptz,
  add column if not exists install_ts timestamptz,
  add column if not exists attribution_class text,
  add column if not exists confidence smallint not null default 0,
  add column if not exists updated_at timestamptz not null default now();

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

-- Only this function defines the canonical ad-source string and accepted aliases.
create or replace function private.meta_source(p_source text)
returns text language sql immutable set search_path = ''
as $$
 select case when lower(trim(coalesce(p_source,''))) in
 ('meta','facebook','fb','instagram','ig','messenger','threads','audience_network')
 then 'meta' else lower(trim(coalesce(p_source,''))) end
$$;

-- A referrer is a query string, not arbitrary JSON. Keep only explicit UTM keys.
create or replace function private.parse_install_referrer(p_raw text)
returns jsonb language sql immutable set search_path = ''
as $$
 with parts as (
   select split_part(pair,'=',1) as k,
          substring(pair from position('=' in pair)+1) as v
   from regexp_split_to_table(
     replace(replace(left(coalesce(p_raw,''),2048),'%3D','='),'%3d','=') ,'&') pair
   where position('=' in pair)>0
 ), mapped as (
   select lower(k) k,
     left(replace(replace(replace(replace(v,'%20',' '),'%2B','+'),'%26','&'),'%3D','='),200) v
   from parts
 )
 select coalesce(jsonb_object_agg(k,v),'{}'::jsonb)
 from mapped where k in ('utm_source','utm_medium','utm_campaign','utm_content','utm_term')
$$;

create or replace function private.classify_install_referrer(p_status text,p_raw text)
returns text language plpgsql immutable set search_path = ''
as $$
declare u jsonb:=private.parse_install_referrer(p_raw);
        s text:=private.meta_source(u->>'utm_source');
        m text:=lower(trim(coalesce(u->>'utm_medium','')));
begin
 if p_status in ('unavailable','not_available','unknown') then return 'unknown'; end if;
 if s='meta' then return 'meta'; end if;
 if s='google-play' and m='organic' then return 'organic'; end if;
 if p_status='none' and coalesce(p_raw,'')='' then return 'direct'; end if;
 if coalesce(p_raw,'')='' and p_status='ok' then return 'organic'; end if;
 if coalesce(p_raw,'')='' then return 'direct'; end if;
 return 'other';
end
$$;

-- Expose one safe, authenticated install RPC. Previous 4-argument RPC stays intact.
-- A temporary Play Services failure is not frozen into the user's first touch.
create or replace function public.record_install_attributed(
 p_install_id text,p_referrer_status text,p_raw_referrer text,p_install_secret text,
 p_click_ts bigint default null,p_install_ts bigint default null
) returns text language plpgsql security definer set search_path = ''
as $$
declare uid uuid:=auth.uid(); parsed jsonb; cls text; src text; conf smallint;
        old public.installs%rowtype; ts_click timestamptz; ts_install timestamptz;
begin
 if uid is null then raise exception 'session required' using errcode='42501'; end if;
 if length(coalesce(p_install_id,'')) not between 8 and 100 then raise exception 'invalid install ID'; end if;
 if length(coalesce(p_install_secret,'')) not between 8 and 200 then raise exception 'invalid install secret'; end if;
 if length(coalesce(p_raw_referrer,''))>2048 then raise exception 'referrer too long'; end if;
 cls:=private.classify_install_referrer(p_referrer_status,p_raw_referrer);
 if cls='unknown' then return 'unknown'; end if;
 parsed:=private.parse_install_referrer(p_raw_referrer);
 src:=case when cls='meta' then 'ads' else 'organic' end;
 conf:=case when cls='meta' then 5 when cls='organic' then 4 when cls='other' then 3 else 2 end;
 if p_click_ts between 946684800 and 4102444800 then ts_click:=to_timestamp(p_click_ts); end if;
 if p_install_ts between 946684800 and 4102444800 then ts_install:=to_timestamp(p_install_ts); end if;

 select * into old from public.installs where install_id=p_install_id for update;
 if found then
   if old.install_secret is distinct from left(p_install_secret,200)
      or old.user_id is distinct from uid then
     raise exception 'install already belongs to another identity' using errcode='42501';
   end if;
   if conf>old.confidence then
     update public.installs set
       source=src,referrer_status=left(p_referrer_status,100),
       raw_referrer=left(p_raw_referrer,2048),
       utm_source=parsed->>'utm_source',utm_medium=parsed->>'utm_medium',
       utm_campaign=parsed->>'utm_campaign',utm_content=parsed->>'utm_content',
       utm_term=parsed->>'utm_term',click_ts=ts_click,install_ts=ts_install,
       attribution_class=cls,confidence=conf,updated_at=now()
     where install_id=p_install_id;
   end if;
 else
   insert into public.installs(install_id,user_id,source,referrer_status,raw_referrer,
     utm_campaign,install_secret,utm_source,utm_medium,utm_content,utm_term,
     click_ts,install_ts,attribution_class,confidence)
   values(p_install_id,uid,src,left(p_referrer_status,100),left(p_raw_referrer,2048),
     parsed->>'utm_campaign',left(p_install_secret,200),parsed->>'utm_source',
     parsed->>'utm_medium',parsed->>'utm_content',parsed->>'utm_term',
     ts_click,ts_install,cls,conf);
 end if;
 -- Respect the existing immutable user acquisition label for legacy installs.
 insert into private.user_sources(user_id,source)
 values(uid,(select source from public.installs where install_id=p_install_id))
 on conflict(user_id) do nothing;

 -- Collect campaign dimensions separately; acquisition source remains immutable.
 insert into private.user_attribution as ua(
   user_id,first_touch_source,first_touch_medium,first_touch_campaign,
   first_touch_content,first_touch_install_id,first_touch_at,
   last_touch_source,last_touch_medium,last_touch_campaign,
   last_touch_content,last_touch_install_id,last_touch_at)
 values(uid,cls,parsed->>'utm_medium',parsed->>'utm_campaign',
   parsed->>'utm_content',p_install_id,now(),cls,
   parsed->>'utm_medium',parsed->>'utm_campaign',parsed->>'utm_content',
   p_install_id,now())
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
revoke all on function public.record_install_attributed(text,text,text,text,bigint,bigint)
  from public,anon;
grant execute on function public.record_install_attributed(text,text,text,text,bigint,bigint)
  to authenticated;
revoke all on function private.meta_source(text) from public,anon,authenticated;
revoke all on function private.parse_install_referrer(text) from public,anon,authenticated;
revoke all on function private.classify_install_referrer(text,text) from public,anon,authenticated;

-- Only source_of remains authoritative for user-facing ads/organic segmentation.
-- Existing Meta purchase, consent, and payment verification remain unchanged.
