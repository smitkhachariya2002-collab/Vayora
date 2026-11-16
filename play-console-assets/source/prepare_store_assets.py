from pathlib import Path
import urllib.request
p=Path('mobile/assets/storefonts');p.mkdir(exist_ok=True)
b=urllib.request.urlopen('https://raw.githubusercontent.com/google/fonts/main/ofl/inter/Inter%5Bopsz,wght%5D.ttf',timeout=30).read()
for n in ['Thin','ExtraLight','Light','Regular','Medium','SemiBold','Bold','ExtraBold','Black']:(p/('Inter-'+n+'.ttf')).write_bytes(b)
lic=urllib.request.urlopen('https://raw.githubusercontent.com/google/fonts/main/ofl/inter/OFL.txt',timeout=30).read();Path('play-console-assets/Inter-OFL.txt').write_bytes(lic)
p=Path('mobile/pubspec.yaml');Path('release-check/pubspec-before-assets.yaml').write_bytes(p.read_bytes());s=p.read_text().replace('    - assets/icon.png','    - assets/icon.png\n    - assets/storefonts/');p.write_text(s)
