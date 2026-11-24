-- ===========================================================================
-- CAREERS DECIDED AND OFFER CODES (2026-11-24)
-- ===========================================================================
-- WHY: the code review of 2026-11-24 (release A1). A candidate told to
-- proceed kept an open interview invitation, and the careers page let a
-- time be chosen (or other times asked for) after any decision. An
-- Employment Offer's code allowed five new codes an hour, each with five
-- tries: about 18,000 guesses over the link's 30 days.
--
-- WHAT CHANGED
--   * `hiring_decide` cancels an invited or other-times interview on
--     Proceed too (a picked or confirmed one stays for the team, as
--     before); every other outcome cancels as before.
--   * `careers_pick` and `careers_none` refuse (`not-open`) once the
--     candidate is past New, Invited or Interview.
--   * `hiring_doc_wrong_today(doc)` (internal): the wrong codes typed for a
--     document this Malaysian day, whatever code they were typed against;
--     at ten, `careers_doc_open` and `hiring_doc_code` answer
--     `locked-today` until the next day.
--
-- ORDER: this file (connector), then hiring-mail (passes `locked-today` on),
-- then the pages. An old careers page reads `locked-today` as a code not
-- recognised. Safe to run twice.
-- ROLLBACK: restate `hiring_decide`, `careers_pick`, `careers_none`,
-- `hiring_doc_code` and `careers_doc_open` from their last definitions
-- before this banner; drop `hiring_doc_wrong_today(uuid)`.
-- ===========================================================================

/* The wrong codes typed for one document this Malaysian day. Internal. */
create or replace function public.hiring_doc_wrong_today(p_doc uuid)
returns integer language sql stable security definer set search_path = public as $$
  select coalesce(sum(s.tries), 0)::integer from public.hiring_doc_codes s
   where s.doc_id = p_doc
     and s.created_at >= ((now() at time zone 'Asia/Kuala_Lumpur')::date)::timestamp at time zone 'Asia/Kuala_Lumpur'
$$;
revoke all on function public.hiring_doc_wrong_today(uuid) from public, anon, authenticated;

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
   where candidate_id = c.id
     and (state in ('invited', 'none')
          or (p_outcome <> 'proceed' and (state = 'picked' or (state = 'confirmed' and held_at is null))));
  update public.hiring_docs set state = 'withdrawn', updated_at = now()
   where candidate_id = c.id and p_outcome <> 'proceed' and state = 'sent';
  perform public.hiring_log(c.id, 'candidate.decided',
    case p_outcome when 'proceed' then 'Proceed' when 'pool' then 'Keep in talent pool' else 'Do not proceed' end);
  return jsonb_build_object('ok', true, 'was', c.outcome, 'email', p_outcome in ('pool', 'not'));
end $$;
grant execute on function public.hiring_decide(uuid, text, text) to authenticated;

