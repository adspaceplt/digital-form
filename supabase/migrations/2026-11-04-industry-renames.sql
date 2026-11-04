-- ===========================================================================
-- INDUSTRY RENAMES REACH EVERY CLIENT (2026-11-04)
-- ===========================================================================
-- A rename of an industry carried onto its clients through the clients
-- table's own guards, so a colleague holding Business settings whose group
-- sees its own clients only was refused (`client-scope`) by a client they
-- do not hold, and the rename failed whole. `industry_save` now lets the
-- update through as `team_hand_over` does (`adspace.team_owner`, on for that
-- one update and off after). Other keeps its name (`fixed`), so the list
-- and the quotation website keep it last. Every refusal of the one before
-- stays. Safe to run twice. Rollback: run industry_save from
-- 2026-11-04-industries.sql again.
-- ===========================================================================

create or replace function public.industry_save(p_was text, p_name text, p_name_zh text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_zh   text := nullif(btrim(regexp_replace(coalesce(p_name_zh, ''), '\s+', ' ', 'g')), '');
  v_was  public.industries;
  v_n    int := 0;
  v_moved text[] := '{}';
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if length(v_name) < 2 or length(v_name) > 40 then return jsonb_build_object('error', 'bad-name'); end if;
  if v_zh is not null and length(v_zh) > 40 then return jsonb_build_object('error', 'bad-name-zh'); end if;
  perform pg_advisory_xact_lock(hashtextextended('industries', 0));
  if p_was is not null then
    select * into v_was from public.industries i where i.name = p_was for update;
    if v_was.name is null then return jsonb_build_object('error', 'not-found'); end if;
    -- Other keeps its name, so it stays the last choice (review 6).
    if v_was.name = 'Other' and v_name <> 'Other' then return jsonb_build_object('error', 'fixed'); end if;
  end if;
  if exists (select 1 from public.industries i where lower(i.name) = lower(v_name) and i.name is distinct from p_was) then
    return jsonb_build_object('error', 'taken');
  end if;
  if v_was.name is null then
    insert into public.industries (name, name_zh, updated_by) values (v_name, v_zh, me.id);
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Industries', 'Added: ' || v_name);
    return jsonb_build_object('ok', true, 'name', v_name);
  end if;
  v_moved := array_remove(array[
    case when v_was.name <> v_name then 'Name: ' || v_was.name || ' → ' || v_name end,
    case when v_was.name_zh is distinct from v_zh then 'Chinese name: ' || coalesce(v_was.name_zh, 'not set') || ' → ' || coalesce(v_zh, 'not set') end], null);
  if cardinality(v_moved) = 0 then return jsonb_build_object('ok', true, 'name', v_name, 'clients', 0); end if;
  update public.industries i set name = v_name, name_zh = v_zh, updated_at = now(), updated_by = me.id
   where i.name = v_was.name;
  -- A rename carries onto every client holding the old name (the user,
  -- 2026-11-04: "A").
  -- The rename reaches every client, the ones outside the caller's own
  -- client scope included: the guard lets it through as it does a
  -- hand-over (`adspace.team_owner`), set for this update alone (review 2).
  if v_was.name <> v_name then
    perform set_config('adspace.team_owner', 'on', true);
    update public.clients c set industry = v_name where c.industry = v_was.name;
    get diagnostics v_n = row_count;
    perform set_config('adspace.team_owner', 'off', true);
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Industries', v_name || ' · ' || array_to_string(v_moved, ' · ') ||
          case when v_n = 1 then ' · 1 client updated' when v_n > 1 then ' · ' || v_n || ' clients updated' else '' end);
  return jsonb_build_object('ok', true, 'name', v_name, 'clients', v_n);
end $$;
revoke all on function public.industry_save(text, text, text) from public, anon;
grant execute on function public.industry_save(text, text, text) to authenticated;

-- END OF INDUSTRY RENAMES REACH EVERY CLIENT ---------------------------------

select public.functions_tidy();
