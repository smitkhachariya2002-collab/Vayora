-- Rollback-only approval/upload/audience tests; the final report intentionally aborts all fixtures.
do $outer$
declare
  owner_id uuid := gen_random_uuid(); creator uuid := gen_random_uuid();
  ads_viewer uuid := gen_random_uuid(); org_viewer uuid := gen_random_uuid();
  cid uuid; pid uuid; admin_pid uuid; plan_id uuid; aud text; post_aud text; src text; viewer uuid;
  base text; rejected boolean; n int; expected boolean; total int; failed int; fail_list text;
begin
  create temp table t_res (name text, ok boolean) on commit drop;
  create function pg_temp.rec(label text, pass boolean) returns void language plpgsql security definer as $f$ begin insert into pg_temp.t_res values(label,coalesce(pass,false)); end $f$;
  create function pg_temp.imp(uid uuid) returns void language plpgsql as $f$ begin
    perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated','is_anonymous',false)::text,true);
    perform set_config('request.jwt.claim.sub',uid::text,true);
    set local role authenticated;
  end $f$;
  insert into private.owner_bootstrap(email) values('upload-owner@example.test') on conflict do nothing;
  insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,is_anonymous) values
    (owner_id,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','upload-owner@example.test',now(),false),
    (creator,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','upload-creator@example.test',now(),false),
    (ads_viewer,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','upload-ads@example.test',now(),false),
    (org_viewer,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','upload-organic@example.test',now(),false);
  insert into private.user_sources(user_id,source) values(creator,'ads'),(ads_viewer,'ads'),(org_viewer,'organic');
  select id into plan_id from public.plans where code='gold';
  insert into public.subscriptions(user_id,plan_id,plan_code,plan_name,kind,ends_at) values(creator,plan_id,'gold','Gold','admin_grant',now()+interval '1 day');
  perform pg_temp.imp(creator); perform public.accept_consent('v1'); reset role;
  foreach aud in array array['all','ads','organic'] loop
    perform pg_temp.imp(creator);
    insert into public.channels(name) values('Upload matrix '||aud) returning id into cid;
    rejected := false;
    begin insert into storage.objects(bucket_id,name) values('media',cid||'/blocked.mp4'); exception when insufficient_privilege then rejected := true; end;
    reset role;
    perform pg_temp.rec(aud||': unapproved channel cannot upload media',rejected);
    perform pg_temp.imp(owner_id); perform public.review_channel(cid,true,aud); reset role;
    base := cid||'/'||gen_random_uuid();
    perform pg_temp.imp(creator);
    insert into storage.objects(bucket_id,name) values('media',base||'/main.mp4'),('media',base||'/thumb.jpg'),('media',base||'/trailer.mp4');
    insert into public.posts(channel_id,title,status,audience) values(cid,'Creator upload','published','all') returning id into pid;
    insert into public.post_items(post_id,media_key,thumbnail_key,trailer_key,mime,size_bytes,is_premium) values(pid,base||'/main.mp4',base||'/thumb.jpg',base||'/trailer.mp4','video/mp4',1024,false);
    reset role;
    perform pg_temp.rec(aud||': approved creator saves video, thumbnail and trailer',
      (select count(*)=3 from storage.objects where bucket_id='media' and name like base||'/%') and exists(select 1 from public.post_items where post_id=pid and thumbnail_key is not null and trailer_key is not null));
    perform pg_temp.rec(aud||': user upload stays draft and inherits admin channel audience',
      exists(select 1 from public.posts where id=pid and status='draft' and audience=aud and created_by=creator));
    perform pg_temp.imp(ads_viewer); select count(*) into n from public.posts where id=pid; reset role;
    perform pg_temp.rec(aud||': draft not visible to ads viewer',n=0);
    perform pg_temp.imp(org_viewer); select count(*) into n from public.posts where id=pid; reset role;
    perform pg_temp.rec(aud||': draft not visible to organic viewer',n=0);
    perform pg_temp.imp(creator);
    rejected := false; begin update public.post_items set media_key=gen_random_uuid()||'/other.mp4' where post_id=pid; exception when insufficient_privilege then rejected:=true; end;
    reset role; perform pg_temp.rec(aud||': cannot attach another channel full video',rejected);
    perform pg_temp.imp(creator);
    rejected := false; begin update public.post_items set thumbnail_key=gen_random_uuid()||'/other.jpg' where post_id=pid; exception when insufficient_privilege then rejected:=true; end;
    reset role; perform pg_temp.rec(aud||': cannot attach another channel thumbnail',rejected);
    perform pg_temp.imp(creator);
    rejected := false; begin update public.post_items set trailer_key=gen_random_uuid()||'/other.mp4' where post_id=pid; exception when insufficient_privilege then rejected:=true; end;
    reset role; perform pg_temp.rec(aud||': cannot attach another channel trailer',rejected);
    -- Admin can upload directly into every approved channel, including another user's channel.
    perform pg_temp.imp(owner_id);
    insert into public.posts(channel_id,title,audience,status) values(cid,'Admin bulk image',aud,'draft') returning id into admin_pid;
    insert into storage.objects(bucket_id,name) values('media',cid||'/'||admin_pid||'.jpg');
    insert into public.post_items(post_id,media_key,thumbnail_key,mime,size_bytes,is_premium) values(admin_pid,cid||'/'||admin_pid||'.jpg',cid||'/'||admin_pid||'.jpg','image/jpeg',1024,false);
    update public.posts set status='published' where id=admin_pid;
    reset role;
    perform pg_temp.rec(aud||': admin bulk upload can publish in a user-created channel',exists(select 1 from public.posts where id=admin_pid and status='published'));
    foreach post_aud in array array['all','ads','organic'] loop
      perform pg_temp.imp(owner_id); update public.posts set status='published',audience=post_aud where id=pid; reset role;
      foreach src in array array['ads','organic'] loop
        viewer := case when src='ads' then ads_viewer else org_viewer end;
        expected := (aud='all' or aud=src) and (post_aud='all' or post_aud=src);
        perform pg_temp.imp(viewer);
        select count(*) into n from public.posts where id=pid;
        reset role;
        perform pg_temp.rec(aud||' channel / '||post_aud||' video / '||src||': post visibility', (n=1)=expected);
        perform pg_temp.imp(viewer);
        select count(*) into n from public.post_items where post_id=pid;
        reset role;
        perform pg_temp.rec(aud||' channel / '||post_aud||' video / '||src||': media metadata visibility',(n=1)=expected);
        perform pg_temp.imp(viewer);
        select count(*) into n from storage.objects where bucket_id='media' and name in(base||'/main.mp4',base||'/thumb.jpg',base||'/trailer.mp4');
        reset role;
        perform pg_temp.rec(aud||' channel / '||post_aud||' video / '||src||': full, thumbnail and trailer access',(n=3)=expected and (expected or n=0));
      end loop;
    end loop;
  end loop;
  select count(*),count(*) filter(where not ok),string_agg(name,' | ') filter(where not ok) into total,failed,fail_list from t_res;
  raise exception 'RESULT total=% failed=% :: %',total,failed,coalesce(fail_list,'none');
end $outer$;
