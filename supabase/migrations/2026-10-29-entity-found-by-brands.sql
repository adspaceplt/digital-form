-- ===========================================================================
-- A BILLING ENTITY FOUND BY ITS BRANDS — Add entity and console search find
-- an entity by the brands it bills, word by word (2026-10-29)
-- ===========================================================================
-- WHY (the user, 2026-10-29: "Cant even find or lookup"): Add entity found
-- an entity by its registered name alone, as one phrase. S P Setia (Johor)
-- is billed as KESAS KENANGAN SDN. BHD., so "Setia" found nothing.
--
-- WHAT CHANGED
--   * `billing_entities_find(p_q)` reads what is typed word by word: every
--     word is found in the registered name, or in the name or Client ID of
--     a brand it bills that the reader sees ("setia" finds KESAS KENANGAN
--     SDN. BHD.; "kesas sdn" too). BRN digits, the ten, the scope and the
--     refusals are as before.
--
-- ORDER: this file (connector), then the pages. Either order is safe: the
-- answer's shape is unchanged. Safe to run twice.
--
-- ROLLBACK: run BILLING ENTITIES' billing_entities_find again.
-- ===========================================================================

-- A BILLING ENTITY FOUND BY ITS BRANDS --------------------------------------

create or replace function public.billing_entities_find(p_q text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_q text := btrim(coalesce(p_q, ''));
  v_words text[];
  v_digits text := regexp_replace(coalesce(p_q, ''), '\D', '', 'g');
begin
  if not public.allowed('clients.billing', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if length(v_q) < 2 then return jsonb_build_object('entities', '[]'::jsonb); end if;
  -- Each word as a pattern, a wildcard typed read as a letter.
  select array_agg('%' || replace(replace(replace(w, '\', '\\'), '%', '\%'), '_', '\_') || '%')
    into v_words
    from regexp_split_to_table(v_q, '\s+') w where w <> '';
  return jsonb_build_object('entities', coalesce((
    select jsonb_agg(x.j order by x.n) from (
      select public.billing_entity_json(e.id, null) as j, e.legal_name as n
        from public.billing_entities e
       where (not exists (
                select 1 from unnest(v_words) l
                 where not (coalesce(e.legal_name, '') ilike l
                            or exists (select 1 from public.client_entities ce
                                         join public.clients x on x.id = ce.client_id
                                        where ce.entity_id = e.id and public.client_seen(x.id, 'view')
                                          and (x.name ilike l or coalesce(x.client_code, '') ilike l))))
              or (length(v_digits) >= 4 and regexp_replace(coalesce(e.company_no, ''), '\D', '', 'g') like '%' || v_digits || '%'))
         and (not exists (select 1 from public.client_entities ce where ce.entity_id = e.id)
              or exists (select 1 from public.client_entities ce
                          where ce.entity_id = e.id and public.client_seen(ce.client_id, 'view')))
       order by e.legal_name
       limit 10) x), '[]'::jsonb));
end $$;
revoke all on function public.billing_entities_find(text) from public, anon;
grant execute on function public.billing_entities_find(text) to authenticated;

-- END OF A BILLING ENTITY FOUND BY ITS BRANDS -------------------------------

select public.functions_tidy();
