-- ===========================================================================
-- PAGE AVAILABILITY — Upgrade mode a page at a time (2026-10-29)
-- ===========================================================================
-- WHY (the user, 2026-10-29: "can revamp the upgrade be for each page
-- basis? Eg. We could start Upgrade for /client page, start Temporarily
-- Unavailable for /admin", then "Ok good build all" on the mockup):
-- Upgrade mode covered every page at once, so stopping the quotation
-- website meant covering the client portal, Content Review and the rest.
--
-- WHAT IT CHANGES
--   Each page is a row of `app_flags` keyed `page:{key}` (admin, client,
--   review, script, details, creators, creator, quote, supplier, verify),
--   with `kind` (`upgrade` Upgrade in progress, `paused` Temporarily
--   unavailable), its window, a note, a Chinese note and whether the cover
--   offers Chat on WhatsApp. The front door, the 404 and namecards are never
--   covered. `page_states()` (anon) answers every page covered or set,
--   the console's note to the team alone; `page_pulse` adds it as `pages`.
--   `page_set(p_pages, p_kind, p_note, p_note_zh, p_starts, p_ends,
--   p_whatsapp)` (`team.upgrade`) sets several at once (`bad-page`,
--   `bad-kind`, `bad-window`), filed `team.changed` under Portal from and
--   to; `page_states_all()` reads every page for the Settings sheet.
--   `quote_website_create` refuses `unavailable` while the quotation
--   website is covered. `maintenance_set` (a console served before) sets
--   every page; `maintenance_state` answers on only while every page is
--   covered. An Upgrade mode standing when this runs becomes every page's.
--
-- ORDER: this file, 2026-10-07-function-hygiene.sql again (its
-- `open_to_anon` names `page_states`), then the pages. A page served before
-- keeps reading `maintenance_state`. Safe to run twice.
--
-- ROLLBACK: run UPGRADE MODE's maintenance_state and maintenance_set, the
-- latest page_pulse and quote_website_create again; the `page:` rows and
-- the new columns may stay.
-- ===========================================================================

-- PAGE AVAILABILITY ---------------------------------------------------------

alter table public.app_flags add column if not exists kind text;
alter table public.app_flags add column if not exists note_zh text;
alter table public.app_flags add column if not exists whatsapp boolean not null default false;

create or replace function public.page_keys()
returns text[]
language sql immutable set search_path = public as $$
  select array['admin', 'client', 'review', 'script', 'details', 'creators', 'creator', 'quote', 'supplier', 'verify']
$$;
revoke all on function public.page_keys() from public, anon, authenticated;

create or replace function public.page_name(p text)
returns text
language sql immutable set search_path = public as $$
  select case p when 'admin' then 'Console' when 'client' then 'Client portal' when 'review' then 'Content Review'
    when 'script' then 'Video Scripts' when 'details' then 'Details form' when 'creators' then 'Creator selection'
    when 'creator' then 'Creator page' when 'quote' then 'Quotation website' when 'supplier' then 'Supplier form'
    when 'verify' then 'Verify a document' end
$$;
revoke all on function public.page_name(text) from public, anon, authenticated;

-- An Upgrade mode standing when this first runs becomes every page's.
do $$
declare f public.app_flags;
begin
  if not exists (select 1 from public.app_flags where key like 'page:%') then
    select * into f from public.app_flags where key = 'maintenance';
    if f.key is not null and f.on_now and (f.ends_at is null or f.ends_at > now()) then
      insert into public.app_flags (key, on_now, note, starts_at, ends_at, set_by, set_at, kind)
      select 'page:' || k, true, f.note, f.starts_at, f.ends_at, f.set_by, f.set_at, 'upgrade'
        from unnest(public.page_keys()) k
      on conflict (key) do nothing;
    end if;
  end if;
end $$;

-- A page's state as the pages read it; a page not set is left out.
create or replace function public.page_states()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(substr(f.key, 6), jsonb_build_object(
           'on', f.starts_at is null or f.starts_at <= now(),
           'set', true,
           'kind', coalesce(f.kind, 'upgrade'),
           'note', case when f.key <> 'page:admin' or public.is_team() then f.note end,
           'note_zh', f.note_zh,
           'starts_at', f.starts_at,
           'ends_at', f.ends_at,
           'whatsapp', f.whatsapp)), '{}'::jsonb)
    from public.app_flags f
   where f.key like 'page:%' and f.on_now and (f.ends_at is null or f.ends_at > now())
