-- ===========================================================================
-- AUDIT FIXES (2026-11-15)
-- ===========================================================================
-- WHY: the whole-portal audit of 2026-11-15 (items 1, 5, 9, 15 to 18).
--
-- WHAT IT CHANGES
--   * `get_review_feed`: a revision's "asked" names no colleague. Add changes
--     is the team's, and the client's page reads it as the team's.
--   * `agent_schedule_do`: a WhatsApp the Assistant sends later is kept with
--     its contact, so Sent recently finds it.
--   * `quote_proceed_remind`: a lead with a Sales by is a lead taken.
--   * `client_details_submit`: Own clients only reaches the Sales by too.
--   * `creator_bill_prep`: a fee set in another currency than the creator is
--     paid in now is refused `currency-changed`, so it is set again.
--   * `creator_submit`, `creator_add_file`, `creator_remove_file`,
--     `creator_rate`, `creator_may_upload`, `creator_post_save`: the code
--     through `creator_code_try`, so a wrong code is counted and a locked
--     address answered `locked`, as `get_creator` does.
--   * `submit_review` is internal: pages decide through `submit_review_seen`.
--
-- ORDER: the pages first (js/api.js sends every decision through
-- submit_review_seen), then this file. A page served before that sends a
-- decision with no version meets "Please refresh to review the latest
-- version."
-- Safe to run twice.
--
-- ROLLBACK: restate each function from its band before this one in
-- schema.sql, then
-- grant execute on function public.submit_review(text, uuid, text, text, text, text, text, text) to anon, authenticated;
-- and add 'submit_review' back to open_to_anon (FUNCTION HYGIENE).
-- ===========================================================================

-- AUDIT FIXES ----------------------------------------------------------------

