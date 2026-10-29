-- ===========================================================================
-- REVIEW FIXES OF 2026-10-29 — an IPv6 caller counted by its block, any
-- invoice number reminded, the demo's counts reset with its PIN, a website
-- quotation past the WhatsApp cap said to the team (2026-10-29)
-- ===========================================================================
-- WHY (the review of the releases after #796, 2026-10-29, the user: "ok fix
-- all"):
--    7. `request_ip()` answered an IPv6 caller's whole address, so a guesser
--       changing its address inside its own /64 (every IPv6 host holds one)
--       never met a lock, and filled `link_tries` with a row a guess.
--   11. `invoice_email_begin` took an invoice number of letters, digits and
--       / . _ - alone, so a Bukku number such as INV#2026-001 refused every
--       reminder to its client (the email escapes it anyway).
--   14. A demo PIN locked by wrong tries stayed locked when a new PIN was
--       set: only waiting freed it.
--   17. A website quotation past the day's WhatsApp cap told the team as
--       any other, so nobody knew the prospect had no message.
--
-- WHAT IT CHANGES
--   * `request_ip()` (internal): an IPv6 address reads as its /64; every
--     count keyed on it (a link's passcode, /verify/, the demo PIN, a
--     creator's code) takes it. Rows kept under a whole IPv6 address age
--     out as before.
--   * `invoice_email_begin` (restated whole from OVERDUE REMINDER WORDING):
--     an invoice number is 1 to 60 characters with no control character.
--   * `demo_set` (restated whole from DEMO ACCESS): a new PIN clears the
--     demo's wrong tries and locks.
--   * `quote_website_create` (restated whole from WEBSITE WHATSAPP CAP):
--     the cap is read before the team's notice, which ends Not sent on
--     WhatsApp (daily limit) past it; the message follows the same answer.
--
-- ORDER: this file (connector), then the pages. Either order is safe: no
-- answer changes its shape. Safe to run twice.
--
-- ROLLBACK: request_ip, invoice_email_begin, demo_set and
-- quote_website_create from their last definitions before this banner.
-- ===========================================================================

create or replace function public.request_ip()
returns text
language plpgsql stable security definer set search_path = public as $$
declare
  h json := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::json;
  v text;
begin
  v := left(coalesce(
    case when nullif(h ->> 'x-adspace-relay', '') is not null
          and h ->> 'x-adspace-relay' = (select s.value from public.app_secrets s where s.key = 'ip_relay_secret')
         then nullif(btrim(h ->> 'x-adspace-ip'), '') end,
    nullif(btrim(h ->> 'cf-connecting-ip'), ''),
    nullif(btrim(reverse(split_part(reverse(coalesce(h ->> 'x-forwarded-for', '')), ',', 1))), ''),
    ''), 64);
  -- An IPv6 caller is counted by its /64, the block one machine or network
  -- holds: a guesser changing its address inside it is one caller (review
  -- 2026-10-29, 7). An IPv4 address, one written as IPv6 (::ffff:), and a
  -- value that is no address stay as they are.
  if position(':' in v) > 0 and v !~* '^::ffff:' then
    begin
      v := host(network(set_masklen(v::inet, 64))) || '/64';
    exception when others then null;
    end;
  end if;
  return v;
end $$;
revoke all on function public.request_ip() from public, anon, authenticated;

create or replace function public.invoice_email_begin(p_actor uuid, p_client uuid, p_contact bigint, p_name text,
  p_email text, p_invoices jsonb, p_cc boolean, p_subject text, p_body text, p_again boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me     public.team_members;
  t      public.invoice_email_template;
  rcp    jsonb;
  inv    jsonb;
  hours  numeric;
  r      public.invoice_emails;
  v_n    int;
  v_to   text;
  v_cc   text;
  v_who  text;
  v_co   text;
  v_tot  text;
  v_nos  text;
  v_list text[];
  v_vals jsonb;
  v_s    text;
  v_b    text;
  v_id   uuid;
begin
  select * into me from public.team_members x where x.id = p_actor and x.active;
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_contact is null or p_contact <= 0 then return jsonb_build_object('error', 'bad-request'); end if;
  if jsonb_typeof(p_invoices) <> 'array' or jsonb_array_length(p_invoices) < 1 or jsonb_array_length(p_invoices) > 50 then
    return jsonb_build_object('error', 'bad-invoices');
  end if;
  for inv in select value from jsonb_array_elements(p_invoices) loop
    if btrim(coalesce(inv->>'number', '')) = '' or coalesce(inv->>'number', '') !~ '^[^[:cntrl:]]{1,60}$' or coalesce(inv->>'currency', '') !~ '^[A-Z]{3}$'
       or (inv->>'amount') is null or (inv->>'amount')::numeric <= 0
       or (coalesce(inv->>'link', '') <> '' and inv->>'link' !~ '^https://[a-z0-9-]+\.bukku\.my/[A-Za-z0-9/_-]+$') then
      return jsonb_build_object('error', 'bad-invoices');
    end if;
  end loop;
  perform pg_advisory_xact_lock(hashtextextended('invoice-mail:' || p_contact::text, 0));
  select * into r from public.invoice_emails x
   where x.bukku_contact = p_contact and x.status = 'sending' and x.created_at > now() - interval '10 minutes'
   order by x.created_at desc limit 1;
  if r.id is not null then return jsonb_build_object('error', 'sending'); end if;
  hours := coalesce(public.app_setting('wa_repeat_hours', (now() at time zone 'Asia/Kuala_Lumpur')::date), 24);
  if hours > 0 and not coalesce(p_again, false) then
    select * into r from public.invoice_emails x
     where x.bukku_contact = p_contact and x.status <> 'failed' and x.created_at > now() - make_interval(secs => hours * 3600)
     order by x.created_at desc limit 1;
    if r.id is not null then
      return jsonb_build_object('error', 'recent', 'recent', jsonb_build_object('at', r.created_at, 'to', r.to_email,
        'by', (select m.name from public.team_members m where m.id = r.sent_by)));
    end if;
  end if;
  rcp := case when p_client is null then null else public.invoice_recipient(p_client) end;
  v_to := coalesce(rcp->>'email', nullif(btrim(coalesce(p_email, '')), ''));
  if v_to is null or v_to !~ '^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$' then return jsonb_build_object('error', 'no-email'); end if;
  v_cc := case when coalesce(p_cc, false) and lower(coalesce(rcp->>'cc', '')) <> lower(v_to) then rcp->>'cc' end;
  v_co := coalesce(rcp->>'company', nullif(btrim(coalesce(p_name, '')), ''), 'Client');
  v_who := coalesce(rcp->>'name', 'Sir or Madam');
  v_n := jsonb_array_length(p_invoices);
  select string_agg(public.invoice_money(s.amt, s.cur), ' and ' order by s.cur) into v_tot
    from (select x->>'currency' as cur, sum((x->>'amount')::numeric) as amt
            from jsonb_array_elements(p_invoices) x group by x->>'currency') s;
  select array_agg(x->>'number' order by o) into v_list from jsonb_array_elements(p_invoices) with ordinality as a (x, o);
  v_nos := case when v_n = 1 then v_list[1]
                else array_to_string(v_list[1:v_n - 1], ', ') || ' and ' || v_list[v_n] end;
  v_vals := jsonb_build_object('contact name', v_who, 'client', v_co, 'invoice no', v_nos, 'count', v_n::text,
    'total', v_tot, 'sign off', case when rcp->>'name' is not null then 'Yours sincerely' else 'Yours faithfully' end);
  select * into t from public.invoice_email_template x where x.id = 1;
  v_s := btrim(regexp_replace(public.supplier_email_fill(coalesce(nullif(btrim(coalesce(p_subject, '')), ''),
           case when v_n = 1 then t.subject_one else t.subject_many end), v_vals), '\s+', ' ', 'g'));
  v_b := btrim(replace(public.supplier_email_fill(coalesce(nullif(btrim(coalesce(p_body, '')), ''), t.body), v_vals), E'\r', ''));
  if length(v_s) < 2 or length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 5000 then return jsonb_build_object('error', 'bad-body'); end if;
  if v_b !~* '\{\s*invoices\s*\}' then return jsonb_build_object('error', 'no-invoices'); end if;
  insert into public.invoice_emails (client_id, bukku_contact, client_name, invoices, to_email, cc_email, subject, body, sent_by)
  values (p_client, p_contact, v_co, p_invoices, v_to, v_cc, v_s, v_b, me.id)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'to', v_to, 'cc', v_cc, 'subject', v_s, 'body', v_b,
    'legal', t.legal, 'disclaimer', t.disclaimer);
end $$;
revoke all on function public.invoice_email_begin(uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean) from public, anon, authenticated;
grant execute on function public.invoice_email_begin(uuid, uuid, bigint, text, text, jsonb, boolean, text, text, boolean) to service_role;

create or replace function public.demo_set(p_on boolean, p_pin text default null)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_me public.team_members;
  v_was boolean;
  v_pin text := btrim(coalesce(p_pin, ''));
  v_held boolean;
  v_bits text[] := '{}';
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  v_me := public.ops_me();
  if v_pin <> '' and v_pin !~ '^[0-9]{4,8}$' then return jsonb_build_object('error', 'bad-pin'); end if;
  v_held := exists (select 1 from public.app_secrets s where s.key = 'demo_pin' and coalesce(s.value, '') <> '');
  if coalesce(p_on, false) and v_pin = '' and not v_held then return jsonb_build_object('error', 'no-pin'); end if;
  v_was := coalesce((select f.on_now from public.app_flags f where f.key = 'demo'), false);
  if v_pin <> '' then
    insert into public.app_secrets (key, value) values ('demo_pin', crypt(v_pin, gen_salt('bf', 8)))
    on conflict (key) do update set value = excluded.value, updated_at = now();
    v_bits := v_bits || 'PIN changed'::text;
    -- A new PIN starts every count afresh: the wrong tries a guesser or a
    -- mistyping colleague left no longer lock it (review 2026-10-29, 14).
    update public.link_tries set fails = 0, locked_until = null, strikes = 0, struck_until = null
     where kind = 'demo' and (fails > 0 or locked_until is not null or strikes > 0);
    update public.link_attempts set fails = 0, locked_until = null
     where kind = 'demo' and (fails > 0 or locked_until is not null);
  end if;
  if v_was is distinct from coalesce(p_on, false) then
    v_bits := array['Demo access: ' || case when v_was then 'On' else 'Off' end || ' → ' || case when p_on then 'On' else 'Off' end] || v_bits;
  end if;
  insert into public.app_flags as f (key, on_now, set_by, set_at)
  values ('demo', coalesce(p_on, false), coalesce(v_me.name, v_me.email), now())
  on conflict (key) do update set on_now = excluded.on_now,
    set_by = case when f.on_now is distinct from excluded.on_now or v_pin <> '' then excluded.set_by else f.set_by end,
    set_at = case when f.on_now is distinct from excluded.on_now or v_pin <> '' then excluded.set_at else f.set_at end;
  if array_length(v_bits, 1) > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (coalesce(v_me.name, v_me.email, 'admin'), 'team.changed', 'Demo access', array_to_string(v_bits, ' · '));
  end if;
  return public.demo_state();
end $$;
revoke all on function public.demo_set(boolean, text) from public, anon;
grant execute on function public.demo_set(boolean, text) to authenticated;

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
  v_idem  text := nullif(btrim(coalesce(p_idem, '')), '');
  v_sel   jsonb;
  v_q     public.quotations;
  v_c     public.clients;
  v_base  text;
  v_slug  text;
  v_n     int := 1;
  v_r     jsonb;
  v_new   boolean := false;
  v_wa_ok boolean := false;
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
    insert into public.clients (name, access_token, stage, industry, source, market, slug, deal_note)
    values (v_brand, public.new_link_key(), 'lead', v_ind, 'website',
            case when v_wa like '65%' then 'SG' else 'MY' end, v_slug,
            'Quotation requested on the website.')
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
  -- Whether the prospect is told on WhatsApp is known before the team is,
  -- so a quotation past the day's cap says so in the team's notice (review
  -- 2026-10-29, 17: the 31st of the day read as the 1st).
  begin
    v_wa_ok := public.quote_wa_allowed(v_q.id);
  exception when others then v_wa_ok := false;
  end;
  perform public.quote_tell(v_c.id, 'quote.website', 'Quotation made on the website · ' || v_c.name,
    v_q.ref || ' · ' || coalesce('Monthly incl. SST RM ' ||
      to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00'), 'one-off') || ' · ' || v_name
      || case when v_wa_ok then '' else ' · Not sent on WhatsApp (daily limit)' end,
    v_q.id::text);
  -- The prospect is told on WhatsApp that the quotation is ready, its link
  -- button the quotation's key; a queueing fault never fails the quotation.
  -- No more a day than the Business setting allows (audit 2026-10-29, 3):
  -- past it the quotation is made and the team told, the message not sent.
  begin
    if v_wa_ok then
      perform public.wa_enqueue('quote_ready', v_wa, v_name,
        jsonb_build_array(public.contact_greeting(v_sal, v_name), v_brand, v_q.ref),
        'quotation', v_q.id, v_c.id, v_q.access_key);
    end if;
  exception when others then null;
  end;
  return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key);
exception when raise_exception then
  if sqlerrm like 'quote:%' then return jsonb_build_object('error', substr(sqlerrm, 7)); end if;
  raise;
end $$;
revoke all on function public.quote_website_create(jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.quote_website_create(jsonb, jsonb, text) to service_role;

-- END OF REVIEW FIXES OF 2026-10-29 ---------------------------------------

select public.functions_tidy();
