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
select finish();
rollback;
