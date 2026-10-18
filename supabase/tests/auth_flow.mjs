// Real Auth + PostgREST round trips against disposable local Supabase only.
// Never print credentials, confirmation links or token responses.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomUUID, randomBytes } from 'node:crypto';
const config = JSON.parse(await readFile(process.argv[2], 'utf8'));
const api = config.API_URL;
const mailbox = config.INBUCKET_URL || 'http://127.0.0.1:54324';
for (const url of [api, mailbox]) assert(['127.0.0.1','localhost'].includes(new URL(url).hostname), 'Local runner only');
const key = config.ANON_KEY;
async function request(path, {token=key, method='GET', body}={}) {
  const res = await fetch(api + path, {method, headers: {apikey:key, Authorization:'Bearer '+token,
    'Content-Type':'application/json'}, body:body === undefined ? undefined : JSON.stringify(body)});
  assert(res.ok, 'Local API request failed: '+path+' ('+res.status+')');
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}
const rpc = (name, token, body={}) => request('/rest/v1/rpc/'+name, {token, method:'POST', body});
function strings(value) {
  if (typeof value === 'string') return [value];
  return value && typeof value === 'object' ? Object.values(value).flatMap(strings) : [];
}
async function confirmation(email, type) {
  // CLI releases use Mailpit (current) or the compatible Inbucket mailbox API.
  const local = email.split('@')[0];
  for (let attempt=0; attempt<30; attempt++) {
    for (const listPath of ['/api/v1/messages','/api/v1/mailbox/'+encodeURIComponent(local)]) {
      const res = await fetch(mailbox+listPath);
      if (!res.ok) continue;
      const data = await res.json();
      const messages = Array.isArray(data) ? data : data.messages || [];
      for (const message of messages) {
        const id = message.ID || message.id;
        const path = Array.isArray(data)
          ? '/api/v1/mailbox/'+encodeURIComponent(local)+'/'+id : '/api/v1/message/'+id;
        const detail = await fetch(mailbox+path);
        if (!detail.ok) continue;
        const text = strings(await detail.json()).join(' ').replaceAll('&amp;', '&');
        const links = text.match(/https?:\/\/[^\s<>"']+/g) || [];
        const link = links.find(v => {
          try { const u = new URL(v); return u.origin === new URL(api).origin &&
            u.pathname.endsWith('/verify') && u.searchParams.get('type') === type; }
          catch { return false; }
        });
        if (link) {
          const verified = await fetch(link, {redirect:'manual'});
          const location = verified.headers.get('location') || '';
          assert([302,303].includes(verified.status), 'Confirmation redirects');
          assert(location.startsWith('com.vayora.app://login-callback'), 'Android callback preserved');
          assert(!location.includes('error='), 'Confirmation succeeded');
          return;
        }
      }
    }
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  throw new Error('Local confirmation email not found for '+type);
}
const install = randomUUID(), secret = randomBytes(32).toString('hex');
const email = 'account-'+randomUUID()+'@example.test', password = randomBytes(24).toString('hex');
const guest = await request('/auth/v1/signup', {method:'POST',body:{}});
assert.equal(guest.user.is_anonymous, true);
const token = guest.access_token, id = guest.user.id;
await rpc('record_install',token,{install_id:install,install_secret:secret,referrer_status:'none',raw_referrer:''});
await request('/rest/v1/consents',{method:'POST',token,body:{user_id:id,policy_version:'v1'}});
await request('/auth/v1/user?redirect_to='+encodeURIComponent('com.vayora.app://login-callback'),{
  method:'PUT',token,body:{email,password}});
await confirmation(email,'email_change');
const member = await request('/auth/v1/token?grant_type=password',{method:'POST',body:{email,password}});
assert.equal(member.user.id,id,'Confirmed guest keeps UUID');
assert.equal(member.user.is_anonymous,false);
await rpc('attribute_user',member.access_token,{install_id:install,install_secret:secret});
let status = await rpc('my_status',member.access_token);
assert.equal(status.is_guest,false);
assert.equal(status.source,'organic');
const consents = await request('/rest/v1/consents?select=policy_version&user_id=eq.'+id,{token:member.access_token});
assert.equal(consents.length,1,'Consent history survives confirmation');
console.log('PASS: real guest upgrade, email confirmation, UUID/history and mobile callback');
const adsInstall = randomUUID(), adsSecret = randomBytes(32).toString('hex');
const other = await request('/auth/v1/signup',{method:'POST',body:{}});
await rpc('record_install',other.access_token,{install_id:adsInstall,install_secret:adsSecret,
  referrer_status:'provided',raw_referrer:'utm_source=meta'});
assert.equal((await rpc('my_status',other.access_token)).source,'ads');
await rpc('attribute_user',member.access_token,{install_id:adsInstall,install_secret:adsSecret});
assert.equal((await rpc('my_status',member.access_token)).source,'organic');
await request('/auth/v1/logout',{method:'POST',token:member.access_token});
const fresh = await request('/auth/v1/signup',{method:'POST',body:{}});
assert.notEqual(fresh.user.id,id);
assert.equal(fresh.user.is_anonymous,true);
console.log('PASS: existing-account login keeps first source; logout creates a new guest');
await request('/auth/v1/recover?redirect_to='+encodeURIComponent('com.vayora.app://login-callback'),
  {method:'POST',body:{email}});
await confirmation(email,'recovery');
console.log('PASS: real recovery email uses Android callback');

// Competing real API requests reserve against the same locked profile counter.
const service=config.SERVICE_ROLE_KEY;
assert(service,'Local service role key is present');
const cloudMember=await request('/auth/v1/token?grant_type=password',{method:'POST',body:{email,password}});
await request('/rest/v1/app_mode?id=eq.true',{token:service,method:'PATCH',body:{free_mode:true}});
const folderResponse=await fetch(api+'/rest/v1/rpc/cloud_reserve',{method:'POST',headers:{apikey:key,Authorization:'Bearer '+cloudMember.access_token,'Content-Type':'application/json',Accept:'application/vnd.pgrst.object+json'},
 body:JSON.stringify({name:'Cloud folder',is_folder:true})});
assert(folderResponse.ok,'Composite reservation supports a single-row response');
const folder=await folderResponse.json();assert.equal(typeof folder.id,'string');assert.equal(folder.is_folder,true);
const quota=16106127360,chunk=1024*1024;
await request('/rest/v1/profiles?id=eq.'+id,{token:service,method:'PATCH',body:{used_bytes:quota-3*chunk}});
const reservations=await Promise.all(Array.from({length:8},async(_,i)=>{
 const result=await fetch(api+'/rest/v1/rpc/cloud_reserve',{method:'POST',headers:{apikey:key,Authorization:'Bearer '+cloudMember.access_token,'Content-Type':'application/json'},
 body:JSON.stringify({name:'Concurrent-'+i+'.bin',size:chunk,mime:'application/octet-stream'})});
 return result.status;
}));
assert.equal(reservations.filter(s=>s>=200&&s<300).length,3,'Only the remaining quota is reserved under concurrency');
status=await rpc('my_status',cloudMember.access_token);
assert.equal(status.used_bytes,quota,'Atomic counter stops exactly at quota');
console.log('PASS: concurrent cloud reservations cannot oversubscribe quota');
