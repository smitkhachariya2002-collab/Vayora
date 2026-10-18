begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email,is_anonymous) values
('ca000000-0000-4000-8000-000000000001','channel-owner@example.test',false),
('ca000000-0000-4000-8000-000000000002','channel-creator@example.test',false),
('ca000000-0000-4000-8000-000000000003','channel-other@example.test',false),
('ca000000-0000-4000-8000-000000000004',null,true),
('ca000000-0000-4000-8000-000000000005','channel-editor@example.test',false);
insert into public.admins values
('ca000000-0000-4000-8000-000000000001','owner'),
('ca000000-0000-4000-8000-000000000005','content');
set local role authenticated;
select set_config('request.jwt.claim.sub','ca000000-0000-4000-8000-000000000002',true);
select lives_ok($$insert into public.channels(id,name,created_by,review_status,status,audience,members_count,reviewed_by,reviewed_at)
values('cb000000-0000-4000-8000-000000000001','Creator channel','ca000000-0000-4000-8000-000000000001',
'approved','published','ads',99,'ca000000-0000-4000-8000-000000000001',now())$$,'App creation normalizes forged fields');
select is((select review_status from public.channels where id='cb000000-0000-4000-8000-000000000001'),'pending','Always pending');
select is((select status from public.channels where id='cb000000-0000-4000-8000-000000000001'),'draft','Always draft');
select is((select audience::text from public.channels where id='cb000000-0000-4000-8000-000000000001'),'all','Always Everyone');
select is((select members_count from public.channels where id='cb000000-0000-4000-8000-000000000001'),0::bigint,'Counter reset');
select is((select created_by from public.channels where id='cb000000-0000-4000-8000-000000000001'),auth.uid(),'Creator forced to auth.uid');
select ok((select reviewed_by is null and reviewed_at is null from public.channels where id='cb000000-0000-4000-8000-000000000001'),'App cannot forge reviewer');
select throws_ok($$insert into public.channels(name,created_by) values('ab',auth.uid())$$,'23514',null,'Name minimum enforced in database');
select lives_ok($$update public.channels set name='New channel',description='Updated',category='Entertainment',
tags=array['india'],icon_url=null where id='cb000000-0000-4000-8000-000000000001'$$,'Creator can edit only descriptive fields');
select throws_ok($$update public.channels set review_status='approved' where id='cb000000-0000-4000-8000-000000000001'$$,'P0001','Protected channel fields','Cannot self approve');
select throws_ok($$update public.channels set audience='ads' where id='cb000000-0000-4000-8000-000000000001'$$,'P0001','Protected channel fields','Cannot change audience');
select throws_ok($$update public.channels set status='published' where id='cb000000-0000-4000-8000-000000000001'$$,'P0001','Protected channel fields','Cannot self publish');
select throws_ok($$update public.channels set created_at=now()+interval '1 day' where id='cb000000-0000-4000-8000-000000000001'$$,'P0001','Protected channel fields','Cannot change other fields');
select throws_ok($$insert into private.channel_operations values(txid_current(),'cb000000-0000-4000-8000-000000000001',auth.uid(),'review')$$,'42501',null,'Private review capability cannot be forged');
select throws_ok($$select public.review_channel('cb000000-0000-4000-8000-000000000001',true,'all')$$,'P0001','Owner required','Creator cannot call review RPC');
select throws_ok($$select public.admin_save_channel(null,'Bypass')$$,'P0001','Admin required','Creator cannot use admin creation RPC');
insert into public.channels(id,name,created_by) values
('cb000000-0000-4000-8000-000000000002','Request two',auth.uid()),
('cb000000-0000-4000-8000-000000000003','Request three',auth.uid());
select throws_ok($$insert into public.channels(name,created_by) values('Request four',auth.uid())$$,'P0001','you already have 3 channels waiting for approval','Fourth pending request rejected');
select throws_ok($$insert into public.posts(channel_id,title,created_by) values('cb000000-0000-4000-8000-000000000001','Too early',auth.uid())$$,'42501',null,'Pending channel cannot publish posts');

select set_config('request.jwt.claim.sub','ca000000-0000-4000-8000-000000000003',true);
select is((select count(*) from public.channels where id::text like 'cb000000%'),0::bigint,'Pending channels invisible to other members');
select set_config('request.jwt.claim.sub','ca000000-0000-4000-8000-000000000004',true);
select is((select count(*) from public.channels where id::text like 'cb000000%'),0::bigint,'Pending channels invisible to guests');
select throws_ok($$insert into public.channels(name,created_by) values('Guest request',auth.uid())$$,'42501',null,'Guests cannot create requests');