create or replace function public.careers_pick(p_key text, p_slot int)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  c public.hiring_candidates;
  i public.hiring_interviews;
  v_days int := coalesce(public.app_setting('hiring_link_days', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 30);
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into c from public.hiring_candidates where link_key = p_key and removed_at is null for update;
  if c.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if c.last_step_at + make_interval(days => v_days) <= now() then return jsonb_build_object('error', 'expired'); end if;
  -- A decision taken closes the choice (review 2026-11-24).
  if c.stage not in ('new', 'invited', 'interview') then return jsonb_build_object('error', 'not-open'); end if;
  select * into i from public.hiring_interviews where candidate_id = c.id and state = 'invited'
   order by invited_at desc limit 1 for update;
  if i.id is null then return jsonb_build_object('error', 'not-open'); end if;
  if i.reply_by <= now() then return jsonb_build_object('error', 'reply-passed'); end if;
  if p_slot is null or p_slot < 1 or p_slot > cardinality(i.slots) then return jsonb_build_object('error', 'bad-slot'); end if;
  if i.slots[p_slot] < now() then return jsonb_build_object('error', 'slot-past'); end if;
  update public.hiring_interviews set state = 'picked', picked = p_slot, picked_at = now(), updated_at = now() where id = i.id;
  update public.hiring_candidates set last_step_at = now(), updated_at = now() where id = c.id;
  insert into public.hiring_events (candidate_id, actor, action, detail)
  values (c.id, 'Candidate page', 'candidate.interview', 'Time chosen: ' || public.hiring_when(i.slots[p_slot]));
  perform public.hiring_tell(c.id, 'hiring.picked', 'A candidate chose an interview time',
    c.position || ' · ' || public.hiring_when(i.slots[p_slot]) || '. Approve it to send the confirmation.');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.careers_pick(text, int) from public;
grant execute on function public.careers_pick(text, int) to anon, authenticated;

create or replace function public.careers_none(p_key text, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  c public.hiring_candidates;
  i public.hiring_interviews;
  v_days int := coalesce(public.app_setting('hiring_link_days', (now() at time zone 'Asia/Kuala_Lumpur')::date)::int, 30);
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  if char_length(coalesce(p_note, '')) > 300 then return jsonb_build_object('error', 'too-long'); end if;
  select * into c from public.hiring_candidates where link_key = p_key and removed_at is null for update;
  if c.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if c.last_step_at + make_interval(days => v_days) <= now() then return jsonb_build_object('error', 'expired'); end if;
  -- A decision taken closes the choice (review 2026-11-24).
  if c.stage not in ('new', 'invited', 'interview') then return jsonb_build_object('error', 'not-open'); end if;
  select * into i from public.hiring_interviews where candidate_id = c.id and state = 'invited'
   order by invited_at desc limit 1 for update;
  if i.id is null then return jsonb_build_object('error', 'not-open'); end if;
  if i.reply_by <= now() then return jsonb_build_object('error', 'reply-passed'); end if;
  update public.hiring_interviews set state = 'none', candidate_note = nullif(btrim(coalesce(p_note, '')), ''), updated_at = now() where id = i.id;
  update public.hiring_candidates set last_step_at = now(), updated_at = now() where id = c.id;
  insert into public.hiring_events (candidate_id, actor, action, detail)
  values (c.id, 'Candidate page', 'candidate.interview', 'Other times asked for');
  perform public.hiring_tell(c.id, 'hiring.none', 'A candidate asked for other interview times',
    c.position || '. Send new times from the candidate''s Interview tab.');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.careers_none(text, text) from public;
grant execute on function public.careers_none(text, text) to anon, authenticated;

create or replace function public.hiring_doc_code(p_key text, p_doc uuid, p_device text, p_ip text)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  d public.hiring_docs := public.careers_doc_of(p_key, p_doc);
  c public.hiring_candidates;
  v_code text;
begin
  if d.id is null then return jsonb_build_object('error', 'not_found'); end if;
  perform 1 from public.hiring_docs where id = d.id for update;
  select * into c from public.hiring_candidates where id = d.candidate_id;
  if public.hiring_doc_wrong_today(d.id) >= 10 then return jsonb_build_object('error', 'locked-today'); end if;
  if (select count(*) from public.hiring_doc_codes s where s.doc_id = d.id and s.created_at > now() - interval '1 hour') >= 5 then
    return jsonb_build_object('error', 'too-many');
  end if;
  v_code := lpad(((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
  insert into public.hiring_doc_codes (doc_id, code_hash, email, expires_at)
  values (d.id, crypt(v_code, gen_salt('bf', 6)), c.email, now() + interval '15 minutes');
  insert into public.signing_steps (doc_kind, doc_id, step, email, ip, country, device)
  values ('hiring_doc', d.id, 'code', c.email, nullif(left(coalesce(p_ip, ''), 64), ''), nullif(public.request_country(), ''), public.seal_device(p_device));
  return jsonb_build_object('ok', true, 'code', v_code, 'email', c.email, 'name', c.name, 'ref', d.serial,
    'doc', d.kind);
end $$;
revoke all on function public.hiring_doc_code(text, uuid, text, text) from public, anon, authenticated;
grant execute on function public.hiring_doc_code(text, uuid, text, text) to service_role;

create or replace function public.careers_doc_open(p_key text, p_doc uuid, p_code text, p_device text)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  d public.hiring_docs := public.careers_doc_of(p_key, p_doc);
  s public.hiring_doc_codes;
  v_tok text;
begin
  if d.id is null then return jsonb_build_object('error', 'not_found'); end if;
  perform 1 from public.hiring_docs where id = d.id for update;
  -- Ten wrong codes a document a Malaysian day, whatever code they were
  -- typed against (review 2026-11-24: a new code every hour gave five more).
  if public.hiring_doc_wrong_today(d.id) >= 10 then return jsonb_build_object('error', 'locked-today'); end if;
  select * into s from public.hiring_doc_codes x where x.doc_id = d.id and x.used_at is null
   order by x.created_at desc limit 1 for update;
  if s.id is null then return jsonb_build_object('error', 'no-code'); end if;
  if s.expires_at <= now() then return jsonb_build_object('error', 'code-expired'); end if;
  if s.tries >= 5 then return jsonb_build_object('error', 'locked'); end if;
  if regexp_replace(coalesce(p_code, ''), '\s+', '', 'g') !~ '^[0-9]{6}$'
     or crypt(regexp_replace(p_code, '\s+', '', 'g'), s.code_hash) <> s.code_hash then
    update public.hiring_doc_codes set tries = tries + 1 where id = s.id;
    return jsonb_build_object('error', 'wrong', 'left', greatest(0, 4 - s.tries));
  end if;
  v_tok := encode(gen_random_bytes(24), 'hex');
  update public.hiring_doc_codes set used_at = now(), view_hash = encode(digest(v_tok, 'sha256'), 'hex'),
    view_until = now() + interval '30 minutes' where id = s.id;
  insert into public.signing_steps (doc_kind, doc_id, step, email, ip, country, device)
  values ('hiring_doc', d.id, 'opened', s.email, nullif(public.request_ip(), ''), nullif(public.request_country(), ''), public.seal_device(p_device));
  return public.careers_doc_json(d) || jsonb_build_object('view', v_tok);
end $$;
revoke all on function public.careers_doc_open(text, uuid, text, text) from public;
grant execute on function public.careers_doc_open(text, uuid, text, text) to anon, authenticated;

-- END OF CAREERS DECIDED AND OFFER CODES ------------------------------------

select public.functions_tidy();
