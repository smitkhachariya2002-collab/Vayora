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
    packages = {n.get(A+'name') for n in root.findall('./queries/package')}
    expected = ["com.google.android.apps.nbu.paisa.user","com.phonepe.app","net.one97.paytm","in.org.npci.upiapp","in.amazon.mShop.android.shopping","com.dreamplug.androidapp","com.mobikwik_new","com.csam.icici.bank.imobile","com.bandhan.mbanking"]
    assert set(expected) <= packages, f'{path}: missing explicit wallet visibility'
    assert any(
        any(a.get(A+'name') == 'android.intent.action.VIEW' for a in intent.findall('action'))
        and any(d.get(A+'scheme') == 'https' for d in intent.findall('data'))
        for intent in root.findall('./queries/intent')
    ), f'{path}: missing HTTPS visibility'
    assert not any(n.get(A+'name') == 'android.permission.QUERY_ALL_PACKAGES'
                   for n in root.findall('uses-permission')), path
    print(f'PASS: generic UPI/HTTPS and wallet visibility, no QUERY_ALL_PACKAGES: {path}')
