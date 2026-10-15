-- ===========================================================================
-- DATA HELD TO ITS LEVEL — what a function answers or tells is held to the
-- reader's own parts and scope, and a document no longer standing is not
-- sent (2026-10-15)
-- ===========================================================================
-- WHY (the audit of 2026-10-15, S4, S7, S10, S11, I7, I12)
--   * S4: the Pre-Advertising Checklist prefilled the registered name (a
--     billing column) and the newest quotation for any Clients View reader,
--     and the onboarding hint named the quotation too.
--   * S7: "Billing details received" told every colleague at Clients:
--     Billing Work, whatever their client scope; S10: the details form kept
--     a contact phone of any length.
--   * S11: WhatsApp sent a superseded Letter of Offer or a quotation marked
--     Not proceeding when a page asked.
--   * I7: Undo after Accept caption overwrote a correction made since, from
--     a caption the page sent.
--   * I12: the greeting said "Ms Ms Jane Doe" and "Tan" for Tan Sri Ahmad.
--
-- WHAT CHANGED
--   * `checklist_prefill` names the registered name only for a reader at
--     Clients: Billing View (or Documents Work), else the brand; the
--     quotation only at Clients: Services View. `client_checklist`'s
--     quotation hint asks the same.
--   * `client_details_submit` tells a colleague only where their bands and
--     client scope reach the client (as `client_row_seen`), and refuses a
--     contact phone of more than 30 characters (`bad-contact_phone`).
--   * `wa_compose_prepare` refuses `void` for a quotation Not proceeding and
--     a superseded letter.
--   * `review_caption_undo` puts back the round kept in `post_versions`, and
--     refuses `moved` where the file, title or caption changed since the
--     accept.
--   * `contact_greeting` says a salutation once and keeps Tan Sri, Puan Sri,
--     Dato' Sri, Datin Sri and Datuk Sri whole.
--
-- ORDER
--   This file alone; no page changes. A page from before reads the same
--   shapes (a refusal it does not name reads in its general words).
--
-- Safe to run twice. Rollback: run CLIENT CHECKLISTS' checklist_prefill
-- and client_checklist, CLIENT DETAILS FORM's client_details_submit,
-- WHATSAPP DOCUMENTS' wa_compose_prepare, ACCEPT CAPTION UNDO's
-- review_caption_undo and WHATSAPP GREETING AND COUNTS' contact_greeting
-- again.
-- ===========================================================================

create or replace function public.checklist_prefill(p_client uuid, p_kind text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c public.clients;
  q text;
  sw jsonb;
  j text := E'\n';
begin
  select * into c from public.clients where id = p_client;
  if c.id is null or p_kind <> 'pre_ads' then return '{}'::jsonb; end if;
  select x.ref into q from public.quotations x
   where x.client_id = p_client and x.removed_at is null order by x.issued_at desc limit 1;
  select b.analysis->'swot' into sw from public.brand_analyses b
   where b.client_id = p_client and b.confirmed_at is not null order by b.version desc limit 1;
  return jsonb_strip_nulls(jsonb_build_object(
    -- The registered name is Billing's, and a quotation Services' (audit S4):
    -- each is prefilled only for a reader who may open it.
    'details.entity', nullif(coalesce(case when public.allowed('clients.billing', 'view') or public.register_may('client', 'work')
                                           then nullif(btrim(c.legal_name), '') end, c.name), ''),
    'details.quotation', case when public.allowed('clients.services', 'view') then q end,
    'competitors.direct', nullif(btrim(coalesce(c.brief->>'competitors', '')), ''),
    'competitors.strength', nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(sw->'strengths', '[]'::jsonb))), j), ''),
    'competitors.weakness', nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(sw->'weaknesses', '[]'::jsonb))), j), ''),
    'competitors.opportunities', nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(sw->'opportunities', '[]'::jsonb))), j), ''),
    'competitors.threats', nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(sw->'threats', '[]'::jsonb))), j), '')));
end $$;
revoke all on function public.checklist_prefill(uuid, text) from public, anon, authenticated;

