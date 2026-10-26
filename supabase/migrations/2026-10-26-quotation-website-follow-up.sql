-- ===========================================================================
-- QUOTATION WEBSITE FOLLOW-UP — a prospect says they are ready to proceed
-- with their quotation, the team revises it in place of the first, and the
-- prospect is told on WhatsApp that it is ready (2026-10-26)
-- ===========================================================================
-- WHY (the user, 2026-10-26): the Letter of Offer is the sales team's to
-- send after a conversation, never the website's; the website's rates are
-- the card's, and the team usually revises them once it has spoken to the
-- prospect. Only a prospect ready to go ahead is asked forward, never a
-- free proposal, and the team is held to answering.
--
-- WHAT IT CHANGES
--   * The website no longer asks for billing details or a Letter of Offer.
--     Beside the quotation the prospect may say they are ready to proceed
--     (`quote_proceed(p_key, p_start, p_decider)`, anon, by the quotation's
--     key), answering when they would start (`month`: within a month,
--     `quarter`: in 1 to 3 months) and whether they decide (`yes`,
--     `others`); refused `bad-answer`, `expired`, `not-proceeding`. It
--     stamps `quotations.proceed_at`, `proceed_due` (the moment plus
--     `quote_reply_days` working days, 2, weekends and public holidays
--     passed over; a Business setting), `proceed_start` and
--     `proceed_decider`, tells the leads team with the answers (kind
--     `quote.proceed`) and files `client.quotation`. Pressed again it
--     answers `again` and changes nothing.
--   * `quote_proceed_remind()` (pg_cron `quote-proceed-remind`, every
--     fifteen minutes) tells the managers (Clients: Leads Full Access, or an
--     admin) once, six hours before the time ends, while nobody has taken
--     the lead, it is not marked Do not contact, not withdrawn and not
--     removed.
--   * A revised quotation replaces the website's (`quotations.replaces`):
--     `quotation_replace(p_new, p_old)` (Clients: Quotations at Work, the
--     client in scope) links a quotation made in the console to the
--     website quotation of the same client it revises; the prospect's link
--     shows the latest revision.
--   * Do not contact (`quotations.no_contact_at`, `no_contact_by`):
--     `quotation_set` takes `no_contact` and `contact` on a website
--     quotation, filed from and to; a quotation so marked sends no
--     reminder.
--   * `quote_website_read` answers the quotation the link shows (the latest
--     revision, else the website's own), whether the prospect said they are
--     ready to proceed, whether a Letter of Offer stands on it, and the
--     colleague who took the lead (their name and position, and their
--     mobile only where their namecard shows it). It never answers billing.
--   * `quote_website_create` queues the `quote_ready` WhatsApp message to
--     the prospect (greeting, brand, reference; its link button the
--     quotation's key) where that template is on; a queueing fault never
--     fails the quotation.
--   * `quote_reply_days` is seeded (2); the SQL Editor part lets
--     `app_settings_set` take it (1 to 10), since that function holds a
--     delete the connector stops on.
--
-- ORDER: this file (connector), then the pages, then
-- 2026-10-26-quotation-website-follow-up-editor.sql in the SQL Editor (the
-- `quote_ready` purpose, `app_settings_set` taking `quote_reply_days`, and
-- the billing step's functions and column dropped). A page served before this file offers no Ready to proceed (it
-- reads that the database needs an update); an old open quotation page
-- still asks billing until the editor part drops it, then answers
-- not-found.
--
-- ROLLBACK: pages first; then drop the five new functions and the cron
-- job, restore the earlier quote_website_read, quote_website_create,
-- and quotation_set from schema.sql's earlier sections;
-- the new columns may stay (nothing else reads them).
-- ===========================================================================

alter table public.quotations add column if not exists proceed_at timestamptz;
alter table public.quotations add column if not exists proceed_due timestamptz;
alter table public.quotations add column if not exists proceed_start text check (proceed_start in ('month', 'quarter'));
alter table public.quotations add column if not exists proceed_decider text check (proceed_decider in ('yes', 'others'));
alter table public.quotations add column if not exists proceed_reminded_at timestamptz;
alter table public.quotations add column if not exists replaces uuid references public.quotations(id) on delete set null;
alter table public.quotations add column if not exists no_contact_at timestamptz;
alter table public.quotations add column if not exists no_contact_by text;
create index if not exists quotations_replaces_idx on public.quotations (replaces) where replaces is not null;
grant select (proceed_at, proceed_due, proceed_start, proceed_decider, replaces, no_contact_at, no_contact_by) on table public.quotations to authenticated;

insert into public.app_settings (key, from_date, value)
select 'quote_reply_days', date '2023-08-14', 2
 where not exists (select 1 from public.app_settings s where s.key = 'quote_reply_days');

-- The moment a prospect ready to proceed is owed contact by: working days after it.
create or replace function public.quote_reply_by(p_at timestamptz)
returns timestamptz
language sql stable security definer set search_path = public as $$
  select public.ops_add_business_days(p_at,
    coalesce(public.app_setting('quote_reply_days', (p_at at time zone 'Asia/Kuala_Lumpur')::date), 2)::int)
$$;
revoke all on function public.quote_reply_by(timestamptz) from public, anon, authenticated;

-- The quotation a website link shows: the latest revision of it, else its own.
create or replace function public.quote_shown(p_id uuid)
returns uuid
language sql stable security definer set search_path = public as $$
  with recursive chain(id, n) as (
    select p_id, 0
    union all
    select q.id, c.n + 1 from public.quotations q join chain c on q.replaces = c.id
     where q.removed_at is null and c.n < 20
  )
  select c.id from chain c join public.quotations q on q.id = c.id
   order by c.n desc, q.issued_at desc limit 1
$$;
revoke all on function public.quote_shown(uuid) from public, anon, authenticated;

create or replace function public.quote_website_read(p_key text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  w  public.quotations;
  q  public.quotations;
  c  public.clients;
  m  public.team_members;
  v_offer boolean;
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
  select exists (select 1 from public.client_services s where s.quotation_id = q.id and s.archived_at is null) into v_offer;
  return jsonb_build_object(
    'ref', q.ref, 'first_ref', w.ref, 'revised', q.id <> w.id,
    'brand', coalesce(w.contact->>'brand', w.brand), 'version', q.version,
    'issued_at', q.issued_at, 'valid_until', q.valid_until, 'lines', q.lines, 'totals', q.totals,
    'selection', w.selection, 'attention', w.contact->>'name',
    'status', case when v_offer then 'offer' else q.status end,
    'proceed_at', w.proceed_at, 'proceed_due', w.proceed_due,
    'rep', case when m.id is null then null else jsonb_build_object('name', m.name, 'title', nullif(btrim(coalesce(m.designation, '')), ''),
             'whatsapp', case when coalesce(m.card_mobile, true) then nullif(public.wa_number(m.mobile), '') end) end,
    'market', case when c.market = 'SG' then 'SG' else 'MY' end,
    'today', (now() at time zone 'Asia/Kuala_Lumpur')::date);
end $$;
revoke all on function public.quote_website_read(text) from public;
grant execute on function public.quote_website_read(text) to anon, authenticated;

-- What the prospect answered, in the team's words.
create or replace function public.quote_proceed_words(p_start text, p_decider text)
returns text
language sql immutable set search_path = public as $$
  select case p_start when 'month' then 'starts within a month' else 'starts in 1 to 3 months' end || ' · ' ||
         case p_decider when 'yes' then 'decision maker' else 'others involved' end
$$;
revoke all on function public.quote_proceed_words(text, text) from public, anon, authenticated;

create or replace function public.quote_proceed(p_key text, p_start text, p_decider text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  w  public.quotations;
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
  if w.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if coalesce(p_start, '') not in ('month', 'quarter') or coalesce(p_decider, '') not in ('yes', 'others') then
    return jsonb_build_object('error', 'bad-answer');
  end if;
  if w.valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'expired'); end if;
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

create or replace function public.quotation_replace(p_new uuid, p_old uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  n public.quotations;
  o public.quotations;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into n from public.quotations where id = p_new for update;
  select * into o from public.quotations where id = p_old;
  if n.id is null or o.id is null or n.client_id <> o.client_id or n.id = o.id
     or n.removed_at is not null or o.removed_at is not null
     or not public.client_scope_ok('client', n.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if n.source <> 'console' or n.replaces is not null then return jsonb_build_object('error', 'bad-quotation'); end if;
  update public.quotations set replaces = o.id where id = n.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', n.brand, n.ref || ' revises ' || o.ref);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_replace(uuid, uuid) from public, anon;
grant execute on function public.quotation_replace(uuid, uuid) to authenticated;

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
  return v_n;
end $$;
revoke all on function public.quote_proceed_remind() from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron is not enabled: no reminders to contact a prospect go out until it is.';
    return;
  end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'quote-proceed-remind';
  perform cron.schedule('quote-proceed-remind', '*/15 * * * *', 'select public.quote_proceed_remind()');
end $$;

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
  perform public.quote_tell(v_c.id, 'quote.website', 'Quotation made on the website · ' || v_c.name,
    v_q.ref || ' · ' || coalesce('Monthly incl. SST RM ' ||
      to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00'), 'one-off') || ' · ' || v_name,
    v_q.id::text);
  -- The prospect is told on WhatsApp that the quotation is ready, its link
  -- button the quotation's key; a queueing fault never fails the quotation.
  begin
    perform public.wa_enqueue('quote_ready', v_wa, v_name,
      jsonb_build_array(public.contact_greeting(v_sal, v_name), v_brand, v_q.ref),
      'quotation', v_q.id, v_c.id, v_q.access_key);
  exception when others then null;
  end;
  return jsonb_build_object('ok', true, 'ref', v_q.ref, 'key', v_q.access_key);
exception when raise_exception then
  if sqlerrm like 'quote:%' then return jsonb_build_object('error', substr(sqlerrm, 7)); end if;
  raise;
end $$;
revoke all on function public.quote_website_create(jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.quote_website_create(jsonb, jsonb, text) to service_role;

create or replace function public.quotation_set(p_id uuid, p_what text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_word text;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_q from public.quotations where id = p_id;
  if v_q.id is null or not public.client_scope_ok('client', v_q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if p_what = 'not_proceeding' then
    update public.quotations set status = 'not_proceeding' where id = p_id; v_word := ' marked Not proceeding';
  elsif p_what = 'proceeding' then
    update public.quotations set status = case when requested_at is not null then 'requested' else 'sent' end
     where id = p_id;
    v_word := ' restored';
  elsif p_what in ('no_contact', 'contact') then
    if v_q.source <> 'website' then return jsonb_build_object('error', 'bad-what'); end if;
    update public.quotations
       set no_contact_at = case when p_what = 'no_contact' then coalesce(no_contact_at, now()) end,
           no_contact_by = case when p_what = 'no_contact' then coalesce(no_contact_by, me.name) end
     where id = p_id;
    v_word := case when p_what = 'no_contact' then ' · Do not contact: off → on' else ' · Do not contact: on → off' end;
  elsif p_what = 'remove' then
    update public.quotations set removed_at = now(), removed_by = me.name where id = p_id; v_word := ' removed';
  elsif p_what = 'restore' then
    update public.quotations set removed_at = null, removed_by = null where id = p_id; v_word := ' restored';
  else
    return jsonb_build_object('error', 'bad-what');
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', v_q.brand, v_q.ref || v_word);
  return jsonb_build_object('ok', true);
end $$;

-- END OF QUOTATION WEBSITE FOLLOW-UP -----------------------------------------

select public.functions_tidy();
