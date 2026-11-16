"""Destructive fixtures are restricted to a disposable local Supabase database."""
import pathlib,subprocess,sys,re
root=pathlib.Path(__file__).parent
url='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
def run(sql,report=False):
 p=subprocess.run(['psql',url,'-X','-v','ON_ERROR_STOP=1'],input=sql,text=True,capture_output=True)
 output=p.stdout+p.stderr
 if report:
  match=re.search(r'RESULT total=\d+ failed=0\b[^\n]*',output)
  if match: print(match.group());return
 if p.returncode: print(output);sys.exit(1)
run((root/'fixtures.sql').read_text())
run('begin;\n'+(root/'DRAFT_puffle_v109_preserving_upgrade.sql').read_text()+'\ncommit;')
print('PASS populated conversion on Supabase')
consent_migrations=list((root.parent/'migrations').glob('*_app_policy_consent.sql')) or list(pathlib.Path('/tmp/vayora-reviewed-upgrade').glob('*_app_policy_consent.sql'))
assert len(consent_migrations)==1
run(consent_migrations[0].read_text())
run((root/'app_consent_test.sql').read_text())
print('PASS guest consent, isolation, policy validation and unchanged channel access')
for p in sorted((root/'tests').glob('*.sql')):
 run("begin; insert into private.owner_bootstrap(email) values('owner@example.test') on conflict do nothing; update public.app_mode set free_mode=false,plans_visible_for='everyone',free_plans_for='none'; update public.payment_settings set enabled=true,upi_id='2728412a@bandhan',payee_name='As Enterprice';\n"+p.read_text(),True)
upi_migrations=list((root.parent/'migrations').glob('*_verify_upi_before_activation.sql')) or list(pathlib.Path('/tmp/vayora-reviewed-upgrade').glob('*_verify_upi_before_activation.sql'))
assert len(upi_migrations)==1
run(upi_migrations[0].read_text())
run((root/'upi_verification_test.sql').read_text())
print('PASS client callbacks cannot activate plans; verified callbacks are idempotent')
for suffix in ['owner_requested_instant_upi','instant_upi_no_daily_review']:
 candidates=list((root.parent/'migrations').glob('*_'+suffix+'.sql')) or list(pathlib.Path('/tmp/vayora-reviewed-upgrade').glob('*_'+suffix+'.sql'))
 assert len(candidates)==1
 run(candidates[0].read_text())
run((root/'instant_upi_test.sql').read_text())
print('PASS owner-requested instant activation, duplicate protection and bank-unverified status')
notices=list((root.parent/'migrations').glob('*_single_button_consent_notice.sql')) or list(pathlib.Path('/tmp/vayora-reviewed-upgrade').glob('*_single_button_consent_notice.sql'))
assert len(notices)==1
run(notices[0].read_text())
run("begin; select set_config('request.jwt.claims','{\"sub\":\"10000000-0000-0000-0000-000000000003\",\"role\":\"authenticated\",\"is_anonymous\":true}',true); set local role authenticated; select public.accept_app_consent('2026-11-16-v3'); do $$begin if not exists(select 1 from public.app_policy_acceptances where user_id=auth.uid() and policy_version='2026-11-16-v3') then raise exception 'New notice not saved'; end if;end$$; rollback;")
print('PASS new explicit notice version accepted for guests')
run((root/'rollback.sql').read_text())
run("do $$begin if (select count(*) from public.profiles)<>3 or (select count(*) from public.payment_orders)<>2 or (select count(*) from public.subscriptions)<>1 or not has_schema_privilege('authenticated','public','usage') then raise exception 'Rollback mismatch';end if;end$$;")
print('PASS rollback preserves original data and access')
