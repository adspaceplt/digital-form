-- ===========================================================================
-- CREATOR PAYMENTS REVIEWED — the fixes the code review of Creator R1 to R5
-- found (2026-11-10). Safe to run twice. Rollback at the foot. Mirrored byte
-- for byte in supabase/schema.sql under the same banner; tests/sql.js
-- compares the two.
--
-- WHAT CHANGED
-- * `creator_bills_take`: a bill read with no balance keeps the state it had
--   (never Paid by default; `bukku-sync` sends no balance as null); a bill
--   first read already paid sends Payment sent where its booking was posted
--   in the portal (`posted_on`), one from before the portal still telling
--   nobody.
-- * `mail_sweep`: a sheet row left at Sending ten minutes is failed, so the
--   next wake tries it again.
-- * `creator_sheet_release` (the service role's): a row the sender could not
--   try (the sheet unread, no header naming a value) is put back with its try
--   given back; `creator_sheet_set` saving a change puts every failed row
--   back in the queue with its tries cleared.
-- * `creator_pay_form`: a bill's `paid_at`, the day the portal first read it
--   paid, which the creator's Payments reads (never the bill's own date).
-- * `creator_mail_fill`: the one fill of a creator email's fields, used by
--   `creator_mail_queue` and `creator_mail_job`.
-- ===========================================================================

/* One template's fields filled from their values: each {field}, its case and
   spaces as typed, takes its value whole (a backslash kept as typed). */
