-- ===========================================================================
-- AGENCY VALUES ON THE SERVER (2026-11-28)
-- ===========================================================================
-- WHY: the restructure's release 8 (docs/MAP.md §G). Functions still typed
-- the agency's values (the portal's domain in every link a notice or email
-- carries, the link domain, the CDN a creator's file is held to, the
-- agency's name where a record names no colleague): an install of another
-- agency would have sent its people to this one's addresses.
-- WHAT IT CHANGES: each function below is restated from its last definition
-- with every such value read by `agency(key)` (`portal_domain`,
-- `link_domain`, `cdn_base`, `trading_name`). Nothing else in any body
-- changes, and every answer is the one it gave before while the profile
-- holds its seed. Signatures, grants and refusals are unchanged.
--   quotation_record, link_resolve, creator_add_file, ops_outstation_remind,
--   mail_log, client_proposal_sent, creator_mail_queue, creator_mail_job,
--   campaign_options_posted_mail, agent_schedule_do,
--   creator_pay_requests_notice, hiring_person_set, hiring_tell,
--   hiring_tell_once, health_daily, feedback_mail_begin, outstation_remind,
--   feedback_wa_copy, quotation_details_ask, quote_details_mail_begin.
-- Left as they stand: `client_brand_logo` (its stored logo value is an
-- identifier a check holds), the function wake calls (the project's own
-- address, not the agency's), the seeded templates' words (the template
-- store's releases) and the checklist and personnel field templates.
-- ORDER: `2026-11-28-agency-profile.sql` first (live), then this file. No
-- page and no edge function changes with it; an open tab meets the same
-- answers before and after.
-- ROLLBACK: run each function's previous definition again (the band of
-- schema.sql before this one that last defines it). Safe to run twice.

-- AGENCY VALUES ON THE SERVER ------------------------------------------------

create or replace function public.quotation_record(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  q public.quotations;
  s jsonb;
  v_steps jsonb := '[]'::jsonb;
begin
  if not public.is_team() or not public.allowed('clients.quotes', 'view') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'view') then
    return jsonb_build_object('error', 'not-found');
  end if;
  s := q.signed;
  v_steps := jsonb_build_array(jsonb_build_object('step', 'issued', 'at', q.issued_at,
    'by', case when q.source = 'website' then null else q.made_by end, 'team', q.source <> 'website',
    'note', 'Rate Card v.' || q.version));
  if q.source = 'website' and q.released_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'sent', 'at', q.released_at, 'by', q.released_by,
      'team', true, 'via', 'link'));
  end if;
  v_steps := v_steps || coalesce((
    select jsonb_agg(jsonb_build_object('step', 'sent', 'at', w.created_at, 'by', coalesce(w.created_by, public.agency('trading_name')), 'team', true,
             'via', 'whatsapp', 'to', w.to_name,
             'state', case when w.read_at is not null then 'read' when w.delivered_at is not null then 'delivered' else w.state end))
      from public.wa_outbox w
     where w.ref_kind = 'quotation' and w.ref_id = q.id and coalesce(w.state, '') <> 'failed'), '[]'::jsonb);
  v_steps := v_steps || coalesce((
    select jsonb_agg(jsonb_build_object('step', 'sent', 'at', e.created_at,
             'by', coalesce((select m.name from public.team_members m where m.id = e.sent_by), public.agency('trading_name')), 'team', true,
             'via', 'email', 'to', e.to_email, 'state', e.status))
      from public.client_emails e
     where e.kind = 'quotation' and e.ref_id = q.id and e.status <> 'failed'), '[]'::jsonb);
  v_steps := v_steps || coalesce((
    select jsonb_agg(jsonb_build_object('step', g.step, 'at', g.at, 'team', false, 'email', g.email,
             'in_contacts', g.in_contacts, 'ip', g.ip, 'country', g.country, 'device', g.device))
      from public.signing_steps g
     where g.doc_kind = 'quotation' and g.doc_id = q.id), '[]'::jsonb);
  if q.signed_at is not null and s is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'signed', 'at', q.signed_at, 'team', false,
      'by', s->'signer'->>'name', 'role', s->'signer'->>'designation', 'via', coalesce(s->>'via', 'online'),
      'company', s->'company'->>'legal_name',
      'email', s->'record'->>'email', 'in_contacts', (s->'record'->>'in_contacts')::boolean,
      'ip', s->'record'->>'ip', 'country', s->'record'->>'country',
      'device', coalesce(s->'record'->>'device', s->'record'->>'agent'),
      'entered_by', case when s->>'via' = 'paper' then s->'record'->>'by' end));
  end if;
  if q.submitted_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'submitted', 'at', q.submitted_at, 'team', true,
      'by', q.submitted_by, 'to', q.reviewer_name));
  end if;
  if q.returned_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'returned', 'at', q.returned_at, 'team', true,
      'by', q.returned_by, 'note', q.return_note));
  end if;
  if q.reviewed_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'confirmed', 'at', q.reviewed_at, 'team', true,
      'by', q.reviewed_by, 'role', q.reviewed_role));
  end if;
  if q.withdrawn_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'withdrawn', 'at', q.withdrawn_at, 'team', true,
      'by', q.withdrawn_by, 'note', 'From ' || public.register_day(q.withdrawn_on) || ' · ' || q.withdrawn_reason));
  end if;
  if q.sealed_at is not null then
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('step', 'sealed', 'at', q.sealed_at, 'team', true,
      'by', q.sealed_by, 'note', q.seal_sha));
  end if;
  return jsonb_build_object('id', q.id, 'ref', q.ref, 'brand', q.brand, 'company', s->'company'->>'legal_name',
    'signed', q.signed_at is not null, 'confirmed', q.reviewed_at is not null,
    'withdrawn', q.withdrawn_at is not null, 'declined', q.declined_at is not null,
    'seal', case when q.seal_key is null then null else jsonb_build_object('sha', q.seal_sha, 'pages_sha', q.seal_pages_sha,
                 'at', q.sealed_at, 'by', q.sealed_by) end,
    'steps', coalesce((select jsonb_agg(x order by (x->>'at')::timestamptz, x->>'step') from jsonb_array_elements(v_steps) x), '[]'::jsonb));
