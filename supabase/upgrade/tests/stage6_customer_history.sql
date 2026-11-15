-- Repeat-buyer history is admin-only and compares immutable paid-order snapshots.
do $outer$
declare u uuid:=gen_random_uuid();owner_ uuid:=gen_random_uuid();low_ uuid:=gen_random_uuid();high_ uuid:=gen_random_uuid();one_ uuid:=gen_random_uuid();two_ uuid:=gen_random_uuid();three_ uuid:=gen_random_uuid();four_ uuid:=gen_random_uuid();result_ jsonb;v boolean;total_ int;failed_ int;names text;
begin
 create temp table checks(name text,ok boolean) on commit drop;
 create function pg_temp.ck(n text,v boolean) returns void language plpgsql security definer as $f$begin insert into pg_temp.checks values(n,coalesce(v,false));end$f$;
 create function pg_temp.imp(u uuid) returns void language plpgsql as $f$begin perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','is_anonymous',false)::text,true);perform set_config('request.jwt.claim.sub',u::text,true);set local role authenticated;end$f$;
 insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,is_anonymous) select x,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',x::text||'@example.test',now(),false from unnest(array[u,owner_])x;
 insert into public.admins(user_id,role) values(owner_,'owner');
 insert into public.plans(id,code,name,price_inr,duration_days) values(low_,'test-low-'||left(low_::text,8),'Lower plan',49,7),(high_,'test-high-'||left(high_::text,8),'Higher plan',259,30);
 insert into public.payment_orders(id,user_id,plan_id) values(one_,u,low_),(two_,u,low_),(three_,u,high_),(four_,u,low_);
 update public.payment_orders o set status='paid',activated_at=times.at_,bank_verified=true from(values(one_,now()-interval '4 days'),(two_,now()-interval '3 days'),(three_,now()-interval '2 days'),(four_,now()-interval '1 day')) times(id_,at_) where o.id=times.id_;
 perform pg_temp.imp(u);v:=false;begin perform public.admin_customer_purchases(u);exception when others then v:=true;end;reset role;perform pg_temp.ck('customer history is owner only',v);
 perform pg_temp.imp(owner_);result_:=public.admin_customer_purchases(u);reset role;
 perform pg_temp.ck('email identifies repeat buyer',result_->>'email'=u::text||'@example.test' and (result_->>'paid_orders')::int=4);
 perform pg_temp.ck('lower-price change visible',result_->'history'->0->>'change'='Lower-priced plan');
 perform pg_temp.ck('higher-price change visible',result_->'history'->1->>'change'='Higher-priced plan');
 perform pg_temp.ck('same plan purchase visible',result_->'history'->2->>'change'='Same plan');
 perform pg_temp.ck('first purchase identified',result_->'history'->3->>'change'='First purchase');
 update public.plans set price_inr=999 where id=low_;
 perform pg_temp.imp(owner_);result_:=public.admin_customer_purchases(u);reset role;
 perform pg_temp.ck('history uses purchase snapshots not current prices',(result_->'history'->0->>'amount_inr')::numeric=49);
 perform pg_temp.ck('admin repeat history creates no ad event',not exists(select 1 from public.meta_events where user_id=u));
 select count(*),count(*) filter(where not ok),string_agg(name,' | ') filter(where not ok) into total_,failed_,names from checks;raise exception 'RESULT total=% failed=% :: %',total_,failed_,coalesce(names,'none');
end $outer$;
