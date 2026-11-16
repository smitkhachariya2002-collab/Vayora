from pathlib import Path
import hashlib,shutil,urllib.request,zipfile

root=Path(__file__).resolve().parent.parent
out=root/'release-check'
kit=out/'Vayora-Release-Kit'
(kit/'builds').mkdir(parents=True,exist_ok=True)
release='https://github.com/smitkhachariya2002-collab/Vayora/releases/download/'
for tag,names in [('v1.0.9',['Vayora.apk','Vayora-ads.apk']),('v1.0.9-upi-build18',['Vayora-plans-upi.aab'])]:
 expected={line.split()[1]:line.split()[0] for line in urllib.request.urlopen(release+tag+'/checksums.txt',timeout=60).read().decode().splitlines()}
 for name in names:
  target=kit/'builds'/name
  if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest()!=expected[name]:
   cached=out/name
   if name=='Vayora-plans-upi.aab':cached=out/('upi-'+name)
   if cached.exists() and hashlib.sha256(cached.read_bytes()).hexdigest()==expected[name]:shutil.copy2(cached,target)
   else:urllib.request.urlretrieve(release+tag+'/'+name,target)
  assert hashlib.sha256(target.read_bytes()).hexdigest()==expected[name],name
  print('PASS release checksum',name,flush=True)
shutil.copytree(root/'play-console-assets',kit/'play-console-assets',dirs_exist_ok=True)
shutil.copy2(root/'play-console-assets/README.txt',kit/'README.txt')
files=sorted(p for p in kit.rglob('*') if p.is_file() and p.name!='kit-checksums.txt')
(kit/'kit-checksums.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.relative_to(kit).as_posix()+'\n' for p in files))
archive=out/'Vayora-1.0.9-Plans-UPI-Release-Kit.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(kit.rglob('*')):
  if p.is_file():z.write(p,p.relative_to(kit))
with zipfile.ZipFile(archive) as z:assert z.testzip() is None
print('PASS ZIP integrity',archive,flush=True)