end $$;

create or replace function public.link_resolve(p_slug text, p_qr text default null)
returns table (url text, state text)
language plpgsql security definer stable set search_path = public as $$
declare
  v_slug   text := lower(btrim(coalesce(p_slug, '')));
  v_code   text := lower(btrim(coalesce(p_qr, '')));
  v_target text;
  v_live   boolean;
begin
  if v_slug = '' then
    return query select null::text, 'missing'::text;
    return;
  end if;

  select l.target_url, l.active into v_target, v_live
    from public.links l
   where l.slug = v_slug;

  if v_target is null then
    -- A colleague's namecard, while they are active and the card is on.
    select 'https://' || public.agency('portal_domain') || '/card/?k=' || t.card_key into v_target
      from public.team_members t
     where t.card_slug = v_slug and t.active and t.card_on and t.card_key is not null;
    if v_target is null then
      return query select null::text, 'missing'::text;
      return;
    end if;
    return query select v_target, 'ok'::text;
    return;
  end if;
  if not v_live then
    return query select null::text, 'paused'::text;
    return;
  end if;

  -- A scan carries its code; a typed link does not, and is never turned away
  -- by one. A code that belongs to another slug is as revoked as a dead one.
  if v_code <> '' and not exists (
       select 1 from public.link_qrs q
        where q.code = v_code and q.slug = v_slug and q.active) then
    return query select null::text, 'revoked'::text;
    return;
  end if;

  return query select v_target, 'ok'::text;
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
  if p_url is null or p_url !~ ('^' || regexp_replace(public.agency('cdn_base'), '([.?*+^$|(){}\[\]\\])', '\\\1', 'g') || '/content/creator/' || p_option::text
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

create or replace function public.ops_outstation_remind()
returns integer
language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0;
begin
  for r in
    select e.id, e.meeting_at, coalesce((select t.id from public.team_members t where t.id = e.meeting_owner_id and t.active),
                                       (select t.id from public.team_members t where t.id = e.manager_id and t.active)) as who, c.name as client_name
      from public.ops_engagements e
      left join public.clients c on c.id = e.client_id
     where e.meeting_channel = 'onsite' and not e.meeting_na and e.meeting_at is not null
       and e.outstation_told_at is null
       and e.meeting_at + make_interval(mins => coalesce(e.meeting_minutes, 30)) <= now()
       and coalesce(e.status, '') <> 'cancelled'
     for update of e skip locked
  loop
    if r.who is not null and exists (select 1 from public.team_members t where t.id = r.who and t.active) then
      insert into public.ops_notifications (team_member_id, kind, title, body, link, dedupe_key)
      values (r.who, 'outstation', 'Submit the outstation record',
              coalesce(r.client_name, 'Client') || ' · on-site meeting on ' ||
                public.register_day((r.meeting_at at time zone 'Asia/Kuala_Lumpur')::date),
              'https://' || public.agency('link_domain') || '/outstation',
              'outstation.' || r.id::text || '.' || extract(epoch from r.meeting_at)::bigint::text)
      on conflict (dedupe_key) do nothing;
      n := n + 1;
    end if;
    update public.ops_engagements set outstation_told_at = now() where id = r.id;
  end loop;
  return n;
end $$;

create or replace function public.mail_log(p_month date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  v_from date := date_trunc('month', coalesce(p_month, (now() at time zone 'Asia/Kuala_Lumpur')::date))::date;
  v_a    timestamptz;
  v_b    timestamptz;
  v_sup  boolean;
  v_bill boolean;
  v_quo  boolean;
  v_all  boolean;
  v_cr   boolean;
  v_team boolean;
  v_con  boolean;
begin
  if me.id is null or not public.allowed('whatsapp', 'view') then return jsonb_build_object('error', 'denied'); end if;
  v_a := v_from::timestamp at time zone 'Asia/Kuala_Lumpur';
  v_b := (v_from + interval '1 month')::timestamp at time zone 'Asia/Kuala_Lumpur';
  v_sup := public.allowed('suppliers', 'view');
  v_bill := public.allowed('clients.billing', 'view');
  v_quo := public.allowed('clients.quotes', 'view');
  v_all := public.client_scope_free('view');
  v_cr := public.allowed('campaigns.creators', 'view');
  v_team := public.allowed('team', 'view');
  v_con := public.allowed('clients.contacts', 'view');
  return jsonb_build_object(
    'month', v_from,
    'senders', (select jsonb_object_agg(m.key, m.name || ' <' || m.address || '>') from public.mail_senders m),
    'items', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
        select * from (
          select 'supplier'::text as source, e.id, e.purpose as kind, e.to_email, e.cc_email, e.subject, e.body,
                 t.name as sent_by, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 null::uuid as client_id, null::text as client, e.supplier_id, s.name as supplier, s.code as supplier_code,
                 d.serial as reference, null::text as to_name, null::uuid as ref_id, null::uuid as again_of
            from public.supplier_emails e
            left join public.suppliers s on s.id = e.supplier_id
            left join public.documents d on d.id = e.document_id
            left join public.team_members t on t.id = e.sent_by
           where v_sup and e.created_at >= v_a and e.created_at < v_b
          union all
          select 'client', e.id, e.kind, e.to_email, e.cc_email, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 e.client_id, c.name, null, null, null,
                 e.reference, k.name, null, null
            from public.client_emails e
            left join public.clients c on c.id = e.client_id
            left join public.client_contacts k on k.id = e.contact_id
            left join public.team_members t on t.id = e.sent_by
           where e.created_at >= v_a and e.created_at < v_b
             and public.client_email_may(e.kind, 'view')
             and (case when e.client_id is null then v_all else public.client_seen(e.client_id, 'view') end)
          union all
          select 'invoice', e.id, e.purpose, e.to_email, e.cc_email, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 e.client_id, coalesce(c.name, e.client_name), null, null, null,
                 (select string_agg(i->>'number', ', ' order by o) from jsonb_array_elements(e.invoices) with ordinality as a (i, o)),
                 null, null, null
            from public.invoice_emails e
            left join public.clients c on c.id = e.client_id
            left join public.team_members t on t.id = e.sent_by
           where v_bill and e.created_at >= v_a and e.created_at < v_b
             and (case when e.client_id is null then v_all else public.client_seen(e.client_id, 'view') end)
          union all
          select 'manual', e.id, 'message', e.to_email, e.cc_email, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 e.client_id, c.name, e.supplier_id, s.name, s.code,
                 e.attachment, e.to_name, null, null
            from public.team_emails e
            left join public.clients c on c.id = e.client_id
            left join public.suppliers s on s.id = e.supplier_id
            left join public.team_members t on t.id = e.sent_by
           where e.created_at >= v_a and e.created_at < v_b
             and (case when e.client_id is not null then public.allowed('clients.contacts', 'view') and public.client_seen(e.client_id, 'view')
                       when e.supplier_id is not null then v_sup else true end)
             and (not e.finance or v_bill)
          union all
          select 'creator', e.id, 'creator_' || e.purpose, e.to_email, null, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 null, null, null, null, null,
                 r.ref, k.name, null, e.again_of
            from public.creator_emails e
            left join public.creators k on k.id = e.creator_id
            left join public.creator_pay_requests r on r.id = e.request_id
            left join public.team_members t on t.id = e.sent_by
           where v_cr and e.created_at >= v_a and e.created_at < v_b
          union all
          select 'system', e.id, e.kind, e.to_email, null, e.subject, e.body,
                 t.name, e.created_at, e.status, e.error, e.sent_at, e.delivered_at, e.opened_at, e.bounced_at,
                 e.client_id, c.name, null, null, null,
                 e.reference, e.to_name, e.ref_id, e.again_of
            from public.system_emails e
            left join public.clients c on c.id = e.client_id
            left join public.team_members t on t.id = e.sent_by
           where e.created_at >= v_a and e.created_at < v_b
             and (case when e.kind like 'hiring%' then public.hiring_role(e.candidate_id) is not null
                       when e.kind = 'invite_team' then v_team
                       when e.kind = 'invite_client' then v_con and e.client_id is not null and public.client_seen(e.client_id, 'view')
                       else false end)
          union all
          select 'signing', g.id, 'signing', g.email, null, 'Your ' || public.agency('trading_name') || ' signing code for quotation ' || q.ref, null,
                 null, g.created_at,
                 case when g.used_at is not null then 'used' when g.expires_at < now() then 'expired' else 'requested' end,
                 null, g.created_at, null, null, null,
                 q.client_id, c.name, null, null, null,
                 q.ref, nullif(btrim(coalesce(g.payload->'contact'->>'salutation', '') || ' ' || coalesce(g.payload->'contact'->>'name', '')), ''),
                 null, null
            from public.quote_sign_codes g
            join public.quotations q on q.id = g.quotation_id
            left join public.clients c on c.id = q.client_id
           where v_quo and g.created_at >= v_a and g.created_at < v_b
             and (case when q.client_id is null then v_all else public.client_seen(q.client_id, 'view') end)
        ) u
        order by u.created_at desc
        limit 2000) x), '[]'::jsonb));
