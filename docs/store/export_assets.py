"""Reproducible graphics from production Flutter widgets and original demo art."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import argparse, json, re, subprocess, hashlib, zipfile
ROOT=Path(__file__).resolve().parent
REPO=ROOT.parent.parent
BG=(10,10,20); SURFACE=(20,20,36); WHITE=(244,244,250)
PRIMARY=(124,92,255); PINK=(255,92,168)
BOLD=REPO/'mobile/assets/fonts/Poppins-Bold.ttf'
MEDIUM=REPO/'mobile/assets/fonts/Poppins-Medium.ttf'
CAPTIONS=["Discover channels you'll love","Watch trailers and full videos","Smooth full-screen player","Join channels and follow creators","15 GB free cloud storage","Safe community, you're in control"]
NAMES=['explore','post','player','channels','cloud','menu']
TABLET=['explore','post','cloud','channels']
def font(size,bold=True):return ImageFont.truetype(str(BOLD if bold else MEDIUM),size)
def gradient(size,stops):
 im=Image.new('RGB',size);d=ImageDraw.Draw(im)
 for y in range(size[1]):
  t=y/max(1,size[1]-1)*(len(stops)-1);a=min(int(t),len(stops)-2);f=t-a
  c=tuple(round(stops[a][i]*(1-f)+stops[a+1][i]*f) for i in range(3))
  d.line((0,y,size[0],y),fill=c)
 return im
def artwork():
 folder=ROOT/'source-art';folder.mkdir(parents=True,exist_ok=True)
 palettes=[[(38,32,85),(155,101,167)],[(37,69,72),(205,166,110)],[(39,35,90),(173,102,157)],[(29,76,91),(184,159,125)]]
 for index in range(4):
  im=gradient((1200,675),palettes[index]);d=ImageDraw.Draw(im)
  d.ellipse((860,70,1010,220),fill=(255,216,165))
  if index in [0,3]:
   d.polygon([(0,450),(270,145),(540,430),(825,230),(1200,470),(1200,675),(0,675)],fill=(85,72,128))
   d.polygon([(195,230),(270,145),(356,250),(290,225),(262,245)],fill=(224,214,237))
   d.polygon([(0,590),(390,370),(610,515),(930,340),(1200,520),(1200,675),(0,675)],fill=(32,52,79))
   d.polygon([(370,675),(685,495),(800,485),(525,675)],fill=(126,145,157))
   for x,y,h in [(80,550,135),(155,590,110),(1010,600,180),(1110,570,145)]:
    d.rectangle((x-4,y-h//2,x+4,y+40),fill=(22,37,45))
    d.polygon([(x,y-h),(x-38,y),(x+38,y)],fill=(29,67,69))
  elif index==1:
   d.rounded_rectangle((100,470,1100,675),40,fill=(86,55,43))
   d.ellipse((330,220,870,650),fill=(224,216,197));d.ellipse((370,255,830,610),fill=(55,102,72))
   for cx,cy,col in [(470,340,(236,140,76)),(590,430,(215,184,99)),(725,360,(212,101,78)),(510,520,(124,161,83)),(690,530,(242,205,122))]:d.ellipse((cx-43,cy-36,cx+43,cy+36),fill=col)
   d.line((930,260,900,600),fill=(220,202,171),width=16)
  else:
   d.rounded_rectangle((165,295,1040,600),40,fill=(36,32,64))
   for n in range(15):
    x=190+n*54;d.rounded_rectangle((x,330,x+44,570),6,fill=(234,231,244))
    if n%7 not in [2,6]:d.rounded_rectangle((x+27,330,x+53,465),5,fill=(55,44,78))
   for n in range(4):d.arc((350+n*30,80+n*10,740+n*30,310+n*10),180,350,fill=(220,170,235),width=5)
  im.save(folder/f'art-{index}.png',optimize=True)
def wrap(text,draw,f,maxwidth):
 words=text.split();lines=[];line=''
 for word in words:
  candidate=(line+' '+word).strip()
  if draw.textbbox((0,0),candidate,font=f)[2]>maxwidth and line:lines.append(line);line=word
  else:line=candidate
 if line:lines.append(line)
 return lines
def caption(im,text):
 w,h=im.size;scale=w/1080;d=ImageDraw.Draw(im);f=font(round(64*scale))
 lines=wrap(text,d,f,w-round(160*scale));top=round(90*scale);lineh=round(88*scale)
 for i,line in enumerate(lines):
  tw=d.textbbox((0,0),line,font=f)[2];d.text(((w-tw)/2,top+i*lineh),line,font=f,fill=WHITE)
 d.rounded_rectangle((round(w*.45),top+len(lines)*lineh+30*scale,round(w*.55),top+len(lines)*lineh+38*scale),round(4*scale),fill=PRIMARY)
 return top+len(lines)*lineh+round(100*scale)
def framed(im,raw,box,phone=True):
 # Uniform fit only: never stretch, crop or retouch production UI.
 x,y,w,h=map(round,box);d=ImageDraw.Draw(im);r=max(16,round(w*.045))
 d.rounded_rectangle((x,y,x+w,y+h),r,fill=SURFACE,outline=(79,65,120),width=max(2,w//250))
 pad=max(5,w//100);status=round(w*.07) if phone else round(w*.045);area=(w-2*pad,h-2*pad-status)
 screen=raw.convert('RGB');screen.thumbnail(area,Image.Resampling.LANCZOS)
 sx=x+(w-screen.width)//2;sy=y+pad+status+(area[1]-screen.height)//2;im.paste(screen,(sx,sy))
 if phone and w>=400:
  d.text((x+pad+round(w*.04),y+pad+round(w*.01)),'9:41',font=font(max(10,round(w*.028)),False),fill=WHITE)
  bx=x+w-round(w*.09);by=y+pad+round(w*.022);bw=round(w*.045);bh=max(5,round(w*.019))
  d.rounded_rectangle((bx,by,bx+bw,by+bh),2,outline=WHITE,width=1);d.rectangle((bx+2,by+2,bx+bw-2,by+bh-2),fill=WHITE)
def screenshot(device,name,index,size,text):
 im=Image.new('RGB',size,BG);w,h=size;top=caption(im,text);scale=w/1080
 width=round(w*(.79 if device=='phone' else .85));height=round(h-top-60*scale)
 framed(im,Image.open(ROOT/'raw'/f'{device}-{name}.png'),((w-width)//2,top,width,height),phone=device=='phone')
 if name=='menu':
  iw=round(w*.29);ih=round(iw*1920/1080)+35;ix=round(w*.14);iy=h-ih-round(95*scale)
  d=ImageDraw.Draw(im);d.rounded_rectangle((ix-10,iy-50,ix+iw+10,iy+ih+10),20,fill=SURFACE,outline=PRIMARY,width=2)
  d.text((ix+12,iy-44),'Profile',font=font(round(28*scale)),fill=WHITE)
  framed(im,Image.open(ROOT/'raw'/'phone-profile.png'),(ix,iy,iw,ih))
 folder=ROOT/device;folder.mkdir(exist_ok=True);im.save(folder/f'{index:02}.png',optimize=True)
def feature():
 im=Image.new('RGB',(1024,500),BG);glow=Image.new('RGB',im.size,BG);d=ImageDraw.Draw(glow)
 for r in range(430,0,-5):
  t=1-r/430;c=tuple(round(BG[i]+t*.33*(PRIMARY[i]-BG[i])) for i in range(3));d.ellipse((820-r,230-r,820+r,230+r),fill=c)
 im=Image.blend(im,glow,.85);d=ImageDraw.Draw(im);d.arc((480,-190,1220,620),70,300,fill=(71,51,134),width=5)
 layer=Image.new('RGBA',im.size,(0,0,0,0));ld=ImageDraw.Draw(layer)
 for b in [(676,154,815,280),(744,107,892,280),(830,174,952,286)]:ld.ellipse(b,fill=(155,92,255,60))
 ld.rounded_rectangle((690,220,930,303),32,fill=(255,92,168,35))
 layer=layer.filter(ImageFilter.GaussianBlur(15));im=Image.alpha_composite(im.convert('RGBA'),layer).convert('RGB');d=ImageDraw.Draw(im)
 icon=Image.open(ROOT/'icon-512.png').convert('RGBA').resize((78,78),Image.Resampling.LANCZOS);im.paste(icon,(112,155),icon)
 d.text((210,144),'Vayora',font=font(76),fill=WHITE)
 d.text((112,258),'Videos. Channels. Your cloud.',font=font(25,False),fill=WHITE)
 framed(im,Image.open(ROOT/'raw'/'phone-explore.png'),(715,88,184,328))
 im.save(ROOT/'feature-graphic-1024x500.png',optimize=True)
def build():
 import cairosvg
 cairosvg.svg2png(url=str(REPO/'mobile/assets/branding/icon.svg'),write_to=str(ROOT/'icon-512.png'),output_width=512,output_height=512)
 icon=Image.open(ROOT/'icon-512.png').convert('RGBA');icon.save(ROOT/'icon-512.png',optimize=True)
 for i,name in enumerate(NAMES):screenshot('phone',name,i+1,(1080,1920),CAPTIONS[i])
 for device,size in [('tablet7',(1200,1920)),('tablet10',(1600,2560))]:
  for i,name in enumerate(TABLET):screenshot(device,name,i+1,size,CAPTIONS[NAMES.index(name)])
 feature();verify()
def verify():
 expected={'icon-512.png':((512,512),1024*1024,'App icon'),'feature-graphic-1024x500.png':((1024,500),15*1024*1024,'Feature graphic')}
 for device,size,count,label in [('phone',(1080,1920),6,'Phone screenshots'),('tablet7',(1200,1920),4,'7-inch tablet screenshots'),('tablet10',(1600,2560),4,'10-inch tablet screenshots')]:
  for i in range(1,count+1):expected[f'{device}/{i:02}.png']=(size,8*1024*1024,label)
 manifest=[];ocr={}
 for name,(size,limit,label) in expected.items():
  p=ROOT/name
  with Image.open(p) as im:
   assert im.size==size,(name,im.size);assert im.format=='PNG'
   assert im.mode==('RGBA' if name=='icon-512.png' else 'RGB'),(name,im.mode)
   if name.startswith(('phone/','tablet')):assert max(size)<=2*min(size)
  assert p.stat().st_size<limit,(name,p.stat().st_size)
  text=subprocess.run(['tesseract',str(p),'stdout','--psm','11'],capture_output=True,text=True,check=True).stdout
  forbidden=re.search(r'₹|\b(?:UPI|plans?|buy|lorem|ipsum|debug)\b|payment\s+(?:history|successful|status)|\b\d+\s*(?:INR|rupees)\b|[\w.+-]+@[\w.-]+',text,re.I)
  assert not forbidden,(name,forbidden.group(0) if forbidden else '')
  ocr[name]=text
  manifest.append({'file':name,'width':size[0],'height':size[1],'bytes':p.stat().st_size,'mode':'RGBA' if name=='icon-512.png' else 'RGB','upload':label,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
 (ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 (ROOT/'ocr-review.json').write_text(json.dumps(ocr,indent=2)+'\n')
 readme="""# Vayora — Google Play listing graphics

