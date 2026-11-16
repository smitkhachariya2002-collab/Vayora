alter table public.app_policy_acceptances drop constraint app_policy_acceptances_policy_version_check;
alter table public.app_policy_acceptances add constraint app_policy_acceptances_policy_version_check check (policy_version in ('2026-11-15-v2','2026-11-16-v3'));
