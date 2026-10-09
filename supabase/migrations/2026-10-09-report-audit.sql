-- ===========================================================================
-- REPORT AUDIT — a report's figures are read against Meta's before it is
-- submitted and again before it is published, and nothing passes while one
-- differs.
-- 2026-10-09. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/smsql.js compares the
-- two.
--
-- WHAT CHANGED
--   The user, 2026-10-09: "there shouldnt be any mismatches". Check and
--   submit's figures check becomes the Report audit, in two parts: the
--   Commentary (the AI's reading of the words, as before) and Against Meta
--   (the page reads Meta through `meta-import` and compares every figure the
--   report takes from Meta, exactly, at the precision the report holds it;
--   no AI use). This file holds the readings and the gate.
--   1. `sm_report_audits` (RLS on, no policy, no grant): each reading: the
--      version, when, who, the outcome (`match`, `mismatch`, `unavailable`,
--      `override`), the print of the figures read, the rows that differed,
--      and a note (what Meta answered, or an admin's reason).
--   2. `sm_report_meta_print(p_id)`: one print of the figures the report
--      takes from Meta: an Advertising Report's Meta ads (their figures, age
--      split, retention and Ad IDs) and Step 1's reach, impressions and
--      amount spent; an Accounts Report's Facebook and Instagram posts (link
--      and figures). Any change to one of them changes the print.
--   3. `sm_report_audit_needed(p_id)`: whether the report's client (or its
--      white-label brand) links what the report is read from: an ad account
--      for an Advertising Report; a Page or an Instagram account the report
--      holds an account for, for an Accounts Report. Not linked, nothing is
--      required.
--   4. `sm_report_audit_save(p_id, p_outcome, p_rows, p_note)`: a reading
--      filed by the page (Reports at Work, the client in the colleague's
--      scope): an Advertising Report in draft, review or confirmed (Meta is
--      read again before Publish); an Accounts Report in draft (a post's
--      figures are lifetime totals that grow by the hour, so the reading at
--      submission is the one that stands). `override` is an admin's alone,
--      after a reading Meta did not answer, with a reason. A reading the same
--      as the last refreshes its time; a new outcome is filed
--      `report.audited` (Report audit).
--   5. `sm_report_audit_last(p_id)`: the last reading of the version, whether
--      the figures still print as they did, whether the gate holds, and when
--      the figures took their present print (Reports at View).
--   6. `sm_report_audit_blocks(p_id, p_after)`: `meta-audit` where a linked
--      report's last reading since p_after is not a match (or an admin's
--      override) of the figures as they stand. sm_report_submit asks it;
--      sm_report_publish asks it since confirmation for an Advertising
--      Report, and for an Accounts Report holds the reading it was submitted
--      on (a report submitted before this file holds none and is not held).
--   7. activity_section() files `report.audited` under Reports.
--
-- ROLLBACK
--   Run sm_report_submit as REPORT MONTH GATE defines it, sm_report_publish
--   as REPORTS defines it and activity_section as ACTIVITY FILES A RESTORE
--   AND A DELETE defines it; then remove the functions
--   sm_report_audit_last(uuid), sm_report_audit_save(uuid, text, jsonb,
--   text), sm_report_audit_blocks(uuid, timestamptz),
--   sm_report_audit_needed(uuid) and sm_report_meta_print(uuid), and the
--   table sm_report_audits.
-- ===========================================================================

create table if not exists public.sm_report_audits (
  id          uuid primary key default gen_random_uuid(),
  report_id   uuid not null references public.sm_reports(id) on delete cascade,
  version_no  integer not null,
  read_at     timestamptz not null default now(),
  by_id       uuid references public.team_members(id) on delete set null,
  by_name     text,
  outcome     text not null,
  print       text,
  diffs       jsonb not null default '[]'::jsonb,
  note        text,
  constraint sm_report_audits_outcome check (outcome in ('match', 'mismatch', 'unavailable', 'override'))
);
create index if not exists sm_report_audits_report_idx
  on public.sm_report_audits (report_id, version_no, read_at desc);
alter table public.sm_report_audits enable row level security;
revoke all on public.sm_report_audits from public, anon, authenticated;

/* The figures the report takes from Meta, as one print. A JSON array a row,
   so a value that moves from one field to the next never prints the same. */
