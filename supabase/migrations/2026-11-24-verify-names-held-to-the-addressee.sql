-- ===========================================================================
-- VERIFY NAMES HELD TO THE ADDRESSEE (2026-11-24)
-- ===========================================================================
-- WHY: the audit of 2026-11-24 (the user: "fix all except 2"). /verify/'s
-- name check took a client's brand (`clients.name`, a quotation's `brand`)
-- and a supplier's trading name, which anybody can read off a post, and
-- the name's answer carried the Document ID, which opens `verify_details`
-- with no name lock. Five wrong names a reference from anywhere locked the
-- real addressee out for 24 hours.
--
-- WHAT IT CHANGES
--   * `verify_find`: a document's names are the registered company name
--     (a supplier's own name where it holds none, a letter's addressee as
--     printed), the person it names and its contact; never a brand.
--   * `verify_details_name` answers without `document_id`.
--   * `verify_name_wrong` / `verify_name_wait`: five wrong names lock one
--     connection (`verify_name_caller_tries`); fifty from all connections
--     lock the reference (`verify_name_tries`); five where no connection is
--     read, as before.
--
-- ORDER: this file alone; /verify/ reads `document_id` only where it is
-- answered, so no page changes. Safe to run twice.
-- ROLLBACK: run the four functions from VERIFY BY THE NAME ADDRESSED TO
-- again; the new table may stay.
-- ===========================================================================

-- VERIFY NAMES HELD TO THE ADDRESSEE ----------------------------------------

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
  return null;
end $$;
revoke all on function public.verify_find(text) from public, anon, authenticated;

/* Wrong names a reference from one connection: five in 24 hours lock that
   connection out of the name for that reference; fifty from all of them
   together lock it for everybody (`verify_name_tries`), so nobody can lock
   the real addressee out alone. */
create table if not exists public.verify_name_caller_tries (
  serial       text not null,
  ip           text not null,
  n            integer not null default 0,
  since        timestamptz not null default now(),
  locked_until timestamptz,
  primary key (serial, ip)
);
alter table public.verify_name_caller_tries enable row level security;
revoke all on public.verify_name_caller_tries from public, anon, authenticated;

/* The minutes a reference's name stays locked to this caller, 0 where it
   is open. */
create or replace function public.verify_name_wait(p_key text)
returns integer
language sql stable set search_path = public as $$
  select coalesce((select greatest(1, ceil(extract(epoch from (max(x.u) - now())) / 60)::integer)
                     from (select t.locked_until as u from public.verify_name_tries t
                            where t.serial = p_key and t.locked_until > now()
                           union all
                           select c.locked_until from public.verify_name_caller_tries c
                            where c.serial = p_key and c.ip = public.request_ip() and c.locked_until > now()) x
                   having max(x.u) is not null), 0)
$$;
revoke all on function public.verify_name_wait(text) from public, anon, authenticated;

create or replace function public.verify_name_wrong(p_key text)
returns void
language plpgsql volatile set search_path = public as $$
declare
  v_ip text := public.request_ip();
begin
  if v_ip <> '' then
    insert into public.verify_name_caller_tries as t (serial, ip, n, since) values (p_key, v_ip, 1, now())
    on conflict (serial, ip) do update
      set n = case when t.since < now() - interval '24 hours' then 1 else t.n + 1 end,
          since = case when t.since < now() - interval '24 hours' then now() else t.since end;
    update public.verify_name_caller_tries t set locked_until = now() + interval '24 hours'
     where t.serial = p_key and t.ip = v_ip and t.n >= 5 and (t.locked_until is null or t.locked_until <= now());
  end if;
  insert into public.verify_name_tries as t (serial, n, since) values (p_key, 1, now())
  on conflict (serial) do update
    set n = case when t.since < now() - interval '24 hours' then 1 else t.n + 1 end,
        since = case when t.since < now() - interval '24 hours' then now() else t.since end;
  update public.verify_name_tries t set locked_until = now() + interval '24 hours'
   where t.serial = p_key and t.n >= case when v_ip <> '' then 50 else 5 end
     and (t.locked_until is null or t.locked_until <= now());
end $$;
revoke all on function public.verify_name_wrong(text) from public, anon, authenticated;

create or replace function public.verify_details_name(p_serial text, p_name text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  f jsonb;
  k text := public.verify_name_key(left(coalesce(p_name, ''), 200));
  v_contact text := (select b.address from public.mail_boxes b where b.key = 'legal');
  v_wait integer := public.verify_detail_count();
  v_team boolean := public.is_team();
  v_key text;
  v_lock integer;
begin
  if v_wait > 0 then
    return jsonb_build_object('locked', true, 'minutes', v_wait, 'contact', v_contact);
  end if;
  f := public.verify_find(p_serial);
  if f is null or not public.verify_by_day(f) or length(k) < 2 then
    return jsonb_build_object('no_match', true, 'contact', v_contact);
  end if;
  v_key := upper(replace(f ->> 'serial', '/', '-'));
  v_lock := case when v_team then 0 else public.verify_name_wait(v_key) end;
  if v_lock > 0 then
    return jsonb_build_object('locked', true, 'reference', true, 'minutes', v_lock, 'contact', v_contact);
  end if;
  if not coalesce((f -> 'names') ? k, false) then
    if not v_team then perform public.verify_name_wrong(v_key); end if;
    return jsonb_build_object('no_match', true, 'contact', v_contact);
  end if;
  -- a name never answers the Document ID: it would open verify_details,
  -- which holds no name lock
  return public.verify_answer(f, v_contact) - 'document_id';
end $$;
revoke all on function public.verify_details_name(text, text) from public;
grant execute on function public.verify_details_name(text, text) to anon, authenticated;

-- END OF VERIFY NAMES HELD TO THE ADDRESSEE ---------------------------------

select public.functions_tidy();
