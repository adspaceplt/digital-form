-- ===========================================================================
-- TONE SWEEP 6 (2026-11-23)
-- ===========================================================================
-- WHY: three readers went through every word changed since tone sweep 5
-- (1,577 lines, 32 findings; the user, 2026-11-23: "Fix the 32 tone sweep 6
-- findings ... in one release"). The database's own words follow the
-- pages' in the same release.
--
-- WHAT IT CHANGES (words only; no stored key, refusal or rule moves)
--   * `quote_website_create`: the team's notice reads RM x per month incl.
--     SST, and Send by {day} ({weekday}), {time}; the activity line reads
--     Planned commencement, as the field is named.
--   * `sm_reports_task_follow`: Report reverted to draft.
--   * `sm_reports_brand_task`: White label set on the report / removed from
--     the report.
--   * `ops_transition_task`: a client post's checklist item reads Decision
--     made to keep the post live or take it down; the items already made
--     are renamed where they still read the old words.
--   * `hiring_decide`: the record reads Do not proceed.
--   * `hiring_email_templates_save`: Decision date changed and Application
--     unsuccessful, as Settings names the two templates; the Decision date
--     subject is renamed only where the team has not edited it.
--   * `bukku_take`: Used Bukku's details.
--
-- ORDER: the pages first (they draw the same words), then this file. An
-- old line already filed keeps its words.
-- Rollback: run the bands each function was last restated in again
-- (QUOTATION WEBSITE, REPORT TASK FOLLOWS TO DONE, CLIENT POSTS, HIRING,
-- INTERVIEW TIME CHANGED, A SUPPLIER LINKED TO BUKKU) and the two updates
-- below in reverse.
-- Safe to run twice.
-- ===========================================================================

create or replace function public.quote_website_create(p_sel jsonb, p_contact jsonb, p_idem text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_name  text := btrim(regexp_replace(coalesce(p_contact->>'name', ''), '\s+', ' ', 'g'));
  v_email text := lower(btrim(coalesce(p_contact->>'email', '')));
  v_wa    text := public.quote_website_number(p_contact->>'whatsapp');
  v_brand text := btrim(regexp_replace(coalesce(p_contact->>'brand', ''), '\s+', ' ', 'g'));
  v_ind   text := nullif(btrim(coalesce(p_contact->>'industry', '')), '');
  v_lang  text := case when p_contact->>'lang' = 'zh' then 'zh' else 'en' end;
  v_sal   text := nullif(btrim(coalesce(p_contact->>'salutation', '')), '');
  v_start text := nullif(btrim(coalesce(p_contact->>'commence', '')), '');
  v_on_t  text := nullif(btrim(coalesce(p_contact->>'commence_on', '')), '');
  v_on    date;
  v_idem  text := nullif(btrim(coalesce(p_idem, '')), '');
  v_sel   jsonb;
  v_q     public.quotations;
  v_c     public.clients;
  v_base  text;
  v_slug  text;
  v_n     int := 1;
  v_r     jsonb;
  v_new   boolean := false;
begin
  if v_idem is null or length(v_idem) > 80 then return jsonb_build_object('error', 'bad-request'); end if;
  -- The quotation website covered (Page availability) makes nothing.
  if public.page_covered('quote') then return jsonb_build_object('error', 'unavailable'); end if;
  select * into v_q from public.quotations q
   where q.idem = v_idem and q.source = 'website' and lower(q.contact->>'email') = v_email;
  if v_q.id is not null then
    return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key, 'again', true);
  end if;
  if length(v_name) < 2 or length(v_name) > 80 then return jsonb_build_object('error', 'bad-name'); end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_email) > 160 then return jsonb_build_object('error', 'bad-email'); end if;
  if v_wa !~ '^(60(1[0-9]{8,9}|7[0-9]{7,8})|65[0-9]{8})$' then return jsonb_build_object('error', 'bad-whatsapp'); end if;
  if length(v_brand) < 2 or length(v_brand) > 120 then return jsonb_build_object('error', 'bad-brand'); end if;
  -- A name or brand is never a web address: both go into the WhatsApp the
  -- prospect is sent from ADspace's number (2026-10-26, audit).
  if v_name ~* public.quote_link_like() then return jsonb_build_object('error', 'bad-name'); end if;
  if v_brand ~* public.quote_link_like() then return jsonb_build_object('error', 'bad-brand'); end if;
  -- An industry on the list kept in Settings (INDUSTRIES, 2026-11-04).
  if v_ind is not null and not exists (select 1 from public.industries i where i.name = v_ind) then
    return jsonb_build_object('error', 'bad-industry');
  end if;
  if v_sal is not null and v_sal not in ('Mr', 'Ms', 'Mrs', 'Mdm', 'Dr', 'Prof', 'Dato''', 'Datin', 'Datuk',
      'Dato'' Sri', 'Datin Sri', 'Tan Sri', 'Puan Sri', 'Tun', 'Tuan', 'Puan', 'Encik', 'Cik') then
    return jsonb_build_object('error', 'bad-salutation');
  end if;
  -- When they plan to start: the console's Urgency to commence, for the
  -- team's planning; it changes no price. Left out by a page served before.
  if v_start is not null and v_start not in ('1_3', '3_6', '6_plus') then
    return jsonb_build_object('error', 'bad-commence');
  end if;
  -- A preferred start date, optional (PREFERRED START DATE, 2026-11-21):
  -- a day from today in Malaysia to the date ceiling, kept on the quotation
  -- it was asked on (START DATE ON THE QUOTATION, 2026-11-21).
  if v_on_t is not null then
    if v_on_t !~ '^\d{4}-\d{2}-\d{2}$' then return jsonb_build_object('error', 'bad-start-date'); end if;
    begin
      v_on := v_on_t::date;
    exception when others then
      return jsonb_build_object('error', 'bad-start-date');
    end;
    if v_on < (now() at time zone 'Asia/Kuala_Lumpur')::date or v_on > date '2099-12-31' then
      return jsonb_build_object('error', 'bad-start-date');
    end if;
  end if;
  if coalesce((p_contact->>'consent')::boolean, false) is not true then return jsonb_build_object('error', 'consent'); end if;
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-selection'); end if;
  if jsonb_typeof(p_sel->'once') = 'array' and jsonb_array_length(p_sel->'once') > 20
     or jsonb_typeof(p_sel->'extra') = 'object' and (select count(*) from jsonb_object_keys(p_sel->'extra')) > 10 then
    return jsonb_build_object('error', 'bad-selection');
  end if;

  -- What the price reads, and nothing else.
  v_sel := jsonb_strip_nulls(jsonb_build_object(
    'mix', case when jsonb_typeof(p_sel->'mix') = 'string' and length(p_sel->>'mix') <= 20 then p_sel->'mix' end,
    'plan', case when jsonb_typeof(p_sel->'plan') = 'string' and length(p_sel->>'plan') <= 80 then p_sel->'plan' end,
    'term', case when jsonb_typeof(p_sel->'term') in ('number', 'string') and length(p_sel->>'term') <= 4 then p_sel->'term' end,
    'budget', case when jsonb_typeof(p_sel->'budget') in ('number', 'string') and length(p_sel->>'budget') <= 12 then p_sel->'budget' end,
    'translate', case when jsonb_typeof(p_sel->'translate') = 'boolean' then p_sel->'translate' end,
    'platforms', (select jsonb_agg(distinct v) from jsonb_array_elements_text(
                    case when jsonb_typeof(p_sel->'platforms') = 'array' then p_sel->'platforms' else '[]'::jsonb end) v
                   where v in ('meta', 'tiktok', 'rednote', 'linkedin')),
    'langs', (select jsonb_agg(distinct l) from jsonb_array_elements_text(
                case when jsonb_typeof(p_sel->'langs') = 'array' then p_sel->'langs' else '[]'::jsonb end) l
               where l in ('en', 'zh', 'ms')),
    'extra', case when jsonb_typeof(p_sel->'extra') = 'object' then
               (select jsonb_object_agg(left(k, 80), p_sel->'extra'->k) from jsonb_object_keys(p_sel->'extra') k) end,
    'once', case when jsonb_typeof(p_sel->'once') = 'array' then
              (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('slug', left(o->>'slug', 80), 'qty', o->'qty')))
                 from jsonb_array_elements(p_sel->'once') o where jsonb_typeof(o) = 'object') end));

  -- Two posts at once are counted one after the other.
  perform pg_advisory_xact_lock(hashtextextended('quote-web:' || least(v_email, v_wa), 0));
  perform pg_advisory_xact_lock(hashtextextended('quote-web:' || greatest(v_email, v_wa), 0));
  if (select count(*) from public.quotations q
       where q.source = 'website' and q.issued_at > now() - interval '1 day'
         and (lower(q.contact->>'email') = v_email or q.contact->>'whatsapp' = '+' || v_wa)) >= 5 then
    return jsonb_build_object('error', 'limit');
  end if;

  -- A lead this person already is (the same contact holds both the email
  -- and the number), else a new one.
  select c.* into v_c from public.clients c
    join public.client_contacts k on k.client_id = c.id
   where c.stage in ('lead', 'contacted', 'proposal')
     and k.archived_at is null
     and lower(k.email) = v_email
     and public.quote_website_number(k.whatsapp) = v_wa
   order by c.created_at desc limit 1;
  if v_c.id is null then
    v_base := btrim(regexp_replace(lower(v_brand), '[^a-z0-9]+', '-', 'g'), '-');
    if v_base = '' then v_base := 'client'; end if;
    v_slug := v_base;
    while exists (select 1 from public.clients c where lower(c.slug) = v_slug) loop
      v_n := v_n + 1; v_slug := v_base || '-' || v_n;
    end loop;
    insert into public.clients (name, access_token, stage, industry, source, market, slug, deal_note, commence)
    values (v_brand, public.new_link_key(), 'lead', v_ind, 'website',
            case when v_wa like '65%' then 'SG' else 'MY' end, v_slug,
            'Quotation requested on the website.', v_start)
    returning * into v_c;
    insert into public.client_contacts (client_id, salutation, name, email, whatsapp, lang, is_primary)
    values (v_c.id, v_sal, v_name, v_email, '+' || v_wa, v_lang, true);
    insert into public.activity_log (actor, action, subject, detail)
    values ('Quotation website', 'client.added', v_c.name, 'Website · ' || coalesce(v_sal || ' ', '') || v_name);
    v_new := true;
  end if;

  v_r := public.quotation_make(v_c.id, v_sel, v_idem, 'website', null,
    jsonb_strip_nulls(jsonb_build_object('salutation', v_sal, 'name', v_name, 'email', v_email,
      'whatsapp', '+' || v_wa, 'lang', v_lang, 'brand', v_brand)));
  if v_r ? 'error' then
    if v_new then raise exception using message = 'quote:' || (v_r->>'error'); end if;
    return v_r;
  end if;
  select * into v_q from public.quotations where id = (v_r->>'id')::uuid;
  -- A lead asking again says when it plans to start now, once its
  -- quotation is made (a refused one changes nothing).
  if not v_new and v_start is not null and v_c.commence is distinct from v_start then
    update public.clients set commence = v_start where id = v_c.id;
    insert into public.activity_log (actor, action, subject, detail)
    values ('Quotation website', 'client.edited', v_c.name, 'Planned commencement: ' ||
      coalesce(public.quote_commence_word(v_c.commence), 'not set') || ' → ' || public.quote_commence_word(v_start));
  end if;
  -- The price waits for the team (the user, 2026-10-29: "the price
  -- shouldnt send out straight"): the quotation is owed a reply by working
  -- days, the team is told to review it, and the prospect is sent nothing
  -- until a colleague sends it (`quotation_send`).
  update public.quotations set reply_due = public.quote_reply_by(now()), commence_on = v_on where id = v_q.id
   returning * into v_q;
  perform public.quote_tell(v_c.id, 'quote.website', 'Quotation to review · ' || v_c.name,
    v_q.ref || ' · ' || coalesce('RM ' ||
      to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00') || ' per month incl. SST', 'one-off') || ' · ' || v_name
      || coalesce(' · Preferred start date ' || public.register_day(v_on),
                  ' · Starts ' || lower(public.quote_commence_word(v_start)), '')
      || ' · Send by ' || public.register_day((v_q.reply_due at time zone 'Asia/Kuala_Lumpur')::date)
      || ' (' || trim(to_char(v_q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMDay')) || '), ' ||
      lower(to_char(v_q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam')),
    v_q.id::text);
  return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key);
exception when raise_exception then
  if sqlerrm like 'quote:%' then return jsonb_build_object('error', substr(sqlerrm, 7)); end if;
  raise;
end $$;
revoke all on function public.quote_website_create(jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.quote_website_create(jsonb, jsonb, text) to service_role;

create or replace function public.sm_reports_task_follow()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  e public.ops_engagements;
  t public.ops_tasks;
  v_to text;
  v_was uuid;
  v_note text;
  v_back boolean := false;
begin
  if new.brand_id is not null or new.on_request then return null; end if;
  if tg_op = 'UPDATE' and new.status is not distinct from old.status
     and new.sent_on is not distinct from old.sent_on then
    return null;
  end if;
  v_to := public.sm_report_task_target(new.status, new.sent_on);
  if v_to is null then return null; end if;
  /* The report moved back: into draft, or no longer marked as sent. */
  if tg_op = 'UPDATE' then
    v_back := (new.status = 'draft' and old.status is distinct from 'draft')
           or (new.status = 'published' and old.status = 'published'
               and new.sent_on is null and old.sent_on is not null);
  end if;
  select x.* into e from public.ops_engagements x
   cross join lateral public.ops_month_span(x.period, x.start_day) s
   where x.client_id = new.client_id and x.status <> 'cancelled'
     and new.period_end between s.starts and s.ends
   order by x.period desc limit 1;
  if e.id is null then return null; end if;
  select * into t from public.ops_tasks x
   where x.engagement_id = e.id and x.source_type = 'report_' || new.kind
     and x.cancelled_at is null and x.archived_at is null
   order by x.created_at desc limit 1
   for update;
  /* A finished task moves only with its report moving back. */
  if t.id is null or (t.completed_at is not null and not v_back) then return null; end if;

  if tg_op = 'INSERT' and new.created_by is not null then
    select team_member_id into v_was from public.ops_task_assignees
     where task_id = t.id and responsibility = 'owner' and ended_at is null;
    if v_was is distinct from new.created_by then
      update public.ops_task_assignees set ended_at = now()
       where task_id = t.id and responsibility = 'owner' and ended_at is null;
      insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
      values (t.id, new.created_by, 'owner', new.created_by);
      perform public.ops_log(t.id, 'assignment_changed',
        jsonb_build_object('owner_id', v_was), jsonb_build_object('owner_id', new.created_by),
        jsonb_build_object('report', true, 'report_id', new.id, 'stage_key', t.stage_key));
      /* The new owner's row may already have caught the task up
         (ops_tasks_report_catch_up): read its stage again, so the move is
         filed once. */
      select x.stage_key into t.stage_key from public.ops_tasks x where x.id = t.id;
    end if;
  end if;

  if t.stage_key is distinct from v_to then
    v_note := case
      when tg_op = 'INSERT' then 'Report started'
      when new.status = 'draft' then 'Report reverted to draft'
      when new.status = 'review' then 'Report submitted for review'
      when new.status = 'confirmed' then 'Report confirmed'
      when new.sent_on is null and v_back then 'Report marked as not sent'
      when new.sent_on is null then 'Report published'
      else 'Report sent to the client' end;
    perform public.sm_report_task_move(t.id, v_to, new.sent_on, v_note, new.id);
  elsif tg_op = 'INSERT' then
    update public.ops_tasks set version = version + 1, updated_at = now() where id = t.id;
  end if;
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.sm_reports_task_follow() from public, anon, authenticated;

create or replace function public.sm_reports_brand_task()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  e public.ops_engagements;
  t public.ops_tasks;
  v_starts date;
  v_ends date;
  v_to text;
  v_owner uuid;
  v_was uuid;
  v_note text;
begin
  if new.on_request or new.brand_id is not distinct from old.brand_id then return null; end if;
  select x.* into e from public.ops_engagements x
   cross join lateral public.ops_month_span(x.period, x.start_day) s
   where x.client_id = new.client_id and x.status <> 'cancelled'
     and new.period_end between s.starts and s.ends
   order by x.period desc limit 1;
  if e.id is null then return null; end if;
  select s.starts, s.ends into v_starts, v_ends from public.ops_month_span(e.period, e.start_day) s;
  select * into t from public.ops_tasks x
   where x.engagement_id = e.id and x.source_type = 'report_' || new.kind
     and x.cancelled_at is null and x.archived_at is null
   order by x.created_at desc limit 1
   for update;
  if t.id is null or t.completed_at is not null then return null; end if;

  if new.brand_id is not null then
    if old.brand_id is not null then return null; end if;
    if exists (select 1 from public.sm_reports r
                where r.id <> new.id and r.client_id = new.client_id and r.kind = new.kind
                  and r.brand_id is null and not coalesce(r.on_request, false)
                  and r.period_end between v_starts and v_ends) then
      return null;
    end if;
    v_to := 'todo';
    v_owner := e.manager_id;
    v_note := 'White label set on the report';
  else
    v_to := public.sm_report_task_target(new.status, new.sent_on);
    v_owner := new.created_by;
    v_note := 'White label removed from the report';
  end if;

  if v_owner is not null then
    select a.team_member_id into v_was from public.ops_task_assignees a
     where a.task_id = t.id and a.responsibility = 'owner' and a.ended_at is null;
    if v_was is distinct from v_owner then
      update public.ops_task_assignees set ended_at = now()
       where task_id = t.id and responsibility = 'owner' and ended_at is null;
      insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
      values (t.id, v_owner, 'owner', coalesce(me.id, v_owner));
      perform public.ops_log(t.id, 'assignment_changed',
        jsonb_build_object('owner_id', v_was), jsonb_build_object('owner_id', v_owner),
        jsonb_build_object('report', true, 'report_id', new.id, 'note', v_note));
    end if;
  end if;
  if v_to is not null and t.stage_key is distinct from v_to then
    perform public.sm_report_task_move(t.id, v_to, new.sent_on, v_note, new.id);
  end if;
  return null;
exception when others then
  return null;
end $$;
revoke all on function public.sm_reports_brand_task() from public, anon, authenticated;

create or replace function public.ops_transition_task(
  p_task uuid, p_next text, p_version integer default null, p_note text default null,
  p_assignee uuid default null, p_skip_reason text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  m   public.team_members;
  t   public.ops_tasks;
  cur public.ops_workflow_stages;
  nxt public.ops_workflow_stages;
  sk  public.ops_workflow_stages;
  eng public.ops_engagements;
  has_owner boolean;
  has_draft boolean;
  has_final boolean;
  was_owner uuid;
  side text[] := array['blocked', 'waiting', 'kiv', 'cancelled'];
  skipping boolean := false;
  going_back boolean := false;
  ws  public.ops_work_sessions;
  wmins integer;
  v_round integer;
  held text[] := array['on_hold', 'blocked', 'cancelled'];
  resume_to text[];
  first_key text;
  resuming boolean := false;
  by_client boolean := false;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if not public.ops_may_see_task(p_task) then return jsonb_build_object('error', 'denied'); end if;
  if not public.allowed('ops', 'work') then return jsonb_build_object('error', 'denied'); end if;

  select * into t from public.ops_tasks where id = p_task for update;
  if t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_version is not null and p_version <> t.version then
    return jsonb_build_object('error', 'stale', 'task', public.ops_task_json(p_task));
  end if;
  if t.stage_key = p_next then return public.ops_task_json(p_task); end if;
  /* The stage is the owner's to move. Once a task is handed to somebody,
     whoever created it or held it before reads it and no longer moves it; an
     admin still may. */
  if not public.ops_owner_may_move(p_task) then return jsonb_build_object('error', 'not-owner'); end if;

  cur := public.ops_stage(t.workflow_id, t.stage_key);
  nxt := public.ops_stage(t.workflow_id, p_next);
  if nxt.id is null then return jsonb_build_object('error', 'no-such-stage'); end if;
  /* A retired stage keeps the tasks already standing on it and takes no new
     ones: Planning and the content meeting are the month's, not a task's. */
  if nxt.retired then return jsonb_build_object('error', 'retired-stage'); end if;
  /* A task on hold, blocked or cancelled goes back to the stage it left
     (held_from, stamped by ops_tasks_held_from), and a cancelled one also
     to the start of the line; never on past stages it had not reached
     (the user, 2026-10-18: keep it light, AQC review happens on WhatsApp).
     Moving between the three is a step as before. A task held before the
     column knew where from keeps the steps of its workflow. */
  if cur.key = any (held) and not (p_next = any (held)) and t.held_from is not null then
    select s.key into first_key from public.ops_workflow_stages s
     where s.workflow_id = t.workflow_id and not s.retired
       and not (s.stage_group = any (side)) and s.stage_group <> 'revision'
       and not (s.key = any (held))
     order by s.position limit 1;
    resume_to := array[t.held_from];
    if cur.key = 'cancelled' or coalesce((public.ops_stage(t.workflow_id, t.held_from)).retired, true) then
      resume_to := resume_to || first_key;
    end if;
    if not (p_next = any (resume_to)) then
      return jsonb_build_object('error', 'held-resume', 'allowed', to_jsonb(resume_to));
    end if;
    resuming := true;
  end if;
  /* Content the client posts has no Live stage and no performance review
     of ours: Scheduled leads straight to Completed, a step and never a skip
     (CLIENT POSTS, 2026-11-22). */
  if coalesce(t.client_posts, false) then
    if p_next in ('live', 'performance_review') then
      return jsonb_build_object('error', 'client-posts');
    end if;
    by_client := cur.key = 'scheduled' and p_next = 'completed';
  end if;
  if not resuming and not by_client and not (p_next = any (cur.next_stage_keys)) then
    /* A step the deliverable does not need is skipped, forward along the
       line, with a reason on the record: who skipped it and why is written
       against every stage that was passed over. Nothing beside the line can
       be skipped into or out of, and nothing is skipped backwards. */
    /* A revision is where work is sent back from a review, so it is never
       a step somebody skips forward into. */
    if not (cur.stage_group = any (side)) and not (nxt.stage_group = any (side))
       and nxt.stage_group <> 'revision'
       and nxt.position > cur.position then
      if nullif(btrim(coalesce(p_skip_reason, '')), '') is null then
        return jsonb_build_object('error', 'skip-reason-required');
      end if;
      skipping := true;
    /* Going back is picking an earlier stage on the line, and says why; the
       reason goes on the record with the move. A revision is entered only
       from the review that sends work to it. */
    elsif not (cur.stage_group = any (side)) and not (nxt.stage_group = any (side))
       and nxt.stage_group <> 'revision'
       and nxt.position < cur.position then
      if nullif(btrim(coalesce(p_note, '')), '') is null then
        return jsonb_build_object('error', 'back-reason-required');
      end if;
      going_back := true;
    else
      return jsonb_build_object('error', 'bad-transition',
        'allowed', to_jsonb(cur.next_stage_keys));
    end if;
  end if;

  /* A performance review goes back to whoever created the task unless the
     move names somebody else. */
  if p_next = 'performance_review' and p_assignee is null and exists (
       select 1 from public.team_members where id = t.created_by and active) then
    p_assignee := t.created_by;
  end if;

  -- What each gate needs before it opens.
  has_owner := exists (select 1 from public.ops_task_assignees
                        where task_id = p_task and responsibility = 'owner' and ended_at is null)
               or p_assignee is not null;
  has_draft := exists (select 1 from public.ops_task_links
                        where task_id = p_task and archived_at is null
                          and kind in ('draft', 'review'));
  has_final := exists (select 1 from public.ops_task_links
                        where task_id = p_task and archived_at is null and kind = 'final');

  if p_next = 'ready' and (not has_owner or t.current_final_due_at is null) then
    return jsonb_build_object('error', 'ready-needs-owner-and-due');
  end if;
  if p_next = 'editing' and exists (
       select 1 from public.ops_video_details v
        where v.task_id = p_task and v.footage_ready is false) then
    return jsonb_build_object('error', 'footage-not-ready');
  end if;
  /* Production waits on the month's own facts: its readiness ticks
     answered, and its content meeting held or marked not applicable. The
     month's stage is worked out from those facts on the page and is never
     stored, so the stored status is not read here (2026-09-27). A task with
     no month (ad hoc, internal) has nothing to wait on. */
  if p_next = 'in_production' and t.engagement_id is not null then
    select * into eng from public.ops_engagements where id = t.engagement_id;
    if exists (select 1 from public.ops_engagement_checks c
                where c.engagement_id = eng.id
                  and c.state in ('not_started', 'waiting_client', 'in_progress')) then
      return jsonb_build_object('error', 'planning-incomplete');
    end if;
    if not (eng.meeting_na or (eng.meeting_at is not null and eng.meeting_at <= now())) then
      return jsonb_build_object('error', 'meeting-required');
    end if;
  end if;
  /* AQC review comes first: the client sees the work only once it has been
     through AQC review at least once. */
  if p_next = 'client_review'
     and exists (select 1 from public.ops_workflow_stages s
                  where s.workflow_id = t.workflow_id and s.key = 'internal_review')
     and not exists (select 1 from public.ops_task_events e
                      where e.task_id = p_task and e.event_type = 'stage_changed'
                        and e.to_value ->> 'stage_key' = 'internal_review') then
    return jsonb_build_object('error', 'needs-aqc');
  end if;
  /* The draft reaches the client as a link on the task or through the
     team's WhatsApp group with the client. Either way the record says how:
     the link, or a note naming where it went. */
  if p_next = 'client_review' and not has_draft
     and nullif(btrim(coalesce(p_note, '')), '') is null then
    return jsonb_build_object('error', 'needs-draft');
  end if;
  /* A revision says what has to change, and so does taking a post down. */
  if ((nxt.stage_group = 'revision' and p_next <> 'changes_requested') or p_next = 'taken_down')
     and nullif(btrim(coalesce(p_note, '')), '') is null then
    return jsonb_build_object('error', 'note-required');
  end if;
  /* After approval: a schedule needs its date, going live is confirmed with
     its own date through ops_mark_live and needs the post's link or a note,
     and a task is completed only once its performance checklist is done. */
  if p_next = 'scheduled' and t.publish_at is null then
    return jsonb_build_object('error', 'needs-schedule');
  end if;
  if p_next = 'live' and t.live_at is null then
    return jsonb_build_object('error', 'needs-live-date');
  end if;
  if p_next = 'live' and not has_final and coalesce(p_note, '') = '' then
    return jsonb_build_object('error', 'needs-final-or-reason');
  end if;
  if p_next = 'completed' and exists (
       select 1 from public.ops_task_checklist_items c
        where c.task_id = p_task and c.required and c.completed_at is null) then
    return jsonb_build_object('error', 'checklist-incomplete');
  end if;
  if p_next = 'delivered' and not has_final then
    return jsonb_build_object('error', 'needs-final-link');
  end if;
  if p_next = 'done' and t.delivered_at is null
     and coalesce(p_note, '') = '' then
    return jsonb_build_object('error', 'needs-delivery-or-reason');
  end if;
  if p_next = 'published' and not has_final and coalesce(p_note, '') = '' then
    return jsonb_build_object('error', 'needs-final-or-reason');
  end if;

  /* The hand to the next person, recorded on the move: the previous owner
     ends, the new one begins, and the event names both with the stage it
     happened at. Work level, because handing the work on is part of doing
     it; reassigning a task without moving it stays Manage. */
  if p_assignee is not null then
    select team_member_id into was_owner from public.ops_task_assignees
     where task_id = p_task and responsibility = 'owner' and ended_at is null;
    if p_assignee is distinct from was_owner then
      if not exists (select 1 from public.team_members where id = p_assignee and active) then
        return jsonb_build_object('error', 'no-such-person');
      end if;
      update public.ops_task_assignees set ended_at = now()
       where task_id = p_task and responsibility = 'owner' and ended_at is null;
      insert into public.ops_task_assignees (task_id, team_member_id, responsibility, assigned_by)
      values (p_task, p_assignee, 'owner', m.id);
      perform public.ops_log(p_task, 'assignment_changed',
        jsonb_build_object('owner_id', was_owner),
        jsonb_build_object('owner_id', p_assignee),
        jsonb_build_object('handover', true, 'stage_key', p_next, 'from_stage_key', t.stage_key));
    end if;
  end if;

  if skipping then
    for sk in select * from public.ops_workflow_stages
               where workflow_id = t.workflow_id
                 and position > cur.position and position < nxt.position
                 and not (stage_group = any (side))
                 and stage_group <> 'revision' and not retired
                 and not (coalesce(t.client_posts, false) and key in ('live', 'performance_review'))
               order by position loop
      perform public.ops_log(p_task, 'stage_skipped',
        jsonb_build_object('stage_key', sk.key), jsonb_build_object('stage_key', p_next),
        jsonb_build_object('reason', btrim(p_skip_reason)));
    end loop;
  end if;

  /* The round: how many times this task has now entered this review or
     this revision, counted off its own history, so nothing is stored that
     a reverted move could leave wrong. */
  if nxt.is_review or nxt.stage_group = 'revision' then
    select count(*) + 1 into v_round from public.ops_task_events e
     where e.task_id = p_task and e.event_type = 'stage_changed'
       and e.to_value ->> 'stage_key' = p_next;
  end if;

  update public.ops_tasks set
    stage_key = p_next,
    version = version + 1,
    updated_at = now(),
    first_draft_submitted_at = case
      when first_draft_submitted_at is null and nxt.is_review then now()
      else first_draft_submitted_at end,
    delivered_at = case when p_next = 'delivered' then coalesce(delivered_at, now())
                        else delivered_at end,
    completed_at = case when nxt.is_terminal and p_next <> 'cancelled' then coalesce(completed_at, now())
                        when not nxt.is_terminal then null
                        else completed_at end,
    /* Leaving Cancelled for a live stage is a reopening, and the stamp
       leaves with it, as completed_at does; left behind, the task went on
       reading cancelled at the stage it had been reopened to. */
    cancelled_at = case when p_next = 'cancelled' then coalesce(cancelled_at, now())
                        when not nxt.is_terminal then null
                        else cancelled_at end,
    blocked_at = case when p_next = 'blocked' then blocked_at else null end,
    blocked_category = case when p_next = 'blocked' then blocked_category else null end
  where id = p_task;

  /* The performance review brings its own checklist, the same five checks
     for a brand post and a KOC post, added once however often the task
     comes back to the stage. */
  if p_next = 'performance_review' then
    insert into public.ops_task_checklist_items (task_id, label, position, required)
    select p_task, x.label,
           coalesce((select max(c.position) from public.ops_task_checklist_items c
                      where c.task_id = p_task), 0) + x.n,
           true
      from (values (1, 'Reach and views checked'),
                   (2, 'Engagement checked (likes, comments, shares, saves)'),
                   (3, 'Comments checked for brand safety'),
                   (4, 'Leads or sales checked, where tracked'),
                   (5, 'Decision made to keep the post live or take it down')) as x(n, label)
     where not exists (select 1 from public.ops_task_checklist_items c
                        where c.task_id = p_task and c.label = x.label);
  end if;

  /* A finished task is not being worked on, so every timer running on it
     stops with it, each filed as the stop it is. */
  if nxt.is_terminal then
    for ws in select * from public.ops_work_sessions
               where task_id = p_task and ended_at is null loop
      wmins := greatest(0, (extract(epoch from (now() - ws.started_at)) / 60)::integer);
      update public.ops_work_sessions set ended_at = now(), minutes = wmins where id = ws.id;
      perform public.ops_log(p_task, 'work_stopped', null,
        jsonb_build_object('session_id', ws.id, 'minutes', wmins),
        jsonb_build_object('note', 'Stopped when the task finished'));
    end loop;
  end if;

  perform public.ops_log(p_task, 'stage_changed',
    jsonb_build_object('stage_key', t.stage_key),
    jsonb_build_object('stage_key', p_next),
    (case when p_note is null then '{}'::jsonb else jsonb_build_object('note', p_note) end)
    || (case when skipping then jsonb_build_object('skip_reason', btrim(p_skip_reason)) else '{}'::jsonb end)
    || (case when going_back then jsonb_build_object('back', true) else '{}'::jsonb end)
    || (case when v_round is not null then jsonb_build_object('round', v_round) else '{}'::jsonb end));
  if p_next = 'delivered' then
    perform public.ops_log(p_task, 'delivered', null, null, '{}'::jsonb);
  end if;
  if nxt.is_terminal and p_next <> 'cancelled' then
    perform public.ops_log(p_task, 'completed', null, null, '{}'::jsonb);
  end if;
  if p_next = 'cancelled' then
    perform public.ops_log(p_task, 'cancelled', null, null,
      jsonb_build_object('reason', p_note));
  end if;
  return public.ops_task_json(p_task);
end $$;
grant execute on function public.ops_transition_task(uuid, text, integer, text, uuid, text) to authenticated;

create or replace function public.hiring_decide(p_id uuid, p_outcome text, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_role text := public.hiring_role(p_id);
  c public.hiring_candidates;
  v_back text;
begin
  if v_role is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_role not in ('admin', 'owner') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_outcome, '') not in ('proceed', 'pool', 'not', 'reopen') then return jsonb_build_object('error', 'bad-outcome'); end if;
  if char_length(coalesce(p_note, '')) > 1000 then return jsonb_build_object('error', 'too-long'); end if;
  select * into c from public.hiring_candidates where id = p_id for update;
  if c.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if c.stage = 'hired' then return jsonb_build_object('error', 'closed'); end if;
  if p_outcome = 'reopen' then
    if c.outcome is null then return jsonb_build_object('ok', true, 'same', true); end if;
    v_back := case when exists (select 1 from public.hiring_interviews i where i.candidate_id = c.id and i.state = 'confirmed') then 'interview'
      when exists (select 1 from public.hiring_interviews i where i.candidate_id = c.id and i.state in ('invited', 'picked', 'none')) then 'invited'
      else 'new' end;
    update public.hiring_candidates set stage = v_back, outcome = null, outcome_note = null, outcome_by = null, outcome_at = null,
      pool_consent = null, pool_until = null, outcome_mail = null, outcome_mail_at = null,
      decide_by = null, decide_note = null, decide_soon_at = null, decide_due_at = null, decide_moved_at = null, last_step_at = now(), updated_at = now()
     where id = c.id;
    update public.hiring_docs set state = 'withdrawn', updated_at = now() where candidate_id = c.id and state = 'sent';
    perform public.hiring_log(c.id, 'candidate.decided', 'Reopened');
    return jsonb_build_object('ok', true, 'was', c.outcome, 'note', c.outcome_note);
  end if;
  if c.outcome = p_outcome then return jsonb_build_object('ok', true, 'same', true); end if;
  update public.hiring_candidates set
    stage = case p_outcome when 'proceed' then 'offer' when 'pool' then 'pool' else 'closed' end,
    outcome = p_outcome, outcome_note = nullif(btrim(coalesce(p_note, '')), ''), outcome_by = me.id, outcome_at = now(),
    pool_consent = case when p_outcome = 'pool' then 'asked' end, pool_until = null, outcome_mail = null, outcome_mail_at = null,
    decide_by = null, decide_note = null, decide_soon_at = null, decide_due_at = null, decide_moved_at = null,
    last_step_at = now(), updated_at = now()
   where id = c.id;
  update public.hiring_interviews set state = 'cancelled', updated_at = now()
   where candidate_id = c.id and p_outcome <> 'proceed' and (state in ('invited', 'picked', 'none') or (state = 'confirmed' and held_at is null));
  update public.hiring_docs set state = 'withdrawn', updated_at = now()
   where candidate_id = c.id and p_outcome <> 'proceed' and state = 'sent';
  perform public.hiring_log(c.id, 'candidate.decided',
    case p_outcome when 'proceed' then 'Proceed' when 'pool' then 'Keep in talent pool' else 'Do not proceed' end);
  return jsonb_build_object('ok', true, 'was', c.outcome, 'email', p_outcome in ('pool', 'not'));
end $$;
grant execute on function public.hiring_decide(uuid, text, text) to authenticated;

create or replace function public.hiring_email_templates_save(p_rows jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me      public.team_members := public.ops_me();
  x       jsonb;
  t       public.hiring_email_templates;
  v_bad   jsonb;
  v_moved text[] := '{}';
  v_word  text;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  for x in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    select * into t from public.hiring_email_templates y where y.kind = x->>'kind' for update;
    if t.kind is null then return jsonb_build_object('error', 'bad-request'); end if;
    if length(btrim(coalesce(x->>'subject', ''))) < 3 or length(x->>'subject') > 200 then
      return jsonb_build_object('error', 'bad-subject', 'kind', t.kind);
    end if;
    if length(btrim(coalesce(x->>'body', ''))) < 10 or length(x->>'body') > 5000 then
      return jsonb_build_object('error', 'bad-body', 'kind', t.kind);
    end if;
    v_bad := public.template_check(coalesce(x->>'subject', '') || ' ' || coalesce(x->>'body', ''), 'candidate');
    if v_bad is not null then return v_bad || jsonb_build_object('kind', t.kind); end if;
    if (t.on_send, t.subject, t.body) is distinct from
       (coalesce((x->>'on')::boolean, true), btrim(x->>'subject'), btrim(x->>'body')) then
      v_word := case t.kind when 'invite' then 'Interview invitation' when 'confirm' then 'Interview confirmed'
        when 'rescheduled' then 'Interview time changed'
        when 'cancelled' then 'Interview cancelled' when 'held' then 'Thank you for your interview'
        when 'moved' then 'Decision date changed' when 'pool' then 'Talent pool' when 'not' then 'Application unsuccessful'
        when 'doc' then 'Employment document' when 'doc_again' then 'Employment document sent again'
        when 'confirmed' then 'Document confirmed' else 'Document expired' end;
      v_moved := v_moved || (v_word ||
        case when t.on_send is distinct from coalesce((x->>'on')::boolean, true)
             then ': ' || case when t.on_send then 'Sent → Not sent' else 'Not sent → Sent' end
             else ': wording changed' end);
      update public.hiring_email_templates y set on_send = coalesce((x->>'on')::boolean, true), subject = btrim(x->>'subject'),
        body = btrim(x->>'body'), updated_at = now(), updated_by = me.id where y.kind = t.kind;
    end if;
  end loop;
  if cardinality(v_moved) > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Candidate emails', array_to_string(v_moved, ' · '));
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.hiring_email_templates_save(jsonb) from public, anon;
grant execute on function public.hiring_email_templates_save(jsonb) to authenticated;

create or replace function public.bukku_take(p_actor uuid, p_kind text, p_id uuid, p_values jsonb, p_hash text,
                                             p_changed text[], p_mode text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  l public.bukku_links; p jsonb; k public.client_contacts;
  v_ent uuid; v_who text; v_name text; v_detail text; v_bc uuid; v_bc_set boolean := false;
  v_changed text[] := coalesce(p_changed, '{}');
  v_open text[];
  v_words constant jsonb := '{"legal_name": "Registered Company Name", "company_no": "Business Registration No.",
    "company_no_old": "Old Registration No.", "tin": "TIN", "sst_no": "SST Registration No.",
    "finance_email": "Finance email", "billing_address": "Billing address", "person": "Billing contact"}';
  v_t text;
  v_new boolean := false;
  s public.suppliers; v_company boolean; v_fields text[];
  v_sw constant jsonb := '{"legal_name": "Name", "company_no": "BRN", "tin": "TIN",
    "sst_no": "SST Registration No.", "person": "Person in charge", "finance_email": "Finance email",
    "billing_address": "Billing address"}';
begin
  if p_kind not in ('client', 'entity', 'supplier') or p_mode not in ('read', 'hold', 'save')
     or (p_kind = 'supplier' and p_mode = 'save')
     or jsonb_typeof(p_values) is distinct from 'object' then
    return jsonb_build_object('error', 'bad-request');
  end if;
  l := public.bukku_link_row(p_kind, p_id);
  if l.contact_id is null then return jsonb_build_object('error', 'not-linked'); end if;
  p := public.bukku_portal(p_kind, p_id);
  if p is null then return jsonb_build_object('error', 'not-found'); end if;
  select array_agg(f) into v_changed from unnest(v_changed) f where v_words ? f;
  v_changed := coalesce(v_changed, '{}');
  select array_agg(f) into v_open from unnest(v_changed) f
   where nullif(btrim(coalesce(p->>f, '')), '') is not null;
  v_open := coalesce(v_open, '{}');
  update public.bukku_links x set read_at = now(), read_hash = left(p_hash, 200),
         person = nullif(left(btrim(coalesce(p_values->>'person', '')), 120), '')
   where x.kind = l.kind and x.record_id = l.record_id;
  /* A supplier (2026-11-22): its details stay the portal's. A read writes
     nothing and says what differs, the link held only while nothing does;
     Use Bukku's writes the differing fields alone, never an NRIC or the
     bank details. */
  if p_kind = 'supplier' then
    select * into s from public.suppliers x where x.id = p_id;
    v_company := coalesce(s.kind, 'company') = 'company';
    select array_agg(f) into v_fields from jsonb_array_elements_text(coalesce(p->'fields', '[]'::jsonb)) f;
    select array_agg(f) into v_changed from unnest(v_changed) f where f = any(coalesce(v_fields, '{}'));
    v_changed := coalesce(v_changed, '{}');
    if p_mode = 'read' and cardinality(v_changed) > 0 then
      return jsonb_build_object('ok', true, 'held', false, 'differs', to_jsonb(v_changed));
    end if;
    if cardinality(v_changed) > 0 then
      update public.suppliers x
         set name = case when 'legal_name' = any(v_changed)
                         then coalesce(public.bukku_name_case(p_values->>'legal_name', v_company), x.name) else x.name end,
             brn = case when v_company and 'company_no' = any(v_changed)
                        then nullif(regexp_replace(coalesce(p_values->>'company_no', ''), '[^0-9A-Za-z]', '', 'g'), '') else x.brn end,
             tin = case when 'tin' = any(v_changed) then nullif(btrim(coalesce(p_values->>'tin', '')), '') else x.tin end,
             sst_no = case when 'sst_no' = any(v_changed) then nullif(btrim(coalesce(p_values->>'sst_no', '')), '') else x.sst_no end,
             finance_email = case when 'finance_email' = any(v_changed)
                                  then nullif(lower(btrim(coalesce(p_values->>'finance_email', ''))), '') else x.finance_email end,
             address = case when 'billing_address' = any(v_changed) then nullif(btrim(coalesce(p_values->>'billing_address', '')), '') else x.address end,
             contact_name = case when 'person' = any(v_changed)
                                 then nullif(public.bukku_name_case(p_values->>'person', false), '') else x.contact_name end,
             updated_at = clock_timestamp()
       where x.id = p_id;
      select string_agg(v_sw->>f, ', ' order by array_position(array['legal_name', 'company_no', 'tin', 'sst_no',
               'person', 'finance_email', 'billing_address'], f))
        into v_t from unnest(v_changed) f;
      select x.name into v_who from public.team_members x where x.id = p_actor;
      select coalesce(x.name, x.code) into v_name from public.suppliers x where x.id = p_id;
      insert into public.activity_log (actor, action, subject, detail)
      values (coalesce(v_who, 'Bukku'), 'supplier.edited', v_name,
              coalesce(s.code || ' · ', '') || 'Used Bukku''s details: ' || v_t || ' · ' || coalesce(l.code, l.contact_id::text));
    end if;
    update public.bukku_links x set held_at = coalesce(x.held_at, now())
     where x.kind = l.kind and x.record_id = l.record_id;
    return jsonb_build_object('ok', true, 'held', true, 'changed', to_jsonb(v_changed), 'person_in', true);
  end if;
  /* The first read of a link not yet held writes nothing over a detail
     the portal holds: it waits on Send to Bukku or Use Bukku's. */
  if p_mode = 'read' and l.held_at is null and cardinality(v_open) > 0 then
    return jsonb_build_object('ok', true, 'held', false, 'differs', to_jsonb(v_changed));
  end if;

  if p_kind = 'client' then
    v_ent := public.client_main_entity(p_id);
    if v_ent is null then
      insert into public.billing_entities (legal_name) values (nullif(btrim(coalesce(p_values->>'legal_name', '')), ''))
      returning id into v_ent;
      insert into public.client_entities (client_id, entity_id, is_main) values (p_id, v_ent, true);
      v_new := true;
    end if;
  else
    v_ent := p_id;
  end if;
  if p_values ? 'person' and nullif(btrim(coalesce(p_values->>'person', '')), '') is not null then
    k := public.bukku_person_contact(p_kind, p_id, p_values->>'person');
    if k.id is not null then
      v_bc_set := true;
      v_bc := case when k.is_primary and k.client_id = coalesce(case when p_kind = 'client' then p_id end,
                                                                public.entity_home_client(p_id)) then null else k.id end;
    end if;
  end if;
  update public.billing_entities e
     set legal_name = case when p_values ? 'legal_name' and ('legal_name' = any(v_changed) or nullif(btrim(coalesce(e.legal_name, '')), '') is null)
                           then nullif(upper(btrim(regexp_replace(coalesce(p_values->>'legal_name', ''), '\s+', ' ', 'g'))), '')
                           else e.legal_name end,
         company_no = case when p_values ? 'company_no' and ('company_no' = any(v_changed) or nullif(btrim(coalesce(e.company_no, '')), '') is null) then nullif(btrim(coalesce(p_values->>'company_no', '')), '') else e.company_no end,
         company_no_old = case when p_values ? 'company_no_old' and ('company_no_old' = any(v_changed) or nullif(btrim(coalesce(e.company_no_old, '')), '') is null) then nullif(btrim(coalesce(p_values->>'company_no_old', '')), '') else e.company_no_old end,
         tin = case when p_values ? 'tin' and ('tin' = any(v_changed) or nullif(btrim(coalesce(e.tin, '')), '') is null) then nullif(btrim(coalesce(p_values->>'tin', '')), '') else e.tin end,
         sst_no = case when p_values ? 'sst_no' and ('sst_no' = any(v_changed) or nullif(btrim(coalesce(e.sst_no, '')), '') is null) then nullif(btrim(coalesce(p_values->>'sst_no', '')), '') else e.sst_no end,
         finance_email = case when p_values ? 'finance_email' and ('finance_email' = any(v_changed) or nullif(btrim(coalesce(e.finance_email, '')), '') is null) then nullif(lower(btrim(coalesce(p_values->>'finance_email', ''))), '') else e.finance_email end,
         billing_address = case when p_values ? 'billing_address' and ('billing_address' = any(v_changed) or nullif(btrim(coalesce(e.billing_address, '')), '') is null) then nullif(btrim(coalesce(p_values->>'billing_address', '')), '') else e.billing_address end,
         bill_contact_id = case when v_bc_set then v_bc else e.bill_contact_id end,
         updated_at = case when cardinality(v_changed) > 0 or v_new
                             or (v_bc_set and v_bc is distinct from e.bill_contact_id)
                           then clock_timestamp() else e.updated_at end
   where e.id = v_ent;
  -- A client's first entity, made here, is carried to the client's own
  -- columns (audit 2026-10-30: the update changed nothing, so the mirror
  -- never ran).
  if v_new then perform public.billing_entity_put(v_ent, p_id); end if;
  update public.bukku_links x set held_at = coalesce(x.held_at, now())
   where x.kind = l.kind and x.record_id = l.record_id;

  if cardinality(v_changed) > 0 then
    select string_agg(v_words->>f, ', ' order by array_position(array['legal_name', 'company_no', 'company_no_old', 'tin', 'sst_no',
             'person', 'finance_email', 'billing_address'], f))
      into v_t from unnest(v_changed) f;
    select x.name into v_who from public.team_members x where x.id = p_actor;
    v_detail := case p_mode when 'read' then 'Read from Bukku: ' when 'save' then 'Saved to Bukku: ' else 'Used Bukku''s details: ' end
                || v_t || ' · ' || coalesce(l.code, l.contact_id::text);
    v_who := case when p_mode = 'read' then 'Bukku' else coalesce(v_who, 'Bukku') end;
    if p_kind = 'entity' then
      perform public.bukku_file_entity(p_id, v_who, v_detail);
    else
      select x.name into v_name from public.clients x where x.id = p_id;
      insert into public.activity_log (actor, action, subject, detail) values (v_who, 'client.billing', v_name, v_detail);
    end if;
  end if;
  return jsonb_build_object('ok', true, 'held', true, 'changed', to_jsonb(v_changed),
    'person_in', v_bc_set or nullif(btrim(coalesce(p_values->>'person', '')), '') is null);
end $$;
revoke all on function public.bukku_take(uuid, text, uuid, jsonb, text, text[], text) from public, anon, authenticated;
grant execute on function public.bukku_take(uuid, text, uuid, jsonb, text, text[], text) to service_role;

update public.ops_task_checklist_items set label = 'Decision made to keep the post live or take it down'
 where label = 'Keep live or take down decided';
update public.hiring_email_templates set subject = 'Decision date changed: {position}'
 where kind = 'moved' and subject = 'Decision date updated: {position}';

-- END OF TONE SWEEP 6 --------------------------------------------------------
select public.functions_tidy();
