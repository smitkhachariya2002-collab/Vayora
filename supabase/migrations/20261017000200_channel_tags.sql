-- Channel tags; creation/review and creator-only edits retain existing RLS.
alter table public.channels add column tags text[] not null default '{}';

create function private.valid_channel_tags(value text[]) returns boolean
language sql immutable set search_path='' as $$
 select value is not null and cardinality(value)<=10 and coalesce(array_ndims(value),1)=1
 and not exists(select 1 from unnest(value) as tag where tag is null or length(btrim(tag)) not between 1 and 30)
$$;
revoke all on function private.valid_channel_tags(text[]) from public,anon;
grant execute on function private.valid_channel_tags(text[]) to authenticated,service_role;
alter table public.channels add constraint channels_tags_valid check(private.valid_channel_tags(tags));
