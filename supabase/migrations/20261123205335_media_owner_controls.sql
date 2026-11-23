-- Display metadata is editable by the owner; it never changes channel membership.
create function private.guard_display_followers() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('authenticated','anon') and not public.is_owner() and
 ((tg_op='INSERT' and new.display_followers<>0) or (tg_op='UPDATE' and new.display_followers is distinct from old.display_followers))
 then raise exception 'Only the owner can change displayed followers' using errcode='42501'; end if;
 return new;
end $$;
create trigger channel_display_followers before insert or update on public.channels for each row execute function private.guard_display_followers();
