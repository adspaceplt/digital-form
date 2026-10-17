-- ===========================================================================
-- MALAYSIA TIME IN THE DATABASE — every "today" the database works out is
-- Malaysia's day, as every page's is. 2026-10-17. Safe to run twice.
-- Rollback at the foot. Mirrored byte for byte in supabase/schema.sql under
-- the same banner; tests/sql.js compares the two and holds that no function
-- asks the server's day again.
--
-- WHAT CHANGED (the security audit of 2026-10-16, finding A; the user: "all
-- must in MYT")
--   The database's TimeZone is UTC, so `current_date` and `now()::date` are
--   the UTC day: yesterday until 8:00am in Malaysia. Until then on the 1st,
--   the new month and quarter were refused or read as the one before
--   (`perf_today`, which every Performance rule asks: a quarter confirmed, a
--   month opened for a self-rating, a commission's month), an issue logged
--   today was "in the future", and My Work's late list counted a day late.
--   1. Each function whose last definition read the server's day takes
--      Malaysia's, `(now() at time zone 'Asia/Kuala_Lumpur')::date`, as
--      `health_today()` and the rest of the schema already do: `perf_today`,
--      `app_setting` (a setting with no day given), `register_add` (an entry
--      with no date), `creator_post_save` (a post's day and when it was
--      measured), `perf_overview`, `perf_breach_log`,
--      `ops_engagement_set_meeting`, `ops_report` (its late list reads a
--      final date's Malaysian day too), `ops_create_task` (a task with no
--      month takes this month) and `portal_meetings` (three months back from
--      this month's start). Nothing else in them changes.
--   2. The date a call or visit, a Letter of Offer and a register entry
--      take when none is given (`client_touches.happened_at`,
--      `client_documents.issued_at`, `documents.issued_at`) is Malaysia's day.
--   The database's own TimeZone stays UTC: PostgREST writes every timestamp
--   in it (`…+00:00`), which the pages read and compare, and a date turned
--   into a timestamp (`p_day::timestamptz`) is read in it; changing it would
--   move both. pg_cron keeps its own zone.
--
-- ROLLBACK
--   Run each function again from its section as it stood before 2026-10-17
--   (the same body with `current_date`), and set the three defaults back to
--   `current_date`. Nothing is stored differently.
-- ===========================================================================

alter table public.client_touches   alter column happened_at set default ((now() at time zone 'Asia/Kuala_Lumpur')::date);
alter table public.client_documents alter column issued_at   set default ((now() at time zone 'Asia/Kuala_Lumpur')::date);
alter table public.documents        alter column issued_at   set default ((now() at time zone 'Asia/Kuala_Lumpur')::date);

create or replace function public.perf_today()
returns date language sql stable as $$
  select (now() at time zone 'Asia/Kuala_Lumpur')::date
$$;

create or replace function public.app_setting(p_key text, p_at date)
returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select s.value from public.app_settings s where s.key = p_key and s.from_date <= coalesce(p_at, (now() at time zone 'Asia/Kuala_Lumpur')::date)
      order by s.from_date desc limit 1),
    (select s.value from public.app_settings s where s.key = p_key order by s.from_date limit 1))
$$;
revoke all on function public.app_setting(text, date) from public, anon, authenticated;

create or replace function public.register_add(
  p_serial    text,
  p_family    text,
  p_kind      text,
  p_issued_at date,
  p_recipient text,
  p_client    uuid,
  p_note      text,
  p_file_url  text,
  p_member    uuid default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who   text := lower(auth.jwt() ->> 'email');
  me    public.team_members%rowtype;
  v_serial text := nullif(btrim(coalesce(p_serial, '')), '');
  v_fam text := coalesce(nullif(btrim(p_family), ''), 'other');
  v_id  uuid;
  cl    public.clients%rowtype;
  tm    public.team_members%rowtype;
begin
  if v_fam not in ('quote_cover', 'client', 'hr', 'other') then return jsonb_build_object('error', 'bad-family'); end if;
  if not public.register_may(v_fam, 'work') then return jsonb_build_object('error', 'not-allowed'); end if;
  if v_serial is null then return jsonb_build_object('error', 'serial-required'); end if;
  if v_serial !~ '^[A-Za-z0-9/._-]{3,40}$' then return jsonb_build_object('error', 'serial-shape'); end if;
  if public.serial_taken(v_serial) then return jsonb_build_object('error', 'serial-taken'); end if;
  if coalesce(btrim(p_kind), '') = '' then return jsonb_build_object('error', 'kind-required'); end if;
  if v_fam = 'hr' then
    if p_member is not null then select * into tm from public.team_members where id = p_member; end if;
  elsif p_client is not null then
    select * into cl from public.clients where id = p_client;
  end if;
  select * into me from public.team_members where lower(email) = who and active limit 1;

  insert into public.documents
    (family, kind, serial, client_id, member_id, issued_at, recipient, signed, source, file_url, note, issued_by)
  values
    (v_fam, btrim(p_kind), v_serial, cl.id, tm.id, coalesce(p_issued_at, (now() at time zone 'Asia/Kuala_Lumpur')::date),
     jsonb_build_object('name', coalesce(btrim(p_recipient), '')), false, 'manual',
     nullif(btrim(p_file_url), ''), nullif(btrim(p_note), ''), coalesce(me.name, who))
  returning id into v_id;

  insert into public.activity_log (actor, action, subject, detail)
  values (who, 'register.added',
          case when v_fam = 'hr' then 'HR' else coalesce(cl.name, btrim(p_recipient), '') end,
          case when v_fam = 'hr' then btrim(p_kind) else v_serial || ' · ' || btrim(p_kind) end);
  return jsonb_build_object('ok', true, 'id', v_id, 'serial', v_serial);
exception
  when unique_violation then return jsonb_build_object('error', 'serial-taken');
end $$;
grant execute on function public.register_add(text, text, text, date, text, uuid, text, text, uuid) to authenticated;

create or replace function public.creator_post_save(
  p_code text, p_option uuid, p_platform text, p_url text, p_published date,
  p_impressions bigint, p_engagements bigint, p_views bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cr     creators%rowtype;
  o      campaign_options%rowtype;
  p      option_posts%rowtype;
  v_plat text;
  v_url  text := nullif(btrim(coalesce(p_url, '')), '');
  v_nums boolean := p_impressions is not null or p_engagements is not null or p_views is not null;
  v_live boolean := false;
begin
  select * into cr from creators where access_code = upper(p_code) and active;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  select * into o from campaign_options where id = p_option and creator_id = cr.id for update;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if o.state not in ('scheduled', 'posted') then return jsonb_build_object('error', 'closed'); end if;

  -- One of the placements this booking is for, by its printed name.
  select btrim(x) into v_plat
    from unnest(string_to_array(coalesce(o.platforms, ''), ',')) x
   where public.post_platform_key(x) = public.post_platform_key(p_platform)
   limit 1;
  if v_plat is null then return jsonb_build_object('error', 'platform'); end if;
  if v_url is not null and not public.post_link_ok(v_plat, v_url) then
    return jsonb_build_object('error', 'link');
  end if;
  if coalesce(p_impressions, 0) < 0 or coalesce(p_engagements, 0) < 0 or coalesce(p_views, 0) < 0 then
    return jsonb_build_object('error', 'number');
  end if;
  if p_published is not null and (p_published > (now() at time zone 'Asia/Kuala_Lumpur')::date + 1 or p_published < date '2023-08-14') then
    return jsonb_build_object('error', 'date');
  end if;

  select * into p from option_posts
   where option_id = p_option and public.post_platform_key(platform) = public.post_platform_key(v_plat)
   limit 1;
  if p.id is null then
    insert into option_posts (option_id, platform, window_days)
    values (p_option, v_plat, 7) returning * into p;
  end if;
  -- The numbers are counted over the period the team set, and wait for it.
  if v_nums and (p.measure_from is null or p.measure_to is null) then
    return jsonb_build_object('error', 'period');
  end if;

  update option_posts
     set post_url = coalesce(v_url, post_url),
         published_at = coalesce(p_published, published_at, case when v_url is not null then (now() at time zone 'Asia/Kuala_Lumpur')::date end),
         impressions = case when v_nums then p_impressions else impressions end,
         engagements = case when v_nums then p_engagements else engagements end,
         views = case when v_nums then p_views else views end,
         measured_at = case when v_nums then (now() at time zone 'Asia/Kuala_Lumpur')::date else measured_at end,
         entered_by = 'creator', entered_at = now()
   where id = p.id;

  -- The post is out: the booking says so, on the creator's word.
  if o.state = 'scheduled' and v_url is not null then
    update campaign_options set state = 'posted' where id = p_option;
    v_live := true;
  end if;

  insert into public.activity_log (actor, action, subject, detail)
  select cr.name, 'campaign.results', c.title,
         cr.name || ' · ' || v_plat ||
         case when v_url is not null and v_url is distinct from p.post_url then ' · link' else '' end ||
         case when v_nums then ' · ' || coalesce(p_views::text, '—') || ' views, ' ||
              coalesce(p_engagements::text, '—') || ' engagements, ' ||
              coalesce(p_impressions::text, '—') || ' impressions' else '' end ||
         case when v_live then ' · Posted' else '' end
    from campaigns c where c.id = o.campaign_id;

  return jsonb_build_object('ok', true, 'posted', v_live);
end $$;
revoke all on function public.creator_post_save(text, uuid, text, text, date, bigint, bigint, bigint) from public;
grant execute on function public.creator_post_save(text, uuid, text, text, date, bigint, bigint, bigint) to anon, authenticated;

create or replace function public.perf_overview(p_period date)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare me_row public.team_members; m date;
begin
  me_row := public.ops_me();
  if me_row.id is null or not public.ops_granted('team.performance', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  m := date_trunc('month', coalesce(p_period, (now() at time zone 'Asia/Kuala_Lumpur')::date))::date;
  return jsonb_build_object('period', m, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('team_member_id', t.id, 'name', t.name,
             'status', coalesce(r.status, 'none')) order by t.name)
      from public.team_members t
      left join public.perf_reviews r on r.team_member_id = t.id and r.period = m
     where t.id is distinct from me_row.id
       and ((t.active and public.perf_reviewed(t.id)) or r.id is not null)), '[]'::jsonb));
end $$;
revoke all on function public.perf_overview(date) from public, anon, authenticated;
grant execute on function public.perf_overview(date) to authenticated;

create or replace function public.perf_breach_log(p_token text, p_member uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  err text; m public.team_members; on_ date; p date; cat text; sev integer; rep boolean;
  st text; nb public.perf_breaches; cl uuid;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_member = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if not exists (select 1 from public.team_members where id = p_member and active) then
    return jsonb_build_object('error', 'not-found');
  end if;
  begin on_ := (p_payload ->> 'occurred_on')::date; exception when others then on_ := null; end;
  if on_ is null or on_ > (now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'bad-date'); end if;
  cat := p_payload ->> 'category';
  if cat is null or cat not in ('client', 'delivery', 'compliance', 'asset') then
    return jsonb_build_object('error', 'bad-category');
  end if;
  sev := case when (p_payload ->> 'severity') ~ '^[1-4]$' then (p_payload ->> 'severity')::integer end;
  if sev is null then return jsonb_build_object('error', 'bad-severity'); end if;
  if coalesce(btrim(p_payload ->> 'what'), '') = '' then return jsonb_build_object('error', 'what-needed'); end if;
  /* The client it concerns, optional (2026-10-15): a VIC client's issue
     counts double, stamped at logging. */
  if nullif(p_payload ->> 'client_id', '') is not null then
    begin cl := (p_payload ->> 'client_id')::uuid; exception when others then cl := null; end;
    if cl is null or not exists (select 1 from public.clients c where c.id = cl) then
      return jsonb_build_object('error', 'bad-client');
    end if;
  end if;
  p := date_trunc('month', on_)::date;
  select status into st from public.perf_reviews where team_member_id = p_member and period = p;
  if st is not null and st <> 'draft' then
    return jsonb_build_object('error', 'month-released', 'month', public.perf_month_word(p));
  end if;
  /* The same kind of breach earlier in the same quarter is a repeat, unless
     the reviewer says otherwise. */
  rep := case when p_payload ? 'repeated' and jsonb_typeof(p_payload -> 'repeated') = 'boolean'
              then (p_payload ->> 'repeated')::boolean
              else exists (select 1 from public.perf_breaches b
                            where b.team_member_id = p_member and b.category = cat
                              and b.voided_at is null
                              and date_trunc('quarter', b.occurred_on) = date_trunc('quarter', on_)
                              and b.occurred_on <= on_) end;
  insert into public.perf_breaches (team_member_id, occurred_on, period, category, severity,
                                    repeated, late, what, evidence, logged_by, client_id)
  values (p_member, on_, p, cat, sev, rep, coalesce((p_payload ->> 'late')::boolean, false),
          btrim(p_payload ->> 'what'), nullif(btrim(p_payload ->> 'evidence'), ''), m.id, cl)
  returning * into nb;
  perform public.perf_log((select id from public.perf_reviews where team_member_id = p_member and period = p),
    p_member, 'breach_logged', jsonb_build_object('breach', nb.id, 'category', cat, 'severity', sev,
      'repeated', rep, 'late', nb.late, 'vic', nb.vic,
      'deduction', public.perf_deduction_vic_at(sev, rep, nb.late, nb.vic, public.perf_today())));
  return jsonb_build_object('ok', true, 'id', nb.id, 'repeated', rep, 'vic', nb.vic,
    'deduction', public.perf_deduction_vic_at(sev, rep, nb.late, nb.vic, public.perf_today()), 'period', p);
end $$;
revoke all on function public.perf_breach_log(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.perf_breach_log(text, uuid, jsonb) to authenticated;

create or replace function public.ops_engagement_set_meeting(
  p_engagement uuid, p_at timestamptz, p_channel text default null,
  p_owner uuid default null, p_note text default null, p_na boolean default false,
  p_minutes integer default null, p_link text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; e public.ops_engagements; lk text;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.ops_may_see_engagement(p_engagement) then return jsonb_build_object('error', 'denied'); end if;
  select * into e from public.ops_engagements where id = p_engagement for update;
  if e.id is null then return jsonb_build_object('error', 'not-found'); end if;

  if coalesce(p_na, false) then
    update public.ops_engagements set meeting_na = true, meeting_note = coalesce(p_note, meeting_note),
           meeting_link = null, updated_at = now(), version = version + 1 where id = p_engagement;
    perform public.ops_engagement_log(p_engagement, 'meeting_na', jsonb_build_object('note', p_note));
    return public.ops_engagement_json(p_engagement);
  end if;
  if p_at is null then return jsonb_build_object('error', 'no-date'); end if;
  if p_channel is not null and p_channel not in ('onsite', 'google_meet', 'zoom', 'other') then
    return jsonb_build_object('error', 'bad-channel');
  end if;
  if e.meeting_at is null and (p_at at time zone 'Asia/Kuala_Lumpur')::date < (now() at time zone 'Asia/Kuala_Lumpur')::date
     and coalesce(p_channel, e.meeting_channel, '') <> 'onsite' then
    return jsonb_build_object('error', 'meeting-in-past');
  end if;
  if p_minutes is not null and (p_minutes < 15 or p_minutes > 240) then
    return jsonb_build_object('error', 'bad-minutes');
  end if;
  lk := nullif(btrim(coalesce(p_link, '')), '');
  if lk is not null and lk !~* '^https://([a-z0-9-]+\.)*(meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com)/' then
    return jsonb_build_object('error', 'bad-meeting-link');
  end if;
  update public.ops_engagements set
    meeting_at = p_at, meeting_channel = coalesce(p_channel, meeting_channel),
    meeting_owner_id = coalesce(p_owner, meeting_owner_id, m.id),
    meeting_note = case when p_note is null then meeting_note else nullif(btrim(p_note), '') end,
    meeting_minutes = coalesce(p_minutes, meeting_minutes),
    meeting_link = case when p_link is null then meeting_link else lk end,
    outstation_told_at = case when e.meeting_at is distinct from p_at then null else outstation_told_at end,
    meeting_na = false, updated_at = now(), version = version + 1
  where id = p_engagement;
  perform public.ops_engagement_log(p_engagement, 'meeting_set',
    jsonb_build_object('at', p_at, 'channel', p_channel, 'owner_id', p_owner, 'was', e.meeting_at,
                       'minutes', p_minutes));
  return public.ops_engagement_json(p_engagement);
end $$;
grant execute on function public.ops_engagement_set_meeting(uuid, timestamptz, text, uuid, text, boolean, integer, text) to authenticated;

create or replace function public.ops_report(
  p_from timestamptz default (now() - interval '90 days'),
  p_to   timestamptz default now())
returns jsonb
language plpgsql security definer stable set search_path = public as $$
declare
  out jsonb;
begin
  if not public.ops_granted('ops.reports', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;

  with
  /* Where client review begins in each workflow. The final due date is the
     day the work is owed AT that stage, so everything below that position is
     "has not reached the client yet". Read from `stage_group` and never from
     a stage key: the two seeded workflows name that stage differently. */
  floors as (
    select workflow_id, min(position) as at
      from public.ops_workflow_stages
     where stage_group = 'client_review'
     group by workflow_id
  ),
  /* Where a priority's deadline is met (2026-10-11): client review, else the
     workflow's first review (an everyday task's Review). */
  pfloors as (
    select workflow_id,
           coalesce(min(position) filter (where stage_group = 'client_review'),
                    min(position) filter (where stage_group = 'internal_review')) as at
      from public.ops_workflow_stages
     group by workflow_id
  ),
  live as (
    select t.*, s.label as stage_label, s.position as stage_position,
           s.stage_group, f.at as review_at,
           public.ops_priority_by(coalesce(t.priority_at, t.created_at), t.priority_level) as prio_by, pf.at as prio_at
      from public.ops_tasks t
      join public.ops_workflow_stages s
        on s.workflow_id = t.workflow_id and s.key = t.stage_key
      left join floors f on f.workflow_id = t.workflow_id
      left join pfloors pf on pf.workflow_id = t.workflow_id
     where t.completed_at is null and t.cancelled_at is null
       and t.archived_at is null
  ),

  /* 1. WHAT IS RUNNING, by the words on the screen. Grouped by the stage's
        own label rather than by its group, because "what is on shooting" is
        the question and Shooting is a label, not a group. */
  running as (
    select jsonb_agg(x order by x ->> 'position', x ->> 'label') as j from (
      select jsonb_build_object(
               'stage_key', stage_key, 'label', stage_label,
               'position', stage_position, 'stage_group', stage_group,
               'count', count(*)) as x
        from live
       group by stage_key, stage_label, stage_position, stage_group
    ) q
  ),

  /* 2. WHAT IS LATE. Past the commitment and still short of client review,
        or past a priority's deadline and short of its review (On hold and
        Blocked still count): whichever comes first (the user, 2026-10-11).
        The same rule the queue row draws, stated once more here because a
        report a page computes for itself is a second definition. */
  late_now as (
    select l.*,
           (l.current_final_due_at is not null and (l.current_final_due_at at time zone 'Asia/Kuala_Lumpur')::date < (now() at time zone 'Asia/Kuala_Lumpur')::date
            and (l.review_at is null or l.stage_position < l.review_at)) as due_late,
           (l.prio_by is not null and l.prio_by < now()
            and (l.prio_at is null or l.stage_position < l.prio_at or l.stage_group in ('kiv', 'blocked'))) as prio_late
      from live l
  ),
  late as (
    select jsonb_agg(x order by x ->> 'due_at') as j from (
      select jsonb_build_object(
               'task_id', l.id, 'task_no', l.task_no, 'title', l.title,
               'client', c.name, 'stage', l.stage_label,
               'due_at', case when l.prio_late and (not l.due_late or l.prio_by < l.current_final_due_at)
                              then l.prio_by else l.current_final_due_at end,
               'days_over', greatest(case when l.due_late then (now() at time zone 'Asia/Kuala_Lumpur')::date - (l.current_final_due_at at time zone 'Asia/Kuala_Lumpur')::date end,
                                     case when l.prio_late then floor(extract(epoch from (now() - l.prio_by)) / 86400)::int end),
               'over_minutes', case when l.prio_late then floor(extract(epoch from (now() - l.prio_by)) / 60)::int end,
               'owner', (select tm.name
                           from public.ops_task_assignees a
                           join public.team_members tm on tm.id = a.team_member_id
                          where a.task_id = l.id and a.responsibility = 'owner'
                            and a.ended_at is null
                          limit 1)) as x
        from late_now l
        left join public.clients c on c.id = l.client_id
       where l.due_late or l.prio_late
    ) q
  ),

  /* 3. HOW LONG EACH STAGE TAKES. A task enters a stage at the event that
        names it and leaves at the next event, or at its own ending, or now.
        Only spans that were ENTERED inside the period are counted, so the
        window means what it says and a task that sat in Editing since March
        does not land in every report for ever. */
  spans as (
    select e.task_id,
           e.to_value ->> 'stage_key' as stage_key,
           e.created_at as from_at,
           coalesce(
             lead(e.created_at) over (partition by e.task_id order by e.created_at),
             t.completed_at, t.cancelled_at, now()) as to_at
      from public.ops_task_events e
      join public.ops_tasks t on t.id = e.task_id
     where e.event_type in ('task_created', 'stage_changed')
       and e.to_value ->> 'stage_key' is not null
  ),
  /* One row per span and no grouping: an earlier draft grouped by the span's
     own timestamps, which silently collapsed two tasks that entered the same
     stage in the same instant into one measurement. The label is looked up
     once per stage below instead of aggregated here. */
  span_mins as (
    select s.stage_key,
           extract(epoch from (s.to_at - s.from_at)) / 60 as mins
      from spans s
     where s.from_at >= p_from and s.from_at < p_to
       and s.to_at > s.from_at
  ),
  stage_time as (
    select jsonb_agg(x order by x ->> 'label') as j from (
      select jsonb_build_object(
               'stage_key', stage_key,
               'label', coalesce((select w.label from public.ops_workflow_stages w
                                   where w.key = sm.stage_key limit 1), stage_key),
               'n', count(*),
               'median_minutes', round(percentile_cont(0.5) within group (order by mins))::int,
               'p90_minutes', round(percentile_cont(0.9) within group (order by mins))::int) as x
        from span_mins sm
       group by stage_key
    ) q
  ),

  /* 4. WAS IT THERE ON TIME. Of the tasks that reached client review inside
        the period, how many got there on or before the date they were owed.
        Replanning is counted beside it and never folded into it: an extension
        that moves the date would otherwise erase the miss it was granted for,
        and a rate that cannot be missed is not a measurement. */
  reached as (
    select distinct on (e.task_id)
           e.task_id, e.created_at as at, t.current_final_due_at as due,
           public.ops_priority_by(coalesce(t.priority_at, t.created_at), t.priority_level) as prio_by,
           (t.original_final_due_at is distinct from t.current_final_due_at) as replanned
      from public.ops_task_events e
      join public.ops_tasks t on t.id = e.task_id
      join public.ops_workflow_stages w
        on w.workflow_id = t.workflow_id and w.key = e.to_value ->> 'stage_key'
     where e.event_type = 'stage_changed'
       and w.stage_group = 'client_review'
       and e.created_at >= p_from and e.created_at < p_to
     order by e.task_id, e.created_at
  ),
  on_time as (
    select jsonb_build_object(
             'reached', count(*),
             'met', count(*) filter (where (due is null or at::date <= due::date) and (prio_by is null or at <= prio_by)),
             'missed', count(*) filter (where not ((due is null or at::date <= due::date) and (prio_by is null or at <= prio_by))),
             'replanned', count(*) filter (where replanned)) as j
      from reached
  ),

  /* 5. BY PERSON. The foundation of a KPI and not a KPI: what somebody
        finished in the window, how much of it was on time, and how long their
        work took end to end. No ranking and no score — a number a person can
        check is worth more than a league table nobody trusts. */
  done as (
    select t.id, t.created_at, coalesce(t.completed_at, t.delivered_at) as ended,
           t.current_final_due_at as due,
           public.ops_priority_by(coalesce(t.priority_at, t.created_at), t.priority_level) as prio_by,
           /* When a priority's deadline was met: the first move into its
              review or beyond (never On hold, Blocked or Cancelled). */
           (select min(e.created_at)
              from public.ops_task_events e
              join public.ops_workflow_stages w
                on w.workflow_id = t.workflow_id and w.key = e.to_value ->> 'stage_key'
              join pfloors pf on pf.workflow_id = t.workflow_id
             where e.task_id = t.id and e.event_type = 'stage_changed'
               and w.position >= pf.at and w.stage_group not in ('kiv', 'blocked', 'cancelled')) as met_at,
           (select a.team_member_id
              from public.ops_task_assignees a
             where a.task_id = t.id and a.responsibility = 'owner'
             order by a.ended_at nulls first, a.assigned_at desc
             limit 1) as owner_id
      from public.ops_tasks t
     where t.completed_at is not null
       and t.completed_at >= p_from and t.completed_at < p_to
  ),
  by_person as (
    select jsonb_agg(x order by x ->> 'name') as j from (
      select jsonb_build_object(
               'team_member_id', d.owner_id,
               'name', coalesce(tm.name, 'Nobody'),
               'completed', count(*),
               'on_time', count(*) filter (where (d.due is null or d.ended::date <= d.due::date)
                                         and (d.prio_by is null or coalesce(d.met_at, d.ended) <= d.prio_by)),
               'median_cycle_minutes',
                 round(percentile_cont(0.5) within group (
                   order by extract(epoch from (d.ended - d.created_at)) / 60))::int) as x
        from done d
        left join public.team_members tm on tm.id = d.owner_id
       group by d.owner_id, tm.name
    ) q
  ),

  /* 6. WHO IS CARRYING THE OPEN WORK (2026-09-28). One row a Task Owner:
        the open tasks they hold, and how many of those are late by the rule
        in 2 above. The team's whole queue is `ops.all`, so it is answered
        only where that part is granted. */
  open_by_person as (
    select jsonb_agg(x order by (x ->> 'open')::int desc, x ->> 'name') as j from (
      select jsonb_build_object(
               'team_member_id', o.owner_id,
               'name', coalesce(tm.name, 'No task owner'),
               'open', count(*),
               'late', count(*) filter (where o.is_late)) as x
        from (select l.id,
                     (select a.team_member_id
                        from public.ops_task_assignees a
                       where a.task_id = l.id and a.responsibility = 'owner' and a.ended_at is null
                       limit 1) as owner_id,
                     (l.due_late or l.prio_late) as is_late
                from late_now l) o
        left join public.team_members tm on tm.id = o.owner_id
       where public.ops_granted('ops.all', 'view')
       group by o.owner_id, tm.name
    ) q
  )

  select jsonb_build_object(
           'from', p_from, 'to', p_to,
           'running',    coalesce((select j from running), '[]'::jsonb),
           'late',       coalesce((select j from late), '[]'::jsonb),
           'stage_time', coalesce((select j from stage_time), '[]'::jsonb),
           'on_time',    coalesce((select j from on_time), '{}'::jsonb),
           'by_person',  coalesce((select j from by_person), '[]'::jsonb),
           'open_by_person', case when public.ops_granted('ops.all', 'view')
                                  then coalesce((select j from open_by_person), '[]'::jsonb) end)
    into out;

  return out;
end $$;
grant execute on function public.ops_report(timestamptz, timestamptz) to authenticated;

create or replace function public.ops_create_task(p_payload jsonb, p_idem text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m     public.team_members;
  tpl   public.ops_task_templates;
  fam   public.ops_template_variants;
  byfmt boolean := false;
  wf    uuid;
  tid   uuid;
  owner uuid;
  publish timestamptz;
  fd    timestamptz;
  fin   timestamptz;
  item  jsonb;
  i     integer := 0;
  scope text;
  ttype text;
  cid   uuid;
  bad   text;
  descr text;
  period text;
  cper  text;
  week  integer;
  seq   integer;
  code  text;
  title text;
  first_stage text;
  wkey  text;
  base  timestamptz;
  eng   public.ops_engagements;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  -- The same press twice is one task.
  if p_idem is not null then
    select id into tid from public.ops_tasks where idem_key = p_idem;
    if tid is not null then return public.ops_task_json(tid); end if;
  end if;

  scope := coalesce(p_payload ->> 'scope', 'client');
  cid := (p_payload ->> 'client_id')::uuid;
  /* A task linked to a month's engagement takes the client from it: the
     person names the month once and the client comes with it. */
  if (p_payload ->> 'engagement_id') is not null then
    select * into eng from public.ops_engagements where id = (p_payload ->> 'engagement_id')::uuid;
    if eng.id is null then return jsonb_build_object('error', 'not-found'); end if;
    if cid is null then cid := eng.client_id; scope := 'client'; end if;
  end if;
  bad := public.ops_scope_error(scope, cid);
  if bad is not null then return jsonb_build_object('error', bad); end if;

  ttype := coalesce(p_payload ->> 'task_type', 'adhoc');
  if ttype not in ('engagement', 'adhoc', 'goodwill', 'special') then
    return jsonb_build_object('error', 'bad-task-type');
  end if;

  /* The description is the team's to edit and may start blank on a task that
     carries a code; a task with no code is named by its description alone, so
     there it is required. `title` is accepted from older callers as the
     description. */
  descr := nullif(btrim(coalesce(p_payload ->> 'content_desc', p_payload ->> 'title', '')), '');

  if (p_payload ->> 'template_id') is not null then
    select * into tpl from public.ops_task_templates
     where id = (p_payload ->> 'template_id')::uuid;
    descr := coalesce(descr, nullif(btrim(coalesce(tpl.default_title, tpl.name, '')), ''));
  end if;
  /* No template named: the family that owns the chosen format fills the task
     (its checklist, complexity, draft and final offsets, owner) and the
     format's own variant its hours (TEMPLATE FAMILIES, 2026-09-28). */
  if tpl.id is null and nullif(p_payload ->> 'deliverable_type', '') is not null then
    select v.* into fam from public.ops_template_variants v
      join public.ops_task_templates t on t.id = v.template_id and t.active
     where v.format = p_payload ->> 'deliverable_type';
    if fam.id is not null then
      select * into tpl from public.ops_task_templates where id = fam.template_id;
      byfmt := true;
    end if;
  end if;
  /* New work goes on the content workflow. A caller may still name another
     (a template's own, or one somebody adds), and a task already on a retired
     workflow is never moved. */
  wf := coalesce((p_payload ->> 'workflow_id')::uuid,
                 (select id from public.ops_workflows where key = p_payload ->> 'workflow_key' and active),
                 case when byfmt then null else tpl.workflow_id end,
                 (select id from public.ops_workflows where key = 'content' and active),
                 (select id from public.ops_workflows where active order by created_at limit 1));
  if wf is null then return jsonb_build_object('error', 'workflow-required'); end if;
  select key into first_stage from public.ops_workflow_stages
   where workflow_id = wf order by position limit 1;
  select key into wkey from public.ops_workflows where id = wf;

  publish := (p_payload ->> 'publish_at')::timestamptz;
  fd := coalesce((p_payload ->> 'first_draft_due_at')::timestamptz,
        case when publish is not null and tpl.first_draft_offset_business_days is not null
             then public.ops_add_business_days(publish, -tpl.first_draft_offset_business_days)
             when tpl.first_draft_offset_business_days is not null
             then public.ops_add_business_days(now(), tpl.first_draft_offset_business_days)
        end);
  /* A template's due date is a number of calendar days from the day the
     work is made for (the base date the caller names, else today). */
  base := coalesce((p_payload ->> 'base_date')::timestamptz, now());
  fin := coalesce((p_payload ->> 'final_due_at')::timestamptz,
        case when tpl.due_offset_days is not null and not byfmt
             then date_trunc('day', base) + make_interval(days => tpl.due_offset_days)
             when publish is not null and tpl.final_offset_business_days is not null
             then public.ops_add_business_days(publish, -tpl.final_offset_business_days)
             when tpl.final_offset_business_days is not null
             then public.ops_add_business_days(now(), tpl.final_offset_business_days)
        end);
  /* Dates a person typed stand as typed, and a date left blank stays blank:
     nothing is worked out from a template's offsets (the user, 2026-10-05). */
  if coalesce((p_payload ->> 'dates_as_given')::boolean, false) then
    fd := (p_payload ->> 'first_draft_due_at')::timestamptz;
    fin := (p_payload ->> 'final_due_at')::timestamptz;
  end if;
  if fd is not null and fin is not null and not public.ops_due_order_ok(fd, fin) then
    return jsonb_build_object('error', 'draft-not-before-final');
  end if;

  /* The name. The month is the content month (the scheduled publish date's,
     else the one the caller names, else this one); the week is the planned
     publishing week, chosen by the caller and prefilled by the page from the
     date; the running number is the client's for the month. Generated once,
     under the lock, and never rewritten: a publish date that moves later
     leaves the name as it was, because the name is a label and not a fact
     about the date. */
  if wkey = 'task' then
    /* An everyday task is named by what it is. It carries no content code,
       because the code numbers a client's deliverables for the month and a
       task is not one; the content month is kept where it is known, so the
       task can be grouped with the month it belongs to. */
    if descr is null then return jsonb_build_object('error', 'title-required'); end if;
    title := descr;
    period := coalesce(nullif(p_payload ->> 'code_period', ''), eng.period);
  elsif scope <> 'internal' then
    period := coalesce(nullif(p_payload ->> 'code_period', ''),
                       case when publish is not null then to_char(publish, 'YYYY-MM') end,
                       to_char((now() at time zone 'Asia/Kuala_Lumpur')::date, 'YYYY-MM'));
    if period !~ '^\d{4}-\d{2}$' then return jsonb_build_object('error', 'bad-period'); end if;
    /* A client's deliverable belongs to a month the team has planned: one
       that exists, is still open, and has its content meeting set or marked
       not applicable. The same three refusals Bulk add gives. */
    if scope = 'client' then
      cper := period;
      if eng.id is null or eng.period <> cper then
        select * into eng from public.ops_engagements x where x.client_id = cid and x.period = cper;
      end if;
      if eng.id is null then return jsonb_build_object('error', 'no-month'); end if;
      if eng.status in ('completed', 'cancelled') then return jsonb_build_object('error', 'month-closed'); end if;
      if eng.meeting_at is null and not eng.meeting_na then
        return jsonb_build_object('error', 'month-not-confirmed');
      end if;
    end if;
    week := coalesce((p_payload ->> 'code_week')::integer,
                     case when publish is not null
                          then least(5, ((extract(day from publish)::integer - 1) / 7) + 1) end,
                     1);
    if week < 1 or week > 5 then return jsonb_build_object('error', 'bad-week'); end if;
    seq := public.ops_next_seq(cid, period);
    code := public.ops_code_of(period, week, seq);
    title := btrim(code || ' ' || coalesce(descr, ''));
  else
    if descr is null then return jsonb_build_object('error', 'title-required'); end if;
    title := descr;
  end if;

  insert into public.ops_tasks (
    scope, client_id, campaign_id, batch_id, source_type, source_id, template_id,
    workflow_id, stage_key, title, description, remarks, deliverable_type,
    language_codes, priority_level, complexity, estimate_minutes, publish_at,
    original_first_draft_due_at, current_first_draft_due_at,
    original_final_due_at, current_final_due_at, created_by, idem_key,
    legacy_source, legacy_key, data_quality,
    task_type, code, code_period, code_week, code_seq, content_desc,
    engagement_id, manager_id, parent_task_id)
  values (
    scope, cid,
    (p_payload ->> 'campaign_id')::uuid,
    (p_payload ->> 'batch_id')::uuid,
    p_payload ->> 'source_type',
    (p_payload ->> 'source_id')::uuid,
    tpl.id, wf, coalesce(first_stage, 'intake'),
    title, p_payload ->> 'description', p_payload ->> 'remarks',
    coalesce(p_payload ->> 'deliverable_type', tpl.deliverable_type, 'other'),
    coalesce((select array_agg(x) from jsonb_array_elements_text(
               coalesce(p_payload -> 'language_codes', '[]'::jsonb)) x), '{}'),
    coalesce((p_payload ->> 'priority_level')::smallint, 3),
    coalesce(p_payload ->> 'complexity', tpl.default_complexity),
    coalesce((p_payload ->> 'estimate_minutes')::integer, fam.estimate_minutes, tpl.default_estimate_minutes),
    publish, fd, fd, fin, fin, m.id, p_idem,
    p_payload ->> 'legacy_source', p_payload ->> 'legacy_key',
    coalesce(p_payload ->> 'data_quality', 'complete'),
    ttype, code, period, week, seq, descr,
    coalesce(eng.id, (p_payload ->> 'engagement_id')::uuid),
    coalesce((p_payload ->> 'manager_id')::uuid, m.id),
    (p_payload ->> 'parent_task_id')::uuid)
  returning id into tid;

  /* Every task has an owner from the moment it exists: the one named, the
     template's, or else whoever made it. */
  owner := coalesce((p_payload ->> 'owner_id')::uuid, tpl.default_owner_id, m.id);
  if owner is not null then
    insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
    values (tid, owner, 'owner', m.id);
    perform public.ops_log(tid, 'assignment_changed', null,
      jsonb_build_object('owner_id', owner), '{}'::jsonb);
  end if;
  if (p_payload ->> 'reviewer_id') is not null then
    insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
    values (tid, (p_payload ->> 'reviewer_id')::uuid, 'reviewer', m.id);
  end if;

  -- The template's checklist, or the one the caller hands over (a duplicate
  -- carries its source's labels, unticked), in the order stated.
  for item in select * from jsonb_array_elements(
      coalesce(p_payload -> 'checklist', tpl.checklist, '[]'::jsonb)) loop
    i := i + 1;
    insert into public.ops_task_checklist_items (task_id, label, position)
    values (tid, item #>> '{}', i);
  end loop;

  if (p_payload -> 'video') is not null then
    insert into public.ops_video_details (
      task_id, output_duration_seconds, footage_duration_seconds,
      subtitle_required, motion_graphics_required, aspect_ratios,
      script_ready, footage_ready, shoot_required, shoot_at, variant_count)
    values (tid,
      ((p_payload -> 'video') ->> 'output_duration_seconds')::integer,
      ((p_payload -> 'video') ->> 'footage_duration_seconds')::integer,
      coalesce(((p_payload -> 'video') ->> 'subtitle_required')::boolean, false),
      coalesce(((p_payload -> 'video') ->> 'motion_graphics_required')::boolean, false),
      coalesce((select array_agg(x) from jsonb_array_elements_text(
                 coalesce((p_payload -> 'video') -> 'aspect_ratios', '[]'::jsonb)) x), '{}'),
      ((p_payload -> 'video') ->> 'script_ready')::boolean,
      ((p_payload -> 'video') ->> 'footage_ready')::boolean,
      coalesce(((p_payload -> 'video') ->> 'shoot_required')::boolean, false),
      ((p_payload -> 'video') ->> 'shoot_at')::timestamptz,
      coalesce(((p_payload -> 'video') ->> 'variant_count')::integer, 1));
  end if;

  perform public.ops_log(tid, 'task_created', null,
    jsonb_build_object('title', title, 'code', code,
                       'first_draft_due_at', fd, 'final_due_at', fin),
    case when (p_payload ->> 'duplicated_from') is null then '{}'::jsonb
         else jsonb_build_object('duplicated_from', p_payload ->> 'duplicated_from') end);
  return public.ops_task_json(tid);
end $$;
grant execute on function public.ops_create_task(jsonb, text) to authenticated;

create or replace function public.portal_meetings(p_client uuid)
returns jsonb
language plpgsql security definer stable set search_path = public as $$
begin
  if auth.jwt() ->> 'email' is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  if p_client is null or p_client not in (select public.portal_clients()) then
    return jsonb_build_object('error', 'no-access');
  end if;
  /* The content meetings the team has put in the diary, from three months
     back. Nothing about the month's tasks, checks or status beyond this: a
     client reads when we meet, never how the work inside the month is going.
     The link is sent only while the meeting is still ahead. */
  /* Beside them, the meetings the team booked outside a month (Calls and
     visits, kind meeting, with a time; 2026-10-05): the time, the length
     and the link, never what was written about it. */
  return jsonb_build_object('meetings', coalesce((
    select jsonb_agg(x.j order by x.at desc) from (
      select e.meeting_at as at, jsonb_build_object(
               'kind', 'content', 'period', e.period, 'at', e.meeting_at, 'minutes', coalesce(e.meeting_minutes, 30),
               'channel', e.meeting_channel,
               'link', case when e.meeting_at + make_interval(mins => coalesce(e.meeting_minutes, 30)) > now()
                            then e.meeting_link end) as j
        from public.ops_engagements e
       where e.client_id = p_client
         and e.meeting_at is not null
         and not coalesce(e.meeting_na, false)
         and e.status <> 'cancelled'
         and e.meeting_at >= date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') at time zone 'Asia/Kuala_Lumpur' - interval '3 months'
      union all
      select t.meet_at, jsonb_build_object(
               'kind', 'meeting', 'period', null, 'at', t.meet_at, 'minutes', coalesce(t.meet_minutes, 30),
               'channel', case when t.meet_link ~* 'meet\.google\.com' then 'google_meet'
                               when t.meet_link ~* 'zoom\.us' then 'zoom'
                               when t.meet_link ~* 'teams\.' then 'teams' end,
               'link', case when t.meet_at + make_interval(mins => coalesce(t.meet_minutes, 30)) > now()
                            then t.meet_link end)
        from public.client_touches t
       where t.client_id = p_client
         and t.kind = 'meeting' and t.meet_at is not null and t.archived_at is null
         and t.meet_at >= date_trunc('month', now() at time zone 'Asia/Kuala_Lumpur') at time zone 'Asia/Kuala_Lumpur' - interval '3 months') x), '[]'::jsonb));
end $$;
revoke all on function public.portal_meetings(uuid) from public, anon;
grant execute on function public.portal_meetings(uuid) to authenticated;

-- END OF MALAYSIA TIME IN THE DATABASE --------------------------------------

select public.functions_tidy();