create or replace function public.sm_report_meta_print(p_id uuid)
returns text
language sql stable security definer set search_path = public as $$
  select md5(case when r.kind = 'ads' then
      coalesce((select string_agg(jsonb_build_array(a.id, a.result_label, a.results, a.reach, a.impressions, a.spend,
                  a.ctr, a.cpr, a.hook_rate, a.hold_rate, a.avg_play, a.retention, a.age, a.ad_ids)::text, ';' order by a.id)
                  from public.sm_report_ads a
                 where a.report_id = r.id and coalesce(a.platform, 'meta') = 'meta'), '')
      || '#' || jsonb_build_object('reach', r.ads_totals -> 'reach', 'impressions', r.ads_totals -> 'impressions',
                                   'spend', r.ads_totals -> 'spend')::text
    else
      coalesce((select string_agg(jsonb_build_array(p.id, p.url, p.views, p.reach, p.impressions, p.interactions,
                  p.engagements, p.likes, p.comments, p.shares, p.saves)::text, ';' order by p.id)
                  from public.sm_report_posts p
                  join public.sm_report_platforms f on f.id = p.platform_id
                 where p.report_id = r.id and f.platform in ('facebook', 'instagram')), '')
    end)
  from public.sm_reports r where r.id = p_id
$$;
revoke all on function public.sm_report_meta_print(uuid) from public, anon, authenticated;

