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
run((root/'rollback.sql').read_text())
run("do $$begin if (select count(*) from public.profiles)<>3 or (select count(*) from public.payment_orders)<>2 or (select count(*) from public.subscriptions)<>1 or not has_schema_privilege('authenticated','public','usage') then raise exception 'Rollback mismatch';end if;end$$;")
print('PASS rollback preserves original data and access')
