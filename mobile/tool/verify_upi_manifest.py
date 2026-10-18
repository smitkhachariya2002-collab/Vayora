"""Check the compiled/merged manifest, never just the source manifest."""
import sys
import xml.etree.ElementTree as ET
A = '{http://schemas.android.com/apk/res/android}'
for path in sys.argv[1:]:
    root = ET.parse(path).getroot()
    assert any(
        any(a.get(A+'name') == 'android.intent.action.VIEW' for a in intent.findall('action'))
        and any(d.get(A+'scheme') == 'upi' for d in intent.findall('data'))
        for intent in root.findall('./queries/intent')
    ), f'{path}: missing generic UPI visibility query'
    assert not any(n.get(A+'name') == 'android.permission.QUERY_ALL_PACKAGES'
                   for n in root.findall('uses-permission')), path
    print(f'PASS: generic UPI visibility, no QUERY_ALL_PACKAGES: {path}')
