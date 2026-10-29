-- ===========================================================================
-- WEBSITE QUOTATION REVIEWED BEFORE IT IS SENT — the team sends the price (2026-10-29)
-- ===========================================================================
-- WHY (the user, 2026-10-29: "the price shouldnt send out straight", then
-- Option 1): a quotation the website made was shown to the prospect, and
-- sent on WhatsApp, the moment it was priced, with nobody at ADspace having
-- read it (a KOL campaign alone made an empty one the same day).
--
-- WHAT IT CHANGES
--   `quotations.released_at` / `released_by` (when a colleague sent it),
--   `reply_due` (working days after it was made, `quote_reply_days`) and
--   `review_reminded_at`. A website quotation already made counts as sent.
--   `quote_website_create` keeps the quotation, sets its reply, tells the
--   team "Quotation to review" and sends the prospect nothing.
--   `quote_website_read` answers stage `review` with no lines, totals,
--   version or validity while it waits. `quote_proceed` refuses `not-sent`.
--   `quotation_send(p_id)` (Clients: Quotations at Work, the client in
--   scope) sends it: valid from that day, the `quote_ready` WhatsApp queued,
--   filed. `quote_proceed_remind` also tells the managers six hours before
--   an unsent quotation's reply is owed. A revision (Adjust and send) is the
--   team's own and shows as before.
--
-- ORDER: this file, then the pages (an old /quote/ tab reads stage review
-- as its quotation with no lines; the old console offers no Send).
-- Safe to run twice: the backfill runs only while the column is new.
--
-- ROLLBACK: run QUOTATION WEBSITE ASKS WHEN TO START's quote_website_create
-- and the latest quote_website_read, quote_proceed and quote_proceed_remind
-- again; then update quotations set released_at = coalesce(released_at, issued_at)
-- where source = 'website' (the columns may stay).
-- ===========================================================================

-- WEBSITE QUOTATION REVIEWED ------------------------------------------------

do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'quotations' and column_name = 'released_at') then
    alter table public.quotations add column released_at timestamptz;
    update public.quotations set released_at = issued_at where source = 'website';
  end if;
