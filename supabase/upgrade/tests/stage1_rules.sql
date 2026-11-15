-- Rollback-only test harness: impersonates users, raises an exception at the end whose text is the report.
-- Run with psql against a database that has all migrations applied. The expected 'error' is the report;
-- the run PASSES when the report contains no 'FAIL' lines.

do $outer$
declare
  owner_id uuid := gen_random_uuid(); a uuid := gen_random_uuid(); b uuid := gen_random_uuid();
  m uuid := gen_random_uuid(); am uuid := gen_random_uuid(); g uuid := gen_random_uuid();
  c_all uuid; c_org uuid; c_ads uuid; c_pen uuid; c_new uuid; p_all uuid; p_new uuid;
  plan_gold uuid; n int; ok boolean; raised boolean; r1 text; r2 text; r3 text; r4 text; r5 text; v jsonb; t text;
  fail_list text; total int; failed int;
begin
  insert into private.owner_bootstrap(email) values ('owner@example.test') on conflict do nothing;
  create temp table t_res (n text, ok boolean) on commit drop;
  create function pg_temp.rec(nm text, o boolean) returns void language plpgsql security definer as $f$ begin insert into pg_temp.t_res values (nm, coalesce(o,false)); end $f$;
  create function pg_temp.imp(uid uuid, anon boolean) returns void language plpgsql as $f$
  begin
    perform set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated','is_anonymous',anon)::text, true);
    perform set_config('request.jwt.claim.sub', uid::text, true);
    set local role authenticated;
  end $f$;

  insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, is_anonymous) values
   (owner_id,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','owner@example.test',now(),false),
   (a,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',null,null,true),
   (b,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',null,null,true),
   (g,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',null,null,true),
   (m,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','m@example.test',now(),false),
   (am,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','am@example.test',now(),false);
  perform pg_temp.rec('owner bootstrap by confirmed email', exists(select 1 from public.admins where user_id=owner_id and role='owner'));
  perform pg_temp.rec('profile guest flag', (select is_guest from public.profiles where id=a) and not (select is_guest from public.profiles where id=m));

  perform pg_temp.imp(a,true); r1 := public.record_install('inst-ads-0001','ok','utm_source%3Dmeta%26utm_medium%3Dpaid_social%26utm_campaign%3Dapk','s'); reset role;
  perform pg_temp.imp(b,true); r2 := public.record_install('inst-org-0001','ok','utm_source=google','s'); r3 := public.record_install('inst-org-0002','ok','utm_source=facebook','s'); reset role;
  perform pg_temp.imp(m,false); r4 := public.record_install('inst-mem-0001','ok','','s'); reset role;
  perform pg_temp.imp(am,false); r5 := public.record_install('inst-ads-0002','ok','UTM_SOURCE=Instagram&utm_medium=x','s'); reset role;
  perform pg_temp.imp(g,true); perform public.record_install('inst-ads-0003','ok','utm_source=ig','s'); reset role;
  perform pg_temp.rec('meta referrer (url-encoded) -> ads', r1='ads');
  perform pg_temp.rec('google referrer -> organic', r2='organic');
  perform pg_temp.rec('first touch kept (later ads referrer ignored)', r3='organic' and private.source_of(b)='organic');
  perform pg_temp.rec('empty referrer -> organic', r4='organic');
  perform pg_temp.rec('Instagram any-case -> ads', r5='ads');
  update public.meta_settings set enabled=true, pixel_id='1234567890', capi_token='tok';
  perform pg_temp.imp(a,true); perform public.record_install('inst-ads-0001','ok','utm_source=meta','s'); reset role;
  perform pg_temp.rec('AppInstall event only for ads installs (organic/Play send nothing)',
    (select count(*) from public.meta_events where event_name='AppInstall' and user_id in (b,m))=0);
  update public.meta_settings set enabled=false, pixel_id='', capi_token='';
  raised := false; begin update private.user_sources set source='ads' where user_id=b; exception when others then raised := true; end;
  perform pg_temp.rec('source UPDATE blocked even for postgres/admin', raised);
  raised := false; begin delete from private.user_sources where user_id=b; exception when others then raised := true; end;
  perform pg_temp.rec('source DELETE blocked', raised);
  update auth.users set is_anonymous=false, email='g@example.test', email_confirmed_at=now() where id=g;
  perform pg_temp.rec('guest->email keeps id and source', (select not is_guest from public.profiles where id=g) and private.source_of(g)='ads');

  insert into public.channels (name, audience, status, review_status) values ('All ch','all','published','approved') returning id into c_all;
  insert into public.channels (name, audience, status, review_status) values ('Org ch','organic','published','approved') returning id into c_org;
  insert into public.channels (name, audience, status, review_status) values ('Ads ch','ads','published','approved') returning id into c_ads;
  insert into public.channels (name, audience, status, review_status, created_by) values ('Pending ch','all','draft','pending', m) returning id into c_pen;
  insert into public.posts (channel_id, title, audience, status) values (c_all,'post all','all','published') returning id into p_all;
  insert into public.posts (channel_id, title, audience, status) values (c_org,'post org','organic','published');
  insert into public.posts (channel_id, title, audience, status) values (c_ads,'post ads','ads','published');
  insert into public.post_items (post_id, media_key, thumbnail_key, trailer_key, is_premium) values
    (p_all, c_all||'/'||p_all||'/full.mp4', c_all||'/'||p_all||'/thumb.jpg', c_all||'/'||p_all||'/trailer.mp4', true);
  insert into storage.objects (bucket_id, name) values ('media', c_all||'/'||p_all||'/full.mp4'), ('media', c_all||'/'||p_all||'/thumb.jpg'), ('media', c_all||'/'||p_all||'/trailer.mp4');
  select id into plan_gold from public.plans where code='gold';

  perform pg_temp.imp(a,true); select count(*) into n from public.channels where id in (c_all,c_org,c_ads); reset role;
  perform pg_temp.rec('ads guest sees all+ads channels (2)', n=2);
  perform pg_temp.imp(a,true); select count(*) into n from public.posts where channel_id in (c_all,c_org,c_ads); reset role;
  perform pg_temp.rec('ads guest sees all+ads posts (2)', n=2);
  perform pg_temp.imp(b,true); select count(*) into n from public.channels where id in (c_all,c_org,c_ads); reset role;
  perform pg_temp.rec('organic guest sees all+organic channels (2)', n=2);
  perform pg_temp.imp(b,true); select count(*) into n from public.channels where id = c_ads; reset role;
  perform pg_temp.rec('organic guest cannot see ads channel', n=0);
  perform pg_temp.imp(b,true); select count(*) into n from public.posts where channel_id = c_ads; reset role;
  perform pg_temp.rec('organic guest cannot see ads posts', n=0);
  update public.profiles set ads_access_status='approved' where id=m;
  perform pg_temp.imp(m,false); select count(*) into n from public.channels where id = c_ads; reset role;
  perform pg_temp.rec('approved organic WITHOUT plan (paid mode) cannot see ads channel', n=0);
  perform pg_temp.imp(m,false); raised := false;
  begin insert into public.channels(name) values ('Free organic cannot create'); exception when insufficient_privilege then raised := true; end; reset role;
  perform pg_temp.rec('organic free user cannot create channel', raised);
  perform pg_temp.imp(am,false); raised := false;
  begin insert into public.channels(name) values ('Free ads cannot create'); exception when insufficient_privilege then raised := true; end; reset role;
  perform pg_temp.rec('ads free user cannot create channel', raised);
  insert into public.subscriptions (user_id, plan_id, plan_code, plan_name, kind, ends_at) values (am, plan_gold,'gold','Gold','admin_grant',now()+interval '1 day');
  perform pg_temp.imp(am,false); raised := false;
  begin insert into public.channels(name) values ('Paid ads can create'); exception when others then raised := true; end; reset role;
  perform pg_temp.rec('ads premium user can create a pending channel', not raised and exists(select 1 from public.channels where created_by=am and review_status='pending'));
  -- A guest upgrade changes auth.users immediately; the old access token may still say guest.
  perform pg_temp.imp(am,true); raised := false;
  begin insert into public.channels(name) values ('Upgraded paid ads old token'); exception when others then raised := true; end; reset role;
  perform pg_temp.rec('upgraded Premium member can create with stale guest JWT', not raised and exists(select 1 from public.channels where name='Upgraded paid ads old token' and created_by=am and review_status='pending' and status='draft'));
  perform pg_temp.imp(am,true); select public.is_member() into ok; reset role;
  perform pg_temp.rec('saved member status overrides stale guest JWT', ok);
  perform pg_temp.imp(a,false); select public.is_member() into ok; reset role;
  perform pg_temp.rec('actual guest cannot become a member through a member JWT flag', not ok);
  insert into public.subscriptions (user_id, plan_id, plan_code, plan_name, kind, ends_at) values (a, plan_gold,'gold','Gold','admin_grant',now()+interval '1 day');
  perform pg_temp.imp(a,true); raised := false;
  begin insert into public.channels(name) values ('Paid guest must save account'); exception when insufficient_privilege then raised := true; end; reset role;
  perform pg_temp.rec('Premium guest must still save account before channel creation', raised);
  delete from public.subscriptions where user_id=a;
  update public.subscriptions set revoked=true where user_id=am;
  perform pg_temp.imp(am,false); raised := false;
  begin insert into public.channels(name) values ('Revoked premium cannot create'); exception when insufficient_privilege then raised := true; end; reset role;
  perform pg_temp.rec('revoked Premium cannot create channel', raised);
  delete from public.subscriptions where user_id=am;
  insert into public.subscriptions (user_id, plan_id, plan_code, plan_name, kind, ends_at) values (m, plan_gold,'gold','Gold','admin_grant', now()+interval '1 day');
  perform pg_temp.imp(m,false); select count(*) into n from public.channels where id = c_ads; reset role;
  perform pg_temp.rec('approved organic WITH plan sees ads channel', n=1);
  update public.profiles set ads_access_status='pending' where id=m;
  perform pg_temp.imp(m,false); select count(*) into n from public.channels where id = c_ads; reset role;
  perform pg_temp.rec('pending organic with plan cannot see ads channel', n=0);
  perform pg_temp.imp(m,false); select count(*) into n from public.posts where channel_id=c_ads; reset role;
  perform pg_temp.rec('organic Premium pending admin approval cannot see ads-channel videos', n=0);
  perform pg_temp.imp(m,false); t := public.quota_bytes()::text; reset role;
  perform pg_temp.rec('organic Premium pending admin approval still has 2 TB storage', t='2199023255552');
  perform pg_temp.imp(owner_id,false); select count(*) into n from public.channels where id in (c_all,c_org,c_ads,c_pen); reset role;
  perform pg_temp.rec('owner sees everything (4)', n=4);
  perform pg_temp.imp(m,false); select count(*) into n from public.channels where id = c_pen; reset role;
  perform pg_temp.rec('creator sees own pending channel', n=1);
  perform pg_temp.imp(b,true); select count(*) into n from public.channels where id = c_pen; reset role;
  perform pg_temp.rec('others never see pending channel', n=0);
  update public.channels set hidden=true where id=c_all;
  perform pg_temp.imp(a,true); select count(*) into n from public.channels where id = c_all; reset role;
  perform pg_temp.rec('hidden channel never returned', n=0);
  update public.channels set hidden=false where id=c_all;

  perform pg_temp.imp(b,true); select count(*) into n from public.post_items where post_id=p_all; reset role;
  perform pg_temp.rec('premium item row visible (lock shown)', n=1);
  perform pg_temp.imp(b,true); select count(*) into n from storage.objects where bucket_id='media' and name = c_all||'/'||p_all||'/full.mp4'; reset role;
  perform pg_temp.rec('no plan: full video signed URL blocked', n=0);
  perform pg_temp.imp(b,true); select count(*) into n from storage.objects where bucket_id='media' and name in (c_all||'/'||p_all||'/trailer.mp4', c_all||'/'||p_all||'/thumb.jpg'); reset role;
  perform pg_temp.rec('organic guest sees thumbnail but cannot open trailer without login', n=1);
  perform pg_temp.imp(a,true); select count(*) into n from storage.objects where bucket_id='media' and name = c_all||'/'||p_all||'/trailer.mp4'; reset role;
  perform pg_temp.rec('ads guest can sign premium trailer without login or plan', n=1);
  perform pg_temp.imp(a,true); select count(*) into n from storage.objects where bucket_id='media' and name = c_all||'/'||p_all||'/full.mp4'; reset role;
  perform pg_temp.rec('ads guest without plan cannot sign full Premium video', n=0);
  update public.post_items set is_premium=false where post_id=p_all;
  perform pg_temp.imp(b,true); select count(*) into n from storage.objects where bucket_id='media' and name = c_all||'/'||p_all||'/full.mp4'; reset role;
  perform pg_temp.rec('organic guest cannot sign even a free full video before login', n=0);
  perform pg_temp.imp(a,true); select count(*) into n from storage.objects where bucket_id='media' and name = c_all||'/'||p_all||'/full.mp4'; reset role;
  perform pg_temp.rec('ads guest can sign free full video without login', n=1);
  perform pg_temp.imp(m,false); select count(*) into n from storage.objects where bucket_id='media' and name = c_all||'/'||p_all||'/full.mp4'; reset role;
  perform pg_temp.rec('organic signed-in member can sign a free Everyone video', n=1);
  update public.post_items set is_premium=true where post_id=p_all;
  perform pg_temp.imp(m,false); select count(*) into n from storage.objects where bucket_id='media' and name = c_all||'/'||p_all||'/full.mp4'; reset role;
  perform pg_temp.rec('active plan: full video allowed', n=1);
  update public.app_mode set free_mode=true;
  perform pg_temp.imp(g,false); select count(*) into n from storage.objects where bucket_id='media' and name = c_all||'/'||p_all||'/full.mp4'; reset role;
  perform pg_temp.rec('free mode: ads member gets full video', n=1);
  perform pg_temp.imp(b,true); select count(*) into n from storage.objects where bucket_id='media' and name = c_all||'/'||p_all||'/full.mp4'; reset role;
  perform pg_temp.rec('free mode: organic (not approved) still locked', n=0);
  update public.app_mode set free_mode=false;
  perform pg_temp.imp(owner_id,false); select count(*) into n from storage.objects where bucket_id='media' and name = c_all||'/'||p_all||'/full.mp4'; reset role;
  perform pg_temp.rec('admin gets full video', n=1);

  perform pg_temp.imp(m,false);
  insert into public.channels (name, audience, status, review_status, created_by) values ('Mine','ads','published','approved', owner_id) returning id into c_new;
  reset role;
  perform pg_temp.rec('user channel forced pending/draft/all/own', (select review_status='pending' and status='draft' and audience='all' and created_by=m from public.channels where id=c_new));
  perform pg_temp.imp(m,false); raised := false;
  begin update public.channels set review_status='approved' where id=c_new; exception when others then raised := true; end; reset role;
  perform pg_temp.rec('creator cannot self-approve', raised);
  perform pg_temp.imp(m,false); raised := false;
  begin perform public.review_channel(c_new, true, 'organic'); exception when others then raised := true; end; reset role;
  perform pg_temp.rec('non-owner cannot call review_channel', raised);
  perform pg_temp.imp(m,false); raised := false;
  begin insert into public.posts (channel_id, title, status) values (c_new,'x','published'); exception when others then raised := true; end; reset role;
  perform pg_temp.rec('cannot post to unapproved channel', raised);
  perform pg_temp.imp(owner_id,false); perform public.review_channel(c_new, true, 'organic'); reset role;
  perform pg_temp.rec('owner approves with audience', (select review_status='approved' and status='published' and audience='organic' from public.channels where id=c_new));
  perform pg_temp.imp(m,false); raised := false;
  begin insert into public.posts (channel_id, title, status) values (c_new,'x','published'); exception when others then raised := true; end; reset role;
  perform pg_temp.rec('post needs community-rules consent', raised);
  perform pg_temp.imp(m,false); perform public.accept_consent('v1');
  insert into public.posts (channel_id, title, status, audience) values (c_new,'my post','published','ads') returning id into p_new; reset role;
  perform pg_temp.rec('creator posts to own approved channel; audience forced to channel', (select audience='organic' and created_by=m from public.posts where id=p_new));
  perform pg_temp.rec('creator upload forced to draft', (select status='draft' and publish_at is null from public.posts where id=p_new));
  perform pg_temp.imp(m,false); update public.posts set status='published' where id=p_new; reset role;
  perform pg_temp.rec('creator cannot self-publish video', (select status='draft' from public.posts where id=p_new));
  perform pg_temp.imp(b,true); select count(*) into n from public.posts where id=p_new; reset role;
  perform pg_temp.rec('pending video hidden from viewers', n=0);
  perform pg_temp.imp(owner_id,false); update public.posts set status='published', audience='organic' where id=p_new; reset role;
  perform pg_temp.imp(b,true); select count(*) into n from public.posts where id=p_new; reset role;
  perform pg_temp.rec('approved organic video visible to organic viewer', n=1);
  perform pg_temp.imp(a,true); select count(*) into n from public.posts where id=p_new; reset role;
  perform pg_temp.rec('organic video hidden from ads viewer', n=0);
  perform pg_temp.imp(m,false); raised := false;
  begin insert into public.posts (channel_id, title, status) values (c_all,'hack','published'); exception when others then raised := true; end; reset role;
  perform pg_temp.rec('cannot post to someone elses channel', raised);
  perform pg_temp.imp(m,false); update public.channels set description='changed' where id=c_new; reset role;
  perform pg_temp.rec('descriptive edit sends channel back to pending', (select review_status='pending' from public.channels where id=c_new));

  perform pg_temp.imp(m,false); raised := false;
  begin update public.profiles set ads_access_status='approved' where id=m; exception when others then raised := true; end; reset role;
  perform pg_temp.rec('user cannot change own access status', raised);
  perform pg_temp.imp(m,false); raised := false;
  begin update public.profiles set used_bytes=999, display_name='New' where id=m; exception when others then raised := true; end; reset role;
  perform pg_temp.rec('user cannot touch used_bytes', raised or (select used_bytes<>999 from public.profiles where id=m));

  delete from public.subscriptions where user_id=m;
  perform pg_temp.imp(a,true); n := public.quota_bytes(); reset role;
  perform pg_temp.rec('guest quota 0', n=0);
  perform pg_temp.imp(m,false); n := public.quota_bytes(); reset role;
  perform pg_temp.rec('member, paid mode, no plan: quota 0', n=0);
  update public.app_mode set free_mode=true;
  perform pg_temp.imp(m,false); t := (select public.quota_bytes())::text; reset role;
  perform pg_temp.rec('free mode member quota 15 GB', t='16106127360');
  perform pg_temp.imp(m,false); insert into public.cloud_files (user_id,name,storage_path,size_bytes) values (m,'a.jpg', m||'/a.jpg', 1000); reset role;
  perform pg_temp.rec('cloud file counted in used_bytes', (select used_bytes=1000 from public.profiles where id=m));
  perform pg_temp.imp(m,false); raised := false;
  begin insert into public.cloud_files (user_id,name,storage_path,size_bytes) values (m,'big.bin', m||'/big.bin', 20::bigint*1024*1024*1024); exception when others then raised := true; end; reset role;
  perform pg_temp.rec('upload over quota blocked', raised);
  perform pg_temp.imp(a,true); raised := false;
  begin insert into public.cloud_folders (user_id,name) values (a,'x'); exception when others then raised := true; end; reset role;
  perform pg_temp.rec('guest cannot use cloud', raised);
  perform pg_temp.imp(m,false); delete from public.cloud_files where user_id=m; reset role;
  perform pg_temp.rec('deleting file frees used_bytes', (select used_bytes=0 from public.profiles where id=m));
  update public.app_mode set free_mode=false;
  insert into public.subscriptions (user_id, plan_id, plan_code, plan_name, kind, ends_at) values (m, plan_gold,'gold','Gold','admin_grant', now()+interval '1 day');
  perform pg_temp.imp(m,false); t := (select public.quota_bytes())::text; reset role;
  perform pg_temp.rec('active plan quota 2 TB', t='2199023255552');
  delete from public.subscriptions where user_id=m;

  update public.profiles set ads_access_status='none' where id=m;
  perform pg_temp.imp(m,false); raised := false;
  begin perform public.request_full_access(); exception when others then raised := true; end; reset role;
  perform pg_temp.rec('request full access refused in paid mode', raised);
  update public.app_mode set free_mode=true;
  perform pg_temp.imp(m,false); t := public.request_full_access(); reset role;
  perform pg_temp.rec('free mode: organic member request -> pending', t='pending');
  perform pg_temp.imp(am,false); raised := false;
  begin perform public.request_full_access(); exception when others then raised := true; end; reset role;
  perform pg_temp.rec('ads user cannot request (not needed)', raised);
  perform pg_temp.imp(m,false); raised := false;
  begin perform public.set_ads_access(m,'approved'); exception when others then raised := true; end; reset role;
  perform pg_temp.rec('non-owner cannot approve access', raised);
  perform pg_temp.imp(owner_id,false); perform public.set_ads_access(m,'approved'); reset role;
  perform pg_temp.imp(m,false); ok := public.has_ads_access(); reset role;
  perform pg_temp.rec('owner approval grants full access in free mode', ok);
  update public.app_mode set free_mode=false;
  perform pg_temp.imp(m,false); ok := public.has_ads_access(); reset role;
  perform pg_temp.rec('approval alone insufficient in paid mode', not ok);

  update public.plans set free_eligible=true where id=plan_gold;
  update public.app_mode set plans_visible_for='ads';
  perform pg_temp.imp(am,false); ok := public.plans_visible_for_me(); reset role;
  perform pg_temp.imp(m,false); raised := public.plans_visible_for_me(); reset role;
  perform pg_temp.rec('plans visible: ads-only shows ads, hides organic', ok and not raised);
  update public.app_mode set plans_visible_for='none';
  perform pg_temp.imp(am,false); ok := public.plans_visible_for_me(); reset role;
  perform pg_temp.imp(owner_id,false); raised := public.plans_visible_for_me(); reset role;
  perform pg_temp.rec('plans nobody: hidden for users, visible for admin', (not ok) and raised);
  update public.app_mode set plans_visible_for='everyone', free_plans_for='organic';
  perform pg_temp.imp(m,false); ok := public.free_plan_for_me(plan_gold); reset role;
  perform pg_temp.imp(am,false); raised := public.free_plan_for_me(plan_gold); reset role;
  perform pg_temp.rec('free plans organic: organic yes, ads no', ok and not raised);
  update public.app_mode set free_plans_for='everyone';
  perform pg_temp.imp(am,false); ok := public.free_plan_for_me(plan_gold); reset role;
  perform pg_temp.rec('free plans everyone: ads yes', ok);
  update public.app_mode set plans_visible_for='none';
  perform pg_temp.imp(am,false); ok := public.free_plan_for_me(plan_gold); reset role;
  perform pg_temp.rec('hidden plans are never free', not ok);
  update public.app_mode set plans_visible_for='everyone', free_plans_for='none';
  perform pg_temp.rec('promo counter bumped when free plans turned on', (select promo_id>=1 from public.app_mode));

  update public.profiles set ads_access_status='none' where id=m;
  perform pg_temp.imp(m,false); v := public.my_status(); reset role;
  perform pg_temp.rec('my_status has all required keys', v ?& array['user_id','is_guest','is_admin','source','has_ads_access','is_premium','plan_name','plan_ends_at','used_bytes','quota_bytes','free_mode','paid_enabled','access_status','payments_available','free_plans_for','plans_visible','play_verified','play_billing_enabled']);
  perform pg_temp.rec('my_status values (organic member, paid mode)', v->>'source'='organic' and (v->>'paid_enabled')::boolean and (v->>'plans_visible')::boolean and not (v->>'is_premium')::boolean and (v->>'quota_bytes')='0');
  perform pg_temp.imp(owner_id,false); v := public.my_status(); reset role;
  perform pg_temp.rec('my_status is_admin for owner', (v->>'is_admin')::boolean);
  perform pg_temp.rec('plan_catalog revision bumped by changes', (select revision>=5 from public.plan_catalog));

  select count(*), count(*) filter (where not r.ok), string_agg(r.n, ' | ') filter (where not r.ok) into total, failed, fail_list from t_res r;
  raise exception 'RESULT total=% failed=% :: %', total, failed, coalesce(fail_list,'none');
end $outer$;

