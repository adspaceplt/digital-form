-- ===========================================================================
-- TAX CODES CHOSEN AND DELETED — Read from Bukku takes only the codes ticked,
-- and a code no line, quotation or letter names can be deleted (2026-10-22)
-- ===========================================================================
-- WHY (the user, 2026-10-22: "Read from bukku for sst codes pull in 32 items
-- for taxes which i only uses 0% no tax or 8% SST. And you didnt provide
-- option to delete this is a mistake or error"): Read from Bukku took every
-- code Bukku holds, and a code once held could only be stood down.
--
-- WHAT IT CHANGES
--   * `tax_codes_delete(p_codes)` (Business settings): deletes the codes
--     named, all or none; refused `in-use` with the codes a service line, a
--     quotation or a letter names (those are set not offered instead), and
--     `bad-row` for a list of none or past 100. Filed `team.changed` under
--     Tax codes, the codes named.
--   * The page: Read from Bukku opens a list of Bukku's codes to tick (the
--     codes already offered ticked), and only the ticked ones are kept as
--     offered; each code's ⋯ holds Delete, and Select codes deletes several.
--
-- ORDER: this file, then the pages. An old page never calls it. Safe to
-- run twice. Rollback: `revoke execute on function
-- public.tax_codes_delete(text[]) from authenticated` (the function may
-- stay).
-- ===========================================================================

create or replace function public.tax_code_uses(p_code text)
returns int
language sql stable security definer set search_path = public as $$
  select (select count(*) from public.client_services s where s.tax_code = p_code)::int
       + (select count(*) from public.quotations q
           where exists (select 1 from jsonb_array_elements(case when jsonb_typeof(q.lines) = 'array' then q.lines else '[]'::jsonb end) l
                          where l ->> 'tax_code' = p_code)
              or q.selection::text like '%"tax": ' || to_jsonb(p_code)::text || '%')::int
       + (select count(*) from public.client_documents d
           where to_jsonb(d)::text like '%"tax_code": ' || to_jsonb(p_code)::text || '%')::int
$$;
revoke all on function public.tax_code_uses(text) from public, anon, authenticated;

create or replace function public.tax_codes_delete(p_codes text[])
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members := public.ops_me();
  v_codes text[];
  v_used text[];
  v_gone text[];
begin
  if v_me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select array_agg(distinct btrim(c)) into v_codes from unnest(coalesce(p_codes, '{}')) c where btrim(coalesce(c, '')) <> '';
  if v_codes is null or array_length(v_codes, 1) > 100 then return jsonb_build_object('error', 'bad-row'); end if;
  perform 1 from public.tax_codes t where t.code = any(v_codes) for update;
  select array_agg(t.code order by t.code) into v_used
    from public.tax_codes t where t.code = any(v_codes) and public.tax_code_uses(t.code) > 0;
  if v_used is not null then return jsonb_build_object('error', 'in-use', 'codes', to_jsonb(v_used)); end if;
  with d as (delete from public.tax_codes t where t.code = any(v_codes) returning t.code)
  select array_agg(d.code order by d.code) into v_gone from d;
  if v_gone is not null then
    insert into public.activity_log (actor, action, subject, detail)
    values (v_me.name, 'team.changed', 'Tax codes',
            array_length(v_gone, 1) || ' deleted: ' || array_to_string(v_gone, ', '));
  end if;
  return public.tax_codes_list() || jsonb_build_object('deleted', coalesce(array_length(v_gone, 1), 0));
end $$;
revoke all on function public.tax_codes_delete(text[]) from public, anon;
grant execute on function public.tax_codes_delete(text[]) to authenticated;

-- END OF TAX CODES CHOSEN AND DELETED -----------------------------------------

select public.functions_tidy();
