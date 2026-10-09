-- ===========================================================================
-- META CHECKS SWITCH — Import from Meta and the report audit against Meta
-- are on only while Business settings says so and for those holding the
-- part; off, no report waits on Meta and figures are typed as before.
-- 2026-10-10. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two. Runs after REPORT AUDIT and CAPTION WRITER AND AI COST.
--
-- WHAT CHANGED (the user, 2026-10-10: Import from Meta "found it to have
-- quite a number of bugs and the numbers not really tally with actual Meta
-- records … hidden from all team members at this moment, without
-- compromising the usage of manual input"; "agility and not hardcoded")
--   1. `meta_checks` is a Business setting (0 Off, 1 On, from a day), seeded
--      Off. `app_settings_set` takes it, filed "Meta checks: Off → On".
--   2. `reports.meta` (Reports: Meta import and audit) is a granted part, an
--      admin's by itself, read with `ops_granted`.
--   3. `meta_checks_on()` answers both for the caller; `sm_report_audit_needed`
--      asks it first, so with Meta checks off (or without the part) Submit
--      and Publish never wait on Meta and a reading is not filed.
--
-- ROLLBACK
--   Run sm_report_audit_needed from REPORT AUDIT and app_settings_set from
--   CAPTION WRITER AND AI COST again; the setting's row may stay.
-- ===========================================================================

insert into public.app_settings (key, from_date, value)
select 'meta_checks', date '2023-08-14', 0
 where not exists (select 1 from public.app_settings s where s.key = 'meta_checks');

/* Whether Meta is read for the caller: the switch on today (MYT) and the
   part held. */
create or replace function public.meta_checks_on()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.app_setting('meta_checks', (now() at time zone 'Asia/Kuala_Lumpur')::date), 0) = 1
     and public.ops_granted('reports.meta', 'work')
$$;
grant execute on function public.meta_checks_on() to authenticated;

/* Whether the report's client (or brand) links what it is read from, and
   Meta is read at all. */
create or replace function public.sm_report_audit_needed(p_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select public.meta_checks_on() and coalesce((
    select case when r.kind = 'ads' then jsonb_array_length(coalesce(l.ad_accounts, '[]'::jsonb)) > 0
                else (jsonb_typeof(l.page) = 'object' and exists (
                        select 1 from public.sm_report_platforms f where f.report_id = r.id and f.platform = 'facebook'))
                  or (jsonb_typeof(l.instagram) = 'object' and exists (
                        select 1 from public.sm_report_platforms f where f.report_id = r.id and f.platform = 'instagram'))
           end
      from public.sm_reports r
      join public.meta_links l on l.client_id = r.client_id and l.brand_id is not distinct from r.brand_id
     where r.id = p_id), false)
$$;
revoke all on function public.sm_report_audit_needed(uuid) from public, anon, authenticated;

create or replace function public.app_settings_set(p_from date, p_values jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_me public.team_members; v_k text; v_v numeric; v_was numeric; v_name text; v_unit text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_keys constant text[] := array['lead_followup_hours', 'proposal_followup_days', 'sst_pct',
    'term_1_3', 'term_4_5', 'term_6_11', 'term_12_23', 'term_24', 'report_due_days', 'revision_due_days',
    'ai_price_in', 'ai_price_out', 'meta_checks'];
  v_moved text[] := '{}';
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  if p_from is null or p_from < v_today then return jsonb_build_object('error', 'past', 'today', v_today); end if;
  if jsonb_typeof(p_values) is distinct from 'object' then return jsonb_build_object('error', 'bad-value'); end if;
  for v_k in select jsonb_object_keys(p_values) loop
    if not (v_k = any(v_keys)) or jsonb_typeof(p_values -> v_k) <> 'number' then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
    v_v := (p_values ->> v_k)::numeric;
    if round(v_v, 2) <> v_v
       or (v_k = 'lead_followup_hours' and (v_v < 1 or v_v > 720 or v_v <> trunc(v_v)))
       or (v_k = 'proposal_followup_days' and (v_v < 1 or v_v > 365 or v_v <> trunc(v_v)))
       or (v_k = 'report_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'revision_due_days' and (v_v < 1 or v_v > 60 or v_v <> trunc(v_v)))
       or (v_k = 'sst_pct' and (v_v < 0 or v_v > 100))
       or (v_k like 'term_%' and (v_v < -100 or v_v > 100))
       or (v_k like 'ai_price_%' and (v_v < 0 or v_v > 1000))
       or (v_k = 'meta_checks' and v_v not in (0, 1)) then
      return jsonb_build_object('error', 'bad-value', 'key', v_k);
    end if;
  end loop;
  for v_k in select jsonb_object_keys(p_values) loop
    v_v := (p_values ->> v_k)::numeric;
    v_was := public.app_setting(v_k, p_from);
    if v_was is distinct from v_v then
      insert into public.app_settings (key, from_date, value, set_by, set_at)
      values (v_k, p_from, v_v, v_me.id, now())
      on conflict (key, from_date) do update set value = excluded.value, set_by = excluded.set_by, set_at = now();
      v_name := case v_k when 'lead_followup_hours' then 'A lead waits' when 'proposal_followup_days' then 'A proposal waits'
        when 'sst_pct' then 'SST' when 'term_1_3' then '1 to 3 months' when 'term_4_5' then '4 and 5 months'
        when 'term_6_11' then '6 to 11 months' when 'term_12_23' then '12 to 23 months' when 'term_24' then '24 months and more'
        when 'revision_due_days' then 'Revision due' when 'ai_price_in' then 'AI input, a million tokens'
        when 'ai_price_out' then 'AI output, a million tokens' when 'meta_checks' then 'Meta checks' else 'Report due' end;
      v_unit := case when v_k = 'lead_followup_hours' then ' hours' when v_k in ('proposal_followup_days', 'report_due_days', 'revision_due_days') then ' days'
        else '%' end;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_me.name, 'admin'), 'team.changed', 'Settings',
              v_name || ': ' || case when v_k = 'meta_checks' then
                case when v_was = 1 then 'On' else 'Off' end || ' → ' || case when v_v = 1 then 'On' else 'Off' end ||
                ' · from ' || public.register_day(p_from) else '' end ||
              case when v_k = 'meta_checks' then '' else case when v_k like 'ai_price_%' then 'US$' else '' end ||
              trim(to_char(v_was, 'FM999999990.99'), '.') || case when v_k like 'ai_price_%' then '' else v_unit end || ' → ' ||
              case when v_k like 'ai_price_%' then 'US$' else '' end ||
              trim(to_char(v_v, 'FM999999990.99'), '.') || case when v_k like 'ai_price_%' then '' else v_unit end ||
              ' · from ' || public.register_day(p_from) end);
      v_moved := v_moved || v_k;
    end if;
  end loop;
  return public.app_settings_read() || jsonb_build_object('changed', to_jsonb(v_moved));
end $$;
revoke all on function public.app_settings_set(date, jsonb) from public, anon;

-- END OF META CHECKS SWITCH ---------------------------------------------------

select public.functions_tidy();
