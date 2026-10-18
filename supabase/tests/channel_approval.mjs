// Disposable GitHub CI only: exercise concurrent REST inserts using real user JWTs.
import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const cfg=JSON.parse(readFileSync(process.argv[2],'utf8'));
const url=cfg.API_URL,anon=cfg.ANON_KEY,service=cfg.SERVICE_ROLE_KEY;
async function request(path,key,method='GET',body){
 const response=await fetch(url+path,{method,headers:{apikey:key===service?service:anon,Authorization:'Bearer '+key,'Content-Type':'application/json',Prefer:'return=representation'},body:body===undefined?undefined:JSON.stringify(body)});
 const text=await response.text();return {status:response.status,data:text?JSON.parse(text):null};
}
const email='channel-race-'+randomUUID()+'@example.test',password=randomUUID()+'Aa1!';
const created=await request('/auth/v1/admin/users',service,'POST',{email,password,email_confirm:true});
assert.equal(created.status,200);
const login=await request('/auth/v1/token?grant_type=password',anon,'POST',{email,password});
assert.equal(login.status,200);
const token=login.data.access_token,uid=login.data.user.id;
const responses=await Promise.all(Array.from({length:6},(_,i)=>request('/rest/v1/channels',token,'POST',{
 id:randomUUID(),name:'Concurrent request '+i,created_by:uid,review_status:'approved',status:'published',audience:'ads',members_count:100,
})));
assert.equal(responses.filter(r=>r.status===201).length,3,'Exactly three simultaneous requests allowed');
assert.equal(responses.filter(r=>r.data?.message==='you already have 3 channels waiting for approval').length,3);
const rows=await request('/rest/v1/channels?created_by=eq.'+uid,token);
assert.equal(rows.data.length,3);
for(const row of rows.data){assert.equal(row.review_status,'pending');assert.equal(row.status,'draft');assert.equal(row.audience,'all');assert.equal(row.members_count,0);}
console.log('PASS: six concurrent authenticated REST requests create exactly three private draft channels.');
