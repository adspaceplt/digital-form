-- REPORT PUBLISHED, THE PERSON IN CHARGE TOLD --------------------------------
-- 2026-11-03, the user: "when reports are published could it be possible to
-- inform the client person in charge". A report moving to published (from
-- the head's Publish, Reports Select's Publish, or a revision published
-- again) tells the client's Person in charge, the active colleague whose
-- name the client's `owner` holds, in the bell and on their phone, opening
-- the report (`ops_notifications.report_id`), unless they published it
-- themselves (`sm_report_notify` skips the caller). The client is not told:
-- that stays a colleague's Mark as sent. A fault never fails the publish.
--
-- Rollback: drop trigger sm_reports_published_notice on public.sm_reports
-- (the SQL Editor's); the function may stay.

create or replace function public.sm_reports_published_notice()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  c public.clients;
  v_to uuid;
  v_by text;
begin
  if new.status is distinct from 'published' or old.status is not distinct from 'published' then return null; end if;
  select * into c from public.clients x where x.id = new.client_id;
  if c.id is null or btrim(coalesce(c.owner, '')) = '' then return null; end if;
  select t.id into v_to from public.team_members t
   where t.active and lower(btrim(t.name)) = lower(btrim(c.owner))
   limit 1;
  if v_to is null then return null; end if;
  v_by := (public.ops_me()).name;
  perform public.sm_report_notify(v_to, new.id, 'report.published', 'Report published',
    coalesce(nullif(btrim(new.brand_name), ''), c.name) || ' · ' || public.sm_period_word(new.period_start, new.period_end) ||
    case when v_by is not null then ' · Published by ' || v_by else '' end);
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.sm_reports_published_notice() from public, anon, authenticated;

create or replace trigger sm_reports_published_notice
  after update of status on public.sm_reports
  for each row execute function public.sm_reports_published_notice();

-- END OF REPORT PUBLISHED, THE PERSON IN CHARGE TOLD

select public.functions_tidy();
