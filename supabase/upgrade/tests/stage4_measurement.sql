-- All fixtures roll back with the final report; never sends an external request.
do $outer$
declare u uuid:=gen_random_uuid();other_ uuid:=gen_random_uuid();owner_ uuid:=gen_random_uuid();event_ uuid:=gen_random_uuid();session_ uuid:=gen_random_uuid();rev bigint;result_ jsonb;v boolean;total_ int;failed_ int;names text;context_ jsonb;
begin
 create temp table checks(name text,ok boolean) on commit drop;
 create function pg_temp.ck(n text,v boolean) returns void language plpgsql security definer as $f$begin insert into pg_temp.checks values(n,coalesce(v,false));end$f$;
 create function pg_temp.imp(u uuid) returns void language plpgsql as $f$begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','is_anonymous',false)::text,true);
 perform set_config('request.jwt.claim.sub',u::text,true);set local role authenticated;end$f$;
 insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,is_anonymous)
 select x,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x::text||'@example.test',now(),false from unnest(array[u,other_,owner_])x;
 insert into public.admins(user_id,role) values(owner_,'owner');
 -- Disable kick URL inside this rollback so test events cannot leave the database.
 update private.meta_cron set url='';
 update public.meta_settings set enabled=true,pixel_id='123456789012',capi_token='fixture-only';
 select revision into rev from public.meta_settings where id=1;
 context_:=jsonb_build_object('install_id',gen_random_uuid()::text,'extinfo',jsonb_build_array('a2','com.vayora.app','9','1.0.8','14','','en_IN','IST','','1080','1920','3','4','','',''));
 perform pg_temp.imp(u);v:=public.record_activity(event_,'Login',session_);reset role;
 perform pg_temp.ck('default no measurement',not v and not exists(select 1 from private.app_activity where user_id=u));
 perform pg_temp.imp(u);v:=false;begin perform public.set_measurement_preferences(true,true,'{}');exception when others then v:=true;end;reset role;
 perform pg_temp.ck('malformed Android context rejected',v);
 perform pg_temp.imp(u);perform public.set_measurement_preferences(true,false);
 v:=public.record_activity(event_,'VideoStart',session_,jsonb_build_object('media_type','video','password','secret','filename','private.mp4','search','private query'));reset role;
 perform pg_temp.ck('analytics works without Meta',v and exists(select 1 from private.app_activity where user_id=u) and not exists(select 1 from public.meta_events where user_id=u));
 perform pg_temp.ck('sensitive properties stripped',(select properties='{"media_type":"video"}'::jsonb from private.app_activity where event_id=event_));
 perform pg_temp.imp(u);v:=public.record_activity(event_,'VideoStart',session_);reset role;
 perform pg_temp.ck('duplicate activity rejected',not v);
 perform pg_temp.imp(u);v:=false;begin perform public.record_activity(gen_random_uuid(),'Purchase',session_);exception when others then v:=true;end;reset role;
 perform pg_temp.ck('client cannot invent Purchase',v);
 perform pg_temp.imp(u);v:=false;begin perform public.admin_analytics();exception when others then v:=true;end;reset role;
 perform pg_temp.ck('analytics owner only',v);
 perform pg_temp.imp(u);perform public.set_measurement_preferences(true,true,context_);perform public.record_activity(gen_random_uuid(),'Login',session_);reset role;
 perform pg_temp.ck('opt in queues app event with context',exists(select 1 from public.meta_events where user_id=u and event_name='Login' and action_source='app' and app_data->'extinfo'=context_->'extinfo' and advertising_consent and config_revision=rev));
 perform pg_temp.imp(other_);select count(*)=0 into v from public.measurement_preferences where user_id=u;reset role;
 perform pg_temp.ck('preferences private to account',v);
 perform pg_temp.imp(u);v:=false;begin perform public.meta_claim_batch();exception when others then v:=true;end;reset role;
 perform pg_temp.ck('only server can lease delivery',v);
 perform pg_temp.imp(u);perform public.set_measurement_preferences(false,false);reset role;
 perform pg_temp.ck('revocation cancels pending events',not exists(select 1 from public.meta_events where user_id=u and status in('pending','processing')));
 perform pg_temp.ck('essential only deletes retained activity',not exists(select 1 from private.app_activity where user_id=u));
 perform pg_temp.imp(u);perform public.set_measurement_preferences(true,true,context_);perform public.record_activity(gen_random_uuid(),'AppOpen',session_, '{}',now()-interval '2 hours');perform public.record_activity(gen_random_uuid(),'AppOpen',gen_random_uuid());reset role;
 perform pg_temp.imp(owner_);result_:=public.admin_analytics(null,null);reset role;
 perform pg_temp.ck('returning users counted for all-time',(result_->>'returning_users')::int>=1);
 perform pg_temp.imp(owner_);result_:=public.admin_users_filtered(p_search=>u::text,p_customer=>'returning');reset role;
 perform pg_temp.ck('returning-user filter',(result_->>'total')::int=1);
 perform pg_temp.imp(owner_);result_:=public.admin_users_filtered(p_search=>u::text,p_from=>(now() at time zone 'Asia/Kolkata')::date,p_to=>(now() at time zone 'Asia/Kolkata')::date);reset role;
 perform pg_temp.ck('joined dates inclusive IST',(result_->>'total')::int=1);
 update public.meta_settings set capi_token='replacement-token';
 perform pg_temp.ck('token refresh keeps dataset revision',(select revision=rev from public.meta_settings where id=1));
 update public.meta_settings set pixel_id='987654321012';
 perform pg_temp.ck('Pixel switch changes revision',(select revision=rev+1 from public.meta_settings where id=1));
 perform pg_temp.ck('Pixel switch suppresses previous destination',not exists(select 1 from public.meta_events where user_id=u and status in('pending','processing')));
 select count(*),count(*) filter(where not ok),string_agg(name,' | ') filter(where not ok) into total_,failed_,names from checks;
 raise exception 'RESULT total=% failed=% :: %',total_,failed_,coalesce(names,'none');
end $outer$;

