"""Verify identities from compiled manifests, including bundletool's AAB dump."""
import sys
import xml.etree.ElementTree as ET
A='{http://schemas.android.com/apk/res/android}'
path,package,version=sys.argv[1:]
root=ET.parse(path).getroot()
assert root.get('package')==package,(path,root.get('package'))
assert root.get(A+'versionCode')==version,(path,root.get(A+'versionCode'))
callbacks={d.get(A+'scheme') for d in root.findall('.//intent-filter/data') if d.get(A+'host')=='login-callback'}
assert callbacks=={package},(path,callbacks)
providers=root.findall('./application/provider')
assert any(p.get(A+'authorities')==package+'.files' for p in providers),'FileProvider identity mismatch'
for provider in providers:
 for authority in (provider.get(A+'authorities') or '').split(';'):
  if authority.startswith('com.vayora.'):assert authority.startswith(package+'.'),(path,authority)
for node in root.iter():
 for attr in ['permission','readPermission','writePermission']:
  value=node.get(A+attr,'')
  if value.startswith('com.vayora.'):assert value.startswith(package+'.'),(path,value)
for tag in ['permission','uses-permission']:
 for node in root.findall(tag):
  value=node.get(A+'name','')
  if value.startswith('com.vayora.'):assert value.startswith(package+'.'),(path,value)
assert any(a.get(A+'name')=='com.vayora.app.MainActivity' for a in root.findall('./application/activity')),'Kotlin activity namespace must remain valid'
print(f'PASS package={package} versionCode={version} callback={package}://login-callback provider={package}.files; app-owned authorities/permissions isolated')