Royal Violet · Poppins Bold headlines / Medium captions · Videos. Channels. Your cloud.

## Upload
Open **Play Console → Vayora → Grow users → Store presence → Main store listing → Graphics**.
Extract vayora-play-assets.zip before uploading individual images.

| File | Pixels | File size (bytes) | Play Console destination |
|---|---|---:|---|
"""
 for m in manifest:readme+=f"| {m['file']} | {m['width']} × {m['height']} | {m['bytes']:,} | {m['upload']} |\n"
 readme+="""
## Provenance and checks
- Icon: exact launcher SVG artwork, full square, RGBA/32-bit PNG, no added corners/shadow, below 1 MB.
- All screens use current, unmodified production Flutter widgets in a golden-test renderer compiled with PLAY_STORE=true. Device physical dimensions are asserted before capture.
- Phone 1080 × 1920, DPR 3. Tablet 7: 1200 × 1920, DPR 2. Tablet 10: 1600 × 2560, DPR 2. The raw directory retains unframed captures for audit.
- Fictional names, views and member counts. Original nature, travel, cooking and music illustrations are generated by export_assets.py. No production accounts/data, secrets, emails, celebrities, brands or copyrighted film posters. Demo audience: all.
- Mocked Play status: billing disabled, 15 GB quota, approved full-content access. This demonstrates the access-approved experience and does not alter server entitlements.
- Only the native video decoder surface is substituted with the original landscape still. The production Watch layout and controls are real. This static capture does not prove video decoding or playback performance.
- User-approved image 06 combines the real channel Report/Block popup with a clearly labelled real Profile inset. It does not claim that menu exists in Profile.
- Captions are outside app captures. Uniform fitting only, no stretching or cropping. Clean presentation chrome: no notifications, full battery; no debug banners.
- export_assets.py checks exact dimensions, PNG RGB/RGBA mode, size limits and aspect ratios for all 16 images. ocr-review.json records a banned-text scan for prices/currency, UPI, plans/buy/payment screens, placeholder/debug text and emails.
- Flutter asserts no payment UI and no layout errors. Human visual review is recorded in the pull request.
- Feature graphic icon, Poppins wordmark, tagline and actual Explore phone remain within the central 80% safe area.
- Production Flutter, payment, backend and admin code are unchanged.