create or replace function public.creator_mail_fill(p_text text, p_vals jsonb)
returns text
language plpgsql immutable set search_path = public as $$
declare v_out text := coalesce(p_text, ''); v_k text;
begin
  for v_k in select jsonb_object_keys(coalesce(p_vals, '{}'::jsonb)) loop
    v_out := regexp_replace(v_out, '\{\s*' || v_k || '\s*\}', replace(coalesce(p_vals->>v_k, ''), '\', '\\'), 'gi');
  end loop;
  return v_out;
end $$;
revoke all on function public.creator_mail_fill(text, jsonb) from public, anon, authenticated;

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
begin
  select * into t from public.creator_email_templates x where x.purpose = p_purpose;
  if t.purpose is null or not t.on_send then return; end if;
  select * into r from public.creator_pay_requests x where x.id = p_req;
  select * into c from public.creators x where x.id = r.creator_id;
  v_to := lower(btrim(coalesce(case when p_purpose = 'review' then t.to_email else r.email end, '')));
  if v_to !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return; end if;
  v_sub := t.subject;
  v_body := t.body;
  v_vals := jsonb_build_object(
    'creator name', c.name, 'creator id', coalesce(c.creator_code, ''), 'reference', r.ref, 'payee', r.payee,
    'method', public.creator_pay_method(r.method, r.bank), 'account ending', right(r.account, 4),
    'review link', 'https://digital.adspace.me/admin/?s=campaigns&tab=roster&pay=' || c.id);
  v_sub := public.creator_mail_fill(v_sub, v_vals);
  v_body := public.creator_mail_fill(v_body, v_vals);
  insert into public.creator_emails (purpose, creator_id, request_id, to_email, subject, body)
  values (p_purpose, c.id, r.id, v_to, left(v_sub, 200), v_body);
  perform public.creator_mail_kick();
end $$;
revoke all on function public.creator_mail_queue(text, uuid) from public, anon, authenticated;

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
  select * into b from public.creator_bills x where x.option_id = o.id and not x.gone order by x.bill_date desc nulls last limit 1;
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
    'review link', 'https://digital.adspace.me/admin/?s=campaigns&tab=roster&pay=' || c.id);
  v_sub := public.creator_mail_fill(v_sub, v_vals);
  v_body := public.creator_mail_fill(v_body, v_vals);
  insert into public.creator_emails (purpose, creator_id, request_id, option_id, to_email, subject, body)
  values (p_purpose, c.id, r.id, o.id, v_to, left(v_sub, 200), v_body);
  perform public.creator_mail_kick();
end $$;
revoke all on function public.creator_mail_job(text, uuid) from public, anon, authenticated;

create or replace function public.creator_bills_take(p_creator uuid, p_contact bigint, p_rows jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  x jsonb; b public.creator_bills; v_id bigint; v_status text; v_opt uuid; v_n int := 0; v_paid int := 0;
  v_seen bigint[] := '{}'; v_post boolean;
begin
  if p_creator is null or jsonb_typeof(p_rows) is distinct from 'array' then return jsonb_build_object('error', 'bad-request'); end if;
  for x in select * from jsonb_array_elements(p_rows) loop
    v_id := (x->>'id')::bigint;
    if v_id is null then continue; end if;
    v_seen := v_seen || v_id;
    v_opt := public.creator_bill_option(p_creator, x->>'ref', x->>'number');
    select * into b from public.creator_bills y where y.bill_id = v_id for update;
    -- A bill read with no balance keeps the state it had, never Paid by default.
    v_status := case when nullif(x->>'balance', '') is null then coalesce(b.status, 'processing')
                     when (x->>'balance')::numeric <= 0 then 'paid' else 'processing' end;
    v_post := v_opt is not null and exists (select 1 from public.campaign_options o where o.id = v_opt and o.posted_on is not null);
    if b.bill_id is null then
      insert into public.creator_bills (bill_id, creator_id, contact_id, number, ref, bill_date, amount, balance, currency, status,
                                        option_id, read_at, paid_seen_at, paid_told_at)
      values (v_id, p_creator, p_contact, left(x->>'number', 60), left(x->>'ref', 200), nullif(x->>'date', '')::date,
              (x->>'amount')::numeric, nullif(x->>'balance', '')::numeric, left(coalesce(x->>'currency', 'MYR'), 3), v_status, v_opt, now(),
              case when v_status = 'paid' then now() end,
              case when v_status = 'paid' then now() end);
      -- A bill first read already paid is told only for a booking posted in the
      -- portal; one from before the portal (no posted day) tells nobody.
      if v_status = 'paid' and v_post then
        perform public.creator_mail_job('paid', v_opt);
        v_paid := v_paid + 1;
      end if;
    else
      update public.creator_bills y set creator_id = p_creator, contact_id = p_contact, number = left(x->>'number', 60),
        ref = left(x->>'ref', 200), bill_date = nullif(x->>'date', '')::date, amount = (x->>'amount')::numeric,
        balance = coalesce(nullif(x->>'balance', '')::numeric, y.balance), currency = left(coalesce(x->>'currency', 'MYR'), 3), status = v_status,
        option_id = v_opt, gone = false, read_at = now(),
        paid_seen_at = case when v_status = 'paid' then coalesce(y.paid_seen_at, now()) end
       where y.bill_id = v_id;
      if v_status = 'paid' and b.status = 'processing' and b.paid_told_at is null and v_opt is not null then
        update public.creator_bills y set paid_told_at = now() where y.bill_id = v_id;
        perform public.creator_mail_job('paid', v_opt);
        v_paid := v_paid + 1;
      end if;
    end if;
    v_n := v_n + 1;
  end loop;
  update public.creator_bills y set gone = true where y.creator_id = p_creator and not (y.bill_id = any(v_seen)) and not y.gone;
  return jsonb_build_object('ok', true, 'bills', v_n, 'told', v_paid);
end $$;
revoke all on function public.creator_bills_take(uuid, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.creator_bills_take(uuid, bigint, jsonb) to service_role;

create or replace function public.mail_sweep()
returns integer
language plpgsql volatile security definer set search_path = public as $$
declare
  n integer := 0;
  k integer;
begin
  update public.invoice_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.created_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.supplier_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.created_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.client_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.created_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.team_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.created_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.creator_emails x set status = 'unknown', error = coalesce(x.error, 'unknown: not closed')
   where x.status = 'sending' and x.claimed_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  update public.creator_sheet_rows x set status = 'failed', error = coalesce(x.error, 'not closed')
   where x.status = 'sending' and x.claimed_at < now() - interval '10 minutes';
  get diagnostics k = row_count; n := n + k;
  return n;
end $$;
revoke all on function public.mail_sweep() from public, anon, authenticated;

/* A row the sender could not even try (the sheet unread, no header naming a
   value) goes back to the queue with its try given back. The service role's. */
create or replace function public.creator_sheet_release(p_id uuid, p_error text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
begin
  update public.creator_sheet_rows x set status = 'failed', tries = greatest(x.tries - 1, 0),
    error = left(nullif(p_error, ''), 480)
   where x.id = p_id and x.status = 'sending';
  return jsonb_build_object('ok', found);
end $$;
revoke all on function public.creator_sheet_release(uuid, text) from public, anon, authenticated;
grant execute on function public.creator_sheet_release(uuid, text) to service_role;

create or replace function public.creator_sheet_set(p_on boolean, p_sheet text, p_tab text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  s  public.creator_sheet_settings;
  v_id text := nullif(btrim(coalesce(p_sheet, '')), '');
  v_tab text := nullif(btrim(coalesce(p_tab, '')), '');
  v_moved text[] := '{}';
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if v_id ~ '/spreadsheets/d/' then v_id := substring(v_id from '/spreadsheets/d/([A-Za-z0-9_-]+)'); end if;
  if v_id is not null and v_id !~ '^[A-Za-z0-9_-]{20,100}$' then return jsonb_build_object('error', 'bad-sheet'); end if;
  if coalesce(p_on, false) and v_id is null then return jsonb_build_object('error', 'bad-sheet'); end if;
  if v_tab is not null and length(v_tab) > 100 then return jsonb_build_object('error', 'bad-tab'); end if;
  select * into s from public.creator_sheet_settings where id = 1 for update;
  if s.on_send is distinct from coalesce(p_on, false) then
    v_moved := v_moved || ('Add rows: ' || case when s.on_send then 'On → Off' else 'Off → On' end);
  end if;
  if s.spreadsheet_id is distinct from v_id then v_moved := v_moved || 'Google Sheets link changed'::text; end if;
  if s.tab is distinct from v_tab then
    v_moved := v_moved || ('Tab: ' || coalesce(s.tab, 'First tab') || ' → ' || coalesce(v_tab, 'First tab'));
  end if;
  if cardinality(v_moved) = 0 then return jsonb_build_object('ok', true); end if;
  update public.creator_sheet_settings set on_send = coalesce(p_on, false), spreadsheet_id = v_id, tab = v_tab,
    updated_at = now(), updated_by = me.id where id = 1;
  -- The sheet corrected: every row it refused is tried afresh.
  update public.creator_sheet_rows x set status = 'queued', tries = 0, error = null where x.status = 'failed';
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Creator payments sheet', array_to_string(v_moved, ' · '));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.creator_sheet_set(boolean, text, text) from public, anon;
grant execute on function public.creator_sheet_set(boolean, text, text) to authenticated;

create or replace function public.creator_pay_form(p_code text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_id   uuid;
  v_lock integer;
  cr     public.creators;
  v_last public.creator_pay_requests;
  v_paid public.creator_pay_requests;
  v_day  date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  select t.o_creator, t.o_locked into v_id, v_lock from public.creator_code_try(p_code) t;
  if v_lock is not null then return jsonb_build_object('error', 'locked', 'minutes', v_lock); end if;
  select * into cr from public.creators x where x.id = v_id;
  if cr.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if not cr.active then return jsonb_build_object('error', 'inactive'); end if;
  select * into v_last from public.creator_pay_requests x where x.creator_id = cr.id and x.status <> 'withdrawn'
   order by x.seq desc limit 1;
  select * into v_paid from public.creator_pay_requests x where x.creator_id = cr.id and x.status = 'approved'
   order by x.decided_at desc limit 1;
  return jsonb_build_object('ok', true, 'due', public.creator_pay_due(cr.id), 'whatsapp', cr.whatsapp,
    'last', public.creator_pay_json(v_last, false), 'paid', public.creator_pay_json(v_paid, false),
    'days', jsonb_build_object('myr', public.app_setting('creator_pay_days_myr', v_day),
                               'other', public.app_setting('creator_pay_days_other', v_day)),
    'payments', coalesce((select jsonb_agg(jsonb_build_object(
        'job', public.creator_job_ref(o.id), 'campaign', m.title, 'state', o.state,
        'posted_on', o.posted_on, 'pay_by', o.pay_by,
        'bill', (select jsonb_build_object('number', b.number, 'status', b.status, 'date', b.bill_date,
                   'paid_at', b.paid_seen_at, 'amount', b.amount, 'currency', b.currency)
                   from public.creator_bills b where b.option_id = o.id and not b.gone
                  order by (b.status = 'processing') desc, b.bill_date desc nulls last limit 1))
        order by o.posted_on desc nulls first, m.created_at desc)
        from public.campaign_options o join public.campaigns m on m.id = o.campaign_id
       where o.creator_id = cr.id and o.state not in ('option', 'shortlisted', 'backup', 'withdrawn', 'replaced')), '[]'::jsonb));
end $$;
grant execute on function public.creator_pay_form(text) to anon, authenticated;

-- Rollback: run CREATOR PAYMENT DETAILS, CREATOR PAYMENTS, CREATOR PAYMENTS
-- SHEET and CREATOR PAGE PAYMENTS again; drop creator_mail_fill and
-- creator_sheet_release.

-- END OF CREATOR PAYMENTS REVIEWED ---------------------------------------------

select public.functions_tidy();
