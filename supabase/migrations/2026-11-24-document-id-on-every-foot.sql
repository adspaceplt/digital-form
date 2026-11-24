-- ===========================================================================
-- DOCUMENT ID ON EVERY FOOT (2026-11-24)
-- ===========================================================================
-- WHY (the user, 2026-11-24): "does all pdf footer being updated? with
-- Document ID | Verify document | Page x of x". The Social Media Report and
-- the Video Script PDF went to clients with no Document ID, so /verify/
-- could not answer them.
--
-- WHAT CHANGED
--   * `sm_report_versions.doc_code` and `video_scripts.doc_code`, stamped on
--     insert as every other document's (`doc_code_new` takes both tables),
--     unique in each; a published version's snapshot carries its code
--     (`sm_report_version_code`), so every copy drawn from it prints it;
--     every script standing takes its code once.
--   * `verify_find`: a report version or a shared script is found by its
--     Document ID typed as the reference (`by_code`), answered as Social
--     Media Accounts Report, Social Media Advertising Report or Video
--     Script, never a name; `verify_by_day` never lets a name stand for
--     such a code; `verify_serial` answers `by_code`, so the page opens the
--     details with the code typed.
--   * `doc_code_of` answers `report` (a version's id) and `script`;
--     `doc_code_of_key` answers `script` for its client's script link.
--
-- ORDER: this file (connector), then the pages. An old open tab reads the
-- new column through `select *` and draws no code; an old /verify/ page
-- asks for the code a second time. Safe to run twice.
-- ROLLBACK: run `verify_find` from VERIFY NAMES HELD
-- TO THE ADDRESSEE, `verify_serial`, `doc_code_of`,
-- `doc_code_of_key` from VERIFY BY THE NAME ADDRESSED TO, `verify_by_day`
-- and `doc_code_new` from VERIFY DETAILS again; the columns, the indexes
-- and the triggers may stay.
-- ===========================================================================

-- DOCUMENT ID ON EVERY FOOT ---------------------------------------------------

/* A Document ID: eight characters of the link alphabet, unique in its
   table. A report version and a video script take one too (2026-11-24). */
create or replace function public.doc_code_new(p_table text)
returns text language plpgsql volatile set search_path = public, extensions as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  v_out   text;
  v_bytes bytea;
  v_i     integer;
  v_b     integer;
  v_taken boolean;
begin
  if p_table not in ('documents', 'client_documents', 'quotations', 'hiring_docs', 'perf_reviews', 'sm_report_versions', 'video_scripts') then
    raise exception 'bad-table';
  end if;
  loop
    v_out := '';
    while length(v_out) < 8 loop
      v_bytes := gen_random_bytes(16);
      for v_i in 0..15 loop
        v_b := get_byte(v_bytes, v_i);
        /* 248 is 31 × 8: below it every character is equally likely. */
        if v_b < 248 and length(v_out) < 8 then
          v_out := v_out || substr(alphabet, 1 + (v_b % 31), 1);
        end if;
      end loop;
    end loop;
    execute format('select exists (select 1 from public.%I x where x.doc_code = $1)', p_table) into v_taken using v_out;
    exit when not v_taken;
  end loop;
  return v_out;
end $$;
revoke all on function public.doc_code_new(text) from public, anon, authenticated;

alter table public.sm_report_versions add column if not exists doc_code text;
alter table public.video_scripts      add column if not exists doc_code text;
create unique index if not exists sm_report_versions_doc_code_idx on public.sm_report_versions (doc_code) where doc_code is not null;
create unique index if not exists video_scripts_doc_code_idx      on public.video_scripts (doc_code) where doc_code is not null;

/* A version is stamped as it is published, and its snapshot carries the
   code, so the file kept, the client's copy and every redraw print it. */
create or replace function public.sm_report_version_code()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.doc_code is null then new.doc_code := public.doc_code_new('sm_report_versions'); end if;
  if jsonb_typeof(new.snapshot) = 'object' then
    new.snapshot := new.snapshot || jsonb_build_object('doc_code', new.doc_code);
  end if;
  return new;
end $$;
revoke all on function public.sm_report_version_code() from public, anon, authenticated;
create or replace trigger sm_report_version_code before insert on public.sm_report_versions for each row execute function public.sm_report_version_code();
create or replace trigger doc_code_stamp before insert on public.video_scripts for each row execute function public.doc_code_stamp();

/* Every script standing takes its code once. Its own update triggers
   stand aside for the backfill alone, each put back as it was. */
do $$
declare
  g record;
  v_off text[] := '{}';
begin
  if not exists (select 1 from public.video_scripts x where x.doc_code is null) then return; end if;
  for g in select tg.tgname from pg_trigger tg
            where tg.tgrelid = 'public.video_scripts'::regclass and not tg.tgisinternal and tg.tgenabled = 'O'
  loop
    execute format('alter table public.video_scripts disable trigger %I', g.tgname);
    v_off := v_off || g.tgname::text;
  end loop;
  update public.video_scripts x set doc_code = public.doc_code_new('video_scripts') where x.doc_code is null;
  foreach g.tgname in array v_off loop
    execute format('alter table public.video_scripts enable trigger %I', g.tgname);
  end loop;
end $$;

/* The names a document is addressed to: the registered company name, the
   person it names and its contact; never a brand or trading name, which
   is public. */
create or replace function public.verify_find(p_serial text)
returns jsonb
language plpgsql stable set search_path = public as $$
declare
  s text := upper(btrim(coalesce(p_serial, '')));
  sd text;
  d public.documents%rowtype;
  l public.client_documents%rowtype;
  q public.quotations%rowtype;
  h public.hiring_docs%rowtype;
  rv public.perf_reviews%rowtype;
  dl public.perf_deleted%rowtype;
  rp public.sm_report_versions%rowtype;
  vs public.video_scripts%rowtype;
  v_code text;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_state text;
  v_rep date;
begin
  if length(s) < 3 or length(s) > 40 then return null; end if;
  sd := replace(s, '/', '-');
  select * into d from public.documents x
   where upper(replace(x.serial, '/', '-')) = sd
   order by (upper(x.serial) = s) desc, (x.voided_at is null) desc, x.created_at desc limit 1;
  if d.id is not null then
    return jsonb_build_object('src', 'document', 'id', d.id, 'serial', d.serial,
      'kind', case when d.family = 'hr' then 'HR Letter' else d.kind end,
      'issued', d.issued_at, 'code', d.doc_code, 'sealed', false,
      'names', public.verify_names(array[d.recipient ->> 'name',
        (select c.legal_name from public.clients c where c.id = d.client_id),
        (select m.name from public.team_members m where m.id = d.member_id),
        (select coalesce(nullif(to_jsonb(u) ->> 'legal_name', ''), to_jsonb(u) ->> 'name') from public.suppliers u where u.id = d.supplier_id)]),
      'state', case when d.voided_at is null then 'valid' else 'voided' end,
      'steps', public.verify_steps(jsonb_build_array(
        jsonb_build_object('step', 'issued', 'day', d.issued_at),
        jsonb_build_object('step', 'voided', 'day', (d.voided_at at time zone 'Asia/Kuala_Lumpur')::date))));
  end if;
  select * into l from public.client_documents x
   where upper(replace(x.number, '/', '-')) = sd
   order by (upper(x.number) = s) desc limit 1;
  if l.id is not null then
    select x.issued_at into v_rep
      from public.client_documents x where x.id = l.superseded_by;
    return jsonb_build_object('src', 'letter', 'id', l.id, 'serial', l.number, 'kind', 'Letter of Offer',
      'issued', l.issued_at, 'code', l.doc_code, 'sealed', false,
      'names', public.verify_names(array[coalesce(nullif(l.bill_to ->> 'legal_name', ''), l.bill_to ->> 'name'), l.bill_to ->> 'contact',
        (select c.legal_name from public.clients c where c.id = l.client_id)]),
      'state', case when l.voided_at is not null then 'voided'
                    when l.superseded_by is not null then 'replaced'
                    else 'valid' end,
      'steps', public.verify_steps(jsonb_build_array(
        jsonb_build_object('step', 'issued', 'day', l.issued_at),
        jsonb_build_object('step', 'signed', 'day', (l.signed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'confirmed', 'day', (l.verified_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'replaced', 'day', v_rep),
        jsonb_build_object('step', 'voided', 'day', (l.voided_at at time zone 'Asia/Kuala_Lumpur')::date))));
  end if;
  select * into q from public.quotations x
   where (upper(replace(x.ref, '/', '-')) = sd)
     and (x.sent_out_at is not null or x.signed_at is not null)
   order by (upper(x.ref) = s) desc, x.issued_at desc limit 1;
  if q.id is not null then
    select (min(r.issued_at) at time zone 'Asia/Kuala_Lumpur')::date into v_rep
      from public.quotations r where r.replaces = q.id and r.removed_at is null;
    v_state := case when q.withdrawn_at is not null then 'withdrawn'
                    when q.status = 'not_proceeding' or q.removed_at is not null then 'voided'
                    when v_rep is not null then 'replaced'
                    when q.signed_at is null and q.valid_until is not null and q.valid_until < v_today then 'expired'
                    else 'valid' end;
    return jsonb_build_object('src', 'quotation', 'id', q.id, 'serial', q.ref, 'kind', 'Quotation',
      'issued', (q.issued_at at time zone 'Asia/Kuala_Lumpur')::date, 'code', q.doc_code, 'sealed', q.seal_key is not null,
      'names', public.verify_names(array[q.contact ->> 'name', to_jsonb(q) #>> '{bill_to,legal_name}',
        (select c.legal_name from public.clients c where c.id = q.client_id)]),
      'state', v_state,
      'steps', public.verify_steps(jsonb_build_array(
        jsonb_build_object('step', 'issued', 'day', (q.issued_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'sent', 'day', (q.sent_out_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'signed', 'day', (q.signed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'confirmed', 'day', (q.reviewed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'sealed', 'day', (q.sealed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'declined', 'day', (q.declined_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'withdrawn', 'day', q.withdrawn_on),
        jsonb_build_object('step', 'voided', 'day', (q.removed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'replaced', 'day', v_rep),
        jsonb_build_object('step', 'expired', 'day', case when v_state = 'expired' then q.valid_until + 1 end))));
  end if;
  /* An offer or a contract once sent: the version standing first (a
     replacement keeps the reference, the one it replaced void). */
  select * into h from public.hiring_docs x
   where (upper(replace(x.serial, '/', '-')) = sd)
     and x.sent_at is not null and x.state <> 'draft'
   order by (upper(x.serial) = s) desc, (x.state <> 'void') desc, x.sent_at desc limit 1;
  if h.id is not null then
    v_state := case when h.state = 'void' then 'voided'
                    when h.state = 'withdrawn' then 'withdrawn'
                    when h.state = 'declined' then 'declined'
                    when h.state = 'sent' and h.reply_by is not null and h.reply_by < now() then 'expired'
                    else 'valid' end;
    return jsonb_build_object('src', 'hiring', 'id', h.id, 'serial', h.serial, 'kind', 'HR Letter',
      'issued', (h.sent_at at time zone 'Asia/Kuala_Lumpur')::date, 'code', h.doc_code, 'sealed', h.seal_sha is not null,
      'names', public.verify_names(array[(select k.name from public.hiring_candidates k where k.id = h.candidate_id)]),
      'state', v_state,
      'steps', public.verify_steps(jsonb_build_array(
        jsonb_build_object('step', 'issued', 'day', (h.sent_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'signed', 'day', (h.signed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'confirmed', 'day', (h.confirmed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'sealed', 'day', (h.sealed_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'declined', 'day', case when h.state = 'declined' then (coalesce(h.answered_at, h.updated_at) at time zone 'Asia/Kuala_Lumpur')::date end),
        jsonb_build_object('step', 'withdrawn', 'day', case when h.state = 'withdrawn' then (h.updated_at at time zone 'Asia/Kuala_Lumpur')::date end),
        jsonb_build_object('step', 'voided', 'day', (h.voided_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'expired', 'day', case when v_state = 'expired' then (h.reply_by at time zone 'Asia/Kuala_Lumpur')::date end))));
  end if;
  select * into rv from public.perf_reviews pr
   where (upper(replace(pr.serial, '/', '-')) = sd)
     and exists (select 1 from public.perf_events pe where pe.review_id = pr.id and pe.kind = 'printed')
   limit 1;
  if rv.id is not null then
    return jsonb_build_object('src', 'perf', 'id', rv.id, 'serial', rv.serial, 'kind', 'HR Letter',
      'issued', (rv.released_at at time zone 'Asia/Kuala_Lumpur')::date, 'code', rv.doc_code, 'sealed', false,
      'names', public.verify_names(array[(select m.name from public.team_members m where m.id = rv.team_member_id)]),
      'state', case when rv.status = 'draft' then 'replaced' else 'valid' end,
      'steps', public.verify_steps(jsonb_build_array(
        jsonb_build_object('step', 'issued', 'day', (rv.released_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'acknowledged', 'day', (rv.acknowledged_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'finalised', 'day', (rv.finalised_at at time zone 'Asia/Kuala_Lumpur')::date))));
  end if;
  select * into dl from public.perf_deleted pd
   where pd.printed and (upper(replace(pd.serial, '/', '-')) = sd)
   order by pd.deleted_at desc limit 1;
  if dl.id is not null then
    return jsonb_build_object('src', 'perf_deleted', 'id', dl.id, 'serial', dl.serial, 'kind', 'HR Letter',
      'issued', (dl.released_at at time zone 'Asia/Kuala_Lumpur')::date, 'code', null, 'sealed', false, 'state', 'voided',
      'names', public.verify_names(array[(select m.name from public.team_members m where m.id = dl.team_member_id)]),
      'steps', public.verify_steps(jsonb_build_array(
        jsonb_build_object('step', 'issued', 'day', (dl.released_at at time zone 'Asia/Kuala_Lumpur')::date),
        jsonb_build_object('step', 'voided', 'day', (dl.deleted_at at time zone 'Asia/Kuala_Lumpur')::date))));
  end if;
  /* A report as published and a video script as shared hold no reference
     of their own: the Document ID their foot prints is what /verify/ is
     asked (DOCUMENT ID ON EVERY FOOT, 2026-11-24). */
  v_code := regexp_replace(s, '[^0-9A-Z]', '', 'g');
  if v_code ~ '^[2-9A-Z]{8}$' then
    select * into rp from public.sm_report_versions x where x.doc_code = v_code limit 1;
    if rp.id is not null then
      select (min(n.published_at) at time zone 'Asia/Kuala_Lumpur')::date into v_rep
        from public.sm_report_versions n where n.report_id = rp.report_id and n.version_no > rp.version_no;
      return jsonb_build_object('src', 'report', 'id', rp.id, 'serial', substr(v_code, 1, 4) || '-' || substr(v_code, 5, 4), 'by_code', true,
        'kind', case when coalesce(rp.snapshot #>> '{report,kind}', (select r.kind from public.sm_reports r where r.id = rp.report_id)) = 'ads'
                     then 'Social Media Advertising Report' else 'Social Media Accounts Report' end,
        'issued', (rp.published_at at time zone 'Asia/Kuala_Lumpur')::date, 'code', rp.doc_code, 'sealed', false,
        'state', case when rp.withdrawn_at is not null then 'withdrawn' when v_rep is not null then 'replaced' else 'valid' end,
        'steps', public.verify_steps(jsonb_build_array(
          jsonb_build_object('step', 'issued', 'day', (rp.published_at at time zone 'Asia/Kuala_Lumpur')::date),
          jsonb_build_object('step', 'replaced', 'day', v_rep),
          jsonb_build_object('step', 'withdrawn', 'day', (rp.withdrawn_at at time zone 'Asia/Kuala_Lumpur')::date))));
    end if;
    select * into vs from public.video_scripts x where x.doc_code = v_code and x.shared_at is not null limit 1;
    if vs.id is not null then
      return jsonb_build_object('src', 'script', 'id', vs.id, 'serial', substr(v_code, 1, 4) || '-' || substr(v_code, 5, 4), 'by_code', true,
        'kind', 'Video Script',
        'issued', (vs.shared_at at time zone 'Asia/Kuala_Lumpur')::date, 'code', vs.doc_code, 'sealed', false,
        'state', case when vs.status = 'shared' then 'valid' else 'withdrawn' end,
        'steps', public.verify_steps(jsonb_build_array(
          jsonb_build_object('step', 'issued', 'day', (vs.shared_at at time zone 'Asia/Kuala_Lumpur')::date),
          jsonb_build_object('step', 'withdrawn', 'day', case when vs.status <> 'shared' then (vs.updated_at at time zone 'Asia/Kuala_Lumpur')::date end))));
    end if;
  end if;
  return null;
end $$;
revoke all on function public.verify_find(text) from public, anon, authenticated;

/* The day of issue may stand for the Document ID: a document issued before
   every copy carried one (`verify_code_from`), or one that holds none;
   never one found by its code. */
create or replace function public.verify_by_day(f jsonb)
returns boolean language plpgsql stable set search_path = public as $$
declare
  v_from numeric := public.app_setting('verify_code_from', (now() at time zone 'Asia/Kuala_Lumpur')::date);
begin
  if f is null or f ->> 'issued' is null then return false; end if;
  if coalesce((f ->> 'by_code')::boolean, false) then return false; end if;
  if f ->> 'code' is null then return true; end if;
  if v_from is null then return false; end if;
  return (f ->> 'issued')::date < to_date(v_from::bigint::text, 'YYYYMMDD');
end $$;
revoke all on function public.verify_by_day(jsonb) from public, anon, authenticated;

/* The first answer: that ADSPACE PLT issued a document with this reference,
   its kind and its standing; its month only where its name cannot stand
   for the Document ID (a reference may carry its day); `by_code` where the
   reference typed is the Document ID itself. A lookup that finds one is
   counted. */
create or replace function public.verify_serial(p_serial text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  f jsonb;
  v_wait integer := public.verify_count();
  v_name boolean;
begin
  if v_wait > 0 then
    return jsonb_build_object('found', false, 'locked', true, 'minutes', v_wait);
  end if;
  f := public.verify_find(p_serial);
  if f is null then return jsonb_build_object('found', false); end if;
  perform public.verify_check_note(f);
  v_name := public.verify_by_day(f);
  return jsonb_build_object('found', true, 'serial', f ->> 'serial', 'kind', f ->> 'kind', 'state', f ->> 'state',
    'sealed', coalesce((f ->> 'sealed')::boolean, false), 'more', true, 'by_name', v_name,
    'by_code', coalesce((f ->> 'by_code')::boolean, false)) ||
    case when v_name then '{}'::jsonb else jsonb_build_object('issued_month', to_char((f ->> 'issued')::date, 'YYYY-MM')) end;
end $$;
revoke all on function public.verify_serial(text) from public;
grant execute on function public.verify_serial(text) to anon, authenticated;

/* The code of a document, as printed: any for a colleague (a report by its
   version's id, a script by its own), a client's own Letter of Offer for
   its portal login, else none. A page outside the team asks
   `doc_code_of_key` with its own key. */
create or replace function public.doc_code_of(p_kind text, p_id uuid)
returns text
language plpgsql stable security definer set search_path = public as $$
declare v text;
begin
  if p_id is null then return null; end if;
  if public.is_team() then
    v := case p_kind
      when 'document'  then (select x.doc_code from public.documents x where x.id = p_id)
      when 'letter'    then (select x.doc_code from public.client_documents x where x.id = p_id)
      when 'quotation' then (select x.doc_code from public.quotations x where x.id = p_id)
      when 'hiring'    then (select x.doc_code from public.hiring_docs x where x.id = p_id)
      when 'perf'      then (select x.doc_code from public.perf_reviews x where x.id = p_id)
      when 'report'    then (select x.doc_code from public.sm_report_versions x where x.id = p_id)
      when 'script'    then (select x.doc_code from public.video_scripts x where x.id = p_id)
    end;
  elsif p_kind = 'letter' then
    v := (select x.doc_code from public.client_documents x
           where x.id = p_id and x.client_id in (select public.portal_clients()));
  end if;
  if v is null then return null; end if;
  return substr(v, 1, 4) || '-' || substr(v, 5, 4);
end $$;
revoke all on function public.doc_code_of(text, uuid) from public;
grant execute on function public.doc_code_of(text, uuid) to anon, authenticated;

/* The code for the page holding the document's own key: a quotation's
   link (/quote/), a candidate's (/careers/, an offer or contract sent), a
   client's script link (/script/, a script shared). */
create or replace function public.doc_code_of_key(p_kind text, p_id uuid, p_key text)
returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v text;
  k text := btrim(coalesce(p_key, ''));
begin
  if p_id is null then return null; end if;
  if k = '' or public.is_team() then return public.doc_code_of(p_kind, p_id); end if;
  v := case p_kind
    when 'quotation' then (select x.doc_code from public.quotations x
                            where x.id = p_id and x.access_key = k and x.removed_at is null)
    when 'hiring'    then (select x.doc_code from public.hiring_docs x join public.hiring_candidates c on c.id = x.candidate_id
                            where x.id = p_id and c.link_key = lower(k) and x.sent_at is not null and x.state <> 'draft')
    when 'script'    then (select x.doc_code from public.video_scripts x join public.clients c on c.id = x.client_id
                            where x.id = p_id and c.script_key = k and x.status = 'shared')
  end;
  if v is null then return null; end if;
  return substr(v, 1, 4) || '-' || substr(v, 5, 4);
end $$;
revoke all on function public.doc_code_of_key(text, uuid, text) from public;
grant execute on function public.doc_code_of_key(text, uuid, text) to anon, authenticated;

-- END OF DOCUMENT ID ON EVERY FOOT --------------------------------------------

select public.functions_tidy();