create or replace function public.get_review_feed(p_token text, p_passcode text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_client public.clients%rowtype;
begin
  select * into v_client
  from public.clients
  where access_token = p_token and active and not review_hidden;

  if not found then
    return jsonb_build_object('error', 'not_found');
  end if;

  -- Wrong passcodes lock out the caller who typed them, said as a lock
  -- (second audit, item 4); a passcode asked for names nobody (item 6).
  case public.link_passcode('review', v_client.access_token, v_client.passcode, p_passcode)
    when 'locked' then return public.link_locked('review', v_client.access_token);
    when 'wrong' then return jsonb_build_object('error', 'passcode_required');
    else null;
  end case;

  return jsonb_build_object(
    'client', jsonb_build_object(
      'name', v_client.name,
      'logo_url', v_client.logo_url,
      'handles', jsonb_build_object(
        'instagram', v_client.handle_ig,
        'facebook',  v_client.handle_fb,
        'tiktok',    v_client.handle_tiktok,
        'xhs',       v_client.handle_xhs)),
    'batches', coalesce((
      select jsonb_agg(batch order by batch->>'created_at' desc)
      from (
        select jsonb_build_object(
          'id',         b.id,
          'title',      b.title,
          'note',       b.note,
          'created_at', b.created_at,
          'posts', coalesce((
            select jsonb_agg(post order by (post->>'position')::int)
            from (
              select jsonb_build_object(
                'id',         p.id,
                'platform',   p.platform,
                'format',     p.format,
                'handle',     p.handle,
                'caption',    p.caption,
                'caption_zh', p.caption_zh,
                'title',      p.title,
                'media',      p.media,
                'cover_for',  p.cover_for,
                'position',   p.position,
                'round',      p.round,
                'version',    p.content_version,
                'reset_note', case
                  when p.review_reset_at is not null then p.review_reset_note end,
                /* The decision standing on the round on show: never one about
                   a round the client no longer sees, never one taken back. */
                'review',     (
                  select jsonb_build_object(
                    'decision',   r.decision,
                    'note',       r.note,
                    'reviewer',   case when r.source = 'team' then null else r.reviewer end,
                    'created_at', r.created_at,
                    'by_team',    (r.source = 'team'),
                    'suggested',  (r.suggested_caption is not null or r.suggested_caption_zh is not null),
                    /* The client's own edit, so Edit request reopens it. */
                    'suggested_caption',    r.suggested_caption,
                    'suggested_caption_zh', r.suggested_caption_zh)
                  from public.reviews r
                  where r.post_id = p.id and r.round = p.round and r.undone_at is null
                    and (p.review_reset_at is null or r.created_at > p.review_reset_at)
                  order by r.created_at desc
                  limit 1),
                /* What the client asked of the round before, so a revision
                   says what it answers. Words only: the earlier file and copy
                   stay with the team. */
                'asked',      case when p.round > 1 then (
                  select jsonb_build_object(
                    'note',       r.note,
                    'reviewer',   case when r.source = 'team' then null else r.reviewer end,
                    'by_team',    r.source = 'team',
                    'created_at', r.created_at,
                    'suggested',  (r.suggested_caption is not null or r.suggested_caption_zh is not null))
                  from public.reviews r
                  where r.post_id = p.id and r.round = p.round - 1 and r.decision = 'changes'
                    and r.undone_at is null
                  order by r.created_at desc
                  limit 1) end
              ) as post
              from public.posts p
              where p.batch_id = b.id
            ) posts
          ), '[]'::jsonb)
        ) as batch
        from public.batches b
        where b.client_id = v_client.id and b.published
      ) batches
    ), '[]'::jsonb)
  );
end $$;

create or replace function public.quote_proceed_remind()
returns integer
language plpgsql volatile security definer set search_path = public as $$
declare
  r record;
  v_n int := 0;
begin
  for r in
    select q.id, q.ref, q.brand, q.client_id, q.proceed_due, q.proceed_start, q.proceed_decider
      from public.quotations q
      join public.clients c on c.id = q.client_id
     where q.source = 'website' and q.proceed_at is not null and q.proceed_reminded_at is null
       and q.removed_at is null and q.no_contact_at is null and q.status <> 'not_proceeding'
       and nullif(btrim(coalesce(c.owner, '')), '') is null and c.sales_by is null
       and now() >= q.proceed_due - interval '6 hours'
  loop
    update public.quotations set proceed_reminded_at = now() where id = r.id;
    insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
    select m.id, 'quote.proceed', 'Ready to proceed, waiting · ' || r.brand,
           r.ref || ' · ' || public.quote_proceed_words(r.proceed_start, r.proceed_decider) ||
             ' · nobody has taken the lead · contact by ' ||
             public.register_day((r.proceed_due at time zone 'Asia/Kuala_Lumpur')::date) || ', ' ||
             lower(to_char(r.proceed_due at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam')),
           r.client_id, 'quote.proceed:' || r.id || ':remind:' || m.id
      from public.team_members m
     where m.active
       and (m.is_admin or m.role = 'admin'
            or public.level_rank(coalesce(m.access ->> 'clients.leads', m.access ->> 'clients')) >= 3)
    on conflict (dedupe_key) do nothing;
    v_n := v_n + 1;
  end loop;
  -- A website quotation still waiting for the team six hours before its
  -- reply is owed (2026-10-29).
  for r in
    select q.id, q.ref, q.brand, q.client_id, q.reply_due
      from public.quotations q
     where q.source = 'website' and q.released_at is null and q.reply_due is not null
       and q.review_reminded_at is null and q.removed_at is null and q.status <> 'not_proceeding'
       and not exists (select 1 from public.quotations x where x.replaces = q.id and x.removed_at is null)
       and now() >= q.reply_due - interval '6 hours'
  loop
    update public.quotations set review_reminded_at = now() where id = r.id;
    insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
    select m.id, 'quote.website', 'Quotation to review, waiting · ' || r.brand,
           r.ref || ' · not sent to the prospect · send by ' ||
             public.register_day((r.reply_due at time zone 'Asia/Kuala_Lumpur')::date) || ', ' ||
             lower(to_char(r.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam')),
           r.client_id, 'quote.review:' || r.id || ':remind:' || m.id
      from public.team_members m
     where m.active
       and (m.is_admin or m.role = 'admin'
            or public.level_rank(coalesce(m.access ->> 'clients.leads', m.access ->> 'clients')) >= 3)
    on conflict (dedupe_key) do nothing;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
revoke all on function public.quote_proceed_remind() from public, anon, authenticated;

create or replace function public.client_details_submit(p_key text, p_answers jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_f    public.client_detail_forms;
  v_cl   public.clients;
  a      jsonb := coalesce(p_answers, '{}'::jsonb);
  t      text;
  v_name text := upper(btrim(regexp_replace(coalesce(a->>'legal_name', ''), '\s+', ' ', 'g')));
  v_brn  text := upper(regexp_replace(coalesce(a->>'company_no', ''), '\s+', '', 'g'));
  v_old  text := nullif(upper(regexp_replace(coalesce(a->>'company_no_old', ''), '\s+', '', 'g')), '');
  v_tin  text := nullif(upper(regexp_replace(coalesce(a->>'tin', ''), '\s+', '', 'g')), '');
  v_sst  text := nullif(upper(regexp_replace(coalesce(a->>'sst_no', ''), '\s+', '', 'g')), '');
  v_addr text := btrim(coalesce(a->>'billing_address', ''));
  v_fin  text := nullif(lower(btrim(coalesce(a->>'finance_email', ''))), '');
  v_sal  text := nullif(btrim(coalesce(a->>'contact_salutation', '')), '');
  v_cn   text := btrim(regexp_replace(coalesce(a->>'contact_name', ''), '\s+', ' ', 'g'));
  v_cp   text := btrim(coalesce(a->>'contact_phone', ''));
  v_ce   text := lower(btrim(coalesce(a->>'contact_email', '')));
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not_found'); end if;
  select * into v_f from public.client_detail_forms f where f.access_key = p_key and f.voided_at is null for update;
  if v_f.id is null then return jsonb_build_object('error', 'not_found'); end if;
  if v_f.submitted_at is not null then return jsonb_build_object('error', 'submitted'); end if;
  if v_f.expires_at <= now() then return jsonb_build_object('error', 'expired'); end if;
  if exists (select 1 from public.clients c where c.id = v_f.client_id and c.stage = 'past') then
    return jsonb_build_object('error', 'not_found');
  end if;
  if length(v_name) < 2 or length(v_name) > 160 then return jsonb_build_object('error', 'bad-legal_name'); end if;
  if v_brn !~ '^[A-Z0-9-]{6,20}$' then return jsonb_build_object('error', 'bad-company_no'); end if;
  if v_old is not null and v_old !~ '^[A-Z0-9-]{4,20}$' then return jsonb_build_object('error', 'bad-company_no_old'); end if;
  if v_tin is not null and v_tin !~ '^[A-Z0-9-]{6,20}$' then return jsonb_build_object('error', 'bad-tin'); end if;
  if v_sst is not null and v_sst !~ '^[A-Z0-9-]{6,25}$' then return jsonb_build_object('error', 'bad-sst_no'); end if;
  if length(v_addr) < 10 or length(v_addr) > 400 then return jsonb_build_object('error', 'bad-billing_address'); end if;
  if v_fin is not null and (v_fin !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_fin) > 160) then
    return jsonb_build_object('error', 'bad-finance_email');
  end if;
  if v_sal is not null and v_sal not in ('Mr', 'Ms', 'Mrs', 'Mdm', 'Dr', 'Prof', 'Dato''', 'Datin', 'Datuk',
      'Dato'' Sri', 'Datin Sri', 'Tan Sri', 'Puan Sri', 'Tun', 'Tuan', 'Puan', 'Encik', 'Cik') then
    return jsonb_build_object('error', 'bad-contact_salutation');
  end if;
  if length(v_cn) < 2 or length(v_cn) > 80 then return jsonb_build_object('error', 'bad-contact_name'); end if;
  t := regexp_replace(v_cp, '[^0-9]', '', 'g');
  if length(t) < 8 or length(t) > 15 or length(v_cp) > 30 then return jsonb_build_object('error', 'bad-contact_phone'); end if;
  if v_ce !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_ce) > 160 then return jsonb_build_object('error', 'bad-contact_email'); end if;

  update public.client_detail_forms f
     set submitted_at = now(),
         answers = jsonb_strip_nulls(jsonb_build_object(
           'legal_name', v_name, 'company_no', v_brn, 'company_no_old', v_old, 'tin', v_tin, 'sst_no', v_sst,
           'billing_address', v_addr, 'finance_email', v_fin, 'contact_salutation', v_sal,
           'contact_name', v_cn, 'contact_phone', v_cp, 'contact_email', v_ce))
   where f.id = v_f.id;
  select * into v_cl from public.clients c where c.id = v_f.client_id;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Details form', 'client.edited', v_cl.name,
          'Billing details received on the details form from ' || coalesce(v_sal || ' ', '') || v_cn);
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  select m.id, 'client.details', 'Billing details received · ' || v_cl.name,
         'From ' || coalesce(v_sal || ' ', '') || v_cn || '. Review them on the client''s Billing.',
         v_cl.id, 'client.details:' || v_f.id || ':' || m.id
    from public.team_members m
   where m.active
     and (m.is_admin or m.role = 'admin'
          or (public.level_rank(coalesce(m.access ->> 'clients.billing', m.access ->> 'clients')) >= 2
              -- held to the colleague's own client scope, as client_row_seen holds a reader (audit S7)
              and (v_cl.stage not in ('lead', 'contacted', 'proposal', 'past')
                   or public.level_rank(coalesce(m.access ->> case when v_cl.stage = 'past' then 'clients.past' else 'clients.leads' end,
                                                 m.access ->> 'clients')) >= 1)
              and (coalesce(m.client_scope, 'all') <> 'own'
                   or (nullif(btrim(coalesce(v_cl.owner, '')), '') is null and v_cl.stage in ('lead', 'contacted', 'proposal'))
                   or lower(btrim(coalesce(v_cl.owner, ''))) = lower(btrim(coalesce(m.name, '')))
                   or v_cl.sales_by = m.id)))
  on conflict (dedupe_key) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_details_submit(text, jsonb) from public;
grant execute on function public.client_details_submit(text, jsonb) to anon, authenticated;

create or replace function public.agent_schedule_do(s public.agent_schedules, m public.team_members)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p jsonb := s.payload;
  v jsonb;
  b public.batches;
  c public.clients;
  v_on boolean;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_n integer;
  v_what text;
  v_rec jsonb;
begin
  if s.kind = 'reminder' then
    insert into public.ops_notifications (team_member_id, task_id, report_id, client_id, kind, title, body, dedupe_key)
    values (m.id,
            (select t.id from public.ops_tasks t where t.id = nullif(p ->> 'task_id', '')::uuid),
            (select r.id from public.sm_reports r where r.id = nullif(p ->> 'report_id', '')::uuid),
            (select x.id from public.clients x where x.id = nullif(p ->> 'client_id', '')::uuid),
            'assistant.reminder', left(s.title, 200), left(p ->> 'message', 500), 'agent.' || s.id)
    on conflict (dedupe_key) do nothing;
    return jsonb_build_object('ok', true, 'said', 'Reminder sent to you.');
  end if;
  if s.kind = 'mark_sent' then
    v := public.sm_report_sent((p ->> 'report_id')::uuid, coalesce(nullif(p ->> 'sent_on', '')::date, v_today));
    if v ? 'error' then return v; end if;
    insert into public.activity_log (actor, action, subject, detail)
    values (m.name, 'assistant.report', s.title, 'Marked as sent ' || public.register_day(v_today) || ' · scheduled through the Assistant');
    return jsonb_build_object('ok', true, 'said', 'Marked as sent.');
  end if;
  if s.kind = 'add_task' then
    v := public.ops_create_task(p, 'agent-schedule-' || s.id::text);
    if v ? 'error' then return v; end if;
    insert into public.activity_log (actor, action, subject, detail)
    values (m.name, 'assistant.task', coalesce((select x.name from public.clients x where x.id = nullif(p ->> 'client_id', '')::uuid), 'Internal'),
            'Task added: ' || coalesce(p ->> 'title', '') || ' · scheduled through the Assistant');
    return jsonb_build_object('ok', true, 'said', 'Task added.', 'task_id', v ->> 'id');
  end if;
  if s.kind in ('publish_set', 'unpublish_set') then
    if not public.allowed('review.sets', 'work') then return jsonb_build_object('error', 'denied'); end if;
    select * into b from public.batches x where x.id = (p ->> 'set_id')::uuid for update;
    if b.id is null or not public.client_seen(b.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
    v_on := s.kind = 'publish_set';
    if v_on and not exists (select 1 from public.posts po where po.batch_id = b.id) then
      return jsonb_build_object('error', 'empty');
    end if;
    if b.published = v_on then return jsonb_build_object('ok', true, 'said', case when v_on then 'Already published.' else 'Already unpublished.' end); end if;
    update public.batches x set published = v_on where x.id = b.id;
    select * into c from public.clients x where x.id = b.client_id;
    insert into public.activity_log (actor, action, subject, detail)
    values (m.name, case when v_on then 'set.published' else 'set.withdrawn' end, c.name || ' — ' || b.title, null),
           (m.name, 'assistant.set', c.name || ' — ' || b.title,
            case when v_on then 'Published' else 'Unpublished' end || ' · scheduled through the Assistant');
    return jsonb_build_object('ok', true, 'said', case when v_on then 'Published.' else 'Unpublished.' end);
  end if;
  if s.kind = 'whatsapp' then
    v := public.wa_compose_prepare('contact', (p ->> 'to_id')::uuid, p ->> 'purpose', nullif(p ->> 'ref', '')::uuid);
    if v ? 'error' then return v; end if;
    if not exists (select 1 from public.wa_templates t where t.purpose = p ->> 'purpose' and t.active and t.name <> '') then
      return jsonb_build_object('error', 'wa-off');
    end if;
    v_rec := public.wa_sent_recently('contact', (p ->> 'to_id')::uuid, p ->> 'purpose', nullif(p ->> 'ref', '')::uuid, null);
    if coalesce((v_rec ->> 'recent')::boolean, false) then
      return jsonb_build_object('skip', true, 'said', 'Not sent: it was sent on WhatsApp recently.');
    end if;
    /* What waits, as the composer words it: the set's undecided posts, or
       the creator's draft. */
    if p ->> 'purpose' = 'approval' then
      select * into b from public.batches x where x.id = nullif(p ->> 'ref', '')::uuid;
      if b.id is not null then
        select count(*)::int into v_n from public.posts po
         where po.batch_id = b.id
           and not exists (select 1 from public.reviews r where r.post_id = po.id and r.undone_at is null
                              and coalesce(r.round, 1) = coalesce(po.round, 1)
                              and (po.review_reset_at is null or r.created_at > po.review_reset_at));
        v_what := v_n || case when v_n = 1 then ' post' else ' posts' end || ' in ' || b.title;
      else
        v_what := coalesce(nullif(p ->> 'what', ''), 'A draft');
      end if;
    end if;
    perform public.wa_enqueue(p ->> 'purpose', v ->> 'number', v ->> 'name',
      jsonb_build_array(v ->> 'greeting', v ->> 'client',
        case p ->> 'purpose' when 'approval' then v_what when 'representative' then v ->> 'rep' else '' end,
        case when p ->> 'purpose' = 'approval' then 'https://digital.adspace.me/' || coalesce(v ->> 'link', '') else '' end),
      v ->> 'ref_kind', nullif(p ->> 'ref', '')::uuid, (v ->> 'client_id')::uuid,
      case p ->> 'purpose' when 'approval' then v ->> 'link' when 'representative' then v ->> 'code' end);
    /* Sent for a colleague, never Automatic. */
    update public.wa_outbox o set created_by = m.name, to_kind = 'contact', to_id = (p ->> 'to_id')::uuid
     where o.id = (select x.id from public.wa_outbox x where x.created_by = 'system' and x.created_at = now()
                      and x.purpose = p ->> 'purpose' and x.to_number = v ->> 'number' order by x.id limit 1);
    insert into public.activity_log (actor, action, subject, detail)
    values (m.name, 'assistant.whatsapp', coalesce(v ->> 'subject', s.title),
            'Sent on WhatsApp to ' || coalesce(v ->> 'name', '') || ' · scheduled through the Assistant');
    return jsonb_build_object('ok', true, 'said', 'Sent on WhatsApp.');
  end if;
  return jsonb_build_object('error', 'bad-kind');
end $$;
revoke all on function public.agent_schedule_do(public.agent_schedules, public.team_members) from public, anon, authenticated;

create or replace function public.creator_bill_prep(p_option uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  o  public.campaign_options;
  m  public.campaigns;
  c  public.creators;
  f  public.creator_fees;
  l  public.bukku_links;
  b  public.bukku_settings;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_fx numeric := 1;
begin
  if me.id is null or not public.ops_granted('campaigns.pay', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into o from public.campaign_options x where x.id = p_option for update;
  if o.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if o.state not in ('posted', 'completed') then return jsonb_build_object('error', 'not-posted'); end if;
  select * into f from public.creator_fees x where x.option_id = o.id;
  if f.option_id is null or f.amount <= 0 then return jsonb_build_object('error', 'no-fee'); end if;
  -- A fee is billed in the currency the creator is paid in now (audit 2026-11-15).
  if f.currency is distinct from public.creator_pay_currency(o.creator_id) then
    return jsonb_build_object('error', 'currency-changed', 'currency', public.creator_pay_currency(o.creator_id));
  end if;
  select * into l from public.bukku_links x where x.kind = 'creator' and x.record_id = o.creator_id;
  if l.contact_id is null then return jsonb_build_object('error', 'not-linked'); end if;
  if exists (select 1 from public.creator_bills x where x.option_id = o.id and not x.gone) then return jsonb_build_object('error', 'billed'); end if;
  select * into b from public.bukku_settings where id = 1;
  if b.bill_account is null then return jsonb_build_object('error', 'no-account'); end if;
  if f.currency = 'SGD' then
    v_fx := nullif(public.app_setting('fx_sgd', v_today), 0);
    if v_fx is null then return jsonb_build_object('error', 'no-fx'); end if;
  end if;
  if exists (select 1 from public.creator_bill_claims k where k.option_id = o.id and k.claimed_at > now() - interval '10 minutes') then
    return jsonb_build_object('error', 'creating');
  end if;
  insert into public.creator_bill_claims (option_id, claimed_by, claimed_at) values (o.id, me.id, now())
  on conflict (option_id) do update set claimed_by = excluded.claimed_by, claimed_at = now();
  select * into m from public.campaigns x where x.id = o.campaign_id;
  select * into c from public.creators x where x.id = o.creator_id;
  return jsonb_build_object('ok', true, 'creator', o.creator_id, 'contact_id', l.contact_id, 'amount', f.amount, 'currency', f.currency,
    'fx', v_fx, 'ref', public.creator_job_ref(o.id), 'date', v_today,
    'due', case when o.pay_by >= v_today then o.pay_by end, 'account', b.bill_account,
    'description', left(coalesce(nullif(btrim(m.title), ''), 'Creator campaign') || ' · ' || coalesce(c.name, ''), 200));
end $$;
revoke all on function public.creator_bill_prep(uuid) from public, anon;
grant execute on function public.creator_bill_prep(uuid) to authenticated;

create or replace function public.creator_submit(p_code text, p_option uuid, p_caption text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_id   uuid;
  v_lock integer;
  cr creators%rowtype;
  o  campaign_options%rowtype;
  n  integer;
begin
  -- The code through creator_code_try, so a wrong one is counted (audit 2026-11-15).
  select t.o_creator, t.o_locked into v_id, v_lock from public.creator_code_try(p_code) t;
  if v_lock is not null then return jsonb_build_object('error', 'locked', 'minutes', v_lock); end if;
  select * into cr from creators where id = v_id and active;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  select * into o from campaign_options where id = p_option and creator_id = cr.id;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if not public.creator_can_deliver(o.state) then
    return jsonb_build_object('error', 'closed');
  end if;
  -- What a creator types is held to a length (audit 2026-10-18, item 12).
  if length(coalesce(p_caption, '')) > 5000 then return jsonb_build_object('error', 'too-long'); end if;
  select count(*) into n from campaign_deliverables
   where option_id = p_option and removed_at is null;
  if n = 0 then return jsonb_build_object('error', 'empty'); end if;

  /* `submitted` is ours, not the client's. It used to move straight to
     `reviewing`, which on the client's page reads "Your approval": the chip
     asked them to act the moment a creator uploaded, while the files are
     team-only, so there was nothing there for them to open. The team reviews
     it and releases it. */
  update campaign_options
     set state = 'submitted', draft_caption = p_caption, submitted_at = now(),
         changes_by = null          -- that round is over, whoever raised it
   where id = p_option;

  -- A creator is a party to this too, and when they handed in is exactly the
  -- fact a late delivery turns on.
  insert into public.activity_log (actor, action, subject, detail)
  select cr.name, 'campaign.submitted', c.title,
         n::text || ' file' || case when n = 1 then '' else 's' end || ' handed in'
         || case when o.state = 'submitted' then ' · updated' else '' end
    from campaigns c where c.id = o.campaign_id;

  return jsonb_build_object('ok', true, 'files', n);
end $$;

create or replace function public.creator_add_file(
  p_code text, p_option uuid, p_url text, p_name text, p_kind text, p_bytes bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_id   uuid;
  v_lock integer;
  cr     creators%rowtype;
  o      campaign_options%rowtype;
  new_id uuid;
begin
  -- The code through creator_code_try, so a wrong one is counted (audit 2026-11-15).
  select t.o_creator, t.o_locked into v_id, v_lock from public.creator_code_try(p_code) t;
  if v_lock is not null then return jsonb_build_object('error', 'locked', 'minutes', v_lock); end if;
  select * into cr from creators where id = v_id and active;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  /* Qualified, and the variable is not called `id`. A declared `id` against an
     unqualified `where id = p_option` is ambiguous, which PL/pgSQL raises at
     run time rather than at create time: every upload failed in production
     while the schema applied cleanly and every browser suite stayed green. */
  select * into o from campaign_options co
   where co.id = p_option and co.creator_id = cr.id;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if not public.creator_can_deliver(o.state) then
    return jsonb_build_object('error', 'closed');
  end if;
  /* Only the address sign-upload made for this booking: the CDN, the
     creator's folder for this booking, a random name and a short extension.
     Nothing in it can close the attribute a page draws it in (audit 2026-10-16). */
  if p_url is null or p_url !~ ('^https://mycdn\.adspace\.me/content/creator/' || p_option::text
       || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.[a-z0-9]{1,5}$') then
    return jsonb_build_object('error', 'bad-file');
  end if;
  if p_name is null or char_length(btrim(p_name)) not between 1 and 255 then
    return jsonb_build_object('error', 'bad-name');
  end if;
  if p_kind is not null and p_kind not in ('image', 'video', 'file') then
    return jsonb_build_object('error', 'bad-kind');
  end if;
  insert into campaign_deliverables (option_id, url, name, kind, bytes, round)
  values (p_option, p_url, p_name, coalesce(p_kind, 'file'), p_bytes,
          greatest(o.revision_round, 1))
  returning campaign_deliverables.id into new_id;
  return jsonb_build_object('id', new_id);
end $$;
grant execute on function public.creator_add_file(text, uuid, text, text, text, bigint) to anon, authenticated;

create or replace function public.creator_remove_file(p_code text, p_file uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_id   uuid;
  v_lock integer;
  cr creators%rowtype;
  n  integer;
begin
  -- The code through creator_code_try, so a wrong one is counted (audit 2026-11-15).
  select t.o_creator, t.o_locked into v_id, v_lock from public.creator_code_try(p_code) t;
  if v_lock is not null then return jsonb_build_object('error', 'locked', 'minutes', v_lock); end if;
  select * into cr from creators where id = v_id and active;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  update campaign_deliverables d set removed_at = now()
   where d.id = p_file and d.removed_at is null
     and exists (select 1 from campaign_options o
                  where o.id = d.option_id and o.creator_id = cr.id
                    and public.creator_can_retract(o.state));
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('error', 'not-found'); end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.creator_rate(p_code text, p_option uuid, p_stars integer)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_id   uuid;
  v_lock integer;
  cr creators%rowtype;
  o  campaign_options%rowtype;
begin
  if p_stars is not null and (p_stars < 1 or p_stars > 5) then
    return jsonb_build_object('error', 'range');
  end if;
  -- The code through creator_code_try, so a wrong one is counted (audit 2026-11-15).
  select t.o_creator, t.o_locked into v_id, v_lock from public.creator_code_try(p_code) t;
  if v_lock is not null then return jsonb_build_object('error', 'locked', 'minutes', v_lock); end if;
  select * into cr from creators where id = v_id and active;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  select * into o from campaign_options where id = p_option and creator_id = cr.id;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if o.state <> 'completed' then return jsonb_build_object('error', 'closed'); end if;

  update campaign_options set creator_rating = p_stars where id = p_option;

  insert into public.activity_log (actor, action, subject, detail)
  select cr.name, 'campaign.rated', c.title,
         coalesce(p_stars::text || ' of 5', 'rating cleared')
    from campaigns c where c.id = o.campaign_id;

  return jsonb_build_object('ok', true, 'rating', p_stars);
end $$;

create or replace function public.creator_post_save(
  p_code text, p_option uuid, p_platform text, p_url text, p_published date,
  p_impressions bigint, p_engagements bigint, p_views bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_id   uuid;
  v_lock integer;
  cr     creators%rowtype;
  o      campaign_options%rowtype;
  p      option_posts%rowtype;
  v_plat text;
  v_url  text := nullif(btrim(coalesce(p_url, '')), '');
  v_nums boolean := p_impressions is not null or p_engagements is not null or p_views is not null;
  v_live boolean := false;
begin
  -- The code through creator_code_try, so a wrong one is counted (audit 2026-11-15).
  select t.o_creator, t.o_locked into v_id, v_lock from public.creator_code_try(p_code) t;
  if v_lock is not null then return jsonb_build_object('error', 'locked', 'minutes', v_lock); end if;
  select * into cr from creators where id = v_id and active;
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

create or replace function public.creator_may_upload(p_code text, p_option uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_lock integer;
begin
  -- The code through creator_code_try, so a wrong one is counted (audit 2026-11-15).
  select t.o_creator, t.o_locked into v_id, v_lock from public.creator_code_try(p_code) t;
  if v_id is null or v_lock is not null then return false; end if;
  return exists (
    select 1 from campaign_options o
    join creators cr on cr.id = o.creator_id
    where o.id = p_option and cr.active and cr.id = v_id
      and public.creator_can_deliver(o.state));
end $$;

-- A decision is on the version on show: the older entry is internal.
revoke all on function public.submit_review(text, uuid, text, text, text, text, text, text) from public, anon, authenticated;

-- END OF AUDIT FIXES ---------------------------------------------------------
select public.functions_tidy();