end $$;
alter table public.quotations add column if not exists released_by text;
alter table public.quotations add column if not exists reply_due timestamptz;
alter table public.quotations add column if not exists review_reminded_at timestamptz;
grant select (released_at, released_by, reply_due) on table public.quotations to authenticated;

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
  if v_ind is not null and v_ind not in ('Property', 'F&B', 'Retail', 'Wellness', 'Lifestyle',
                                         'Automotive', 'Tech', 'Education', 'Other') then
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
    values ('Website', 'client.added', v_c.name, 'Website · ' || coalesce(v_sal || ' ', '') || v_name);
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
    values ('Website', 'client.edited', v_c.name, 'Urgency to commence: ' ||
      coalesce(public.quote_commence_word(v_c.commence), 'not set') || ' → ' || public.quote_commence_word(v_start));
  end if;
  -- The price waits for the team (the user, 2026-10-29: "the price
  -- shouldnt send out straight"): the quotation is owed a reply by working
  -- days, the team is told to review it, and the prospect is sent nothing
  -- until a colleague sends it (`quotation_send`).
  update public.quotations set reply_due = public.quote_reply_by(now()) where id = v_q.id
   returning * into v_q;
  perform public.quote_tell(v_c.id, 'quote.website', 'Quotation to review · ' || v_c.name,
    v_q.ref || ' · ' || coalesce('Monthly incl. SST RM ' ||
      to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00'), 'one-off') || ' · ' || v_name
      || coalesce(' · Starts ' || lower(public.quote_commence_word(v_start)), '')
      || ' · send by ' || public.register_day((v_q.reply_due at time zone 'Asia/Kuala_Lumpur')::date) || ', ' ||
      lower(to_char(v_q.reply_due at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam')),
    v_q.id::text);
  return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key);
exception when raise_exception then
  if sqlerrm like 'quote:%' then return jsonb_build_object('error', substr(sqlerrm, 7)); end if;
  raise;
end $$;
revoke all on function public.quote_website_create(jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.quote_website_create(jsonb, jsonb, text) to service_role;

create or replace function public.quote_website_read(p_key text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  w  public.quotations;
  q  public.quotations;
  c  public.clients;
  m  public.team_members;
  d  public.client_documents;
  f  public.client_detail_forms;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_stage text;
  v_portal boolean := false;
  v_billed boolean;
  v_own boolean;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  select * into w from public.quotations x
   where x.access_key = p_key and x.source = 'website' and x.removed_at is null;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  select * into q from public.quotations x where x.id = public.quote_shown(w.id);
  select * into c from public.clients x where x.id = w.client_id;
  if nullif(btrim(coalesce(c.owner, '')), '') is not null then
    select * into m from public.team_members x
     where x.active and not coalesce(x.system, false) and x.removed_at is null and x.name = c.owner
     limit 1;
  end if;
  -- The letter that stands on the quotation's lines, the latest first.
  select dd.* into d from public.client_documents dd
   where dd.kind = 'offer' and dd.voided_at is null and dd.superseded_by is null
     and exists (select 1 from public.client_document_services ds
                   join public.client_services s on s.id = ds.service_id
                  where ds.document_id = dd.id and s.quotation_id = q.id)
   order by dd.created_at desc limit 1;
  -- The client's details form is offered only on the quotation that made
  -- the lead: a later website quotation that matched an existing lead's
  -- email and number never opens that lead's form (2026-10-26, audit).
  v_own := c.created_at >= w.issued_at - interval '1 minute'
           and not exists (select 1 from public.quotations o
                            where o.client_id = c.id and o.issued_at < w.issued_at and o.id <> w.id);
  v_billed := coalesce(btrim(c.legal_name), '') <> '' and coalesce(btrim(c.company_no), '') <> ''
              and coalesce(btrim(c.billing_address), '') <> '';

  if d.id is not null then
    if d.verified_at is not null and c.stage = 'active' then
      v_stage := 'welcome';
      select exists (select 1 from public.client_contacts k
                      where k.client_id = c.id and k.archived_at is null and k.portal_access
                        and lower(btrim(k.email)) = lower(btrim(coalesce(w.contact->>'email', '')))) into v_portal;
    elsif d.signed_at is not null then v_stage := 'signed';
    else v_stage := 'letter';
    end if;
  elsif w.status = 'not_proceeding' or q.status = 'not_proceeding' then
    v_stage := 'closed';
  elsif q.source = 'website' and q.released_at is null then
    -- Being reviewed: nothing priced leaves the database (2026-10-29).
    v_stage := 'review';
  elsif q.valid_until < v_today then
    v_stage := 'expired';
  elsif not v_billed and v_own then
    select * into f from public.client_detail_forms x
     where x.client_id = c.id and x.voided_at is null
     order by x.created_at desc limit 1;
    if f.id is not null and f.submitted_at is not null and f.used_at is null then v_stage := 'billing_sent';
    elsif f.id is not null and f.submitted_at is null and f.expires_at > now() then v_stage := 'billing';
    end if;
  elsif v_billed and w.proceed_at is not null then
    v_stage := 'billing_sent';
  end if;
  if v_stage is null then
    v_stage := case when w.proceed_at is not null then 'ready' else 'quote' end;
  end if;

  return jsonb_build_object(
    'ref', q.ref, 'first_ref', w.ref, 'revised', q.id <> w.id,
    'brand', coalesce(w.contact->>'brand', w.brand), 'version', case when q.source <> 'website' or q.released_at is not null then q.version end,
    'issued_at', q.issued_at,
    'valid_until', case when v_stage <> 'review' then q.valid_until end,
    'lines', case when v_stage <> 'review' then q.lines end,
    'totals', case when v_stage <> 'review' then q.totals end,
    'reply_due', case when v_stage = 'review' then q.reply_due end,
    'selection', w.selection, 'attention', w.contact->>'name',
    'stage', v_stage,
    'status', case when d.id is not null then 'offer' else q.status end,
    'details_key', case when v_stage = 'billing' then f.access_key end,
    'portal', v_portal,
    'proceed_at', w.proceed_at, 'proceed_due', w.proceed_due,
    'rep', case when m.id is null then null else jsonb_build_object('name', m.name, 'title', nullif(btrim(coalesce(m.designation, '')), ''),
             'whatsapp', case when coalesce(m.card_on, true) and coalesce(m.card_mobile, true) then nullif(public.wa_number(m.mobile), '') end) end,
    'market', case when c.market = 'SG' then 'SG' else 'MY' end,
    'today', v_today);
end $$;
revoke all on function public.quote_website_read(text) from public;
grant execute on function public.quote_website_read(text) to anon, authenticated;

create or replace function public.quote_proceed(p_key text, p_start text, p_decider text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  w  public.quotations;
  q  public.quotations;
  v_due timestamptz;
  v_words text;
begin
  if coalesce(p_key, '') !~ '^[a-z0-9]{8}$' then return jsonb_build_object('error', 'not-found'); end if;
  select * into w from public.quotations x
   where x.access_key = p_key and x.source = 'website' and x.removed_at is null for update;
  if w.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if w.proceed_at is not null then
    return jsonb_build_object('ok', true, 'again', true, 'at', w.proceed_at, 'due', w.proceed_due);
  end if;
  -- What the prospect sees is the latest revision: its validity and its
  -- state decide (2026-10-26, audit).
  select * into q from public.quotations x where x.id = public.quote_shown(w.id);
  if w.status = 'not_proceeding' or q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if q.source = 'website' and q.released_at is null then return jsonb_build_object('error', 'not-sent'); end if;
  if coalesce(p_start, '') not in ('month', 'quarter') or coalesce(p_decider, '') not in ('yes', 'others') then
    return jsonb_build_object('error', 'bad-answer');
  end if;
  if q.valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'expired'); end if;
  v_due := public.quote_reply_by(now());
  v_words := public.quote_proceed_words(p_start, p_decider);
  update public.quotations
     set proceed_at = now(), proceed_due = v_due, proceed_start = p_start, proceed_decider = p_decider
   where id = w.id;
  insert into public.activity_log (actor, action, subject, detail)
  values ('Quotation website', 'client.quotation', w.brand,
          w.ref || ' · Ready to proceed on the website' ||
          coalesce(' by ' || nullif(btrim(w.contact->>'name'), ''), '') || ' · ' || v_words);
  perform public.quote_tell(w.client_id, 'quote.proceed', 'Ready to proceed · ' || w.brand,
    w.ref || coalesce(' · ' || nullif(btrim(w.contact->>'name'), ''), '') || ' · ' || v_words || ' · contact by ' ||
      public.register_day((v_due at time zone 'Asia/Kuala_Lumpur')::date) || ', ' ||
      lower(to_char(v_due at time zone 'Asia/Kuala_Lumpur', 'FMHH12:MIam')),
    w.id::text);
  return jsonb_build_object('ok', true, 'at', now(), 'due', v_due);
end $$;
revoke all on function public.quote_proceed(text, text, text) from public;
grant execute on function public.quote_proceed(text, text, text) to anon, authenticated;

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
       and nullif(btrim(coalesce(c.owner, '')), '') is null
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

create or replace function public.quotation_send(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_days int;
  v_wa text;
  v_name text;
  v_queued boolean := false;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.source <> 'website' then return jsonb_build_object('error', 'bad-quotation'); end if;
  if q.released_at is not null then return jsonb_build_object('ok', true, 'again', true, 'valid_until', q.valid_until); end if;
  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  -- Valid from the day it is sent, as the prospect first sees it.
  v_days := coalesce(public.app_setting('quote_valid_days', v_today), 30)::int;
  update public.quotations
     set released_at = now(), released_by = me.name, valid_until = v_today + v_days
   where id = q.id returning * into q;
  v_wa := public.quote_website_number(q.contact->>'whatsapp');
  v_name := coalesce(nullif(btrim(q.contact->>'name'), ''), q.brand);
  begin
    if v_wa ~ '^(60|65)[0-9]{8,10}$' then
      perform public.wa_enqueue('quote_ready', v_wa, v_name,
        jsonb_build_array(public.contact_greeting(q.contact->>'salutation', v_name),
                          coalesce(q.contact->>'brand', q.brand), q.ref),
        'quotation', q.id, q.client_id, q.access_key);
      v_queued := true;
    end if;
  exception when others then v_queued := false;
  end;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || ' sent to the prospect' || case when v_queued then ' on WhatsApp' else '' end ||
          ' · valid until ' || public.register_day(q.valid_until));
  return jsonb_build_object('ok', true, 'valid_until', q.valid_until, 'whatsapp', v_queued);
end $$;
revoke all on function public.quotation_send(uuid) from public, anon;
grant execute on function public.quotation_send(uuid) to authenticated;

-- END OF WEBSITE QUOTATION REVIEWED -----------------------------------------

select public.functions_tidy();