end $$;

create or replace function public.client_proposal_sent(p_client uuid, p_detail text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_c public.clients;
  v_me public.team_members;
begin
  update public.clients x set stage = 'proposal'
   where x.id = p_client and x.stage in ('lead', 'contacted')
  returning * into v_c;
  if v_c.id is null then return; end if;
  v_me := public.ops_me();
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_me.name, public.agency('trading_name')), 'client.stage', v_c.name, 'Proposal sent · ' || p_detail);
end $$;

create or replace function public.creator_mail_queue(p_purpose text, p_req uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  t   public.creator_email_templates;
  r   public.creator_pay_requests;
  c   public.creators;
  v_to text;
  v_sub text;
  v_body text;
  v_vals jsonb;
  w   public.creator_pay_requests;
  v_day date;
begin
  select * into t from public.creator_email_templates x where x.purpose = p_purpose;
  if t.purpose is null or not t.on_send then return; end if;
  select * into r from public.creator_pay_requests x where x.id = p_req;
  select * into c from public.creators x where x.id = r.creator_id;
  -- Details changed goes to the email on file, the set it replaced.
  select * into w from public.creator_pay_requests x where x.id = r.prior_id;
  v_to := lower(btrim(coalesce(case when p_purpose = 'review' then t.to_email
                                    when p_purpose = 'changed' then w.email else r.email end, '')));
  v_day := (r.created_at at time zone 'Asia/Kuala_Lumpur')::date;
  if v_to !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return; end if;
  v_sub := t.subject;
  v_body := t.body;
  v_vals := jsonb_build_object(
    'creator name', c.name, 'creator id', coalesce(c.creator_code, ''), 'reference', r.ref, 'payee', r.payee,
    'method', public.creator_pay_method(r.method, r.bank), 'account ending', right(r.account, 4),
    'review link', 'https://' || public.agency('portal_domain') || '/admin/?s=campaigns&tab=roster&pay=' || c.id,
    'date', public.register_day(v_day),
    'chinese date', to_char(v_day, 'YYYY') || '年' || to_char(v_day, 'FMMM') || '月' || to_char(v_day, 'FMDD') || '日',
    'changes', array_to_string(coalesce(r.changes, '{}'), E'\n'));
  v_sub := public.creator_mail_fill(v_sub, v_vals);
  -- A field filled empty (no changes) leaves no blank lines behind it.
  v_body := regexp_replace(public.creator_mail_fill(v_body, v_vals), E'\n{3,}', E'\n\n', 'g');
  -- Off, the email is kept as Not sent and never sent later (2026-11-10).
  insert into public.creator_emails (purpose, creator_id, request_id, to_email, subject, body, status, error)
  values (p_purpose, c.id, r.id, v_to, left(v_sub, 200), v_body,
          case when public.auto_send_on('email') then 'queued' else 'failed' end,
          case when public.auto_send_on('email') then null else 'off: Automatic emails are off.' end);
  perform public.creator_mail_kick();
end $$;

create or replace function public.creator_mail_job(p_purpose text, p_option uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  t   public.creator_email_templates;
  fin public.creator_email_templates;
  o   public.campaign_options;
  c   public.creators;
  m   public.campaigns;
  r   public.creator_pay_requests;
  b   public.creator_bills;
  v_to text; v_sub text; v_body text; v_vals jsonb;
begin
  select * into t from public.creator_email_templates x where x.purpose = p_purpose;
  if t.purpose is null or not t.on_send then return; end if;
  select * into o from public.campaign_options x where x.id = p_option;
  select * into c from public.creators x where x.id = o.creator_id;
  select * into m from public.campaigns x where x.id = o.campaign_id;
  select * into r from public.creator_pay_requests x where x.creator_id = c.id and x.status = 'approved'
   order by x.decided_at desc limit 1;
  -- The bill this email is about: the one just told paid, else the newest.
  select * into b from public.creator_bills x where x.option_id = o.id and not x.gone
   order by x.paid_told_at desc nulls last, x.bill_date desc nulls last limit 1;
  select * into fin from public.creator_email_templates x where x.purpose = 'review';
  v_to := lower(btrim(coalesce(case when p_purpose = 'request' then fin.to_email else r.email end, '')));
  if v_to !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return; end if;
  v_sub := t.subject;
  v_body := t.body;
  v_vals := jsonb_build_object(
    'creator name', c.name, 'creator id', coalesce(c.creator_code, ''),
    'job reference', coalesce(public.creator_job_ref(o.id), '') || coalesce(' (' || o.earlier_job || ')', ''),
    'campaign', coalesce(m.title, ''),
    'posted date', coalesce(public.register_day(o.posted_on), ''),
    'pay by', coalesce(public.register_day(o.pay_by), ''),
    'payee', coalesce(r.payee, 'Payment details pending approval'),
    'method', coalesce(public.creator_pay_method(r.method, r.bank), ''),
    'account ending', coalesce(right(r.account, 4), ''),
    'amount', case when b.amount is null then '' else
      case coalesce(b.currency, 'MYR') when 'MYR' then 'RM ' when 'SGD' then 'S$ ' else b.currency || ' ' end ||
      to_char(b.amount, 'FM999,999,990.00') end,
    'bill number', coalesce(b.number, ''),
    'review link', 'https://' || public.agency('portal_domain') || '/admin/?s=campaigns&tab=roster&pay=' || c.id);
  v_sub := public.creator_mail_fill(v_sub, v_vals);
  v_body := public.creator_mail_fill(v_body, v_vals);
  -- Off, the email is kept as Not sent and never sent later (2026-11-10).
  insert into public.creator_emails (purpose, creator_id, request_id, option_id, to_email, subject, body, status, error)
  values (p_purpose, c.id, r.id, o.id, v_to, left(v_sub, 200), v_body,
          case when public.auto_send_on('email') then 'queued' else 'failed' end,
          case when public.auto_send_on('email') then null else 'off: Automatic emails are off.' end);
  perform public.creator_mail_kick();
end $$;

create or replace function public.campaign_options_posted_mail()
returns trigger
language plpgsql security definer set search_path = public as $$
declare c public.creators; m public.campaigns; v_ref text;
begin
  if new.state is distinct from 'posted' or old.state in ('posted', 'completed') then return null; end if;
  -- Told once a booking: a revert and a second move into Posted tell nobody again.
  if exists (select 1 from public.creator_emails e where e.option_id = new.id and e.purpose in ('request', 'posted')) then return null; end if;
  begin
    perform public.creator_mail_job('request', new.id);
    perform public.creator_mail_job('posted', new.id);
    select * into c from public.creators x where x.id = new.creator_id;
    select * into m from public.campaigns x where x.id = new.campaign_id;
    v_ref := public.creator_job_ref(new.id);
    insert into public.ops_notifications (team_member_id, kind, title, body, link, dedupe_key)
    select tm.id, 'creator.payment', 'Creator payment request · ' || coalesce(v_ref, c.name),
           c.name || ' · ' || coalesce(m.title, '') || coalesce(' · Pay by ' || public.register_day(new.pay_by) || ' (' || trim(to_char(new.pay_by, 'FMDay')) || ')', ''),
           'https://' || public.agency('portal_domain') || '/admin/?s=campaigns&tab=payments&row=' || new.id,
           'creator.payment:' || new.id || ':' || tm.id
      from public.team_members tm
     where tm.active and tm.removed_at is null and not coalesce(tm.system, false)
       and public.allowed_of(tm.id, 'campaigns.pay', 'work')
    on conflict (dedupe_key) do nothing;
  exception when others then
    return null;
  end;
  return null;
end $$;

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
  v_day   date;
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
    -- The record names the day written, never the day it ran (review 2026-11-24).
    v_day := coalesce(nullif(p ->> 'sent_on', '')::date, v_today);
    v := public.sm_report_sent((p ->> 'report_id')::uuid, v_day);
    if v ? 'error' then return v; end if;
    insert into public.activity_log (actor, action, subject, detail)
    values (m.name, 'assistant.report', s.title, 'Marked as sent ' || public.register_day(v_day) || ' · scheduled through the Assistant');
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
        case when p ->> 'purpose' = 'approval' then 'https://' || public.agency('portal_domain') || '/' || coalesce(v ->> 'link', '') else '' end),
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

create or replace function public.creator_pay_requests_notice()
returns trigger
language plpgsql security definer set search_path = public as $$
declare c public.creators;
begin
  if new.status is distinct from 'pending' then return null; end if;
  begin
    select * into c from public.creators x where x.id = new.creator_id;
    insert into public.ops_notifications (team_member_id, kind, title, body, link, dedupe_key)
    select tm.id, 'creator.details', 'Payment details to review · ' || coalesce(c.name, new.ref),
           new.ref || ' · Sent on the creator page',
           'https://' || public.agency('portal_domain') || '/admin/?s=campaigns&tab=payments&row=' || new.id,
           'creator.details:' || new.id || ':' || tm.id
      from public.team_members tm
     where tm.active and tm.removed_at is null and not coalesce(tm.system, false)
       and tm.department = 'marketing'
       and (tm.is_admin or tm.role = 'admin'
            or public.level_rank(coalesce(tm.access ->> 'campaigns.creators', tm.access ->> 'campaigns')) >= 1)
    on conflict (dedupe_key) do nothing;
  exception when others then
    return null;
  end;
  return null;
end $$;

create or replace function public.hiring_person_set(p_id uuid, p_member uuid, p_role text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  c public.hiring_candidates;
  t public.team_members;
  v_was text;
begin
  if me.id is null or not public.ops_granted('team.hiring', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(p_role, '') not in ('owner', 'interviews') then return jsonb_build_object('error', 'bad-role'); end if;
  select * into c from public.hiring_candidates where id = p_id for update;
  if c.id is null or c.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  select * into t from public.team_members where id = p_member and active and removed_at is null and not system;
  if t.id is null then return jsonb_build_object('error', 'bad-colleague'); end if;
  select role into v_was from public.hiring_people where candidate_id = p_id and team_member_id = p_member;
  if v_was = p_role then return jsonb_build_object('ok', true, 'same', true); end if;
  insert into public.hiring_people (candidate_id, team_member_id, role, added_by)
  values (p_id, p_member, p_role, me.id)
  on conflict (candidate_id, team_member_id) do update set role = excluded.role;
  perform public.hiring_log(p_id, 'candidate.people', t.name || case when v_was is null then ' added as ' else ': ' || initcap(v_was) || ' → ' end
    || case p_role when 'owner' then 'Owner' else 'Interviewer' end);
  if v_was is null and t.id <> me.id then
    insert into public.ops_notifications (team_member_id, kind, title, body, link)
    values (t.id, 'hiring.added', 'You were added to a candidate',
            c.position || ' · ' || case p_role when 'owner' then 'Owner' else 'Interviewer' end || ' · added by ' || me.name,
            'https://' || public.agency('portal_domain') || '/admin/?s=team&tab=hiring&candidate=' || c.id);
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.hiring_tell(p_candidate uuid, p_kind text, p_title text, p_body text)
returns void language plpgsql security definer set search_path = public as $$
declare me public.team_members := public.ops_me();
begin
  insert into public.ops_notifications (team_member_id, kind, title, body, link)
  select t.id, p_kind, p_title, p_body, 'https://' || public.agency('portal_domain') || '/admin/?s=team&tab=hiring&candidate=' || p_candidate
    from public.team_members t
   where t.active and t.removed_at is null and not t.system and (me.id is null or t.id <> me.id)
     and exists (select 1 from public.hiring_people p where p.candidate_id = p_candidate and p.team_member_id = t.id and p.role = 'owner');
end $$;

create or replace function public.hiring_tell_once(p_candidate uuid, p_kind text, p_title text, p_body text, p_key text)
returns void language plpgsql security definer set search_path = public as $$
declare me public.team_members := public.ops_me();
begin
  insert into public.ops_notifications (team_member_id, kind, title, body, link, dedupe_key)
  select t.id, p_kind, p_title, p_body, 'https://' || public.agency('portal_domain') || '/admin/?s=team&tab=hiring&candidate=' || p_candidate,
         p_key || ':' || t.id
    from public.team_members t
   where t.active and t.removed_at is null and not t.system and (me.id is null or t.id <> me.id)
     and exists (select 1 from public.hiring_people p where p.candidate_id = p_candidate and p.team_member_id = t.id and p.role = 'owner')
  on conflict (dedupe_key) do nothing;
end $$;

create or replace function public.health_daily(p_today date default null)
returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_today  date := coalesce(p_today, public.health_today());
  v_days   integer := coalesce(public.app_setting('health_remind_days', coalesce(p_today, public.health_today())), 2)::integer;
  v_alert  boolean := coalesce(public.app_setting('health_alert', coalesce(p_today, public.health_today())), 1) = 1;
  v_hol    boolean := public.public_holiday_on(coalesce(p_today, public.health_today())) is not null;
  v_p      jsonb;
  v_end    date;
  m        record;
  a        record;
  n        integer := 0;
begin
  for m in select t.id, t.name from public.team_members t
            where t.active and not coalesce(t.system, false) order by t.id loop
    v_p := public.health_period(m.id, v_today);
    v_end := (v_p ->> 'end')::date;
    if v_days > 0 and not v_hol and (v_p ->> 'due')::boolean and public.health_agreed(m.id)
       and v_today >= (v_p ->> 'start')::date + v_days and v_today <= v_end then
      insert into public.ops_notifications (team_member_id, task_id, kind, title, body, dedupe_key)
      values (m.id, null, 'health.remind',
              'Check in on your health by ' || public.register_day(v_end) || ' (' || trim(to_char(v_end, 'FMDay')) || ').',
              null, 'health.remind.' || m.id || '.' || (v_p ->> 'start'))
      on conflict (dedupe_key) do nothing;
      if found then n := n + 1; end if;
    end if;
    if v_alert and coalesce((v_p #>> '{load,heavy}')::boolean, false) then
      for a in select t.id from public.team_members t
                where t.active and t.id <> m.id and not coalesce(t.system, false)
                  and (coalesce(t.is_admin, false) or t.role = 'admin') loop
        insert into public.ops_notifications (team_member_id, task_id, kind, title, body, link, dedupe_key)
        values (a.id, null, 'health.load', 'Check in with ' || m.name || '.',
                'Their work this week is near their weekly capacity.',
                'https://' || public.agency('portal_domain') || '/admin/?s=team&tab=health',
                'health.load.' || m.id || '.' || (v_p #>> '{load,week}') || '.' || a.id)
        on conflict (dedupe_key) do nothing;
        n := n + 1;
      end loop;
    end if;
  end loop;
  return n;
end $$;

create or replace function public.feedback_mail_begin(p_client uuid, p_kind text, p_again boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  r     jsonb;
  v_cl  public.clients;
  v_ct  public.client_contacts;
  v_t   public.feedback_email_templates;
  v_zh  boolean;
  v_s   text;
  v_b   text;
  v_btn text;
  v_k   text;
  v_v   text;
begin
  if me.id is null or not public.allowed('clients', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
  if coalesce(public.app_setting('client_email_on', (now() at time zone 'Asia/Kuala_Lumpur')::date), 0) <> 1 then
    return jsonb_build_object('error', 'email-off');
  end if;
  if p_kind in ('quick', 'review')
     and (select count(*) from public.feedback_email_templates x where x.kind = p_kind) < 2 then
    return jsonb_build_object('error', 'not-found');
  end if;
  r := public.feedback_request(p_client, p_kind, p_again);
  if r ? 'error' then return r; end if;
  select * into v_cl from public.clients c where c.id = p_client;
  select * into v_ct from public.client_contacts k
   where k.id = (select q.contact_id from public.feedback_requests q where q.id = (r->>'id')::uuid);
  v_zh := coalesce(v_ct.lang, 'en') = 'zh';
  select * into v_t from public.feedback_email_templates x
   where x.kind = p_kind and x.lang = case when v_zh then 'zh' else 'en' end;
  v_s := v_t.subject;
  v_b := v_t.body;
  v_btn := v_t.button;
  foreach v_k in array array['contact name', 'client name', 'link'] loop
    v_v := case v_k when 'contact name' then public.contact_named(v_ct.salutation, v_ct.name)
      when 'client name' then v_cl.name
      else 'https://' || public.agency('portal_domain') || '/feedback/?k=' || (r->>'key') end;
    v_s := regexp_replace(v_s, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
    v_b := regexp_replace(v_b, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
    v_btn := regexp_replace(v_btn, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
  end loop;
  update public.feedback_requests q set mail_status = 'sending' where q.id = (r->>'id')::uuid;
  return r || jsonb_build_object('subject', left(v_s, 200), 'body', v_b, 'button', v_btn, 'lang', case when v_zh then 'zh' else 'en' end);
end $$;

create or replace function public.outstation_remind()
returns integer
language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0;
  v_hours numeric := coalesce(public.app_setting('outstation_remind_hours', (now() at time zone 'Asia/Kuala_Lumpur')::date), 3);
begin
  for r in
    select t.id, t.ref, t.driver_id,
           (select public.outstation_last_activity(s.id) from public.outstation_stops s where s.trip_id = t.id order by s.seq desc limit 1) as last_at
      from public.outstation_trips t
     where t.state = 'open' and t.reminded_at is null
     for update of t skip locked
  loop
    continue when r.last_at is null or r.last_at + make_interval(mins => round(v_hours * 60)::int) > now();
    insert into public.ops_notifications (team_member_id, kind, title, body, link, dedupe_key)
    values (r.driver_id, 'outstation', 'Your trip is still open. Check out?', coalesce(r.ref, 'Outstation trip'),
            'https://' || public.agency('portal_domain') || '/admin/?s=work&view=outstation', 'outstation.open.' || r.id::text)
    on conflict (dedupe_key) do nothing;
    update public.outstation_trips set reminded_at = now() where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.feedback_wa_copy(p_client uuid, p_kind text, p_again boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  r     jsonb;
  v_cl  public.clients;
  v_ct  public.client_contacts;
  v_t   public.feedback_email_templates;
  v_zh  boolean;
  v_url text;
  v_b   text;
  v_btn text;
  v_k   text;
  v_v   text;
begin
  if me.id is null or not public.allowed('clients', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.send_ok('whatsapp') then return jsonb_build_object('error', 'send-off'); end if;
  if p_kind in ('quick', 'review')
     and (select count(*) from public.feedback_email_templates x where x.kind = p_kind) < 2 then
    return jsonb_build_object('error', 'not-found');
  end if;
  r := public.feedback_request(p_client, p_kind, p_again, 'whatsapp');
  if r ? 'error' then return r; end if;
  select * into v_cl from public.clients c where c.id = p_client;
  select * into v_ct from public.client_contacts k
   where k.id = (select q.contact_id from public.feedback_requests q where q.id = (r->>'id')::uuid);
  v_zh := coalesce(v_ct.lang, 'en') = 'zh';
  select * into v_t from public.feedback_email_templates x
   where x.kind = p_kind and x.lang = case when v_zh then 'zh' else 'en' end;
  v_url := 'https://' || public.agency('portal_domain') || '/feedback/?k=' || (r->>'key');
  v_b := v_t.body;
  v_btn := v_t.button;
  foreach v_k in array array['contact name', 'client name', 'link'] loop
    v_v := case v_k when 'contact name' then public.contact_named(v_ct.salutation, v_ct.name)
      when 'client name' then v_cl.name else v_url end;
    v_b := regexp_replace(v_b, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
    v_btn := regexp_replace(v_btn, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
  end loop;
  -- The email's button is the link's words here; a message already
  -- holding the link keeps it where it was written.
  if position(v_url in v_b) = 0 then
    v_b := btrim(v_b) || E'\n\n' || btrim(v_btn) || case when v_zh then '：' else ': ' end || v_url;
  end if;
  return r || jsonb_build_object('text', v_b, 'lang', case when v_zh then 'zh' else 'en' end);
end $$;

create or replace function public.quotation_details_ask(p_id uuid, p_fields text[], p_note text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  q      public.quotations;
  v_f    text[];
  v_note text := nullif(btrim(regexp_replace(coalesce(p_note, ''), '[ \t]+', ' ', 'g')), '');
  v_due  timestamptz;
  v_zh   boolean;
  v_t    public.quote_email_templates;
  v_link text;
  v_body text;
  v_k    text;
  v_v    text;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if q.source <> 'website' or q.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
  if q.released_at is not null then return jsonb_build_object('error', 'sent'); end if;
  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'closed'); end if;
  select coalesce(array_agg(distinct x), '{}') into v_f from unnest(coalesce(p_fields, '{}')) x;
  if exists (select 1 from unnest(v_f) x where x not in ('registration', 'industry', 'online', 'commence')) then
    return jsonb_build_object('error', 'bad-fields');
  end if;
  v_f := array(select x from unnest(array['registration', 'industry', 'online', 'commence']) x where x = any(v_f));
  if v_note is not null and (length(v_note) > 500 or v_note ~* public.quote_link_like()) then return jsonb_build_object('error', 'bad-note'); end if;
  if cardinality(v_f) = 0 and v_note is null then return jsonb_build_object('error', 'bad-fields'); end if;
  v_due := public.ops_add_business_days(now(),
    coalesce(public.app_setting('quote_details_days', (now() at time zone 'Asia/Kuala_Lumpur')::date), 3)::int);
  update public.quotations x
     set details_ask = jsonb_build_object('fields', to_jsonb(v_f), 'note', v_note),
         details_asked_at = now(), details_asked_by = me.name, details_due = v_due, details_at = null, details = null
   where x.id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand, q.ref || ' · Details asked: ' ||
          replace(substr(public.quote_details_lines(v_f, v_note, false), 3), E'\n• ', ', ') ||
          ' · Reply by ' || public.register_day((v_due at time zone 'Asia/Kuala_Lumpur')::date));
  -- The same words as the email, for WhatsApp by hand.
  v_zh := coalesce(q.contact->>'lang', 'en') = 'zh';
  select * into v_t from public.quote_email_templates x where x.kind = 'details' and x.lang = case when v_zh then 'zh' else 'en' end;
  v_link := 'https://' || public.agency('portal_domain') || '/quote/?q=' || q.access_key;
  v_body := coalesce(v_t.body, '');
  foreach v_k in array array['contact name', 'brand', 'reference', 'details', 'reply by', 'link'] loop
    v_v := case v_k when 'contact name' then public.contact_named(q.contact->>'salutation', q.contact->>'name')
      when 'brand' then coalesce(q.contact->>'brand', q.brand) when 'reference' then q.ref
      when 'details' then public.quote_details_lines(v_f, v_note, v_zh)
      when 'reply by' then public.quote_day_word((v_due at time zone 'Asia/Kuala_Lumpur')::date, v_zh)
      else v_link end;
    v_body := regexp_replace(v_body, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
  end loop;
  return jsonb_build_object('ok', true, 'due', v_due, 'key', q.access_key, 'text', v_body || E'\n\n' || v_link);
end $$;

create or replace function public.quote_details_mail_begin(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me    public.team_members := public.ops_me();
  q     public.quotations;
  v_ds  text;
  v_zh  boolean;
  v_t   public.quote_email_templates;
  v_s   text;
  v_b   text;
  v_btn text;
  v_k   text;
  v_v   text;
  v_to  text;
  v_ct  uuid;
  v_id  uuid;
  v_f   text[];
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
  if coalesce(public.app_setting('client_email_on', (now() at time zone 'Asia/Kuala_Lumpur')::date), 0) <> 1 then
    return jsonb_build_object('error', 'email-off');
  end if;
  select * into q from public.quotations x where x.id = p_id;
  if q.id is null or q.source <> 'website' or q.removed_at is not null
     or not public.client_scope_ok('client', q.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if q.released_at is not null then return jsonb_build_object('error', 'sent'); end if;
  v_ds := public.quote_details_state(q);
  if v_ds not in ('asked', 'late') or q.status = 'not_proceeding' then return jsonb_build_object('error', 'closed'); end if;
  if q.no_contact_at is not null then return jsonb_build_object('error', 'no-contact'); end if;
  v_to := lower(btrim(coalesce(q.contact->>'email', '')));
  if not (v_to ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then return jsonb_build_object('error', 'no-email'); end if;
  v_zh := coalesce(q.contact->>'lang', 'en') = 'zh';
  select * into v_t from public.quote_email_templates x where x.kind = 'details' and x.lang = case when v_zh then 'zh' else 'en' end;
  if v_t.kind is null then return jsonb_build_object('error', 'not-found'); end if;
  v_f := array(select jsonb_array_elements_text(q.details_ask->'fields'));
  v_s := v_t.subject; v_b := v_t.body; v_btn := v_t.button;
  foreach v_k in array array['contact name', 'brand', 'reference', 'details', 'reply by', 'link'] loop
    v_v := case v_k when 'contact name' then public.contact_named(q.contact->>'salutation', q.contact->>'name')
      when 'brand' then coalesce(q.contact->>'brand', q.brand) when 'reference' then q.ref
      when 'details' then public.quote_details_lines(v_f, q.details_ask->>'note', v_zh)
      when 'reply by' then public.quote_day_word((q.details_due at time zone 'Asia/Kuala_Lumpur')::date, v_zh)
      else 'https://' || public.agency('portal_domain') || '/quote/?q=' || q.access_key end;
    v_s := regexp_replace(v_s, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
    v_b := regexp_replace(v_b, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
    v_btn := regexp_replace(v_btn, '\{\s*' || v_k || '\s*\}', replace(coalesce(v_v, ''), '\', '\\'), 'gi');
  end loop;
  select k.id into v_ct from public.client_contacts k
   where k.client_id = q.client_id and k.archived_at is null and lower(btrim(coalesce(k.email, ''))) = v_to
   order by k.is_primary desc, k.created_at limit 1;
  insert into public.client_emails (client_id, kind, ref_id, reference, contact_id, to_email, reply_to, subject, body, sent_by)
  values (q.client_id, 'details', q.id, q.ref, v_ct, v_to, public.mail_sender('clients')->>'reply_to', left(v_s, 200), v_b, me.id)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'to_email', v_to,
    'to_name', public.contact_named(q.contact->>'salutation', q.contact->>'name'),
    'subject', left(v_s, 200), 'body', v_b, 'button', v_btn, 'key', q.access_key);
end $$;

-- END OF AGENCY VALUES ON THE SERVER ----------------------------------------

select public.functions_tidy();
