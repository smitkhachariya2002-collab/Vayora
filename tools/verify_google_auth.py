"""Verify Google setup; enable only the linking needed to retain guest data."""
import json
import os
import urllib.request

endpoint = 'https://api.supabase.com/v1/projects/fzloulsjhkdxwagonsgt/config/auth'
headers = {'Authorization': 'Bearer ' + os.environ['SUPABASE_ACCESS_TOKEN'],
           'Content-Type': 'application/json'}

def config():
    with urllib.request.urlopen(urllib.request.Request(endpoint, headers=headers)) as response:
        return json.load(response)

current = config()
assert current.get('external_google_enabled') is True, 'Google provider is disabled'
expected = {'com.vayora.app://login-callback', 'com.vayora.play://login-callback'}
assert expected.issubset(set(current.get('uri_allow_list', '').split(','))), 'Missing app callbacks'
if current.get('security_manual_linking_enabled') is not True:
    body = json.dumps({'security_manual_linking_enabled': True}).encode()
    with urllib.request.urlopen(urllib.request.Request(endpoint, data=body, headers=headers, method='PATCH')) as response:
        response.read()
    current = config()
assert current.get('security_manual_linking_enabled') is True, 'Account linking is disabled'
print('PASS: Google enabled, both app callbacks allowed, guest identity linking enabled. No user records changed.')

