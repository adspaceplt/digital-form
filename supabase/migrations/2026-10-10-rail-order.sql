-- ===========================================================================
-- RAIL ORDER — a colleague arranges the console's sections once, and the web
-- rail and the phone tab bar both follow (2026-10-10, the user: "Add in the
-- phone tab bar rearrange"; "mobile tab and web … both sync edits").
-- 2026-10-10. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED
--   1. `rail_orders` keeps one row a colleague: the section keys in the order
--      they chose, an empty list meaning the standard order. RLS on, no
--      policy, no grant: it is read and written only through the two
--      functions below, each the caller's own row.
--   2. `rail_order_mine()` answers the caller's list (empty where none is
--      kept).
--   3. `rail_order_set(p_sections)` keeps it: every key one of the rail's
--      sections (the Overview stays first and is not ordered), none twice
--      (`bad-order`); an empty list goes back to the standard order. A
--      personal choice, so nothing is filed in the Activity record.
--   The page orders each of the rail's two groups (Work, Internal) by the
--   list, a section it does not name after in the standard order, and the
--   phone tab bar takes the first sections of the rail as it then reads.
--
-- ROLLBACK
--   Pages first (the rail returns to the standard order), then remove the
--   two functions and the table.
-- ===========================================================================

create table if not exists public.rail_orders (
  member_id  uuid primary key references public.team_members(id),
  sections   text[] not null default '{}',
  updated_at timestamptz not null default now()
);
alter table public.rail_orders enable row level security;
revoke all on public.rail_orders from public, anon, authenticated;

create or replace function public.rail_order_mine()
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  me public.team_members;
begin
  me := public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('sections', coalesce((select to_jsonb(o.sections) from public.rail_orders o where o.member_id = me.id), '[]'::jsonb));
end $$;
grant execute on function public.rail_order_mine() to authenticated;

create or replace function public.rail_order_set(p_sections text[])
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members;
  v_list text[] := coalesce(p_sections, '{}');
  v_known constant text[] := array['work', 'clients', 'review', 'scripts', 'campaigns', 'reports', 'whatsapp',
    'register', 'links', 'services', 'team', 'handbook'];
begin
  me := public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if exists (select 1 from unnest(v_list) k where k is null or not (k = any(v_known)))
     or (select count(distinct k) from unnest(v_list) k) <> cardinality(v_list) then
    return jsonb_build_object('error', 'bad-order');
  end if;
  insert into public.rail_orders (member_id, sections, updated_at) values (me.id, v_list, now())
  on conflict (member_id) do update set sections = excluded.sections, updated_at = now();
  return jsonb_build_object('sections', to_jsonb(v_list));
end $$;
grant execute on function public.rail_order_set(text[]) to authenticated;

-- END OF RAIL ORDER ------------------------------------------------------------

select public.functions_tidy();
