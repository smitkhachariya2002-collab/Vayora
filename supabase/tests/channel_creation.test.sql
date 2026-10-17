begin;
create extension if not exists pgtap with schema extensions;
set search_path=public,extensions;
select no_plan();
insert into auth.users(id,email,is_anonymous) values
 ('71000000-0000-4000-8000-000000000001','channel-a@example.test',false),
 ('71000000-0000-4000-8000-000000000002','channel-b@example.test',false),
 ('71000000-0000-4000-8000-000000000003',null,true);
set local role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"71000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select lives_ok($$insert into public.channels(id,name,description,tags,created_by,review_status)
 values('72000000-0000-4000-8000-000000000001','My channel','',array['music','india'],auth.uid(),'approved')$$,
 'Members can create a named channel with optional description and tags');
select is((select review_status from public.channels where id='72000000-0000-4000-8000-000000000001'),'pending','Creator cannot self-approve');
select is((select description from public.channels where id='72000000-0000-4000-8000-000000000001'),'','Description may be empty');
select is((select tags from public.channels where id='72000000-0000-4000-8000-000000000001'),array['music','india'],'Tags persist');
select lives_ok($$update public.channels set name='Renamed',description='Updated description',tags=array['travel'],
 icon_url='https://example.test/new.jpg' where id='72000000-0000-4000-8000-000000000001'$$,'Creator can edit channel details and photo');
select throws_ok($$update public.channels set review_status='approved' where id='72000000-0000-4000-8000-000000000001'$$,
 'P0001','Protected channel fields','Creator cannot change review status');
select throws_ok($$update public.channels set tags=array_fill('tag',array[11]) where id='72000000-0000-4000-8000-000000000001'$$,
 '23514',null,'Database rejects more than ten tags');
select throws_ok($$update public.channels set tags=array[''] where id='72000000-0000-4000-8000-000000000001'$$,
 '23514',null,'Database rejects blank tags');
select throws_ok($$update public.channels set tags=array[repeat('x',31)] where id='72000000-0000-4000-8000-000000000001'$$,
 '23514',null,'Database rejects overly long tags');
select throws_ok($$update public.channels set tags=array[null::text] where id='72000000-0000-4000-8000-000000000001'$$,
 '23514',null,'Database rejects null tags');
select lives_ok($$insert into storage.objects(bucket_id,name) values('public','71000000-0000-4000-8000-000000000001/channel-photos/photo.jpg')$$,
 'Member can upload photo in own storage prefix');
select throws_ok($$insert into storage.objects(bucket_id,name) values('public','71000000-0000-4000-8000-000000000002/channel-photos/forged.jpg')$$,
 '42501',null,'Member cannot upload into another user storage prefix');
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"71000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select is((select count(*) from public.channels where id='72000000-0000-4000-8000-000000000001'),0::bigint,'Other users cannot see pending channel');
update public.channels set name='Stolen',icon_url='https://example.test/stolen.jpg' where id='72000000-0000-4000-8000-000000000001';
delete from storage.objects where bucket_id='public' and name='71000000-0000-4000-8000-000000000001/channel-photos/photo.jpg';
reset role;
select is((select name from public.channels where id='72000000-0000-4000-8000-000000000001'),'Renamed','Other user cannot rename channel');
select is((select icon_url from public.channels where id='72000000-0000-4000-8000-000000000001'),'https://example.test/new.jpg','Other user cannot replace channel photo');
select is((select count(*) from storage.objects where bucket_id='public' and name='71000000-0000-4000-8000-000000000001/channel-photos/photo.jpg'),1::bigint,'Other user cannot delete photo');
set local role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"71000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select throws_ok($$insert into public.channels(name,created_by) values('Guest channel',auth.uid())$$,'42501',null,'Guest cannot create channel');
select throws_ok($$insert into storage.objects(bucket_id,name) values('public','71000000-0000-4000-8000-000000000003/channel-photos/photo.jpg')$$,
 '42501',null,'Guest cannot upload channel photo');
select * from finish();
rollback;
