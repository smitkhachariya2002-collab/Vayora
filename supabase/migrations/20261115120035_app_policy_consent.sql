-- First-launch terms acceptance is separate from member/channel access consent.
create table public.app_policy_acceptances (
  user_id uuid not null references auth.users(id) on delete cascade,
  policy_version text not null check (policy_version = '2026-11-15-v2'),
  accepted_at timestamptz not null default now(),
  primary key(user_id, policy_version)
);
alter table public.app_policy_acceptances enable row level security;
revoke all on public.app_policy_acceptances from public, anon, authenticated;
grant select on public.app_policy_acceptances to authenticated;
grant insert(user_id, policy_version) on public.app_policy_acceptances to authenticated;
create policy app_policy_read on public.app_policy_acceptances for select to authenticated
  using(user_id = (select auth.uid()));
create policy app_policy_accept on public.app_policy_acceptances for insert to authenticated
  with check(user_id = (select auth.uid()));
create function public.accept_app_consent(p_policy text) returns void
language sql security invoker set search_path = '' as $$
  insert into public.app_policy_acceptances(user_id, policy_version)
  values(auth.uid(), p_policy) on conflict do nothing;
$$;
revoke all on function public.accept_app_consent(text) from public, anon;
grant execute on function public.accept_app_consent(text) to authenticated;
