-- ===========================================================================
-- ONE CHECK A MINUTE — an open page's minute check is one request: upgrade
-- mode, the announcements and the bell answered together.
-- 2026-10-09. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED
--   Supabase's usage page (the user, 2026-10-09: "why is it using so much")
--   showed log ingestion near its allowance: every request the portal makes
--   is a logged line of about 2.8 KB. An open console asked four times a
--   minute (upgrade mode, the announcements, the bell's unread and its
--   earlier notices) and a client page twice, about a seventh of all logged
--   requests. `page_pulse(p_audience, p_bell)` answers them in one:
--   `maintenance` as `maintenance_state()` answers it, `announcements` as
--   `announcement_now(p_audience)` does (where an audience is named), and,
--   with `p_bell` for a signed-in colleague, `bell`: their own unread
--   notices (thirty, newest first) and the read ones of the last seven days
--   (ten), never one withdrawn. Each part keeps its own function's rules;
--   nobody reads more than they read before. A page whose database holds no
--   `page_pulse` asks each part alone, as before. It joins `open_to_anon`
--   (FUNCTION HYGIENE): run 2026-10-07-function-hygiene.sql again BEFORE
--   this file, so the tidy at its foot keeps it open.
--
-- ROLLBACK
--   Pages fall back to the three reads by themselves:
--     drop function if exists public.page_pulse(text, boolean);
-- ===========================================================================

create or replace function public.page_pulse(p_audience text default null, p_bell boolean default false)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members;
  v  jsonb := jsonb_build_object('maintenance', public.maintenance_state());
begin
  if p_audience in ('team', 'clients') then
    v := v || jsonb_build_object('announcements', coalesce(public.announcement_now(p_audience), '[]'::jsonb));
  end if;
  if coalesce(p_bell, false) then
    me := public.ops_me();
    if me.id is not null then
      v := v || jsonb_build_object('bell', jsonb_build_object(
        'unread', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc)
                              from (select * from public.ops_notifications o
                                     where o.team_member_id = me.id and o.read_at is null and o.hidden_at is null
                                     order by o.created_at desc limit 30) x), '[]'::jsonb),
        'earlier', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc)
                               from (select * from public.ops_notifications o
                                      where o.team_member_id = me.id and o.read_at is not null and o.hidden_at is null
                                        and o.created_at >= now() - interval '7 days'
                                      order by o.created_at desc limit 10) x), '[]'::jsonb)));
    end if;
  end if;
  return v;
end $$;
revoke all on function public.page_pulse(text, boolean) from public;
grant execute on function public.page_pulse(text, boolean) to anon, authenticated;

-- END OF ONE CHECK A MINUTE --------------------------------------------------

select public.functions_tidy();
