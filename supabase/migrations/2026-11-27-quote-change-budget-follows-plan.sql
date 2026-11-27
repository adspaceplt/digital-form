-- ===========================================================================
-- QUOTE CHANGE BUDGET FOLLOWS THE PLAN (2026-11-27)
-- ===========================================================================
-- WHY (hotfix, the user, 2026-11-27): on a sent quotation's Change
-- selection, a prospect moving from a plan with ads to one without kept
-- the quotation's advertising budget, so the preview priced a Meta
-- advertising line the prospect never asked for (a plan with ads always
-- carries its budget). /quote/ draws the budget only while the plan holds
-- ads or Advertising itself was asked; the change now follows it.
--
-- WHAT IT CHANGES
--   * `quote_change_sel`: where the plan changes from one with ads to one
--     without, the quotation's `budget` is taken out. A budget held beside
--     a plan without ads (Advertising asked on its own) stays, and a move
--     to a plan with ads keeps whatever the quotation held.
--
-- ORDER: the pages and this file in either order; the pages send no budget
-- on a change. An old tab meets the new rule at its next preview. Safe to
-- run twice. Holds no drop or delete.
-- ROLLBACK: run QUOTE FILES CAPPED's `quote_change_sel` again.
-- ===========================================================================

-- QUOTE CHANGE BUDGET FOLLOWS THE PLAN ---------------------------------------

/* The quotation's own selection with the prospect's changes in place, the
   files held to the pieces it makes (what the quotation held stays), and
   the advertising budget taken out where the plan leaves its ads. */
create or replace function public.quote_change_sel(p_base jsonb, p_sel jsonb, p_snap jsonb)
returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v jsonb := coalesce(p_base, '{}'::jsonb);
  s jsonb;
  k text;
  n int;
  v_ex jsonb := '{}'::jsonb;
  v_once jsonb := '[]'::jsonb;
begin
  if p_sel is null then return v; end if;
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-selection'); end if;
  if v ? 'brands' then return jsonb_build_object('error', 'brands'); end if;
  if p_sel ? 'plan' then
    s := public.quote_svc(p_snap, p_sel->>'plan');
    if jsonb_typeof(p_sel->'plan') <> 'string' or s is null or s->'spec'->>'role' is distinct from 'plan' or s->>'rate' is null then
      return jsonb_build_object('error', 'bad-plan');
    end if;
    if p_sel->>'plan' is distinct from v->>'plan' then
      -- A plan with ads carries its budget; a plan without leaves it.
      if coalesce((public.quote_svc(p_snap, v->>'plan')->'spec'->>'ads')::boolean, false)
         and not coalesce((s->'spec'->>'ads')::boolean, false) then v := v - 'budget'; end if;
      v := v - 'mix' - 'extra';
    end if;
    v := v || jsonb_build_object('plan', p_sel->>'plan');
  end if;
  if p_sel ? 'mix' then
    if jsonb_typeof(p_sel->'mix') <> 'string' or p_sel->>'mix' !~ '^[0-9]$' then return jsonb_build_object('error', 'bad-selection'); end if;
    v := v || jsonb_build_object('mix', p_sel->>'mix');
  end if;
  if p_sel ? 'platforms' then
    if jsonb_typeof(p_sel->'platforms') <> 'array' then return jsonb_build_object('error', 'bad-selection'); end if;
    v := v || jsonb_build_object('platforms', coalesce((select jsonb_agg(x order by array_position(array['meta', 'tiktok', 'rednote', 'linkedin'], x))
                                                          from (select distinct x from jsonb_array_elements_text(p_sel->'platforms') x
                                                                 where x in ('meta', 'tiktok', 'rednote', 'linkedin')) d), '[]'::jsonb));
  end if;
  if p_sel ? 'extra' then
    if jsonb_typeof(p_sel->'extra') <> 'object' or (select count(*) from jsonb_object_keys(p_sel->'extra')) > 10 then
      return jsonb_build_object('error', 'bad-extra');
    end if;
    for k in select jsonb_object_keys(p_sel->'extra') loop
      s := public.quote_svc(p_snap, k);
      if s is null or s->'spec'->>'role' is distinct from 'content' or coalesce(p_sel->'extra'->>k, '') !~ '^[0-9]{1,2}$' then
        return jsonb_build_object('error', 'bad-extra');
      end if;
      n := (p_sel->'extra'->>k)::int;
      if n > 0 then v_ex := v_ex || jsonb_build_object(k, n); end if;
    end loop;
    v := v || jsonb_build_object('extra', v_ex);
  end if;
  if p_sel ? 'files' then
    if jsonb_typeof(p_sel->'files') <> 'object' or (select count(*) from jsonb_object_keys(p_sel->'files')) > 5 then
      return jsonb_build_object('error', 'bad-once');
    end if;
    -- the files asked for replace the files held; every other one-time item stays
    select coalesce(jsonb_agg(o), '[]'::jsonb) into v_once from jsonb_array_elements(coalesce(v->'once', '[]'::jsonb)) o
     where not (coalesce(public.quote_svc(p_snap, o->>'slug')->'spec'->>'role', '') = 'addon'
                and public.quote_web_once_ok(public.quote_svc(p_snap, o->>'slug')));
    for k in select jsonb_object_keys(p_sel->'files') loop
      s := public.quote_svc(p_snap, k);
      if s is null or s->'spec'->>'role' is distinct from 'addon' or not public.quote_web_once_ok(s)
         or coalesce(p_sel->'files'->>k, '') !~ '^[0-9]{1,2}$' then
        return jsonb_build_object('error', 'bad-once');
      end if;
      n := (p_sel->'files'->>k)::int;
      if n > 0 then v_once := v_once || jsonb_build_array(jsonb_build_object('slug', k, 'qty', n)); end if;
    end loop;
    v := v || jsonb_build_object('once', v_once);
  end if;
  if p_sel ? 'term' then
    if coalesce(p_sel->>'term', '') !~ '^[0-9]{1,2}$'
       or not ((p_sel->>'term')::int = any (public.quote_web_terms()) or (p_sel->>'term')::int = (p_base->>'term')::int) then
      return jsonb_build_object('error', 'bad-term');
    end if;
    v := v || jsonb_build_object('term', (p_sel->>'term')::int);
  end if;
  -- The files held to the graphics and reels the changed selection makes.
  if v ? 'once' then v := public.quote_files_fit(v, p_snap, p_base); end if;
  return v;
end $$;
revoke all on function public.quote_change_sel(jsonb, jsonb, jsonb) from public, anon, authenticated;

-- END OF QUOTE CHANGE BUDGET FOLLOWS THE PLAN --------------------------------
