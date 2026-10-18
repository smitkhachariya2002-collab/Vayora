begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email,is_anonymous) values
('a1000000-0000-4000-8000-000000000001','owner-a@example.test',false),
('a1000000-0000-4000-8000-000000000002','creator-a@example.test',false),
('a1000000-0000-4000-8000-000000000003',null,true);
insert into public.admins values('a1000000-0000-4000-8000-000000000001','owner');
select is((select display_name from public.profiles where id='a1000000-0000-4000-8000-000000000002'),'User-a1000000','Signup persists default name');
select set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000002',true);
set local role authenticated;
insert into public.channels(id,name,category,created_by) values
('a2000000-0000-4000-8000-000000000001','Travel India','Travel',auth.uid()),
('a2000000-0000-4000-8000-000000000002','Music India','Music',auth.uid());
select throws_ok($$insert into public.posts(channel_id,title,created_by) values('a2000000-0000-4000-8000-000000000001','Denied',auth.uid())$$,'42501',null,'Pending creator cannot create posts');
reset role;
select set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',true);
update public.channels set review_status='approved' where id in('a2000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000002');
select set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000002',true);
set local role authenticated;
insert into public.posts(id,channel_id,title,status,created_by) values
('a3000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000001','Mountains','published',auth.uid()),
('a3000000-0000-4000-8000-000000000002','a2000000-0000-4000-8000-000000000002','A song','published',auth.uid());
select is((select count(*) from public.search_posts('Mountains')),1::bigint,'Server title search');
select is((select count(*) from public.search_posts('Travel India')),1::bigint,'Server channel name search');
select is((select count(*) from public.search_posts('', 'Music')),1::bigint,'Server category filter');
select is((select count(*) from public.search_posts('',null,null,null,false,1,1)),1::bigint,'Server pagination');
select is(public.increment_view('a3000000-0000-4000-8000-000000000001'),1::bigint,'First view counted');
select is(public.increment_view('a3000000-0000-4000-8000-000000000001'),1::bigint,'Duplicate within 30 minutes not counted');
select throws_ok($$update public.posts set view_count=900 where id='a3000000-0000-4000-8000-000000000001'$$,'42501',null,'Clients cannot forge counters');
reset role;
update private.post_views set last_viewed_at=now()-interval '31 minutes';
set local role authenticated;
select is(public.increment_view('a3000000-0000-4000-8000-000000000001'),2::bigint,'View after 30 minutes counted');
reset role;
select set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000001',true);
update public.channels set status='hidden' where id='a2000000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok($$select public.prepare_account_deletion()$$,'P0001','Transfer ownership before deleting this account','Last owner cannot prepare deletion');
reset role;
select throws_ok($$delete from auth.users where id='a1000000-0000-4000-8000-000000000001'$$,'P0001','Transfer ownership before deleting this account','Auth deletion also protects last owner');
select set_config('request.jwt.claims','{"sub":"a1000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000002',true);
set local role authenticated;
select throws_ok($$insert into public.post_items(post_id,media_key) values('a3000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000002/a3000000-0000-4000-8000-000000000001/main')$$,'42501',null,'Hidden creator channel rejects media writes');
update public.posts set title='No' where id='a3000000-0000-4000-8000-000000000001';
select is((select count(*) from public.posts where title='No'),0::bigint,'Hidden creator channel rejects post updates');
reset role;
select * from finish();
rollback;