## Reproduce with GitHub Actions: Play Store graphics
1. python docs/store/export_assets.py --art
2. From mobile/: flutter test test/store_screenshots_test.dart --dart-define=STORE_SCREENSHOTS=true --dart-define=PLAY_STORE=true
3. python docs/store/export_assets.py --build
4. python docs/store/export_assets.py --verify

Flutter 3.35.7, Python 3.12, Pillow 11.1.0, CairoSVG 2.7.1, Tesseract. No live backend required.
Workflow saves generated deliverables only to this PR branch after a commit-head lease check.
ZIP includes the 16 upload images, README and manifest; raw captures and source/test material stay outside the ZIP.

Official specifications: https://support.google.com/googleplay/android-developer/answer/9866151
"""
 (ROOT/'README.md').write_text(readme)
 with zipfile.ZipFile(ROOT/'vayora-play-assets.zip','w',zipfile.ZIP_DEFLATED) as z:
  for name in [*expected,'README.md','manifest.json']:z.write(ROOT/name,name)
 sheet=Image.new('RGB',(1200,680),BG)
 for i in range(6):
  thumb=Image.open(ROOT/f'phone/{i+1:02}.png');thumb.thumbnail((190,570));sheet.paste(thumb,(i*200+5,70))
  ImageDraw.Draw(sheet).text((i*200+85,20),f'{i+1:02}',font=font(24),fill=WHITE)
 sheet.save(ROOT/'contact-sheet.png',optimize=True)
 print(json.dumps(manifest,indent=2))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--art',action='store_true');p.add_argument('--build',action='store_true');p.add_argument('--verify',action='store_true');a=p.parse_args()
 if a.art:artwork()
 if a.build:build()
 elif a.verify:verify()
