-- ===========================================================================
-- OFFER DECLINED OR EXPIRED TOLD (2026-11-21)
-- ===========================================================================
-- WHY: the user, 2026-11-21: "yess" to a colleague notice when a candidate
-- declines an offer or an offer passes its reply-by unanswered. Until now an
-- expired offer or contract emailed the candidate alone (HIRING BEFORE THE
-- FIRST HIRE: "no notice to colleagues"), which the user has now reversed.
--
-- WHAT IT CHANGES
--   * `hiring_tell_once(p_candidate, p_kind, p_title, p_body, p_key)` (no
--     caller's): `hiring_tell`'s Owners, each told once a key
--     (`dedupe_key` `{p_key}:{colleague}`), the notice opening the
--     candidate; never the candidate's name.
--   * `careers_doc_answer` (restated whole from HIRING OFFERS AND
--     CONTRACTS) tells the Owners of a declined offer once a document
--     (`hiring.declined`, key `hiring.declined:{document}`).
--   * `hiring_docs_expire` (restated whole from HIRING BEFORE THE FIRST
--     HIRE) tells the Owners of an offer or contract past its reply-by once
--     a document (`hiring.doc_expired`, key `hiring.doc_expired:{document}`),
--     beside the candidate's email it already queues.
--
-- ORDER: this file alone; no page changes. Safe to run twice.
--
-- ROLLBACK: run `careers_doc_answer` from HIRING OFFERS AND CONTRACTS and
-- `hiring_docs_expire` from HIRING BEFORE THE FIRST HIRE again; drop
-- `hiring_tell_once`.
-- ===========================================================================

/* The Owners of a candidate, each told once for a key (a document's
   decline or expiry), the notice opening the candidate, never its name. */
create or replace function public.hiring_tell_once(p_candidate uuid, p_kind text, p_title text, p_body text, p_key text)
returns void language plpgsql security definer set search_path = public as $$
declare me public.team_members := public.ops_me();
begin
  insert into public.ops_notifications (team_member_id, kind, title, body, link, dedupe_key)
  select t.id, p_kind, p_title, p_body, 'https://digital.adspace.me/admin/?s=team&tab=hiring&candidate=' || p_candidate,
         p_key || ':' || t.id
    from public.team_members t
   where t.active and t.removed_at is null and not t.system and (me.id is null or t.id <> me.id)
     and exists (select 1 from public.hiring_people p where p.candidate_id = p_candidate and p.team_member_id = t.id and p.role = 'owner')
  on conflict (dedupe_key) do nothing;
end $$;
revoke all on function public.hiring_tell_once(uuid, text, text, text, text) from public, anon, authenticated;

create or replace function public.careers_doc_answer(p_key text, p_doc uuid, p_view text, p_answer text, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  d public.hiring_docs := public.careers_doc_of(p_key, p_doc);
  s public.hiring_doc_codes;
  p public.hiring_doc_pay;
  pl jsonb := coalesce(p_payload, '{}'::jsonb);
  v_name text := btrim(coalesce(pl->>'name', ''));
  v_id text := upper(btrim(coalesce(pl->>'id_no', '')));
  v_sig text := coalesce(pl->>'signature', '');
  v_at timestamptz := now();
  v_title text;
begin
  if d.id is null then return jsonb_build_object('error', 'not_found'); end if;
  s := public.careers_doc_view(d.id, p_view);
  if s.id is null then return jsonb_build_object('error', 'code-needed'); end if;
  select * into d from public.hiring_docs where id = d.id for update;
  if d.state <> 'sent' then return jsonb_build_object('error', 'answered'); end if;
  if d.reply_by <= now() then return jsonb_build_object('error', 'expired'); end if;
  v_title := case d.kind when 'offer' then 'Employment Offer' else 'Employment Contract' end;
  if p_answer = 'decline' then
    if d.kind <> 'offer' then return jsonb_build_object('error', 'bad-request'); end if;
    if char_length(coalesce(pl->>'note', '')) > 500 then return jsonb_build_object('error', 'too-long'); end if;
    update public.hiring_docs set state = 'declined', answered_at = v_at, decline_note = nullif(btrim(coalesce(pl->>'note', '')), ''),
      updated_at = now() where id = d.id;
    update public.hiring_candidates set last_step_at = now(), updated_at = now() where id = d.candidate_id;
    insert into public.hiring_events (candidate_id, actor, action, detail)
    values (d.candidate_id, 'Candidate page', 'candidate.document', d.serial || ' declined');
    perform public.hiring_tell_once(d.candidate_id, 'hiring.declined', 'A candidate declined an offer',
      d.serial || '. Open the candidate to decide the next step.', 'hiring.declined:' || d.id);
    return jsonb_build_object('ok', true);
  end if;
  if coalesce(p_answer, '') not in ('accept', 'sign') or (p_answer = 'accept') <> (d.kind = 'offer') then
    return jsonb_build_object('error', 'bad-request');
  end if;
  if char_length(v_name) not between 2 and 120 then return jsonb_build_object('error', 'bad-name'); end if;
  if coalesce(pl->>'agree', '') <> 'true' then return jsonb_build_object('error', 'bad-agree'); end if;
  if d.kind = 'contract' then
    if v_id !~ '^([0-9]{6}-[0-9]{2}-[0-9]{4}|[A-Z0-9]{6,20})$' then return jsonb_build_object('error', 'bad-id'); end if;
    if v_sig !~ '^[MLQCZmlqcz0-9 .,-]+$' or char_length(v_sig) not between 8 and 30000 then return jsonb_build_object('error', 'bad-signature'); end if;
  end if;
  select * into p from public.hiring_doc_pay where doc_id = d.id;
  update public.hiring_docs set state = 'signed', signed_at = v_at, answered_at = v_at,
    signed = jsonb_strip_nulls(jsonb_build_object('via', 'online', 'name', v_name,
      'id_no', case when d.kind = 'contract' then v_id end, 'signature', case when d.kind = 'contract' then v_sig end,
      'record', jsonb_build_object('at', v_at, 'email', s.email, 'ip', nullif(public.request_ip(), ''),
        'country', nullif(public.request_country(), ''), 'device', public.seal_device(pl->>'device'),
        'fingerprint', upper(left(encode(digest(d.serial || d.terms::text || coalesce(p.basic::text, '') || coalesce(p.probation::text, '') ||
          v_name || v_at::text, 'sha256'), 'hex'), 16))))),
    updated_at = now()
   where id = d.id;
  update public.hiring_candidates set last_step_at = now(), updated_at = now() where id = d.candidate_id;
  insert into public.hiring_events (candidate_id, actor, action, detail)
  values (d.candidate_id, 'Candidate page', 'candidate.document', d.serial || case d.kind when 'offer' then ' accepted' else ' signed' end || ' on the candidate page');
  perform public.hiring_tell(d.candidate_id, 'hiring.signed', case d.kind when 'offer' then 'A candidate accepted an offer' else 'A candidate signed a contract' end,
    d.serial || '. Open the candidate to confirm it.');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.careers_doc_answer(text, uuid, text, text, jsonb) from public;
grant execute on function public.careers_doc_answer(text, uuid, text, text, jsonb) to anon, authenticated;

/* Every fifteen minutes: an offer or contract past its reply-by with no
   answer is filed once, queued to email the candidate, and its Owners
   told once (the user, 2026-11-21, reversing 2026-11-20's email alone). */
create or replace function public.hiring_docs_expire()
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in
    select d.id, d.candidate_id, d.kind, d.serial, d.terms->>'position' as position from public.hiring_docs d
      join public.hiring_candidates c on c.id = d.candidate_id
     where d.state = 'sent' and d.reply_by <= now() and d.expired_told_at is null and c.removed_at is null
     for update of d
  loop
    update public.hiring_docs set expired_told_at = now(), expire_mail = 'queued', expire_mail_at = null where id = r.id;
    insert into public.hiring_events (candidate_id, actor, action, detail)
    values (r.candidate_id, 'Portal', 'candidate.document', r.serial || ' expired with no reply');
    perform public.hiring_tell_once(r.candidate_id, 'hiring.doc_expired',
      case r.kind when 'offer' then 'An offer expired with no reply' else 'A contract expired with no reply' end,
      r.serial || '. Open the candidate to decide the next step.', 'hiring.doc_expired:' || r.id);
    n := n + 1;
  end loop;
  if n > 0 then perform public.hiring_mail_kick(); end if;
  return n;
end $$;
revoke all on function public.hiring_docs_expire() from public, anon, authenticated;

-- END OF OFFER DECLINED OR EXPIRED TOLD --------------------------------------

select public.functions_tidy();
