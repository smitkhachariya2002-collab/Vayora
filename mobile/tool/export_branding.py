"""Deterministic exports from editable SVGs; run in GitHub Actions."""
from pathlib import Path
import io
import cairosvg
from PIL import Image, ImageDraw, ImageFont

root=Path(__file__).resolve().parents[2]
brand=root/'mobile/assets/branding'
public=root/'admin/public'; public.mkdir(exist_ok=True)
store=root/'docs/store'; store.mkdir(parents=True,exist_ok=True)
review=root/'docs/visual-refresh/branding'; review.mkdir(parents=True,exist_ok=True)
def export(source,name,size):
    dest=brand/name
    cairosvg.svg2png(url=str(brand/source),write_to=str(dest),output_width=size,output_height=size)
    return Image.open(dest).convert('RGBA')
full=export('icon.svg','icon_1024.png',1024)
full.resize((512,512),Image.Resampling.LANCZOS).save(brand/'icon_512.png')
export('icon_background.svg','icon_background.png',432)
fg=export('icon_foreground.svg','icon_foreground.png',432)
export('icon_monochrome.svg','icon_monochrome.png',432)
export('icon_foreground.svg','splash_symbol.png',288)
export('icon_foreground.svg','splash_android12.png',960)
full.resize((512,512),Image.Resampling.LANCZOS).save(store/'icon-512.png')
for size in [192,512]:
    full.resize((size,size),Image.Resampling.LANCZOS).save(public/f'icon-{size}.png')
full.resize((256,256),Image.Resampling.LANCZOS).save(public/'favicon.ico',sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
feature_svg=(brand/'icon_background.svg').read_text().replace('width="108" height="108" viewBox="0 0 108 108"','width="1024" height="500" viewBox="0 0 1024 500"').replace('<rect width="108" height="108"','<rect width="1024" height="500"')
feature=Image.open(io.BytesIO(cairosvg.svg2png(bytestring=feature_svg.encode()))).convert('RGBA')
logo=fg.resize((360,360),Image.Resampling.LANCZOS)
feature.alpha_composite(logo,(45,70))
font=ImageFont.truetype(str(root/'mobile/assets/fonts/Poppins-Bold.ttf'),110)
ImageDraw.Draw(feature).text((415,170),'Vayora',font=font,fill='white',stroke_width=0)
feature.convert('RGB').save(store/'feature-1024x500.png')
# Clearly labelled asset previews; actual launcher/splash evidence comes from emulator.
preview=Image.new('RGB',(960,390),'#0A0A14');draw=ImageDraw.Draw(preview)
smallfont=ImageFont.truetype(str(root/'mobile/assets/fonts/Poppins-Medium.ttf'),20)
for x,kind in [(40,'Circle'),(355,'Squircle'),(670,'Monochrome')]:
    mask=Image.new('L',(250,250),0);md=ImageDraw.Draw(mask)
    if kind=='Circle': md.ellipse((0,0,249,249),fill=255)
    else: md.rounded_rectangle((0,0,249,249),radius=64,fill=255)
    icon=full.resize((250,250),Image.Resampling.LANCZOS)
    if kind=='Monochrome':
        icon=Image.new('RGBA',(250,250),'#D6C9FF')
        alpha=fg.resize((250,250),Image.Resampling.LANCZOS).getchannel('A')
        symbol=Image.new('RGBA',(250,250),'#342653');symbol.putalpha(alpha)
        icon.alpha_composite(symbol)
    preview.paste(icon,(x,30),mask)
    draw.text((x,305),kind,fill='white',font=smallfont)
draw.text((40,350),'Asset mask previews (not device screenshots)',fill='#9C9CB8',font=smallfont)
preview.save(review/'adaptive-masks.png')
print('Exported SVG branding, Android foreground, favicon, store assets and mask previews')
