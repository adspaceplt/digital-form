-- ===========================================================================
-- PERFORMANCE IN PLAIN WORDS — the two notices a query sends say query,
-- never dispute.
-- 2026-10-05. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/perf.js compares the
-- two. Runs after PERFORMANCE REVIEWS and MY PERFORMANCE BEHIND AN EMAIL
-- CODE, which defined the two functions last.
--
-- WHAT CHANGED
--   The page reads Query, Issue, Shared and Agreed where it read Dispute,
--   Breach, Released and Upheld (the user, 2026-10-05: "why use evidence.
--   Sounds like some criminals"). The stored keys (`disputed`, `breach`,
--   `upheld`, the kinds `perf.disputed` and `perf.answered`) never move;
--   only the words of the two notices and an agreed query's void reason.
--   Each function is otherwise its last definition, unchanged.
--
-- ROLLBACK
--   Run perf_decide from PERFORMANCE REVIEWS and perf_dispute from MY
--   PERFORMANCE BEHIND AN EMAIL CODE again.
-- ===========================================================================

create or replace function public.perf_decide(p_token text, p_dispute uuid, p_decision text,
                                              p_response text, p_value numeric)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  err text; m public.team_members; d public.perf_disputes; r public.perf_reviews;
  b public.perf_breaches; mx numeric; was numeric; col text;
begin
  err := public.perf_check(p_token, 'work');
  if err is not null then return jsonb_build_object('error', err); end if;
  m := public.ops_me();
  if p_decision not in ('upheld', 'partly', 'not_upheld') then return jsonb_build_object('error', 'bad-decision'); end if;
  if coalesce(btrim(p_response), '') = '' then return jsonb_build_object('error', 'reason-needed'); end if;
  select * into d from public.perf_disputes where id = p_dispute for update;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into r from public.perf_reviews where id = d.review_id for update;
  if r.team_member_id = m.id then return jsonb_build_object('error', 'own-review'); end if;
  if r.status <> 'disputed' or d.decision is not null or d.version <> r.version then
    return jsonb_build_object('error', 'already-decided');
  end if;

  if d.item = 'breach' then
    select * into b from public.perf_breaches where id = d.breach_id for update;
    was := b.severity;
    if p_decision = 'upheld' then
      update public.perf_breaches set voided_at = now(), voided_by = m.id, void_reason = 'Query agreed'
       where id = b.id;
    elsif p_decision = 'partly' then
      if p_value is null or p_value not in (1, 2, 3) or p_value >= b.severity then
        return jsonb_build_object('error', 'bad-severity');
      end if;
      update public.perf_breaches set severity = p_value::integer where id = b.id;
    end if;
  else
    mx := case d.item when 'output' then 25 when 'accuracy' then 15 when 'delivery' then 15
                      when 'client' then 20 when 'comms' then 15 when 'initiative' then 10 end;
    col := 's_' || d.item;
    execute format('select %I from public.perf_reviews where id = $1', col) into was using r.id;
    if p_decision in ('upheld', 'partly') then
      if p_value is null or p_value < 0 or p_value > mx or round(p_value, 1) <> p_value then
        return jsonb_build_object('error', 'bad-score', 'max', mx);
      end if;
      execute format('update public.perf_reviews set %I = $1 where id = $2', col) using p_value, r.id;
    end if;
  end if;

  update public.perf_disputes set decision = p_decision, response = btrim(p_response),
         before_value = was,
         after_value = case when p_decision = 'not_upheld' then was
                            when d.item = 'breach' and p_decision = 'upheld' then 0
                            else p_value end,
         decided_by = m.id, decided_at = now()
   where id = d.id;
  if not exists (select 1 from public.perf_disputes x
                  where x.review_id = r.id and x.version = r.version and x.decision is null) then
    update public.perf_reviews set status = 'resolved' where id = r.id;
    perform public.perf_notify(r.team_member_id, 'perf.answered',
      'Your query on ' || public.perf_month_word(r.period) || ' has been answered.',
      'perf.answered.' || r.id || '.' || r.version);
  end if;
  update public.perf_reviews set rev = rev + 1, updated_at = now() where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'decided',
    jsonb_build_object('item', d.item, 'decision', p_decision, 'was', was,
                       'after', case when p_decision = 'not_upheld' then was else p_value end));
  return public.perf_json(r, true);
end $$;

create or replace function public.perf_dispute(p_review uuid, p_items jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.team_members; r public.perf_reviews; it jsonb; n integer := 0; itm text; bid uuid;
begin
  m := public.ops_me();
  if m.id is null then return jsonb_build_object('error', 'not-team'); end if;
  if public.perf_guarded(m.id) and not public.perf_code_fresh() then
    return jsonb_build_object('error', 'code-needed');
  end if;
  select * into r from public.perf_reviews where id = p_review for update;
  if r.id is null or r.team_member_id <> m.id or r.status = 'draft' then
    return jsonb_build_object('error', 'not-found');
  end if;
  if r.status <> 'released' or exists (select 1 from public.perf_disputes d
                                        where d.review_id = r.id and d.version = r.version) then
    return jsonb_build_object('error', 'dispute-closed');
  end if;
  if r.dispute_until <= now() then return jsonb_build_object('error', 'window-closed'); end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    return jsonb_build_object('error', 'nothing-disputed');
  end if;
  for it in select * from jsonb_array_elements(p_items) loop
    itm := it ->> 'item';
    if itm is null or itm not in ('output', 'accuracy', 'delivery', 'client', 'comms', 'initiative', 'breach') then
      return jsonb_build_object('error', 'bad-item');
    end if;
    if coalesce(btrim(it ->> 'reason'), '') = '' then return jsonb_build_object('error', 'reason-needed', 'item', itm); end if;
    bid := null;
    if itm = 'breach' then
      begin bid := (it ->> 'breach_id')::uuid; exception when others then bid := null; end;
      if bid is null or not exists (select 1 from public.perf_breaches b
                                     where b.id = bid and b.team_member_id = m.id
                                       and b.period = r.period and b.voided_at is null) then
        return jsonb_build_object('error', 'bad-item');
      end if;
    end if;
    insert into public.perf_disputes (review_id, version, item, breach_id, reason)
    values (r.id, r.version, itm, bid, btrim(it ->> 'reason'));
    n := n + 1;
  end loop;
  update public.perf_reviews set status = 'disputed', rev = rev + 1, updated_at = now()
   where id = r.id returning * into r;
  perform public.perf_log(r.id, r.team_member_id, 'disputed', jsonb_build_object('items', n));
  perform public.perf_notify(r.reviewer_id, 'perf.disputed',
    m.name || ' raised a query on ' || public.perf_month_word(r.period) || '.',
    'perf.disputed.' || r.id || '.' || r.version);
  return public.perf_json(r, false);
end $$;

-- END OF PERFORMANCE IN PLAIN WORDS ----------------------------------------
