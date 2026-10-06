-- ===========================================================================
-- DOCUMENT TYPES — the team adds and edits its own kinds of letter, each
-- asking on Issue for the fields its wording names.
-- 2026-10-07. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the
-- two.
--
-- WHAT CHANGED
--   1. `doc_types.fields`: how each field the wording names in braces is
--      asked for on Issue ({intern name} as text, {from} as a date, {scope}
--      as a paragraph), a map from the field's name to `text`, `date` or
--      `long`. A field the map does not name is asked as text. The fields
--      themselves are whatever the wording names; {first name}, {role} and
--      {client} fill themselves and are never asked.
--   2. `doc_type_save(...)` adds or edits a type: its group (fixed once
--      made: Quotation, Client letter, HR letter), its name (unique), an HR
--      letter's reference code (ADHR/{Employee ID}/{code}{YYMM}), the
--      wording, whether it is signed, and its fields. `doc_type_set_active`
--      offers it on Issue or stops offering it. Both are Documents: Document
--      types (`register.types`), a granted part: an admin's by itself, any
--      other group's once set. Each is filed `team.changed` under subject
--      Document types, naming what changed from and to. A type is never
--      removed: an issued document names its type.
--
-- ROLLBACK (in the SQL Editor)
--   drop function if exists public.doc_type_set_active(text, boolean);
--   drop function if exists public.doc_type_save(text, text, text, text, text, text, text, text, text, text, boolean, jsonb);
--   alter table public.doc_types drop column if exists fields;
-- ===========================================================================

alter table public.doc_types add column if not exists fields jsonb not null default '{}'::jsonb;