/* Whether the report's client (or brand) links what it is read from. */
create or replace function public.sm_report_audit_needed(p_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
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

/* `meta-audit` where a linked report has no passing reading of its figures
   as they stand, since p_after. */
create or replace function public.sm_report_audit_blocks(p_id uuid, p_after timestamptz default null)
returns text
language plpgsql stable security definer set search_path = public as $$
declare
  r public.sm_reports;
  a public.sm_report_audits;
begin
  select * into r from public.sm_reports where id = p_id;
  if r.id is null or not public.sm_report_audit_needed(p_id) then return null; end if;
  select * into a from public.sm_report_audits x
   where x.report_id = p_id and x.version_no = r.version_no
   order by x.read_at desc, x.id desc limit 1;
  if a.id is null or a.read_at < coalesce(p_after, '-infinity'::timestamptz) then return 'meta-audit'; end if;
  if a.outcome not in ('match', 'override') then return 'meta-audit'; end if;
  if a.print is distinct from public.sm_report_meta_print(p_id) then return 'meta-audit'; end if;
  return null;
end $$;
revoke all on function public.sm_report_audit_blocks(uuid, timestamptz) from public, anon, authenticated;

/* A reading filed. The comparison is the page's (it runs the report's own
   importer over Meta's answer); the print is taken here, so a figure changed
   after the reading is a reading no longer. */
create or replace function public.sm_report_audit_save(p_id uuid, p_outcome text, p_rows jsonb default '[]'::jsonb,
                                                       p_note text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  c public.clients;
  prev public.sm_report_audits;
  v_rows jsonb := coalesce(p_rows, '[]'::jsonb);
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_print text;
  v_id uuid;
  v_at timestamptz;
  v_word text;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_outcome, '') not in ('match', 'mismatch', 'unavailable', 'override') then
    return jsonb_build_object('error', 'bad-outcome');
  end if;
  if jsonb_typeof(v_rows) is distinct from 'array' or jsonb_array_length(v_rows) > 500 or length(v_rows::text) > 200000 then
    return jsonb_build_object('error', 'bad-rows');
  end if;
  if p_outcome = 'match' then v_rows := '[]'::jsonb; end if;
  if p_outcome = 'mismatch' and jsonb_array_length(v_rows) = 0 then return jsonb_build_object('error', 'bad-rows'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.clients where id = r.client_id;
  if not public.client_row_seen(c.stage, c.owner, 'view') then return jsonb_build_object('error', 'denied'); end if;
  if not (r.status = 'draft' or (r.kind = 'ads' and r.status in ('review', 'confirmed'))) then
    return jsonb_build_object('error', 'not-open', 'status', r.status);
  end if;
  if not public.sm_report_audit_needed(p_id) then return jsonb_build_object('error', 'not-linked'); end if;
  select * into prev from public.sm_report_audits x
   where x.report_id = p_id and x.version_no = r.version_no
   order by x.read_at desc, x.id desc limit 1;
  if p_outcome = 'override' then
    if not (coalesce(me.is_admin, false) or me.role = 'admin') then return jsonb_build_object('error', 'denied'); end if;
    if prev.id is null or prev.outcome <> 'unavailable' then return jsonb_build_object('error', 'not-unavailable'); end if;
    if v_note is null then return jsonb_build_object('error', 'reason-required'); end if;
    v_rows := '[]'::jsonb;
  end if;
  if p_outcome = 'match' then v_note := null; end if;
  v_note := left(v_note, 500);
  v_print := public.sm_report_meta_print(p_id);
  if prev.id is not null and p_outcome <> 'override' and prev.outcome = p_outcome
     and prev.print is not distinct from v_print and prev.diffs = v_rows and prev.note is not distinct from v_note then
    update public.sm_report_audits set read_at = now(), by_id = me.id, by_name = me.name where id = prev.id
    returning id, read_at into v_id, v_at;
    return jsonb_build_object('ok', true, 'id', v_id, 'at', v_at, 'outcome', p_outcome, 'again', true);
  end if;
  insert into public.sm_report_audits (report_id, version_no, by_id, by_name, outcome, print, diffs, note)
  values (p_id, r.version_no, me.id, me.name, p_outcome, v_print, v_rows, v_note)
  returning id, read_at into v_id, v_at;
  if prev.id is null or prev.outcome <> p_outcome or p_outcome = 'override' then
    v_word := case p_outcome
      when 'match' then 'Against Meta: matches'
      when 'mismatch' then 'Against Meta: ' || jsonb_array_length(v_rows) || ' to fix'
      when 'unavailable' then 'Against Meta: not checked, Meta unavailable'
      else 'Against Meta: not checked, Meta unavailable · Reason: ' || v_note end;
    perform public.sm_report_log(p_id, 'report.audited', 'Report audit · ' || v_word);
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'at', v_at, 'outcome', p_outcome);
end $$;
revoke all on function public.sm_report_audit_save(uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.sm_report_audit_save(uuid, text, jsonb, text) to authenticated;

/* The last reading of the version, as the audit card reads it. */
create or replace function public.sm_report_audit_last(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  c public.clients;
  a public.sm_report_audits;
  v_print text;
begin
  if me.id is null or not public.allowed('reports', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into c from public.clients where id = r.client_id;
  if not public.client_row_seen(c.stage, c.owner, 'view') then return jsonb_build_object('error', 'denied'); end if;
  v_print := public.sm_report_meta_print(p_id);
  select * into a from public.sm_report_audits x
   where x.report_id = p_id and x.version_no = r.version_no
   order by x.read_at desc, x.id desc limit 1;
  return jsonb_build_object(
    'needed', public.sm_report_audit_needed(p_id),
    'may_override', coalesce(me.is_admin, false) or me.role = 'admin',
    'blocks', public.sm_report_audit_blocks(p_id, null),
    'held', exists (select 1 from public.sm_report_audits x where x.report_id = p_id and x.version_no = r.version_no),
    'print_since', (select min(x.read_at) from public.sm_report_audits x
                     where x.report_id = p_id and x.version_no = r.version_no and x.print = v_print),
    'print_moved', exists (select 1 from public.sm_report_audits x
                            where x.report_id = p_id and x.version_no = r.version_no and x.print is distinct from v_print),
    'last', case when a.id is null then null else jsonb_build_object(
      'at', a.read_at, 'by', a.by_name, 'outcome', a.outcome, 'rows', a.diffs, 'note', a.note,
      'current', a.print is not distinct from v_print) end);
end $$;
revoke all on function public.sm_report_audit_last(uuid) from public, anon, authenticated;
grant execute on function public.sm_report_audit_last(uuid) to authenticated;

/* `p_reason` is the reason a late submit, or one past the month's gate,
   gives; it is read from MONTH REPORTS (2026-10-04) on. The Report audit
   (2026-10-09) holds a linked report until Meta's figures match. */
create or replace function public.sm_report_submit(p_id uuid, p_reviewer uuid default null, p_reason text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  cname text;
  g jsonb;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_gate text;
  v_late text;
  v_extra text := '';
  v_audit text;
begin
  if me.id is null or not public.allowed('reports', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status <> 'draft' then return jsonb_build_object('error', 'not-draft', 'status', r.status); end if;
  if r.kind = 'ads' then
    if not exists (select 1 from public.sm_report_ads where report_id = p_id) then
      return jsonb_build_object('error', 'no-ads');
    end if;
  else
    if not exists (select 1 from public.sm_report_platforms where report_id = p_id) then
      return jsonb_build_object('error', 'no-platforms');
    end if;
    if not exists (select 1 from public.sm_report_posts where report_id = p_id) then
      return jsonb_build_object('error', 'no-posts');
    end if;
  end if;
  v_audit := public.sm_report_audit_blocks(p_id, null);
  if v_audit is not null then return jsonb_build_object('error', v_audit); end if;
  g := public.sm_report_gate(p_id);
  if coalesce((g ->> 'applies')::boolean, false) then
    if not (g ->> 'ok')::boolean then
      if not (g ->> 'may_override')::boolean or v_reason is null then
        return jsonb_build_object('error', 'month-gate', 'missing', g -> 'missing', 'planned', g -> 'planned',
                                  'made', g -> 'made', 'may_override', g -> 'may_override');
      end if;
      v_gate := left(v_reason, 500);
    end if;
    if (g ->> 'late')::boolean then
      if v_reason is null then
        return jsonb_build_object('error', 'late-reason', 'due', g -> 'due');
      end if;
      v_late := left(v_reason, 500);
    end if;
  end if;
  if p_reviewer is null then return jsonb_build_object('error', 'no-reviewer'); end if;
  if p_reviewer = me.id then return jsonb_build_object('error', 'self-review'); end if;
  if not public.sm_report_may_review(p_reviewer) then return jsonb_build_object('error', 'bad-reviewer'); end if;
  perform set_config('adspace.sm_fn', 'on', true);
  update public.sm_reports set status = 'review', submitted_by = me.id, submitted_at = now(),
    reviewer_id = p_reviewer, return_note = null, confirmed_by = null, confirmed_at = null,
    late_reason = v_late, gate_note = v_gate where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  if v_gate is not null then v_extra := v_extra || ' · Past the month''s gate: ' || v_gate; end if;
  if v_late is not null and v_gate is distinct from v_late then v_extra := v_extra || ' · Late: ' || v_late;
  elsif v_late is not null then v_extra := v_extra || ' · Late'; end if;
  perform public.sm_report_log(p_id, 'report.submitted',
    'Reviewer: ' || (select name from public.team_members where id = p_reviewer) || v_extra);
  select c.name into cname from public.clients c where c.id = r.client_id;
  perform public.sm_report_notify(p_reviewer, p_id, 'report.review', 'Report to review',
    cname || ' · ' || public.sm_period_word(r.period_start, r.period_end));
  return jsonb_build_object('ok', true, 'status', 'review');
end $$;
revoke all on function public.sm_report_submit(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.sm_report_submit(uuid, uuid, text) to authenticated;

/* Publish: the confirmed report is frozen as its version and the client
   can read it. The same press twice publishes once. An Advertising Report
   is read against Meta again since it was confirmed; an Accounts Report
   holds the reading it was submitted on (2026-10-09). */
create or replace function public.sm_report_publish(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.sm_reports;
  snap jsonb;
  vid uuid;
  v_audit text;
begin
  if me.id is null or not public.allowed('reports', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into r from public.sm_reports where id = p_id for update;
  if r.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if r.status = 'published' then
    select id into vid from public.sm_report_versions where report_id = p_id and version_no = r.version_no;
    return jsonb_build_object('ok', true, 'status', 'published', 'version_id', vid, 'again', true);
  end if;
  if r.status <> 'confirmed' then return jsonb_build_object('error', 'not-confirmed', 'status', r.status); end if;
  if r.kind = 'ads' then
    v_audit := public.sm_report_audit_blocks(p_id, r.confirmed_at);
  elsif exists (select 1 from public.sm_report_audits x where x.report_id = p_id and x.version_no = r.version_no) then
    v_audit := public.sm_report_audit_blocks(p_id, null);
  end if;
  if v_audit is not null then return jsonb_build_object('error', v_audit); end if;
  snap := public.sm_report_snapshot(p_id, true);
  perform set_config('adspace.sm_fn', 'on', true);
  insert into public.sm_report_versions (report_id, version_no, snapshot, published_by)
  values (p_id, r.version_no, snap, me.name)
  on conflict (report_id, version_no) do update
    set snapshot = excluded.snapshot, published_by = excluded.published_by, published_at = now(),
        withdrawn_at = null, withdrawn_by = null, withdraw_reason = null
  returning id into vid;
  update public.sm_reports set status = 'published' where id = p_id;
  perform set_config('adspace.sm_fn', 'off', true);
  perform public.sm_report_log(p_id, 'report.published');
  return jsonb_build_object('ok', true, 'status', 'published', 'version_id', vid);
end $$;
revoke all on function public.sm_report_publish(uuid) from public, anon, authenticated;
grant execute on function public.sm_report_publish(uuid) to authenticated;

create or replace function public.activity_section(p_action text)
returns text
language sql immutable parallel safe as $$
  select case
    when action in ('campaign.bulk', 'campaign.closed', 'campaign.confirmed',
                    'campaign.created', 'campaign.dates', 'campaign.deleted', 'campaign.edited',
                    'campaign.file_added', 'campaign.qc',
                    'campaign.invoice', 'campaign.invoice_file',
                    'campaign.invoice_removed', 'campaign.keyed', 'campaign.locked',
                    'campaign.opened', 'campaign.rate', 'campaign.rated',
                    'campaign.reinstated', 'campaign.replaced', 'campaign.results', 'campaign.review',
                    'campaign.stage', 'campaign.submitted', 'campaign.task_linked',
                    'campaign.task_unlinked', 'campaign.unbooked',
                    'campaign.unkeyed', 'campaign.withdrawn', 'creator.added',
                    'creator.code', 'creator.links', 'creator.links_restored',
                    'creator.links_self', 'creator.off', 'creator.on', 'creator.removed',
                    'creator.updated') then 'campaigns'
    when action in ('client.action_done', 'client.action_reopened', 'client.added',
                    'client.billing', 'client.brand', 'client.deleted', 'client.edited',
                    'client.review_on', 'client.service', 'client.service_changed',
                    'client.service_removed', 'client.service_restored', 'client.stage', 'client.touch',
                    'client.touch_deleted', 'client.touch_edited', 'client.touch_removed',
                    'client.touch_restored', 'contact.added', 'contact.deleted',
                    'contact.edited', 'contact.portal_invite', 'contact.portal_off',
                    'contact.portal_on', 'contact.primary', 'contact.removed',
                    'contact.restored',
                    'request.changed', 'request.raised',
                    'request.reinstated', 'request.replied', 'request.withdrawn',
                    'service.override') then 'clients'
    when action in ('report.ai_drafted', 'report.ai_failed', 'report.audited', 'report.confirmed',
                    'report.created', 'report.deleted', 'report.published',
                    'report.reassigned', 'report.returned', 'report.revised', 'report.saved',
                    'report.submitted', 'report.unpublished') then 'reports'
    when action in ('qr.created', 'qr.restored', 'qr.revoked', 'shortlink.created',
                    'shortlink.deleted', 'shortlink.imported', 'shortlink.updated') then 'links'
    when action in ('ops.deleted', 'ops.month_deleted', 'ops.numbering') then 'ops'
    when action in ('document.deleted', 'document.issued', 'document.reissued',
                    'document.restored', 'document.signed', 'document.superseded',
                    'document.unsigned', 'document.verified', 'document.voided',
                    'register.added', 'register.edited') then 'register'
    when action in ('client.drive', 'client.handles', 'client.profile',
                    'client.removed', 'drive.imported', 'link.reset', 'post.added',
                    'post.deleted', 'post.edited', 'reapproval.requested',
                    'review.approved', 'review.changes', 'review.removed',
                    'review.unconfirmed',
                    'set.created', 'set.deleted', 'set.published', 'set.renamed',
                    'set.task_linked', 'set.task_unlinked',
                    'set.withdrawn') then 'review'
    when action in ('handbook.added', 'handbook.archived', 'handbook.deleted',
                    'handbook.edited', 'handbook.restored', 'handbook.version') then 'handbook'
    when action in ('service.added', 'service.changed', 'service.deleted',
                    'service.off', 'service.on') then 'services'
    when action in ('team.added', 'team.changed', 'team.edited', 'team.group_added',
                    'team.group_changed', 'team.group_removed', 'team.invited') then 'team'
    else 'other'
  end
  from (select p_action as action) t
$$;
grant execute on function public.activity_section(text) to authenticated;

-- END OF REPORT AUDIT --------------------------------------------------------

select public.functions_tidy();