select set_config('request.jwt.claim.sub','ca000000-0000-4000-8000-000000000005',true);
insert into public.channels(id,name,created_by,audience) values
('cb000000-0000-4000-8000-000000000005','Editor app request',auth.uid(),'ads');
select is((select review_status from public.channels where id='cb000000-0000-4000-8000-000000000005'),'pending','Content admin app insert still pending');
select throws_ok($$select public.review_channel('cb000000-0000-4000-8000-000000000001',true,'all')$$,'P0001','Owner required','Content admin cannot review');
select throws_ok($$insert into public.posts(channel_id,title,created_by) values('cb000000-0000-4000-8000-000000000005','Too early',auth.uid())$$,'42501',null,'Admin app creator also waits before posting');

select set_config('request.jwt.claim.sub','ca000000-0000-4000-8000-000000000001',true);
insert into public.channels(id,name,created_by) values
('cb000000-0000-4000-8000-000000000004','Owner app request',auth.uid());
select is((select review_status from public.channels where id='cb000000-0000-4000-8000-000000000004'),'pending','Owner app insert still pending');
select throws_ok($$update public.channels set review_status='approved' where id='cb000000-0000-4000-8000-000000000004'$$,'P0001','Protected channel fields','Owner cannot bypass review through direct app update');
select is(jsonb_array_length(public.channel_requests()),5,'Owner queue includes all requests and creator identity');
select ok(public.channel_requests()::text like '%channel-creator@example.test%','Queue includes creator email');
select lives_ok($$select public.review_channel('cb000000-0000-4000-8000-000000000001',true,'ads')$$,'Owner approval succeeds');
select is((select review_status from public.channels where id='cb000000-0000-4000-8000-000000000001'),'approved','Approved state stored');
select is((select status from public.channels where id='cb000000-0000-4000-8000-000000000001'),'published','Approval publishes');
select is((select audience::text from public.channels where id='cb000000-0000-4000-8000-000000000001'),'ads','Chosen audience stored');
select ok((select reviewed_by=auth.uid() and reviewed_at is not null from public.channels where id='cb000000-0000-4000-8000-000000000001'),'Reviewer and time stored');
select lives_ok($$select public.review_channel('cb000000-0000-4000-8000-000000000001',true,'ads')$$,'Repeated approval idempotent');
select is((select count(*) from public.channel_members where channel_id='cb000000-0000-4000-8000-000000000001' and user_id='ca000000-0000-4000-8000-000000000002'),1::bigint,'Creator automatically joins once');
select is((select members_count from public.channels where id='cb000000-0000-4000-8000-000000000001'),1::bigint,'Member count reflects creator join');
select lives_ok($$select public.review_channel('cb000000-0000-4000-8000-000000000002',false,'all')$$,'Owner rejection succeeds');
select is((select review_status||'/'||status from public.channels where id='cb000000-0000-4000-8000-000000000002'),'rejected/draft','Rejection remains draft');
select lives_ok($$select public.admin_save_channel(null,'Panel-created channel','Description','Entertainment')$$,'Admin panel creates immediately');
select is((select review_status||'/'||status from public.channels where name='Panel-created channel'),'approved/published','Panel channel approved immediately');

select set_config('request.jwt.claim.sub','ca000000-0000-4000-8000-000000000003',true);
select is((select count(*) from public.channels where id='cb000000-0000-4000-8000-000000000002'),0::bigint,'Rejected remains hidden');
select is((select count(*) from public.channels where id='cb000000-0000-4000-8000-000000000001'),0::bigint,'Approval still respects ads audience');
select set_config('request.jwt.claim.sub','ca000000-0000-4000-8000-000000000002',true);
delete from public.channels where id='cb000000-0000-4000-8000-000000000001';
select is((select count(*) from public.channels where id='cb000000-0000-4000-8000-000000000001'),1::bigint,'Creator cannot delete approved channel');
select lives_ok($$insert into public.posts(channel_id,title,created_by) values('cb000000-0000-4000-8000-000000000001','Now allowed',auth.uid())$$,'Approved creator can post');
delete from public.channels where id='cb000000-0000-4000-8000-000000000003';
select is((select count(*) from public.channels where id='cb000000-0000-4000-8000-000000000003'),0::bigint,'Creator may delete a pending request');
reset role;
select is((select file_size_limit from storage.buckets where id='channel-icons'),5242879::bigint,'Server icon bucket rejects 5 MiB or larger');
select ok(not has_function_privilege('anon','public.review_channel(uuid,boolean,public.audience)','execute'),'Anon cannot invoke review');
select ok(not has_function_privilege('anon','public.channel_requests()','execute'),'Anon cannot read private queue');
select * from finish();
rollback;