$$;
revoke all on function public.page_states() from public;
grant execute on function public.page_states() to anon, authenticated;

create or replace function public.page_covered(p_key text)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((public.page_states() -> p_key ->> 'on')::boolean, false)
$$;
revoke all on function public.page_covered(text) from public, anon, authenticated;

-- Every page for the Settings sheet, who set it and when.
create or replace function public.page_states_all()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ops_granted('team.upgrade', 'view') then return jsonb_build_object('error', 'denied'); end if;
  return (select jsonb_agg(jsonb_build_object(
            'key', k, 'name', public.page_name(k),
            'set', f.key is not null and f.on_now and (f.ends_at is null or f.ends_at > now()),
            'on', f.key is not null and f.on_now and (f.ends_at is null or f.ends_at > now()) and (f.starts_at is null or f.starts_at <= now()),
            'kind', coalesce(f.kind, 'upgrade'), 'note', f.note, 'note_zh', f.note_zh, 'whatsapp', coalesce(f.whatsapp, false),
            'starts_at', f.starts_at, 'ends_at', f.ends_at, 'set_by', f.set_by, 'set_at', f.set_at) order by o)
            from unnest(public.page_keys()) with ordinality as u(k, o)
            left join public.app_flags f on f.key = 'page:' || u.k);
end $$;
revoke all on function public.page_states_all() from public, anon;
grant execute on function public.page_states_all() to authenticated;

