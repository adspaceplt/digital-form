-- ===========================================================================
-- TAB BAR ORDER — the phone tab bar keeps its own order, the Dashboard in any
-- of its places (2026-11-22, the user: "The sequence still doesn't look
-- right. If I want clients to be at the middle, it's not possible now.").
-- 2026-11-22. Safe to run twice. Rollback at the foot. Mirrored byte for
-- byte in supabase/schema.sql under the same banner; tests/smsql.js
-- compares the two.
--
-- WHAT CHANGED
--   1. `rail_orders.tabs` is the bar's tabs in the bar's order: the
--      Dashboard (`overview`) and up to three sections, four keys at most,
--      More always after them on the page. Empty is still the standard (the
--      Dashboard, then the first sections the person may open).
--   2. A choice kept under TAB BAR CHOICE (the sections alone, read in the
--      rail's order) carries over: the Dashboard first, then its sections in
--      the order the rail drew them (the rail's groups, Work, Partners,
--      Company, each in the colleague's own order, else the standard).
--   3. `rail_tabs_set(p_tabs)` keeps the ordered list: every key the
--      Dashboard or one of the rail's sections, none twice, four at most,
--      the Dashboard among them (`bad-tabs`); an empty list goes back to the
--      standard. The caller's own row. `rail_order_mine()` is unchanged.
--   The table stays closed: RLS on, no policy, no grant. A personal choice,
--   so nothing is filed in the Activity record.
--
-- ORDER: the pages, then this file. A page served before it reads a kept
-- choice without the Dashboard as the Dashboard first, then the sections;
-- a save it sends before this file is applied is refused (`bad-tabs`) and
-- the sheet says Not saved, the arrangement kept.
--
-- ROLLBACK
--   Pages first, then restate `rail_tabs_set(text[])` from TAB BAR CHOICE
--   and run `update public.rail_orders set tabs = array_remove(tabs,
--   'overview')`.
-- ===========================================================================

update public.rail_orders o
   set tabs = array['overview'] || array(
         select t.k
           from unnest(o.tabs) with ordinality t(k, n)
           left join (values ('work', 1, 1), ('review', 1, 2), ('scripts', 1, 3), ('reports', 1, 4), ('whatsapp', 1, 5),
                             ('clients', 2, 6), ('campaigns', 2, 7), ('suppliers', 2, 8),
                             ('register', 3, 9), ('services', 3, 10), ('links', 3, 11), ('team', 3, 12)) s(k, g, p) on s.k = t.k
          order by coalesce(s.g, 9), (array_position(o.sections, t.k) is null),
                   coalesce(array_position(o.sections, t.k), s.p, 99), t.n),
       updated_at = now()
 where cardinality(o.tabs) between 1 and 3
   and not ('overview' = any(o.tabs));

create or replace function public.rail_tabs_set(p_tabs text[])
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members;
  v_list text[] := coalesce(p_tabs, '{}');
  v_known constant text[] := array['overview', 'work', 'clients', 'review', 'scripts', 'campaigns', 'reports', 'whatsapp',
    'register', 'suppliers', 'links', 'services', 'team'];
begin
  me := public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if cardinality(v_list) > 4
     or (cardinality(v_list) > 0 and not ('overview' = any(v_list)))
     or exists (select 1 from unnest(v_list) k where k is null or not (k = any(v_known)))
     or (select count(distinct k) from unnest(v_list) k) <> cardinality(v_list) then
    return jsonb_build_object('error', 'bad-tabs');
  end if;
  insert into public.rail_orders (member_id, tabs, updated_at) values (me.id, v_list, now())
  on conflict (member_id) do update set tabs = excluded.tabs, updated_at = now();
  return jsonb_build_object('tabs', to_jsonb(v_list));
end $$;
grant execute on function public.rail_tabs_set(text[]) to authenticated;

-- END OF TAB BAR ORDER -------------------------------------------------------

select public.functions_tidy();