create or replace function public.doc_type_save(
  p_id         text,
  p_family     text,
  p_name       text,
  p_code       text,
  p_title      text,
  p_salutation text,
  p_closing    text,
  p_body_en    text,
  p_body_zh    text,
  p_body_ms    text,
  p_signed     boolean,
  p_fields     jsonb
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me        public.team_members;
  v_old     public.doc_types%rowtype;
  v_name    text := btrim(coalesce(p_name, ''));
  v_code    text := upper(btrim(coalesce(p_code, '')));
  v_title   text := btrim(coalesce(p_title, ''));
  v_sal     text := btrim(coalesce(p_salutation, ''));
  v_close   text := btrim(coalesce(p_closing, ''));
  v_en      text := btrim(coalesce(p_body_en, ''));
  v_zh      text := btrim(coalesce(p_body_zh, ''));
  v_ms      text := btrim(coalesce(p_body_ms, ''));
  v_signed  boolean := coalesce(p_signed, true);
  v_fields  jsonb := coalesce(p_fields, '{}'::jsonb);
  v_family  text;
  v_id      text;
  v_n       int;
  v_key     text;
  v_kind    text;
  v_moves   text[] := '{}';
  v_said    text;
  v_was     text;
begin
  if not public.ops_granted('register.types', 'work') then return jsonb_build_object('error', 'denied'); end if;
  me := public.ops_me();
  if char_length(v_name) < 2 or char_length(v_name) > 80 then return jsonb_build_object('error', 'bad-name'); end if;
  if char_length(v_title) > 200 or char_length(v_sal) > 120 or char_length(v_close) > 120
     or char_length(v_en) > 20000 or char_length(v_zh) > 20000 or char_length(v_ms) > 20000 then
    return jsonb_build_object('error', 'too-long');
  end if;
  if jsonb_typeof(v_fields) <> 'object' or (select count(*) from jsonb_object_keys(v_fields)) > 30 then
    return jsonb_build_object('error', 'bad-fields');
  end if;
  for v_key, v_kind in select e.key, e.value from jsonb_each_text(v_fields) as e loop
    if v_key !~ '^[^{}\n]{1,40}$' or v_kind is null or v_kind not in ('text', 'date', 'long') then
      return jsonb_build_object('error', 'bad-fields');
    end if;
  end loop;

  if coalesce(btrim(p_id), '') <> '' then
    select * into v_old from public.doc_types d where d.id = btrim(p_id);
    if v_old.id is null then return jsonb_build_object('error', 'not-found'); end if;
    if p_family is not null and p_family <> v_old.family then return jsonb_build_object('error', 'family-fixed'); end if;
    v_family := v_old.family;
  else
    if p_family is null or p_family not in ('quote_cover', 'client', 'hr') then return jsonb_build_object('error', 'bad-family'); end if;
    v_family := p_family;
  end if;

  if exists (select 1 from public.doc_types d
              where lower(btrim(d.name)) = lower(v_name) and d.id is distinct from v_old.id) then
    return jsonb_build_object('error', 'taken');
  end if;
  -- An HR letter's reference is ADHR/{Employee ID}/{code}{YYMM}, so its code
  -- is required and is its own among the HR letters offered.
  if v_family = 'hr' then
    if v_code !~ '^[A-Z0-9]{1,4}$' then return jsonb_build_object('error', 'bad-code'); end if;
    if exists (select 1 from public.doc_types d
                where d.family = 'hr' and d.active and upper(coalesce(d.code, '')) = v_code
                  and d.id is distinct from v_old.id) then
      return jsonb_build_object('error', 'code-taken');
    end if;
  else
    v_code := v_old.code;
  end if;

  if v_old.id is null then
    v_id := left(coalesce(nullif(btrim(regexp_replace(lower(v_name), '[^a-z0-9]+', '_', 'g'), '_'), ''), 'type'), 40);
    if exists (select 1 from public.doc_types d where d.id = v_id) then
      v_n := 2;
      while exists (select 1 from public.doc_types d where d.id = v_id || '_' || v_n) loop v_n := v_n + 1; end loop;
      v_id := v_id || '_' || v_n;
    end if;
    insert into public.doc_types (id, family, code, name, title, salutation, closing, body_en, body_zh, body_ms,
                                  signed, position, active, fields)
    values (v_id, v_family, v_code, v_name, v_title, v_sal, v_close, v_en, v_zh, v_ms, v_signed,
            coalesce((select max(d.position) from public.doc_types d), 0) + 10, true, v_fields);
    insert into public.activity_log (actor, action, subject, detail)
    values (coalesce(me.name, lower(auth.jwt() ->> 'email')), 'team.changed', 'Document types',
            'Added: ' || v_name || ' · ' || case v_family when 'hr' then 'HR letter · Code ' || v_code
                                                          when 'client' then 'Client letter' else 'Quotation' end);
    return jsonb_build_object('ok', true, 'id', v_id);
  end if;

  -- What changed, from and to; the wording is long, so it is named only.
  if v_old.name <> v_name then v_moves := v_moves || ('Name: ' || v_old.name || ' → ' || v_name); end if;
  if v_family = 'hr' and coalesce(v_old.code, '') <> v_code then
    v_moves := v_moves || ('Code: ' || coalesce(nullif(v_old.code, ''), 'not set') || ' → ' || v_code);
  end if;
  if coalesce(v_old.title, '') <> v_title then
    v_moves := v_moves || ('Title: ' || coalesce(nullif(v_old.title, ''), 'not set') || ' → ' || coalesce(nullif(v_title, ''), 'not set'));
  end if;
  if coalesce(v_old.salutation, '') <> v_sal then
    v_moves := v_moves || ('Salutation: ' || coalesce(nullif(v_old.salutation, ''), 'not set') || ' → ' || coalesce(nullif(v_sal, ''), 'not set'));
  end if;
  if coalesce(v_old.closing, '') <> v_close then
    v_moves := v_moves || ('Closing: ' || coalesce(nullif(v_old.closing, ''), 'not set') || ' → ' || coalesce(nullif(v_close, ''), 'not set'));
  end if;
  if v_old.signed <> v_signed then
    v_moves := v_moves || ('To be signed: ' || case when v_old.signed then 'Yes → No' else 'No → Yes' end);
  end if;
  if coalesce(v_old.body_en, '') <> v_en then v_moves := v_moves || 'Wording changed'::text; end if;
  if coalesce(v_old.body_zh, '') <> v_zh then v_moves := v_moves || 'Chinese wording changed'::text; end if;
  if coalesce(v_old.body_ms, '') <> v_ms then v_moves := v_moves || 'Malay wording changed'::text; end if;
  if coalesce(v_old.fields, '{}'::jsonb) <> v_fields then
    select coalesce(string_agg(e.key || ' (' || case e.value when 'long' then 'paragraph' else e.value end || ')', ', ' order by e.key), 'none')
      into v_was from jsonb_each_text(coalesce(v_old.fields, '{}'::jsonb)) as e;
    select coalesce(string_agg(e.key || ' (' || case e.value when 'long' then 'paragraph' else e.value end || ')', ', ' order by e.key), 'none')
      into v_said from jsonb_each_text(v_fields) as e;
    v_moves := v_moves || ('Fields: ' || v_was || ' → ' || v_said);
  end if;
  if array_length(v_moves, 1) is null then
    return jsonb_build_object('ok', true, 'id', v_old.id, 'unchanged', true);
  end if;

  update public.doc_types d
     set name = v_name, code = v_code, title = v_title, salutation = v_sal, closing = v_close,
         body_en = v_en, body_zh = v_zh, body_ms = v_ms, signed = v_signed, fields = v_fields
   where d.id = v_old.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, lower(auth.jwt() ->> 'email')), 'team.changed', 'Document types',
          v_name || ' · ' || array_to_string(v_moves, ' · '));
  return jsonb_build_object('ok', true, 'id', v_old.id);
end $$;
grant execute on function public.doc_type_save(text, text, text, text, text, text, text, text, text, text, boolean, jsonb) to authenticated;

-- Offered on Issue, or no longer. The way back never asks.
create or replace function public.doc_type_set_active(p_id text, p_on boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me    public.team_members;
  v_t   public.doc_types%rowtype;
  v_on  boolean := coalesce(p_on, false);
begin
  if not public.ops_granted('register.types', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into v_t from public.doc_types d where d.id = p_id;
  if v_t.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_t.active = v_on then return jsonb_build_object('ok', true, 'unchanged', true); end if;
  if v_on and v_t.family = 'hr' and exists (select 1 from public.doc_types d
       where d.family = 'hr' and d.active and d.id <> v_t.id and upper(coalesce(d.code, '')) = upper(coalesce(v_t.code, ''))) then
    return jsonb_build_object('error', 'code-taken');
  end if;
  me := public.ops_me();
  update public.doc_types d set active = v_on where d.id = v_t.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(me.name, lower(auth.jwt() ->> 'email')), 'team.changed', 'Document types',
          v_t.name || ' · ' || case when v_on then 'Inactive → Active' else 'Active → Inactive' end);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.doc_type_set_active(text, boolean) to authenticated;

-- END OF DOCUMENT TYPES -------------------------------------------------------
