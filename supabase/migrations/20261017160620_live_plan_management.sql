
-- Keep all existing plan IDs, codes and references. Never round a price silently.
do $$ begin
 if exists(select 1 from public.plans where price_inr<>trunc(price_inr)) then
  raise exception 'Plans contain fractional INR prices; set whole-rupee prices before this migration';
 end if;
end $$;
alter table public.plans alter column price_inr type integer using price_inr::integer;
alter table public.plans add constraint plans_price_min check(price_inr>=1);
create function private.plan_perks_array(value jsonb) returns text[] language sql immutable set search_path='' as $$
 select coalesce(array_agg(item),array[]::text[]) from jsonb_array_elements_text(value) item
$$;
alter table public.plans alter column perks drop default;
alter table public.plans alter column perks type text[] using private.plan_perks_array(perks);
alter table public.plans alter column perks set default array[]::text[];
drop function private.plan_perks_array(jsonb);
alter table public.plans alter column active set default false;
alter table public.plans add column badge text;
alter table public.plans add column created_at timestamptz not null default now();
alter table public.plans add column updated_at timestamptz not null default now();
alter table public.plans add constraint plans_name_required check(length(btrim(name))>0);
create function private.guard_plan() returns trigger language plpgsql set search_path='' as $$
begin
 if TG_OP='DELETE' then raise exception 'Deactivate plans instead of deleting them' using errcode='42501'; end if;
 if TG_OP='INSERT' and new.code !~ '^[a-z0-9]+$' then
  raise exception 'Code must contain lowercase letters and numbers only' using errcode='23514';
 end if;
 if TG_OP='UPDATE' then
  if new.code is distinct from old.code then raise exception 'Plan code cannot be changed' using errcode='23514'; end if;
  new.created_at=old.created_at;
 end if;
 new.updated_at=clock_timestamp();
 return new;
end $$;
revoke all on function private.guard_plan() from public,anon,authenticated;
create trigger guard_plan before insert or update or delete on public.plans for each row execute function private.guard_plan();

drop policy if exists plans_delete on public.plans;
drop policy if exists plans_read on public.plans;
create policy plans_guest_read on public.plans for select to anon using(active);
create policy plans_read on public.plans for select to authenticated using(active or (select private.is_owner()));
-- Existing INSERT/UPDATE policies already require is_owner(), with USING + WITH CHECK.
revoke delete,truncate on public.plans from public,anon,authenticated,service_role;
grant select on public.plans to anon,authenticated;

-- A hidden row no longer passes RLS, so its UPDATE might not reach a guest.
-- Publish a data-free catalog revision as well; clients refetch the visible rows.
create table public.plan_catalog(id boolean primary key default true check(id),revision bigint not null default 0);
insert into public.plan_catalog(id)values(true);
alter table public.plan_catalog enable row level security;
revoke all on public.plan_catalog from public,anon,authenticated;
grant select on public.plan_catalog to anon,authenticated;
create policy plan_catalog_read on public.plan_catalog for select to anon,authenticated using(true);
create function private.notify_plan_catalog() returns trigger language plpgsql security definer set search_path='' as $$
begin update public.plan_catalog set revision=revision+1 where id; return null; end $$;
revoke all on function private.notify_plan_catalog() from public,anon,authenticated;
create trigger notify_plan_catalog after insert or update on public.plans for each row execute function private.notify_plan_catalog();
do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='plans') then
  alter publication supabase_realtime add table public.plans;
 end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='plan_catalog') then
  alter publication supabase_realtime add table public.plan_catalog;
 end if;
end $$;

create function private.admin_plan_impact() returns table(plan_id uuid,active_subscribers bigint,orders bigint)
language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_owner() then raise exception 'Owner required' using errcode='42501'; end if;
 return query select p.id,
 (select count(distinct s.user_id) from public.subscriptions s where s.plan_id=p.id and s.revoked_at is null and s.starts_at<=now() and s.ends_at>now()),
 (select count(*) from public.payment_orders o where o.plan_id=p.id)
 from public.plans p;
end $$;
create function public.admin_plan_impact() returns table(plan_id uuid,active_subscribers bigint,orders bigint)
language sql stable set search_path='' as $$ select * from private.admin_plan_impact() $$;
revoke all on function private.admin_plan_impact(),public.admin_plan_impact() from public,anon;
grant execute on function private.admin_plan_impact(),public.admin_plan_impact() to authenticated;

-- Checkout pricing only. Client-response validation/activation functions are untouched.
-- Hold the plan through order creation so a concurrent owner edit cannot mix snapshots.
create or replace function private.direct_payment_order(p_plan uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare pl public.plans; settings public.payment_settings; ord public.payment_orders;
begin
 if not private.is_member() then raise exception 'Login required'; end if;
 if private.client_free_mode() then raise exception 'Payments unavailable in free mode'; end if;
 select * into settings from public.payment_settings where id and enabled and length(btrim(upi_id))>2 and length(btrim(payee_name))>0;
 if not found then raise exception 'Payments are not available right now'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 select * into pl from public.plans where id=p_plan and active for share;
 if not found then raise exception 'Plan unavailable'; end if;
 update public.payment_orders set status='cancelled',reason='Replaced or expired'
 where user_id=auth.uid() and status in ('initiated','pending') and (plan_id<>p_plan or created_at<=now()-interval '24 hours'
 or amount_paise<>pl.price_inr::bigint*100 or duration_days<>pl.duration_days);
 select * into ord from public.payment_orders where user_id=auth.uid() and plan_id=p_plan and status in ('initiated','pending')
 and created_at>now()-interval '24 hours' order by created_at desc limit 1 for update;
 if not found then
 insert into public.payment_orders(user_id,plan_id,amount_paise,duration_days,reference)
 values(auth.uid(),p_plan,pl.price_inr::bigint*100,pl.duration_days,'VY'||to_char(now(),'YYMMDD')||encode(extensions.gen_random_bytes(6),'hex'))
 returning * into ord;
 end if;
 return to_jsonb(ord)||jsonb_build_object('upi_id',settings.upi_id,'payee_name',settings.payee_name);
end $$;