create or replace function public.client_checklist(p_client uuid, p_kind text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  r public.client_checklists;
  t jsonb;
  pre jsonb;
  hints jsonb := '{}'::jsonb;
  q record;
  m timestamptz;
begin
  if me.id is null or not public.allowed('clients', 'view') then return jsonb_build_object('error', 'denied'); end if;
  if not public.client_scope_ok('client', p_client, 'view') then return jsonb_build_object('error', 'client-scope'); end if;
  if p_kind not in ('onboarding', 'pre_ads') then return jsonb_build_object('error', 'bad-kind'); end if;
  select * into r from public.client_checklists where client_id = p_client and kind = p_kind;
  t := coalesce(r.template, public.checklist_template(p_kind));
  if r.id is null then pre := public.checklist_prefill(p_client, p_kind); end if;
  if p_kind = 'onboarding' and public.allowed('clients.services', 'view') then
    select x.ref, x.issued_at into q from public.quotations x
     where x.client_id = p_client and x.removed_at is null order by x.issued_at desc limit 1;
    if q.ref is not null then
      hints := hints || jsonb_build_object('pre.quotation', 'Quotation ' || q.ref || ' issued ' ||
        to_char(q.issued_at at time zone 'Asia/Kuala_Lumpur', 'FMDD Mon YYYY'));
    end if;
  end if;
  if p_kind = 'onboarding' then
    select min(e.meeting_at) into m from public.ops_engagements e where e.client_id = p_client and e.meeting_at is not null;
    if m is not null then
      hints := hints || jsonb_build_object('pre.first_meeting', 'Meeting set for ' ||
        to_char(m at time zone 'Asia/Kuala_Lumpur', 'FMDD Mon YYYY, FMHH12:MIam'));
    end if;
  end if;
  return jsonb_build_object(
    'kind', p_kind, 'title', t->>'title', 'version', t->>'version', 'lead', t->>'lead', 'sections', t->'sections',
    'started', r.id is not null, 'answers', coalesce(r.answers, '{}'::jsonb), 'prefill', coalesce(pre, '{}'::jsonb),
    'sections_na', to_jsonb(coalesce(r.sections_na, '{}'::text[])), 'status', coalesce(r.status, 'open'),
    'prepared', case when r.prepared_at is not null then jsonb_build_object('id', r.prepared_by, 'name', r.prepared_name, 'at', r.prepared_at) end,
    'reviewed', case when r.reviewed_at is not null then jsonb_build_object('id', r.reviewed_by, 'name', r.reviewed_name, 'at', r.reviewed_at) end,
    'history', jsonb_array_length(coalesce(r.history, '[]'::jsonb)),
    'hints', hints, 'me', me.id,
    'can_work', public.allowed('clients', 'work') and public.client_scope_ok('client', p_client, 'work'),
    'can_manage', public.allowed('clients', 'manage') and public.client_scope_ok('client', p_client, 'manage'),
    'updated_at', r.updated_at);
end $$;
revoke all on function public.client_checklist(uuid, text) from public, anon;
grant execute on function public.client_checklist(uuid, text) to authenticated;

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
  values (coalesce(v_sal || ' ', '') || v_cn, 'client.edited', v_cl.name, 'Billing details received on the details form');
  insert into public.ops_notifications (team_member_id, kind, title, body, client_id, dedupe_key)
  select m.id, 'client.details', 'Billing details received · ' || v_cl.name,
         'From ' || coalesce(v_sal || ' ', '') || v_cn || '. Review them on the client''s Billing.',
         v_cl.id, 'client.details:' || v_f.id || ':' || m.id
    from public.team_members m
   where m.active and not coalesce(m.system, false)
     and (m.is_admin or m.role = 'admin'
          or (public.level_rank(coalesce(m.access ->> 'clients.billing', m.access ->> 'clients')) >= 2
              -- held to the colleague's own client scope, as client_row_seen holds a reader (audit S7)
              and (v_cl.stage not in ('lead', 'contacted', 'proposal', 'past')
                   or public.level_rank(coalesce(m.access ->> case when v_cl.stage = 'past' then 'clients.past' else 'clients.leads' end,
                                                 m.access ->> 'clients')) >= 1)
              and (coalesce(m.client_scope, 'all') <> 'own'
                   or (nullif(btrim(coalesce(v_cl.owner, '')), '') is null and v_cl.stage in ('lead', 'contacted', 'proposal'))
                   or lower(btrim(coalesce(v_cl.owner, ''))) = lower(btrim(coalesce(m.name, ''))))))
  on conflict (dedupe_key) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.client_details_submit(text, jsonb) from public;
grant execute on function public.client_details_submit(text, jsonb) to anon, authenticated;

create or replace function public.wa_compose_prepare(p_to_kind text, p_to uuid, p_purpose text, p_ref uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me   public.team_members := public.ops_me();
  k    public.client_contacts;
  cr   public.creators;
  c    public.clients;
  r    public.sm_reports;
  o    public.campaign_options;
  cp   public.campaigns;
  b    public.batches;
  q    public.quotations;
  d    public.client_documents;
  v_n  text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_purpose not in ('message', 'report', 'feedback', 'creator', 'approval', 'quotation', 'offer')
     or p_to_kind not in ('contact', 'creator')
     or (p_purpose in ('report', 'feedback', 'approval', 'quotation', 'offer') and p_to_kind <> 'contact')
     or (p_purpose = 'creator' and p_to_kind <> 'creator') then
    return jsonb_build_object('error', 'bad-request');
  end if;
  if not public.wa_may_send(p_purpose, p_to_kind) then return jsonb_build_object('error', 'denied'); end if;
  if p_to_kind = 'contact' then
    select * into k from public.client_contacts x where x.id = p_to and x.archived_at is null;
    if k.id is null then return jsonb_build_object('error', 'not-found'); end if;
    select * into c from public.clients x where x.id = k.client_id;
    if c.id is null or not public.client_seen(c.id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
    if p_purpose = 'report' then
      select * into r from public.sm_reports x where x.id = p_ref;
      if r.id is null or r.client_id <> c.id then return jsonb_build_object('error', 'not-found'); end if;
      if r.status <> 'published' then return jsonb_build_object('error', 'not-published'); end if;
    end if;
    /* A quotation or a Letter of Offer is the contact's own client's: a
       quotation not removed, a letter not voided. */
    if p_purpose = 'quotation' then
      select * into q from public.quotations x where x.id = p_ref;
      if q.id is null or q.client_id <> c.id or q.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
      if q.status = 'not_proceeding' then return jsonb_build_object('error', 'void'); end if;
    end if;
    if p_purpose = 'offer' then
      select * into d from public.client_documents x where x.id = p_ref;
      if d.id is null or d.client_id <> c.id or d.kind not in ('offer', 'intent', 'cover') then
        return jsonb_build_object('error', 'not-found');
      end if;
      if (d.voided_at is not null or d.superseded_by is not null) then return jsonb_build_object('error', 'void'); end if;
    end if;
    /* An approval reminder names what waits on the client: a published
       content set of theirs, or a creator's draft at Reviewing on a
       campaign of theirs, each read at its own section. */
    if p_purpose = 'approval' then
      select * into b from public.batches x where x.id = p_ref;
      if b.id is not null then
        if b.client_id <> c.id or not public.allowed('review.sets', 'view') then return jsonb_build_object('error', 'not-found'); end if;
        if not coalesce(b.published, false) then return jsonb_build_object('error', 'not-waiting'); end if;
      else
        select * into o from public.campaign_options x where x.id = p_ref;
        if o.id is not null then select * into cp from public.campaigns x where x.id = o.campaign_id; end if;
        if o.id is null or cp.id is null or cp.client_id is distinct from c.id or not public.allowed('campaigns.campaigns', 'view') then
          return jsonb_build_object('error', 'not-found');
        end if;
        if o.state <> 'reviewing' then return jsonb_build_object('error', 'not-waiting'); end if;
      end if;
    end if;
    v_n := public.wa_number(coalesce(case when k.whatsapp !~ '^@' then k.whatsapp end, k.phone), c.market);
    if v_n is null then
      return jsonb_build_object('error', case when k.whatsapp ~ '^@' then 'username' else 'no-number' end);
    end if;
    return jsonb_build_object('ok', true, 'number', v_n, 'name', k.name, 'greeting', public.contact_greeting(k.salutation, k.name),
      'client_id', c.id, 'client', case when r.id is not null then coalesce(nullif(r.brand_name, ''), c.name) else c.name end,
      'subject', c.name, 'ref_kind', case when b.id is not null then 'set' when o.id is not null then 'option'
                       when q.id is not null then 'quotation' when d.id is not null then 'offer' end);
  end if;
  select * into cr from public.creators x where x.id = p_to;
  if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if p_purpose = 'creator' then
    select * into o from public.campaign_options x where x.id = p_ref;
    if o.id is null or o.creator_id <> cr.id then return jsonb_build_object('error', 'not-found'); end if;
    select * into cp from public.campaigns x where x.id = o.campaign_id;
    if cp.id is null or (cp.client_id is not null and not public.client_seen(cp.client_id, 'view')) then
      return jsonb_build_object('error', 'not-found');
    end if;
    if o.state in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced') then
      return jsonb_build_object('error', 'not-booked');
    end if;
  elsif not cr.active then
    return jsonb_build_object('error', 'not-found');
  end if;
  v_n := public.wa_number(cr.whatsapp, 'MY');
  if v_n is null then return jsonb_build_object('error', 'no-creator-number'); end if;
  return jsonb_build_object('ok', true, 'number', v_n, 'name', cr.name, 'greeting', split_part(btrim(cr.name), ' ', 1),
    'client_id', cp.client_id,
    'campaign', case when cp.id is not null then coalesce(nullif(btrim(cp.title), ''), 'Your campaign') end,
    'code', cr.access_code, 'subject', coalesce(nullif(btrim(cp.title), ''), cr.name));
end $$;
revoke all on function public.wa_compose_prepare(text, uuid, text, uuid) from public, anon;
grant execute on function public.wa_compose_prepare(text, uuid, text, uuid) to authenticated;

create or replace function public.review_caption_undo(p_post uuid, p_round int, p_caption text, p_caption_zh text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me       public.team_members;
  v_post   public.posts%rowtype;
  v_was    public.post_versions%rowtype;
  v_ask    public.reviews%rowtype;
begin
  if not public.allowed('review.sets', 'work') then
    return jsonb_build_object('error', 'denied');
  end if;
  select * into me from public.ops_me();
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  select * into v_post from public.posts where id = p_post for update;
  if v_post.id is null then return jsonb_build_object('error', 'no-post'); end if;
  if p_round is null or v_post.round is distinct from p_round + 1
     or exists (select 1 from public.reviews r
                 where r.post_id = v_post.id and r.round = v_post.round and r.undone_at is null
                   and (v_post.review_reset_at is null or r.created_at > v_post.review_reset_at)) then
    return jsonb_build_object('error', 'moved');
  end if;
  -- Only the accepted caption is taken back (audit I7): the round it
  -- replaced is the one kept, and a file, title or caption changed since
  -- the accept is a correction the undo would lose.
  select * into v_was from public.post_versions x
   where x.post_id = v_post.id and x.round = p_round order by x.replaced_at desc limit 1;
  select * into v_ask from public.reviews r
   where r.post_id = v_post.id and r.round = p_round and r.undone_at is null
   order by r.created_at desc limit 1;
  if v_was.id is null or v_post.media is distinct from v_was.media or v_post.title is distinct from v_was.title
     or v_post.caption is distinct from coalesce(v_ask.suggested_caption, v_was.caption)
     or v_post.caption_zh is distinct from coalesce(v_ask.suggested_caption_zh, v_was.caption_zh) then
    return jsonb_build_object('error', 'moved');
  end if;
  update public.posts
     set caption = v_was.caption, caption_zh = v_was.caption_zh, round = p_round
   where id = v_post.id;

  return jsonb_build_object('ok', true, 'round', p_round);
end $$;
revoke all on function public.review_caption_undo(uuid, int, text, text) from public, anon;
grant execute on function public.review_caption_undo(uuid, int, text, text) to authenticated;

create or replace function public.contact_greeting(p_salutation text, p_name text)
returns text
language sql immutable set search_path = public as $$
  -- A salutation is said once, however the name was keyed, and the two-word
  -- titles are whole (audit I12): never "Ms Ms Jane Doe", never "Tan".
  select case when x.s <> ''
              then x.s || ' ' || case when lower(x.n) like lower(x.s) || ' %' then substr(x.n, length(x.s) + 2) else x.n end
              when lower(x.n) ~ '^(tan sri|puan sri|dato''? sri|datin sri|datuk sri) '
              then x.n
              when lower(split_part(x.n, ' ', 1)) ~ '^(mr|ms|mrs|mdm|dr|prof|dato''?|datin|datuk|puan|tun|tuan|encik|cik|madam|miss)\.?$'
               and position(' ' in x.n) > 0
              then x.n
              else split_part(x.n, ' ', 1) end
    from (select btrim(coalesce(p_salutation, '')) as s,
                 btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')) as n) x
$$;
revoke all on function public.contact_greeting(text, text) from public, anon, authenticated;


-- END OF DATA HELD TO ITS LEVEL ---------------------------------------------
select public.functions_tidy();
