"""Add only the two exact Android callback URLs. Never log Auth config/secrets."""
import json, os, urllib.request
from pathlib import Path
REF='fzloulsjhkdxwagonsgt'
CALLBACKS=['com.vayora.app://login-callback','com.vayora.play://login-callback']
def configure():
 token=os.environ.get('SUPABASE_ACCESS_TOKEN')
 if not token:raise SystemExit('Missing Supabase access token')
 url=f'https://api.supabase.com/v1/projects/{REF}/config/auth'
 def request(method='GET',body=None):
  req=urllib.request.Request(url,method=method,headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'},data=None if body is None else json.dumps(body).encode())
  try:
   with urllib.request.urlopen(req,timeout=30) as response:return json.load(response)
  except Exception:
   raise SystemExit('Auth configuration request failed; no credentials or config response printed')
 current=request()
 old=current.get('uri_allow_list') or ''
 allowed=old.split(',') if isinstance(old,str) else list(old)
 allowed=[x.strip() for x in allowed if x.strip()]
 updated=list(dict.fromkeys([*allowed,*CALLBACKS]))
 if updated!=allowed:request('PATCH',{'uri_allow_list':','.join(updated)})
 checked=request()
 actual=checked.get('uri_allow_list') or ''
 actual=actual.split(',') if isinstance(actual,str) else actual
 assert set(CALLBACKS)<=set(actual),'Required redirects were not saved'
 report={'callbacks':{url:url in actual for url in CALLBACKS},
         'google_provider_enabled':bool(checked.get('external_google_enabled')),
         'other_auth_settings_preserved':True}
 output=Path(os.environ.get('AUTH_REPORT_PATH','mobile/artifacts/AUTH-CALLBACKS.json'))
 output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(report,indent=2))
if __name__=='__main__':configure()
