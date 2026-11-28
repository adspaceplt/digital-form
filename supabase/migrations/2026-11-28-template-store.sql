-- ===========================================================================
-- TEMPLATE STORE (2026-11-28)
-- ===========================================================================
-- WHY: restructure release 11 (docs/MAP.md §G; DESIGN.md §7, layer 3). The
-- agency wording a person reads (letters, terms, emails, WhatsApp, HR
-- documents, consent lines, guides, AI prompts) sits in code and in eleven
-- tables of their own, unversioned (MAP-INVENTORY §D). One store holds it:
-- versioned, English and 中文, its placeholders named and bound to a
-- record's fields. This release builds the store and its engine alone; no
-- wording moves into it (releases 12 to 17 do that, area by area).
-- WHAT IT CHANGES
--   * `templates`: a version of one wording in one language (key, kind,
--     language, version, subject, body, placeholders, status draft or live,
--     effective_from, sample, created_by_id and published_by_id to
--     team_members on delete set null). `kind` names the sender's field
--     list (`template_fields`). A live version is never edited or deleted
--     (`templates_guard`); a later one replaces it from its own date. RLS
--     on: read at Business settings (`team.settings`, a granted part,
--     `ops_granted`), written by the functions below alone.
--   * Engine: `template_render(key, lang, record, values, at, strict)`, the
--     version in force on the Malaysian day (`template_in_force`), 中文
--     falling back to English where none is live; record fields bound by
--     `template_values(kind, record)` (client and supplier in this release;
--     the sender's name for every kind), other fields given by the caller
--     and checked against the kind's list; each value escaped where it is
--     inserted (`template_esc`, as `ADspaceWords.esc`); a field with no
--     value kept as `{field}` and named in `missing`, `missing-field` where
--     `strict`.
--   * `templates_list`, `template_draft_save`, `template_publish`,
--     `template_draft_delete`: Business settings at Manage to write, filed
--     `team.changed` under Templates.
--   * Seed: two neutral samples (`sample.greeting`, English and 中文),
--     marked `sample`, into an empty table alone. No agency wording.
-- ORDER: this file alone; no page calls it yet (js/tpl.js ships unloaded
-- for release 12). An open tab meets nothing new.
-- ROLLBACK: drop table public.templates cascade; drop function
-- public.templates_guard(), public.template_norm(text),
-- public.template_names(text), public.template_esc(text),
-- public.template_fill(text, jsonb), public.template_in_force(text, text,
-- date), public.template_values(text, uuid), public.template_render(text,
-- text, uuid, jsonb, date, boolean), public.templates_list(text),
-- public.template_draft_save(uuid, text, text, text, text, text,
-- timestamptz), public.template_publish(uuid, date),
-- public.template_draft_delete(uuid). Nothing else reads them. Safe to run
-- twice.

-- TEMPLATE STORE -------------------------------------------------------------

create table if not exists public.templates (
  id              uuid primary key default gen_random_uuid(),
  key             text not null check (key ~ '^[a-z][a-z0-9]*([._-][a-z0-9]+)*$' and length(key) <= 80),
  kind            text not null check (kind ~ '^[a-z][a-z-]*$'),
  language        text not null check (language in ('en', 'zh')),
  version         int  not null check (version > 0),
  subject         text not null default '' check (length(subject) <= 200),
  body            text not null check (length(body) between 1 and 20000),
  placeholders    text[] not null default '{}',
  status          text not null default 'draft' check (status in ('draft', 'live')),
  effective_from  date,
  sample          boolean not null default false,
  created_by_id   uuid references public.team_members(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  published_by_id uuid references public.team_members(id) on delete set null,
  published_at    timestamptz,
  unique (key, language, version),
  constraint templates_live_dated check ((status = 'live') = (effective_from is not null))
);
create index if not exists templates_in_force_idx
  on public.templates (key, language, effective_from desc, version desc) where status = 'live';

alter table public.templates enable row level security;
revoke all on public.templates from anon;
grant select on public.templates to authenticated;
drop policy if exists templates_read on public.templates;
create policy templates_read on public.templates for select to authenticated
  using (public.ops_granted('team.settings', 'work'));

/* A placeholder's name as every template reads it: lower case, one space. */
create or replace function public.template_norm(p_name text) returns text
language sql immutable set search_path = public as $$
  select btrim(regexp_replace(lower(coalesce(p_name, '')), '\s+', ' ', 'g')) $$;
revoke all on function public.template_norm(text) from public, anon, authenticated;

/* The placeholders a text names, each once, in the order first met. */
create or replace function public.template_names(p_text text) returns text[]
language sql immutable set search_path = public as $$
  select coalesce(array_agg(y.n order by y.f), '{}'::text[])
    from (select public.template_norm(x.m[1]) as n, min(x.o) as f
            from regexp_matches(coalesce(p_text, ''), '\{([^{}]*)\}', 'g') with ordinality as x (m, o)
           group by 1) y $$;
revoke all on function public.template_names(text) from public, anon, authenticated;

/* The page's one escape (ADspaceWords.esc): & < > " and '. */
create or replace function public.template_esc(p_text text) returns text
language sql immutable set search_path = public as $$
  select replace(replace(replace(replace(replace(coalesce(p_text, ''),
    '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;') $$;
revoke all on function public.template_esc(text) from public, anon, authenticated;

/* A text filled from its values: plain and escaped, every field with no
   value kept as {field} and named in missing. */
create or replace function public.template_fill(p_text text, p_values jsonb) returns jsonb
language plpgsql immutable set search_path = public as $$
declare
  v_parts text[] := regexp_split_to_array(coalesce(p_text, ''), '\{[^{}]*\}');
  v_names text[];
  v_i int;
  v_n text;
  v_v text;
  v_t text := '';
  v_h text := '';
  v_miss text[] := '{}'::text[];
begin
  select coalesce(array_agg(x.m[1] order by x.o), '{}'::text[]) into v_names
    from regexp_matches(coalesce(p_text, ''), '\{([^{}]*)\}', 'g') with ordinality as x (m, o);
  for v_i in 1 .. coalesce(array_length(v_parts, 1), 0) loop
    v_t := v_t || v_parts[v_i];
    v_h := v_h || public.template_esc(v_parts[v_i]);
    if v_i <= coalesce(array_length(v_names, 1), 0) then
      v_n := public.template_norm(v_names[v_i]);
      v_v := coalesce(p_values ->> v_n, '');
      if btrim(v_v) <> '' then
        v_t := v_t || v_v;
        v_h := v_h || public.template_esc(v_v);
      else
        v_t := v_t || '{' || v_n || '}';
        v_h := v_h || public.template_esc('{' || v_n || '}');
        if not (v_n = any (v_miss)) then v_miss := v_miss || v_n; end if;
      end if;
    end if;
  end loop;
  return jsonb_build_object('text', v_t, 'html', v_h, 'missing', to_jsonb(v_miss));
end $$;
revoke all on function public.template_fill(text, jsonb) from public, anon, authenticated;

/* A live version is kept as it went live; its placeholders are stamped from
   its words. A colleague deleted clears the id alone. */
create or replace function public.templates_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    if old.status = 'live' then raise exception 'live-template' using errcode = 'P0001'; end if;
    return old;
  end if;
  if tg_op = 'UPDATE' and old.status = 'live'
     and (new.key, new.kind, new.language, new.version, new.subject, new.body, new.status, new.effective_from, new.sample)
         is distinct from (old.key, old.kind, old.language, old.version, old.subject, old.body, old.status, old.effective_from, old.sample) then
    raise exception 'live-template' using errcode = 'P0001';
  end if;
  new.placeholders := public.template_names(coalesce(new.subject, '') || ' ' || coalesce(new.body, ''));
  if tg_op = 'UPDATE' and (new.subject, new.body, new.status) is distinct from (old.subject, old.body, old.status) then
    new.updated_at := now();
  end if;
  return new;
end $$;
revoke all on function public.templates_guard() from public, anon, authenticated;
drop trigger if exists templates_guard on public.templates;
create trigger templates_guard before insert or update or delete on public.templates
  for each row execute function public.templates_guard();

/* The live version in force on a day: the latest from that day or before,
   the later version on a shared day. */
create or replace function public.template_in_force(p_key text, p_lang text, p_at date)
returns public.templates
language sql stable security definer set search_path = public as $$
  select * from public.templates x
   where x.key = p_key and x.language = p_lang and x.status = 'live' and x.effective_from <= p_at
   order by x.effective_from desc, x.version desc
   limit 1 $$;
revoke all on function public.template_in_force(text, text, date) from public, anon, authenticated;

/* A record's fields for a kind, each at the reader's own access. */
create or replace function public.template_values(p_kind text, p_record uuid)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_c public.clients;
  v_su public.suppliers;
  v_out jsonb := '{}'::jsonb;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if 'sender name' = any (coalesce(public.template_fields(p_kind), '{}'::text[])) then
    v_out := v_out || jsonb_build_object('sender name', me.name);
  end if;
  if p_record is null then return v_out; end if;
  if p_kind = 'client' then
    if not public.allowed('clients', 'view') then return jsonb_build_object('error', 'denied'); end if;
    select * into v_c from public.clients x where x.id = p_record;
    if v_c.id is null or not public.client_seen(v_c.id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
    v_out := v_out || jsonb_build_object('client name', v_c.name, 'company name',
      coalesce(case when public.allowed('clients.billing', 'view') then nullif(btrim(v_c.legal_name), '') end, v_c.name));
    if public.allowed('clients.contacts', 'view') then
      v_out := v_out || jsonb_strip_nulls(jsonb_build_object('contact name',
        (select k.name from public.client_contacts k
          where k.client_id = v_c.id and k.is_primary and k.archived_at is null limit 1)));
    end if;
  elsif p_kind = 'supplier' then
    if not public.allowed('suppliers', 'view') then return jsonb_build_object('error', 'denied'); end if;
    select * into v_su from public.suppliers x where x.id = p_record;
    if v_su.id is null then return jsonb_build_object('error', 'not-found'); end if;
    v_out := v_out || jsonb_strip_nulls(jsonb_build_object('supplier name', v_su.name, 'supplier id', v_su.code,
      'contact name', nullif(btrim(v_su.contact_name), ''), 'payment term', v_su.payment_term, 'currency', v_su.currency));
  else
    return jsonb_build_object('error', 'no-record');
  end if;
  return v_out;
end $$;
revoke all on function public.template_values(text, uuid) from public, anon, authenticated;

/* The one engine: a template by key and language, in force on a day,
   filled from its record and from the values its sender gives. */
create or replace function public.template_render(p_key text, p_lang text, p_record uuid default null,
  p_values jsonb default null, p_at date default null, p_strict boolean default false)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_at date := coalesce(p_at, (now() at time zone 'Asia/Kuala_Lumpur')::date);
  v_t public.templates;
  v_fb boolean := false;
  v_vals jsonb;
  v_k text;
  v_n text;
  v_s jsonb;
  v_b jsonb;
  v_miss jsonb;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_lang is null or p_lang not in ('en', 'zh') then return jsonb_build_object('error', 'bad-lang'); end if;
  if p_values is not null and jsonb_typeof(p_values) <> 'object' then return jsonb_build_object('error', 'bad-values'); end if;
  v_t := public.template_in_force(p_key, p_lang, v_at);
  if v_t.id is null and p_lang <> 'en' then
    v_t := public.template_in_force(p_key, 'en', v_at);
    v_fb := v_t.id is not null;
  end if;
  if v_t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  v_vals := public.template_values(v_t.kind, p_record);
  if v_vals ? 'error' then return v_vals; end if;
  for v_k in select jsonb_object_keys(coalesce(p_values, '{}'::jsonb)) loop
    v_n := public.template_norm(v_k);
    if not (v_n = any (coalesce(public.template_fields(v_t.kind), '{}'::text[]))) then
      return jsonb_build_object('error', 'unknown-field', 'field', '{' || v_k || '}',
        'fields', to_jsonb(public.template_fields(v_t.kind)));
    end if;
    if not (v_vals ? v_n) and jsonb_typeof(p_values -> v_k) in ('string', 'number') then
      v_vals := v_vals || jsonb_build_object(v_n, p_values ->> v_k);
    end if;
  end loop;
  v_s := public.template_fill(v_t.subject, v_vals);
  v_b := public.template_fill(v_t.body, v_vals);
  select coalesce(jsonb_agg(y.n order by y.f), '[]'::jsonb) into v_miss
    from (select x.n, min(x.o) as f
            from jsonb_array_elements_text((v_s -> 'missing') || (v_b -> 'missing')) with ordinality as x (n, o)
           group by x.n) y;
  if p_strict and jsonb_array_length(v_miss) > 0 then
    return jsonb_build_object('error', 'missing-field', 'fields', v_miss);
  end if;
  return jsonb_build_object('ok', true, 'id', v_t.id, 'key', v_t.key, 'lang', v_t.language, 'fallback', v_fb,
    'version', v_t.version, 'effective_from', v_t.effective_from, 'sample', v_t.sample,
    'subject', v_s ->> 'text', 'subject_html', v_s ->> 'html', 'text', v_b ->> 'text', 'html', v_b ->> 'html',
    'missing', v_miss);
end $$;
revoke all on function public.template_render(text, text, uuid, jsonb, date, boolean) from public, anon;
grant execute on function public.template_render(text, text, uuid, jsonb, date, boolean) to authenticated;

/* Every version, newest first under its key and language, the one in force
   today marked. Business settings. */
create or replace function public.templates_list(p_key text default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
begin
  if me.id is null or not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  return jsonb_build_object('ok', true, 'fields', public.template_fields_all(), 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', x.id, 'key', x.key, 'kind', x.kind, 'lang', x.language,
      'version', x.version, 'status', x.status, 'effective_from', x.effective_from, 'sample', x.sample,
      'in_force', x.id = (public.template_in_force(x.key, x.language, v_today)).id,
      'subject', x.subject, 'body', x.body, 'placeholders', to_jsonb(x.placeholders),
      'created_by_id', x.created_by_id, 'created_by', cm.name, 'created_at', x.created_at, 'updated_at', x.updated_at,
      'published_by_id', x.published_by_id, 'published_by', pm.name, 'published_at', x.published_at)
      order by x.key, array_position(array['en', 'zh'], x.language), x.version desc)
      from public.templates x
      left join public.team_members cm on cm.id = x.created_by_id
      left join public.team_members pm on pm.id = x.published_by_id
     where p_key is null or x.key = p_key), '[]'::jsonb));
end $$;
revoke all on function public.templates_list(text) from public, anon;
grant execute on function public.templates_list(text) to authenticated;

/* A draft: a new version of a key in a language, or the same draft's words
   changed. Every field is checked against the kind's list before anything
   is written. */
create or replace function public.template_draft_save(p_id uuid, p_key text, p_kind text, p_lang text,
  p_subject text, p_body text, p_expected timestamptz default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_s text := btrim(regexp_replace(coalesce(p_subject, ''), '\s+', ' ', 'g'));
  v_b text := btrim(replace(coalesce(p_body, ''), E'\r', ''));
  v_key text := lower(btrim(coalesce(p_key, '')));
  v_row public.templates;
  v_kind0 text;
  v_ver int;
  v_id uuid;
  v_chk jsonb;
begin
  if me.id is null or not public.ops_granted('team.settings', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  if length(v_s) > 200 then return jsonb_build_object('error', 'bad-subject'); end if;
  if length(v_b) < 2 or length(v_b) > 20000 then return jsonb_build_object('error', 'bad-body'); end if;
  if p_id is null then
    if v_key !~ '^[a-z][a-z0-9]*([._-][a-z0-9]+)*$' or length(v_key) > 80 then return jsonb_build_object('error', 'bad-key'); end if;
    if p_kind is null or public.template_fields(p_kind) is null then return jsonb_build_object('error', 'bad-kind'); end if;
    if p_lang is null or p_lang not in ('en', 'zh') then return jsonb_build_object('error', 'bad-lang'); end if;
    v_chk := public.template_check(v_s || E'\n' || v_b, p_kind);
    if v_chk is not null then return v_chk; end if;
    perform pg_advisory_xact_lock(hashtext('templates:' || v_key));
    select x.kind into v_kind0 from public.templates x where x.key = v_key limit 1;
    if v_kind0 is not null and v_kind0 <> p_kind then return jsonb_build_object('error', 'kind-differs', 'kind', v_kind0); end if;
    select coalesce(max(x.version), 0) + 1 into v_ver from public.templates x where x.key = v_key and x.language = p_lang;
    insert into public.templates (key, kind, language, version, subject, body, created_by_id)
    values (v_key, p_kind, p_lang, v_ver, v_s, v_b, me.id)
    returning id into v_id;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'team.changed', 'Templates',
      v_key || ' (' || case p_lang when 'zh' then '中文' else 'English' end || ') · Version ' || v_ver || ' drafted');
    return jsonb_build_object('ok', true, 'id', v_id, 'version', v_ver);
  end if;
  select * into v_row from public.templates x where x.id = p_id for update;
  if v_row.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_row.status = 'live' then return jsonb_build_object('error', 'live'); end if;
  if p_expected is not null and v_row.updated_at is distinct from p_expected then
    return jsonb_build_object('error', 'stale', 'row', jsonb_build_object('id', v_row.id, 'subject', v_row.subject,
      'body', v_row.body, 'updated_at', v_row.updated_at));
  end if;
  v_chk := public.template_check(v_s || E'\n' || v_b, v_row.kind);
  if v_chk is not null then return v_chk; end if;
  if v_row.subject = v_s and v_row.body = v_b then
    return jsonb_build_object('ok', true, 'id', v_row.id, 'version', v_row.version);
  end if;
  update public.templates x set subject = v_s, body = v_b where x.id = v_row.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Templates',
    v_row.key || ' (' || case v_row.language when 'zh' then '中文' else 'English' end || ') · Version ' || v_row.version || ' changed');
  return jsonb_build_object('ok', true, 'id', v_row.id, 'version', v_row.version);
end $$;
revoke all on function public.template_draft_save(uuid, text, text, text, text, text, timestamptz) from public, anon;
grant execute on function public.template_draft_save(uuid, text, text, text, text, text, timestamptz) to authenticated;

/* A draft goes live from a day: today (Malaysia) or later, never before the
   version in force or planned. The version before stays, read for the days
   before. */
create or replace function public.template_publish(p_id uuid, p_from date)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_row public.templates;
  v_cur date;
begin
  if me.id is null or not public.ops_granted('team.settings', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_row from public.templates x where x.id = p_id;
  if v_row.id is null then return jsonb_build_object('error', 'not-found'); end if;
  perform pg_advisory_xact_lock(hashtext('templates:' || v_row.key));
  select * into v_row from public.templates x where x.id = p_id for update;
  if v_row.status = 'live' then return jsonb_build_object('error', 'live'); end if;
  if p_from is null then return jsonb_build_object('error', 'bad-date'); end if;
  if p_from < v_today then return jsonb_build_object('error', 'past'); end if;
  select max(x.effective_from) into v_cur from public.templates x
   where x.key = v_row.key and x.language = v_row.language and x.status = 'live';
  if v_cur is not null and p_from < v_cur then return jsonb_build_object('error', 'before-current', 'from', v_cur); end if;
  update public.templates x set status = 'live', effective_from = p_from, published_by_id = me.id, published_at = now()
   where x.id = v_row.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Templates',
    v_row.key || ' (' || case v_row.language when 'zh' then '中文' else 'English' end || ') · Version ' || v_row.version
      || ' live from ' || public.register_day(p_from));
  return jsonb_build_object('ok', true, 'id', v_row.id, 'version', v_row.version, 'effective_from', p_from);
end $$;
revoke all on function public.template_publish(uuid, date) from public, anon;
grant execute on function public.template_publish(uuid, date) to authenticated;

/* A draft deleted; a live version never is. */
create or replace function public.template_draft_delete(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_row public.templates;
begin
  if me.id is null or not public.ops_granted('team.settings', 'manage') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_row from public.templates x where x.id = p_id for update;
  if v_row.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_row.status = 'live' then return jsonb_build_object('error', 'live'); end if;
  delete from public.templates x where x.id = v_row.id and x.status = 'draft';
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', 'Templates',
    v_row.key || ' (' || case v_row.language when 'zh' then '中文' else 'English' end || ') · Version ' || v_row.version || ' deleted');
  return jsonb_build_object('ok', true, 'id', v_row.id);
end $$;
revoke all on function public.template_draft_delete(uuid) from public, anon;
grant execute on function public.template_draft_delete(uuid) to authenticated;

/* Two neutral samples, into an empty store alone: a first run, never a
   running list. No agency wording is seeded (the repository is public). */
insert into public.templates (key, kind, language, version, subject, body, status, effective_from, sample)
select x.key, x.kind, x.language, 1, x.subject, x.body, 'live', date '2026-01-01', true
  from (values
    ('sample.greeting', 'client', 'en', 'Sample for {client name}',
     E'Dear {contact name},\n\nThis is a sample template for {client name}.\n\n{sender name}'),
    ('sample.greeting', 'client', 'zh', '{client name}示例',
     E'{contact name}您好：\n\n这是{client name}的示例模板。\n\n{sender name}')
  ) as x (key, kind, language, subject, body)
 where not exists (select 1 from public.templates);

-- END OF TEMPLATE STORE -------------------------------------------------------

select public.functions_tidy();
