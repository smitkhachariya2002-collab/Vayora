-- Both distributions share the same consent checks and payload contract.
do $$
declare definition text;
begin
 definition:=pg_get_functiondef('public.set_measurement_preferences(boolean,boolean,jsonb)'::regprocedure);
 if position('ext->>1<>''com.vayora.app''' in definition)=0 then raise exception 'Unexpected measurement context validator'; end if;
 execute replace(definition,'ext->>1<>''com.vayora.app''','ext->>1 not in (''com.vayora.app'',''com.vayora.play'')');
end $$;
