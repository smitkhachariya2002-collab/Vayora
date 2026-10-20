"""Capture actual Android launcher and launch frames on the disposable CI emulator."""
from pathlib import Path
import subprocess,time,sqlite3,tempfile,hashlib
from PIL import Image
dest=Path('docs/visual-refresh/native');dest.mkdir(parents=True,exist_ok=True)
def adb(*args,check=True):
    return subprocess.run(['adb',*args],check=check,stdout=subprocess.PIPE,stderr=subprocess.PIPE).stdout.decode(errors='replace').strip()
def shot(path):
    path.write_bytes(subprocess.check_output(['adb','exec-out','screencap','-p']))
adb('root');adb('wait-for-device')
adb('install','-r','visual-apk/app-direct-debug.apk')
adb('shell','settings','put','global','window_animation_scale','0')
adb('shell','settings','put','global','transition_animation_scale','0')
adb('shell','settings','put','global','animator_duration_scale','0')
home=adb('shell','cmd','package','resolve-activity','--brief','-a','android.intent.action.MAIN','-c','android.intent.category.HOME').splitlines()[-1]
package=home.split('/')[0]
adb('shell','input','keyevent','KEYCODE_HOME');time.sleep(2)
# A fixture-only desktop shortcut in the disposable AOSP Launcher3 database.
adb('shell','am','force-stop',package)
remote=adb('shell','find',f'/data/user/0/{package}/databases','-name','*.db').splitlines()
installed=False
with tempfile.TemporaryDirectory() as tmp:
    for path in remote:
        local=Path(tmp)/Path(path).name
        adb('pull',path,str(local))
        for suffix in ['-wal','-shm']:
            adb('pull',path+suffix,str(local)+suffix,check=False)
        db=sqlite3.connect(local)
        names={r[0] for r in db.execute("select name from sqlite_master where type='table'")}
        if 'favorites' not in names: db.close();continue
        cols={r[1] for r in db.execute('pragma table_info(favorites)')}
        row={'_id':db.execute('select coalesce(max(_id),0)+1 from favorites').fetchone()[0],
             'title':'Vayora','intent':'#Intent;action=android.intent.action.MAIN;category=android.intent.category.LAUNCHER;component=com.vayora.app/.MainActivity;end',
             'container':-100,'screen':0,'cellX':1,'cellY':2,'spanX':1,'spanY':1,'itemType':0,'profileId':0,'rank':0,'restored':0}
        row={k:v for k,v in row.items() if k in cols}
        db.execute('insert into favorites ('+','.join(row)+') values ('+','.join('?' for _ in row)+')',list(row.values()))
        db.commit();db.execute('pragma wal_checkpoint(truncate)');db.close()
        ownership=adb('shell','stat','-c','%u:%g',path)
        adb('push',str(local),path)
        adb('shell','rm','-f',path+'-wal',path+'-shm')
        adb('shell','chown',ownership,path);adb('shell','restorecon',path)
        installed=True;break
assert installed,'Launcher database fixture unavailable; do not substitute a mock screenshot'
adb('shell','am','start','-n',home);time.sleep(4)
shot(dest/'launcher-home.png')
Image.open(dest/'launcher-home.png').resize((540,960),Image.Resampling.LANCZOS).save(dest/'launcher-home-preview.png')
adb('shell','uiautomator','dump','/sdcard/launcher.xml')
xml=adb('shell','cat','/sdcard/launcher.xml')
assert 'Vayora' in xml,'New icon must be visible on the actual home screen'
# Keep launch frames so the selected native splash screenshot can be audited.
adb('shell','am','force-stop','com.vayora.app')
process=subprocess.Popen(['adb','shell','am','start','-n','com.vayora.app/.MainActivity'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
frames=dest/'launch-frames';frames.mkdir(exist_ok=True)
candidates=[]
for i in range(9):
    time.sleep(.08)
    path=frames/f'frame-{i:02}.png';shot(path)
    im=Image.open(path).convert('RGB').resize((108,192))
    pixels=list(im.getdata())
    dark=sum(1 for r,g,b in pixels if abs(r-10)<4 and abs(g-10)<4 and abs(b-20)<4)/len(pixels)
    white=sum(1 for r,g,b in pixels if min(r,g,b)>235)/len(pixels)
    if dark>.65 and white>.0002: candidates.append((i,path))
process.wait(timeout=30)
assert candidates,'Native splash not captured; inspect launch frames before approving'
# Earliest matching launch frame excludes subsequent Flutter content.
(dest/'native-splash.png').write_bytes(candidates[0][1].read_bytes())
(dest/'README.md').write_text('Actual API 35 AOSP emulator screenshots. launcher-home.png uses the installed debug APK; native-splash.png is the earliest matching launch frame. All raw launch frames are retained. Adaptive circle/squircle and monochrome previews are in ../branding/adaptive-masks.png.\n')
sources=sorted(Path('mobile/assets/branding').glob('*.svg'))+[Path('mobile/flutter_native_splash.yaml')]
(dest/'source-hash.txt').write_text(hashlib.sha256(b''.join(p.read_bytes() for p in sources)).hexdigest())
print('Captured installed launcher icon and native splash on API 35')
