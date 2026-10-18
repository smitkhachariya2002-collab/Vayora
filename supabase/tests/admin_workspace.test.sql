begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email,is_anonymous,email_confirmed_at) values
('a0000000-0000-0000-0000-000000000001','owner-ui@example.test',false,now()),
('a0000000-0000-0000-0000-000000000002','content-ui@example.test',false,now()),
('a0000000-0000-0000-0000-000000000003','member-ui@example.test',false,now());
insert into public.admins values('a0000000-0000-0000-0000-000000000001','owner'),('a0000000-0000-0000-0000-000000000002','content');
set local role authenticated;
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000003',true);
select throws_ok($$select public.admin_metrics()$$,'P0001','Admin required','Members cannot read metrics');
select throws_ok($$select public.admin_directory()$$,'P0001','Owner required','Members cannot list admins');
select throws_ok($$select public.admin_meta()$$,'P0001','Owner required','Members cannot read Meta settings');
select throws_ok($$select public.admin_manage_member('member-ui@example.test','owner','{}',false)$$,'P0001','Owner required','No self promotion');
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000002',true);
select lives_ok($$select public.admin_metrics()$$,'Content admins can read scoped metrics');
select throws_ok($$select public.admin_meta()$$,'P0001','Owner required','Content cannot read settings');
select throws_ok($$select public.admin_save_meta('1','secret','','https://example.test',true)$$,'P0001','Owner required','Content cannot save settings');
select throws_ok($$select public.admin_manage_member('member-ui@example.test','owner','{}',false)$$,'P0001','Owner required','Content cannot promote');
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000001',true);
select lives_ok($$select public.admin_save_meta('123','never-return-this','','https://example.test',false)$$,'Owner saves private token');
select is(public.admin_meta()->>'has_token','true','Only token presence is returned');
select ok(not (public.admin_meta()::text like '%never-return-this%'),'Token is never returned');
select throws_ok($$select public.admin_manage_member('owner-ui@example.test','content','{}',false)$$,'P0001','Cannot remove the last owner','Last owner protected');
select lives_ok($$select public.admin_manage_member('member-ui@example.test','content','{}',false)$$,'Owner grants existing verified account');
select is(jsonb_array_length(public.admin_directory()),3,'Directory contains granted admin');
select throws_ok($$select public.admin_manage_member('missing@example.test','content','{}',false)$$,'P0001','User must register and confirm this email first','Unknown email rejected');
select lives_ok($$select public.admin_manage_member('member-ui@example.test','content','{}',true)$$,'Owner removes admin');
select lives_ok($$select public.admin_payment_summary()$$,'Owner can read exact payment aggregates');
select lives_ok($$select public.admin_user_plans()$$,'Owner can read active plan names');
select ok(not has_function_privilege('anon','public.admin_directory()','execute'),'Anon has no directory execution');
select ok(not has_function_privilege('anon','public.admin_reorder_post_items(uuid,uuid[])','execute'),'Anon cannot reorder');
insert into public.channels(id,name,created_by) values('b0000000-0000-0000-0000-000000000001','Reorder test','a0000000-0000-0000-0000-000000000001');
select public.review_channel('b0000000-0000-0000-0000-000000000001',true,'all');
insert into public.posts(id,channel_id,title,created_by) values('b0000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000001','Reorder','a0000000-0000-0000-0000-000000000001');
insert into public.post_items(id,post_id,media_key) values
('b0000000-0000-0000-0000-000000000003','b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001/b0000000-0000-0000-0000-000000000002/reorder1'),
('b0000000-0000-0000-0000-000000000004','b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001/b0000000-0000-0000-0000-000000000002/reorder2');
select lives_ok($$select public.admin_reorder_post_items('b0000000-0000-0000-0000-000000000002',array['b0000000-0000-0000-0000-000000000004','b0000000-0000-0000-0000-000000000003']::uuid[])$$,'Owner reorders media atomically');
select is((select position from public.post_items where id='b0000000-0000-0000-0000-000000000004'),0,'First item position updated');
select throws_ok($$select public.admin_reorder_post_items('b0000000-0000-0000-0000-000000000002',array['b0000000-0000-0000-0000-000000000003']::uuid[])$$,'P0001','Media list changed; refresh and try again','Incomplete media list rejected');
select set_config('request.jwt.claim.sub','a0000000-0000-0000-0000-000000000002',true);
select throws_ok($$select public.admin_reorder_post_items('b0000000-0000-0000-0000-000000000002',array['b0000000-0000-0000-0000-000000000004','b0000000-0000-0000-0000-000000000003']::uuid[])$$,'P0001','Channel access required','Content cannot reorder another channel');
select throws_ok($$select public.admin_payment_summary()$$,'P0001','Owner required','Content cannot read revenue');
select throws_ok($$select public.admin_user_plans()$$,'P0001','Owner required','Content cannot read all plans');
select finish();
rollback;
