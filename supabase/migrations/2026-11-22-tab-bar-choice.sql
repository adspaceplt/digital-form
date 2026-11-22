-- ===========================================================================
-- TAB BAR CHOICE — a colleague chooses the phone tab bar's sections
-- (2026-11-22, the user: "How to make this flexible.. I want clients to be
-- accessible straight from mobile bottom tab"). 2026-11-22. Safe to run
-- twice. Rollback at the foot. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED
--   1. `rail_orders.tabs`: the sections a colleague turned on for the tab
--      bar, in no order (the bar reads them in the rail's order), at most
--      three; empty is the standard (the first sections the person may
--      open). The table stays closed: RLS on, no policy, no grant.
--   2. `rail_order_mine()` answers `tabs` beside `sections`.
--   3. `rail_tabs_set(p_tabs)` keeps them: every key one of the rail's
--      sections, none twice, three at most (`bad-tabs`); an empty list goes
--      back to the standard. The caller's own row, as `rail_order_set`. A
--      personal choice, so nothing is filed in the Activity record.
--   The Dashboard always holds the bar's first tab and is never chosen; a
--   section the person can no longer open drops out of the bar on the page.
--
-- ORDER: the pages, then this file. A page served before it never asks; a
-- page meeting a database without it saves the order and says the tab bar
-- choice is not available yet.
--
-- ROLLBACK
--   Pages first (the bar returns to the first sections), then remove
--   `rail_tabs_set(text[])`, restate `rail_order_mine()` from RAIL ORDER,
--   and remove the column.
-- ===========================================================================

alter table public.rail_orders add column if not exists tabs text[] not null default '{}';

create or replace function public.rail_order_mine()
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  me public.team_members;
  o public.rail_orders;
begin
  me := public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into o from public.rail_orders r where r.member_id = me.id;
  return jsonb_build_object('sections', coalesce(to_jsonb(o.sections), '[]'::jsonb),
    'tabs', coalesce(to_jsonb(o.tabs), '[]'::jsonb));
end $$;
grant execute on function public.rail_order_mine() to authenticated;

create or replace function public.rail_tabs_set(p_tabs text[])
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members;
  v_list text[] := coalesce(p_tabs, '{}');
  v_known constant text[] := array['work', 'clients', 'review', 'scripts', 'campaigns', 'reports', 'whatsapp',
    'register', 'suppliers', 'links', 'services', 'team'];
begin
  me := public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if cardinality(v_list) > 3
     or exists (select 1 from unnest(v_list) k where k is null or not (k = any(v_known)))
     or (select count(distinct k) from unnest(v_list) k) <> cardinality(v_list) then
    return jsonb_build_object('error', 'bad-tabs');
  end if;
  insert into public.rail_orders (member_id, tabs, updated_at) values (me.id, v_list, now())
  on conflict (member_id) do update set tabs = excluded.tabs, updated_at = now();
  return jsonb_build_object('tabs', to_jsonb(v_list));
end $$;
grant execute on function public.rail_tabs_set(text[]) to authenticated;

-- END OF TAB BAR CHOICE ------------------------------------------------------

select public.functions_tidy();