create or replace function public.page_set(p_pages text[], p_kind text, p_note text default null, p_note_zh text default null,
                                           p_starts timestamptz default null, p_ends timestamptz default null,
                                           p_whatsapp boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_who text;
  v_k text;
  v_on boolean := coalesce(p_kind, 'none') <> 'none';
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_zh text := nullif(btrim(coalesce(p_note_zh, '')), '');
  v_was text;
  v_bits text[] := '{}';
  v_word text;
  v_when text := '';
  f public.app_flags;
begin
  if not public.ops_granted('team.upgrade', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if coalesce(array_length(p_pages, 1), 0) = 0
     or exists (select 1 from unnest(p_pages) k where not (k = any (public.page_keys()))) then
    return jsonb_build_object('error', 'bad-page');
  end if;
  if coalesce(p_kind, 'none') not in ('none', 'upgrade', 'paused') then return jsonb_build_object('error', 'bad-kind'); end if;
  if v_on and p_ends is not null and p_ends <= greatest(coalesce(p_starts, now()), now()) then
    return jsonb_build_object('error', 'bad-window');
  end if;
  select coalesce(t.name, t.email) into v_who from public.team_members t
   where lower(t.email) = lower(auth.jwt() ->> 'email') and t.active limit 1;
  v_word := case p_kind when 'upgrade' then 'Upgrade in progress' when 'paused' then 'Temporarily unavailable' else 'Available' end;
  for v_k in select distinct k from unnest(p_pages) k loop
    select * into f from public.app_flags where key = 'page:' || v_k;
    v_was := case when f.key is not null and f.on_now and (f.ends_at is null or f.ends_at > now())
                  then case coalesce(f.kind, 'upgrade') when 'paused' then 'Temporarily unavailable' else 'Upgrade in progress' end
                  else 'Available' end;
    insert into public.app_flags (key, on_now, note, note_zh, starts_at, ends_at, set_by, set_at, kind, whatsapp)
    values ('page:' || v_k, v_on, case when v_on then left(v_note, 300) end, case when v_on then left(v_zh, 300) end,
            case when v_on and p_starts > now() then p_starts end, case when v_on then p_ends end,
            v_who, now(), case when v_on then p_kind end, v_on and coalesce(p_whatsapp, false))
    on conflict (key) do update
      set on_now = excluded.on_now, note = excluded.note, note_zh = excluded.note_zh, starts_at = excluded.starts_at,
          ends_at = excluded.ends_at, set_by = excluded.set_by, set_at = excluded.set_at, kind = excluded.kind,
          whatsapp = excluded.whatsapp;
    v_bits := v_bits || (public.page_name(v_k) || ': ' || v_was || ' → ' || v_word);
  end loop;
  if v_on and p_starts > now() then
    v_when := ' · from ' || public.register_day((p_starts at time zone 'Asia/Kuala_Lumpur')::date) || ' ' ||
              to_char(p_starts at time zone 'Asia/Kuala_Lumpur', 'HH24:MI');
  end if;
  if v_on and p_ends is not null then
    v_when := v_when || ' · until ' || public.register_day((p_ends at time zone 'Asia/Kuala_Lumpur')::date) || ' ' ||
              to_char(p_ends at time zone 'Asia/Kuala_Lumpur', 'HH24:MI');
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(v_who, 'admin'), 'team.changed', 'Portal',
          'Page availability: ' || array_to_string(v_bits, ', ') || v_when ||
          case when v_on then coalesce(' · ' || left(v_note, 300), '') else '' end);
  return jsonb_build_object('ok', true, 'pages', public.page_states_all());
end $$;
revoke all on function public.page_set(text[], text, text, text, timestamptz, timestamptz, boolean) from public, anon;
grant execute on function public.page_set(text[], text, text, text, timestamptz, timestamptz, boolean) to authenticated;

-- A page served before reads the whole portal: on only while every page is.
create or replace function public.maintenance_state()
returns jsonb language sql security definer stable set search_path = public as $$
  with s as (select public.page_states() as p),
       c as (select s.p -> 'client' as c,
                    (select count(*) from jsonb_object_keys(s.p)) = array_length(public.page_keys(), 1) as every,
                    (select bool_and((s.p -> k ->> 'on')::boolean) from unnest(public.page_keys()) k) as all_on
               from s)
  select case when c.every then jsonb_build_object(
           'on', coalesce(c.all_on, false), 'set', true, 'note', c.c ->> 'note',
           'since', c.c ->> 'starts_at', 'starts_at', c.c ->> 'starts_at', 'ends_at', c.c ->> 'ends_at')
         else jsonb_build_object('on', false, 'set', false) end
    from c
$$;
revoke all on function public.maintenance_state() from public;
grant execute on function public.maintenance_state() to anon, authenticated;

-- A console served before switches every page at once.
create or replace function public.maintenance_set(p_on boolean, p_note text default null,
                                                  p_starts timestamptz default null,
                                                  p_ends timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  v := public.page_set(public.page_keys(), case when coalesce(p_on, false) then 'upgrade' else 'none' end,
                       p_note, null, p_starts, p_ends, false);
  if v ? 'error' then return v; end if;
  return public.maintenance_state();
end $$;
revoke all on function public.maintenance_set(boolean, text, timestamptz, timestamptz) from public, anon;
grant execute on function public.maintenance_set(boolean, text, timestamptz, timestamptz) to authenticated;

create or replace function public.page_pulse(p_audience text default null, p_bell boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members;
  v  jsonb := jsonb_build_object('maintenance', public.maintenance_state(), 'pages', public.page_states());
begin
  if p_audience in ('team', 'clients') then
    v := v || jsonb_build_object('announcements', coalesce(public.announcement_now(p_audience), '[]'::jsonb));
  end if;
  /* The console's minute says the colleague is active, at most once every
     15 minutes; a client page asks for the clients and never stamps. */
  if p_audience = 'team' then
    begin
      update public.team_members t set last_seen_at = now()
       where t.id = (public.ops_me()).id
         and (t.last_seen_at is null or t.last_seen_at < now() - interval '15 minutes');
    exception when others then null;
    end;
  end if;
  if coalesce(p_bell, false) then
    me := public.ops_me();
    if me.id is not null then
      v := v || jsonb_build_object('bell', jsonb_build_object(
        'unread', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc)
                              from (select * from public.ops_notifications o
                                     where o.team_member_id = me.id and o.read_at is null and o.hidden_at is null
                                     order by o.created_at desc limit 30) x), '[]'::jsonb),
        'earlier', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc)
                               from (select * from public.ops_notifications o
                                      where o.team_member_id = me.id and o.read_at is not null and o.hidden_at is null
                                        and o.created_at >= now() - interval '7 days'
                                      order by o.created_at desc limit 10) x), '[]'::jsonb)));
    end if;
  end if;
  return v;
end $$;
revoke all on function public.page_pulse(text, boolean) from public;
grant execute on function public.page_pulse(text, boolean) to anon, authenticated;

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
  -- The quotation website covered (Page availability) makes nothing.
  if public.page_covered('quote') then return jsonb_build_object('error', 'unavailable'); end if;
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

-- END OF PAGE AVAILABILITY --------------------------------------------------

select public.functions_tidy();
