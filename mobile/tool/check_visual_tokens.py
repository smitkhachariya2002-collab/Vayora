"""No obsolete orange paint or scattered colour literals in production Dart."""
from pathlib import Path
import re
old = re.compile(r'0x(?:[0-9A-F]{2})?(?:FF7A1A|E25A00|FFB347|8A2D05|2A1408|3A1B08|FF5F1F|FF8A00|FF6A00)|(?<!App)Colors\.(?:orange|deepOrange)',re.I)
assert old.search('Color(0x33FF7A1A)'), 'guard must include alpha variants'
errors=[]
for p in Path('lib').rglob('*.dart'):
    text=p.read_text()
    if old.search(text): errors.append(f'{p}: obsolete orange token')
    if p.name!='theme.dart' and re.search(r'(?<![\w.])(?:Color[.(]|Colors\.)',text):
        errors.append(f'{p}: colour literals must live in theme.dart')
if errors: raise SystemExit('\n'.join(errors))
print('PASS: colours centralised; no old orange palette in mobile/lib')
