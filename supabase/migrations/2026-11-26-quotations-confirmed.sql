-- ===========================================================================
-- QUOTATIONS CONFIRMED BEFORE THEY GO (2026-11-26)
-- ===========================================================================
-- WHY: the user, 2026-11-26 (F8): "after create quotation is built, it
-- doesnt allow any send clients action or what. only preview and edit and
-- confirm (before confirm it uses XXXX-DRAFT. only after confirm then
-- proceed real serial step … until it is confirmed, everything holds at
-- the pre-stage"; the same for a prospect's request. Then: a website
-- request's number is ADP/REQ{YYMM}-{AAA}, random, never a running count;
-- a revision after Sent is numbered under its family's first quotation
-- (ADP/QT2611-C02-R1, -R2), never a new serial.
--
-- WHAT IT CHANGES
--   * `quotations.confirmed_at`, `confirmed_by`, `revises`, `request_ref`;
--     every quotation made before this band counts as confirmed (stamped
--     once, as the column is made, from its issue).
--   * `quotation_make`: a team's quotation is a draft
--     (ADP/QT{YYMM}-DRAFT-{4 letters}, `quote_draft_ref`, no number
--     spent); a website request takes ADP/REQ{YYMM}-{AAA}
--     (`quote_request_ref`: consonants from a strong source, a short deny
--     list, drawn again on a clash), kept as `request_ref`.
--   * `quotation_confirm(id)`: Confirm quotation takes `quote_ref`, or the
--     family's next -Rn (`quote_revision_ref`, counted on the root, the
--     kept references included) where the draft revises a quotation, and
--     then revises it (`replaces`), so the prospect never meets a draft.
--   * `quotation_release` (Send quotation) is a request's confirmation: it
--     takes its ADP/QT reference then.
--   * `quotation_replace`: a draft names what it will revise (`revises`);
--     an unconfirmed quotation is never revised over.
--   * `quotation_edit`: a draft moved to another month takes that month's
--     draft reference, spending no number.
--   * Held until confirmed, refused `not-confirmed`: `quotation_link`
--     (Copy link), `quotation_resend`, `quotation_paper` (Mark signed),
--     `quotation_offer` (Issue Letter of Offer), `client_email_prepare`
--     (Send by email) and `wa_compose_prepare` (Send on WhatsApp);
--     `quotation_issued(q)` is `confirmed_at is not null`, so /verify/
--     finds none.
--   * `id_formats` takes `request` (REQ, 3 letters) and `revision` (R, 1
--     digit), listed and set as the others; `serial_taken` refuses a
--     quotation's reference and a kept one to a document.
--
-- ORDER: this file, then the page (an open tab's Create meets a draft it
-- cannot confirm until it is refreshed; its Copy link and sends on a draft
-- are refused in words). Safe to run twice: the backfill runs once.
-- Holds no drop of a table or function and no delete.
-- ROLLBACK: restate each function's last definition before this band;
-- confirm any draft left first (`update quotations set confirmed_at =
-- issued_at where confirmed_at is null` after giving each a reference).
-- ===========================================================================

-- QUOTATIONS CONFIRMED BEFORE THEY GO -------------------------------------------

/* A quotation is a draft until a colleague confirms it: it takes its
   reference then, and only then reaches anybody. Every quotation made
   before this band counts as confirmed (once, as the column is made). */
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'quotations' and column_name = 'confirmed_at') then
    alter table public.quotations add column confirmed_at timestamptz;
    update public.quotations set confirmed_at = issued_at;
  end if;
end $$;
alter table public.quotations add column if not exists confirmed_by text;
alter table public.quotations add column if not exists revises uuid references public.quotations(id) on delete set null;
alter table public.quotations add column if not exists request_ref text;
grant select (confirmed_at, confirmed_by, revises, request_ref) on table public.quotations to authenticated;

/* A website request's number and a revision's suffix are Settings'
   numbering, beside the others (`id_formats`). */
alter table public.id_formats drop constraint if exists id_formats_kind_check;
alter table public.id_formats add constraint id_formats_kind_check check (kind in ('creator', 'campaign', 'job', 'trip', 'request', 'revision'));
alter table public.id_formats drop constraint if exists id_formats_check;
alter table public.id_formats add constraint id_formats_check check ((kind = 'job' and pattern is not null)
  or (kind <> 'job' and prefix ~ '^[A-Z]{1,6}$' and width between (case when kind = 'revision' then 1 else 2 end) and 6 and next_no >= 1));
insert into public.id_formats (kind, prefix, width, next_no) values ('request', 'REQ', 3, 1), ('revision', 'R', 1, 1) on conflict (kind) do nothing;

/* A draft's reference: its month and DRAFT, then four letters that keep
   two drafts apart; never a number, so a draft removed spends none. */
create or replace function public.quote_draft_ref(p_at timestamptz)
returns text language plpgsql volatile set search_path = public, extensions as $$
declare
  alphabet constant text := 'BCDFGHJKLMNPQRSTVWXZ';
  v_out text; v_bytes bytea; v_i int; v_b int;
begin
  loop
    v_out := '';
    v_bytes := gen_random_bytes(16);
    for v_i in 0..15 loop
      v_b := get_byte(v_bytes, v_i);
      if v_b < 240 and length(v_out) < 4 then v_out := v_out || substr(alphabet, 1 + (v_b % 20), 1); end if;
    end loop;
    continue when length(v_out) < 4;
    v_out := 'ADP/QT' || to_char(p_at at time zone 'Asia/Kuala_Lumpur', 'YYMM') || '-DRAFT-' || v_out;
    exit when not exists (select 1 from public.quotations q where q.ref = v_out);
  end loop;
  return v_out;
end $$;
revoke all on function public.quote_draft_ref(timestamptz) from public, anon, authenticated;

/* A website request's number: ADP/{prefix}{YYMM}-{letters}, the letters
   drawn at random from consonants alone, so it never spells a word nor
   tells how many requests came in; a clash within the month draws again. */
create or replace function public.quote_request_ref(p_at timestamptz)
returns text language plpgsql volatile set search_path = public, extensions as $$
declare
  alphabet constant text := 'BCDFGHJKLMNPQRSTVWXZ';
  deny constant text[] := array['FCK', 'FKN', 'SHT', 'KKK', 'XXX', 'WTF', 'STD', 'NGR', 'PKM', 'BBW', 'DCK', 'CNT', 'PSS', 'TTS'];
  f public.id_formats;
  v_n int; v_out text; v_ref text; v_bytes bytea; v_i int; v_b int; v_try int := 0;
begin
  select * into f from public.id_formats where kind = 'request';
  v_n := greatest(3, least(6, coalesce(f.width, 3)));
  loop
    v_try := v_try + 1;
    if v_try > 200 then raise exception 'quote_request_ref: no free number'; end if;
    v_out := '';
    v_bytes := gen_random_bytes(32);
    for v_i in 0..31 loop
      v_b := get_byte(v_bytes, v_i);
      if v_b < 240 and length(v_out) < v_n then v_out := v_out || substr(alphabet, 1 + (v_b % 20), 1); end if;
    end loop;
    continue when length(v_out) < v_n or v_out = any (deny);
    v_ref := 'ADP/' || coalesce(nullif(f.prefix, ''), 'REQ') || to_char(p_at at time zone 'Asia/Kuala_Lumpur', 'YYMM') || '-' || v_out;
    exit when not exists (select 1 from public.quotations q where q.ref = v_ref or q.request_ref = v_ref)
          and not exists (select 1 from public.quotation_refs_kept k where k.ref = v_ref);
  end loop;
  return v_ref;
end $$;
revoke all on function public.quote_request_ref(timestamptz) from public, anon, authenticated;

/* A revision after Sent is numbered under its family's first quotation:
   ADP/QT2611-C02, then -R1, -R2, counted on the root and never given
   twice (removed and deleted ones kept in `quotation_refs_kept`). */
create or replace function public.quote_revision_ref(p_of uuid)
returns text language plpgsql volatile set search_path = public as $$
declare
  f public.id_formats;
  v_root text;
  v_pre text;
  v_top int;
begin
  -- The root is the first confirmed quotation up the chain: a website
  -- request revised before it was sent holds no ADP/QT number to count on.
  with recursive up as (
    select q.id, q.replaces, q.ref, 0 as d from public.quotations q where q.id = p_of and q.confirmed_at is not null
    union all
    select p.id, p.replaces, p.ref, up.d + 1 from public.quotations p join up on p.id = up.replaces
     where up.d < 100 and p.confirmed_at is not null)
  select u.ref into v_root from up u order by u.d desc limit 1;
  if v_root is null then return null; end if;
  -- An old revision's own serial stands as it was issued; its root is the
  -- family's first, so a new revision counts on that.
  select * into f from public.id_formats where kind = 'revision';
  v_pre := '-' || coalesce(nullif(f.prefix, ''), 'R');
  perform pg_advisory_xact_lock(hashtext('quote_revision_ref:' || v_root));
  select coalesce(max(substr(x.ref, length(v_root) + length(v_pre) + 1)::int), 0) into v_top
    from (select q.ref from public.quotations q
          union all
          select k.ref from public.quotation_refs_kept k) x
   where x.ref like v_root || v_pre || '%' and substr(x.ref, length(v_root) + length(v_pre) + 1) ~ '^[0-9]{1,6}$';
  return v_root || v_pre || lpad((v_top + 1)::text, greatest(1, least(3, coalesce(f.width, 1))), '0');
end $$;
revoke all on function public.quote_revision_ref(uuid) from public, anon, authenticated;

/* Confirm quotation: a team's draft takes its reference and its normal
   steps begin. A draft revising a quotation already sent takes the next
   -Rn under its family and then revises it; the earlier reads Revised. */
create or replace function public.quotation_confirm(p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  n public.quotations;
  o public.quotations;
  v_by text;
  v_ref text;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into n from public.quotations x where x.id = p_id for update;
  if n.id is null or n.removed_at is not null or not public.client_scope_ok('client', n.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if n.confirmed_at is not null then return jsonb_build_object('ok', true, 'same', true, 'ref', n.ref); end if;
  if n.source <> 'console' then return jsonb_build_object('error', 'website'); end if;
  if n.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if n.revises is not null then
    select * into o from public.quotations x where x.id = n.revises for update;
  end if;
  if o.id is not null and o.removed_at is null then
    if o.signed_at is not null or o.reviewed_at is not null then return jsonb_build_object('error', 'signed'); end if;
    select x.ref into v_by from public.quotations x where x.replaces = o.id and x.removed_at is null and x.id <> n.id limit 1;
    if v_by is not null then return jsonb_build_object('error', 'revised', 'ref', v_by); end if;
    -- A website request revised before it was sent holds no ADP/QT number:
    -- its revision takes a fresh one; else the family's next -Rn.
    v_ref := case when o.confirmed_at is null then public.quote_ref(n.brand, n.issued_at) else public.quote_revision_ref(o.id) end;
    update public.quotations set ref = v_ref, confirmed_at = now(), confirmed_by = me.name, replaces = o.id, revises = null
     where id = n.id returning * into n;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'client.quotation', n.brand, n.ref || ' confirmed · revises ' || o.ref);
  else
    -- What it was to revise is gone: it stands as a quotation of its own.
    v_ref := public.quote_ref(n.brand, n.issued_at);
    update public.quotations set ref = v_ref, confirmed_at = now(), confirmed_by = me.name, revises = null
     where id = n.id returning * into n;
    insert into public.activity_log (actor, action, subject, detail)
    values (me.name, 'client.quotation', n.brand, n.ref || ' confirmed');
  end if;
  return jsonb_build_object('ok', true, 'ref', n.ref);
end $$;
revoke all on function public.quotation_confirm(uuid) from public, anon;
grant execute on function public.quotation_confirm(uuid) to authenticated;

/* No document takes a quotation's reference, nor one kept for a deleted
   quotation, nor a revision's -Rn. */
create or replace function public.serial_taken(p_serial text)
returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.documents where upper(serial) = upper(btrim(p_serial)))
      or exists (select 1 from public.client_documents where upper(number) = upper(btrim(p_serial)))
      or exists (select 1 from public.quotations where upper(ref) = upper(btrim(p_serial)))
      or exists (select 1 from public.quotation_refs_kept where upper(ref) = upper(btrim(p_serial)))
$$;
revoke all on function public.serial_taken(text) from public, anon, authenticated;

create or replace function public.quotation_make(p_client uuid, p_sel jsonb, p_idem text, p_source text,
                                                 p_by text, p_contact jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_c public.clients;
  v_on date := case when p_source = 'console' and jsonb_typeof(p_sel) = 'object' then public.doc_day_of(p_sel->>'date') end;
  v_card jsonb;
  v_p jsonb;
  v_q public.quotations;
  v_now timestamptz := now();
  v_days int;
  v_fx numeric;
  v_x jsonb;
  v_b jsonb;
  v_sel jsonb := case when jsonb_typeof(p_sel) is distinct from 'object' then p_sel
                      when p_source = 'console' then p_sel - 'client' - 'date'
                      else p_sel - 'edits' - 'client' - 'date' end;
begin
  if p_idem is not null then
    select * into v_q from public.quotations q where q.idem = p_idem and q.client_id = p_client;
    if v_q.id is not null then return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'again', true); end if;
  end if;
  /* The quotation's own date (2026-11-12, the user: a document may be
     backdated): its reference's month, its validity, and the SST and terms
     in force; a team's alone, today where none is chosen. */
  if v_on is not null and not public.doc_day_ok(v_on) then return jsonb_build_object('error', 'bad-date'); end if;
  if v_on is not null and v_on <> (v_now at time zone 'Asia/Kuala_Lumpur')::date then
    v_now := (v_on::timestamp + (v_now at time zone 'Asia/Kuala_Lumpur')::time) at time zone 'Asia/Kuala_Lumpur';
  end if;
  v_on := (v_now at time zone 'Asia/Kuala_Lumpur')::date;
  -- the Rate Card chosen in Build quote, else the one live on the date (2026-11-15)
  v_card := public.quote_card(v_on, case when p_source = 'console' then nullif(btrim(coalesce(p_sel->>'card', '')), '') end);
  select * into v_c from public.clients where id = p_client;
  if v_c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_fx := public.quote_fx(v_c.id, v_on);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  v_p := public.quote_fx_out(public.quote_compose(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_c.id, v_on), v_fx),
           v_sel, p_source = 'console'), v_fx);
  if v_p ? 'error' then return v_p; end if;
  /* The advertising budget and the payment terms (2026-11-12): a team's
     own; a website quotation takes none and NET 7. */
  v_x := public.quote_extras(case when p_source = 'console' then v_sel else '{}'::jsonb end);
  if v_x ? 'error' then return v_x; end if;
  if p_source = 'console' then
    v_b := public.quote_client_extras(v_c.id, v_p->'lines', v_sel);
    if v_b ? 'error' then return v_b; end if;
    v_x := v_x || v_b;
  end if;
  /* A quotation holds at least one priced line (2026-10-29): a selection of
     items quoted on request alone (a KOL campaign, a custom creator list)
     made a quotation with no line and no figure. */
  if jsonb_typeof(v_p->'lines') is distinct from 'array' or jsonb_array_length(v_p->'lines') = 0 then
    return jsonb_build_object('error', 'nothing-priced');
  end if;
  v_days := coalesce((v_x->>'valid_days')::int, public.app_setting('quote_valid_days', (v_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::int;
  begin
  insert into public.quotations (ref, client_id, brand, version, version_id, selection, lines, totals, source,
                                 issued_at, valid_until, made_by, contact, idem, access_key, request_ref)
  values (case when p_source = 'website' then public.quote_request_ref(v_now) else public.quote_draft_ref(v_now) end, v_c.id, v_c.name, v_card->>'version', (v_card->>'id')::uuid, v_sel,
          v_p->'lines', v_p->'totals' || jsonb_build_object('on_request', v_p->'on_request') || v_x, p_source,
          v_now, (v_now at time zone 'Asia/Kuala_Lumpur')::date + v_days, p_by, p_contact, p_idem,
          case when p_source = 'website' then public.new_link_key() end, null)
  returning * into v_q;
  -- A website request keeps the number its sender was given, after its
  -- reference is issued at Send quotation (QUOTATIONS CONFIRMED, 2026-11-26).
  if p_source = 'website' then update public.quotations set request_ref = ref where id = v_q.id returning * into v_q; end if;
  -- Two presses at once with one key: the second answers the first's.
  exception when unique_violation then
    select * into v_q from public.quotations q where q.idem = p_idem and q.client_id = p_client;
    if p_idem is null or v_q.id is null then raise; end if;
    return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'again', true);
  end;
  insert into public.activity_log (actor, action, subject, detail)
  values (coalesce(p_by, 'Website'), 'client.quotation', v_c.name,
          v_q.ref || case when p_source = 'website' then ' requested · ' else ' drafted · ' end || coalesce('Monthly incl. SST ' || case when v_fx is null then 'RM ' else 'S$ ' end ||
            to_char((v_q.totals->'month'->>'incl')::numeric, 'FM999,999,990.00'), 'one-time') ||
          ' · Rate Card v.' || v_q.version ||
          case coalesce((v_p->>'adjusted')::int, 0) when 0 then '' when 1 then ' · 1 line changed'
               else ' · ' || (v_p->>'adjusted') || ' lines changed' end);
  return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref, 'key', v_q.access_key);
end $$;
revoke all on function public.quotation_make(uuid, jsonb, text, text, text, jsonb) from public, anon, authenticated;

create or replace function public.quotation_edit(p_id uuid, p_sel jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_c public.clients;
  v_on date := public.doc_day_of(p_sel->>'date');
  v_card jsonb;
  v_ref text;
  v_was_ref text;
  v_p jsonb;
  v_fx numeric;
  v_now timestamptz := now();
  v_days int;
  v_sel jsonb;
  v_was numeric;
  v_is numeric;
  v_cur text;
  v_n int;
  v_doc text;
  v_x jsonb;
  v_b jsonb;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if jsonb_typeof(p_sel) is distinct from 'object' then return jsonb_build_object('error', 'bad-request'); end if;
  if v_on is not null and not public.doc_day_ok(v_on) then return jsonb_build_object('error', 'bad-date'); end if;
  if v_on is not null and v_on <> (v_now at time zone 'Asia/Kuala_Lumpur')::date then
    v_now := (v_on::timestamp + (v_now at time zone 'Asia/Kuala_Lumpur')::time) at time zone 'Asia/Kuala_Lumpur';
  end if;
  v_on := (v_now at time zone 'Asia/Kuala_Lumpur')::date;
  v_card := public.quote_card(v_on, nullif(btrim(coalesce(p_sel->>'card', '')), ''));
  select * into v_q from public.quotations where id = p_id for update;
  if v_q.id is null or not public.client_scope_ok('client', v_q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if v_q.removed_at is not null then return jsonb_build_object('error', 'removed'); end if;
  if v_q.signed_at is not null or v_q.reviewed_at is not null then return jsonb_build_object('error', 'signed'); end if;
  if v_q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = v_q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  if v_q.sent_out_at is not null or v_q.released_at is not null then return jsonb_build_object('error', 'sent'); end if;
  -- A quotation a letter or service lines came from keeps its figures
  -- (2026-11-07), as its removal is refused then: Edit makes its revision.
  select count(*) into v_n from public.client_services s where s.quotation_id = v_q.id;
  if v_n > 0 then return jsonb_build_object('error', 'lines', 'count', v_n); end if;
  select d.number into v_doc from public.client_documents d
   where d.lines @> jsonb_build_array(jsonb_build_object('quotation_id', v_q.id::text))
   order by d.created_at limit 1;
  if v_doc is not null then return jsonb_build_object('error', 'letter', 'number', v_doc); end if;
  select * into v_c from public.clients where id = v_q.client_id;
  if v_c.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if v_card is null then return jsonb_build_object('error', 'no-card'); end if;
  v_fx := public.quote_fx(v_c.id, v_on);
  if v_fx = 0 then return jsonb_build_object('error', 'no-fx'); end if;
  -- As the team builds it: their edits kept (quotation_make's console path);
  -- a website quotation is never adjusted, as quotation_make holds (audit
  -- 2026-11-15).
  v_sel := case when v_q.source = 'console' then p_sel - 'client' - 'date' else p_sel - 'client' - 'date' - 'edits' end;
  v_p := public.quote_fx_out(public.quote_compose(public.quote_fx_snap(public.quote_tax_snap(v_card->'snapshot', v_c.id, v_on), v_fx),
           v_sel, v_q.source = 'console'), v_fx);
  if v_p ? 'error' then return v_p; end if;
  v_x := public.quote_extras(case when v_q.source = 'console' then v_sel else '{}'::jsonb end);
  if v_x ? 'error' then return v_x; end if;
  if v_q.source = 'console' then
    v_b := public.quote_client_extras(v_c.id, v_p->'lines', v_sel);
    if v_b ? 'error' then return v_b; end if;
    v_x := v_x || v_b;
  end if;
  if jsonb_typeof(v_p->'lines') is distinct from 'array' or jsonb_array_length(v_p->'lines') = 0 then
    return jsonb_build_object('error', 'nothing-priced');
  end if;
  v_was := coalesce((v_q.totals->'month'->>'incl')::numeric, (v_q.totals->'once'->>'incl')::numeric);
  v_days := coalesce((v_x->>'valid_days')::int, public.app_setting('quote_valid_days', (v_now at time zone 'Asia/Kuala_Lumpur')::date), 30)::int;
  /* A team's quotation dated into another month takes that month's
     reference (it has not been sent); the one it held is kept, never
     issued again. */
  v_ref := v_q.ref; v_was_ref := v_q.ref;
  if v_q.source = 'console' and v_q.ref !~ ('^ADP/QT' || to_char(v_on, 'YYMM') || '-') then
    -- A draft moved to another month takes that month's draft reference and
    -- spends no number (QUOTATIONS CONFIRMED, 2026-11-26).
    if v_q.confirmed_at is null then
      v_ref := public.quote_draft_ref(v_now);
    else
      v_ref := public.quote_ref(v_q.brand, v_now);
      insert into public.quotation_refs_kept (ref) values (v_q.ref) on conflict do nothing;
    end if;
  end if;
  update public.quotations
     set ref = v_ref, version = v_card->>'version', version_id = (v_card->>'id')::uuid, selection = v_sel,
         lines = v_p->'lines', totals = v_p->'totals' || jsonb_build_object('on_request', v_p->'on_request') || v_x,
         -- A team's quotation is dated when it is made ready; a website one
         -- keeps the day it was asked for (its validity runs from its send).
         issued_at = case when v_q.source = 'console' then v_now else issued_at end,
         valid_until = case when v_q.source = 'console' then (v_now at time zone 'Asia/Kuala_Lumpur')::date + v_days else valid_until end
   where id = v_q.id
  returning * into v_q;
  v_is := coalesce((v_q.totals->'month'->>'incl')::numeric, (v_q.totals->'once'->>'incl')::numeric);
  v_cur := case when v_fx is null then 'RM ' else 'S$ ' end;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', v_c.name,
          case when v_ref <> v_was_ref then v_was_ref || ' → ' else '' end || v_q.ref || ' edited · ' ||
          coalesce(v_cur || to_char(v_was, 'FM999,999,990.00'), 'not set') || ' → ' ||
          coalesce(v_cur || to_char(v_is, 'FM999,999,990.00'), 'not set') ||
          ' · Rate Card v.' || v_q.version ||
          case coalesce((v_p->>'adjusted')::int, 0) when 0 then '' when 1 then ' · 1 line changed'
               else ' · ' || (v_p->>'adjusted') || ' lines changed' end);
  return jsonb_build_object('ok', true, 'id', v_q.id, 'ref', v_q.ref);
end $$;
revoke all on function public.quotation_edit(uuid, jsonb) from public, anon;
grant execute on function public.quotation_edit(uuid, jsonb) to authenticated;

create or replace function public.quotation_release(p_id uuid, p_whatsapp boolean)
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
  v_on boolean;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if p_whatsapp and not public.send_ok('whatsapp') then return jsonb_build_object('error', 'send-off'); end if;
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
  -- A prospect marked Do not contact is not messaged (audit 2026-10-30);
  -- publishing sends them nothing.
  if coalesce(p_whatsapp, true) and q.no_contact_at is not null then return jsonb_build_object('error', 'no-contact'); end if;
  -- The day's WhatsApp messages for website quotations are held to
  -- `quote_wa_day` (counted under one lock); at the limit nothing changes and
  -- Publish still shows the rates.
  if coalesce(p_whatsapp, true) and not public.quote_wa_allowed(q.id) then
    return jsonb_build_object('error', 'wa-limit', 'cap', coalesce(public.app_setting('quote_wa_day', v_today), 30));
  end if;
  -- Valid from the day it is shown, as the prospect first sees it.
  v_days := coalesce(public.app_setting('quote_valid_days', v_today), 30)::int;
  -- Send quotation is a request's confirmation: it takes its reference
  -- now (QUOTATIONS CONFIRMED, 2026-11-26); one confirmed before keeps its.
  update public.quotations
     set released_at = now(), released_by = me.name, valid_until = v_today + v_days,
         ref = case when confirmed_at is null then public.quote_ref(brand, now()) else ref end,
         confirmed_at = coalesce(confirmed_at, now()), confirmed_by = coalesce(confirmed_by, me.name)
   where id = q.id returning * into q;
  if coalesce(p_whatsapp, true) then
    v_wa := public.quote_website_number(q.contact->>'whatsapp');
    v_name := coalesce(nullif(btrim(q.contact->>'name'), ''), q.brand);
    -- Sent on WhatsApp only where its template is on: wa_enqueue says nothing
    -- when it is off (audit 2026-10-30).
    select exists (select 1 from public.wa_templates x where x.purpose = 'quote_ready' and x.active and x.name <> '') into v_on;
    begin
      if v_on and v_wa ~ '^(60|65)[0-9]{8,10}$' then
        perform public.wa_enqueue('quote_ready', v_wa, v_name,
          jsonb_build_array(public.contact_greeting(q.contact->>'salutation', v_name),
                            coalesce(q.contact->>'brand', q.brand), q.ref),
          'quotation', q.id, q.client_id, q.access_key);
        v_queued := true;
      end if;
    exception when others then v_queued := false;
    end;
  end if;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || case when coalesce(p_whatsapp, true)
                        then ' sent to the prospect' || case when v_queued then ' on WhatsApp' else '' end
                        else ' published on the quotation link' end ||
          ' · valid until ' || public.register_day(q.valid_until));
  return jsonb_build_object('ok', true, 'valid_until', q.valid_until, 'whatsapp', v_queued);
end $$;
revoke all on function public.quotation_release(uuid, boolean) from public, anon, authenticated;

create or replace function public.quotation_link(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  v_ip text := nullif(public.request_ip(), '');
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- A draft goes nowhere until it is confirmed (QUOTATIONS CONFIRMED, 2026-11-26).
  if q.confirmed_at is null then return jsonb_build_object('error', 'not-confirmed'); end if;
  if q.access_key is null then
    update public.quotations set access_key = public.new_link_key() where id = q.id returning * into q;
  end if;
  -- Where the link was copied from, so the colleague's own opening is never
  -- taken for the client's (QUOTATION COPIER'S OPENING, 2026-11-25). Kept
  -- 30 days (privacy_retention), never read by a page.
  if v_ip is not null then
    insert into public.quotation_link_copies (quotation_id, ip, at) values (q.id, v_ip, now())
    on conflict (quotation_id, ip) do update set at = excluded.at;
  end if;
  return jsonb_build_object('ok', true, 'key', q.access_key);
end $$;
revoke all on function public.quotation_link(uuid) from public, anon;
grant execute on function public.quotation_link(uuid) to authenticated;

create or replace function public.quotation_resend(p_id uuid, p_again boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  t  public.wa_templates;
  o  public.wa_outbox;
  k  public.client_contacts;
  v_today date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_hours numeric;
  v_wa text;
  v_name text;
  v_greet text;
  v_team boolean;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  if not public.send_ok('whatsapp') then return jsonb_build_object('error', 'send-off'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- A draft goes nowhere until it is confirmed (QUOTATIONS CONFIRMED, 2026-11-26).
  if q.confirmed_at is null then return jsonb_build_object('error', 'not-confirmed'); end if;
  v_team := q.source <> 'website';
  if not v_team and q.access_key is null then return jsonb_build_object('error', 'bad-quotation'); end if;
  if not v_team and q.released_at is null then return jsonb_build_object('error', 'not-sent'); end if;
  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if exists (select 1 from public.quotations x where x.replaces = q.id and x.removed_at is null) then
    return jsonb_build_object('error', 'revised');
  end if;
  if q.valid_until is not null and q.valid_until < v_today then return jsonb_build_object('error', 'expired'); end if;
  if q.no_contact_at is not null then return jsonb_build_object('error', 'no-contact'); end if;
  if v_team and q.signed_at is not null then return jsonb_build_object('error', 'signed'); end if;
  select * into t from public.wa_templates x where x.purpose = 'quote_ready' and x.active and x.name <> '';
  if t.purpose is null then return jsonb_build_object('error', 'wa-off'); end if;
  if v_team then
    select * into k from public.client_contacts x
     where x.client_id = q.client_id and x.archived_at is null and x.is_primary
     order by x.created_at limit 1;
    v_wa := public.wa_number(case when btrim(coalesce(k.whatsapp, '')) <> '' and btrim(k.whatsapp) !~ '^@' then k.whatsapp else k.phone end);
    v_name := coalesce(nullif(btrim(coalesce(k.name, '')), ''), q.brand);
    v_greet := public.contact_greeting(k.salutation, v_name);
  else
    v_wa := public.quote_website_number(q.contact->>'whatsapp');
    v_name := coalesce(nullif(btrim(q.contact->>'name'), ''), q.brand);
    v_greet := public.contact_greeting(q.contact->>'salutation', v_name);
  end if;
  if v_wa is null or v_wa !~ '^(60|65)[0-9]{8,10}$' then return jsonb_build_object('error', 'no-number'); end if;
  v_hours := coalesce(public.app_setting('wa_repeat_hours', v_today), 24);
  if v_hours > 0 and not coalesce(p_again, false) then
    select * into o from public.wa_outbox x
     where x.purpose = 'quote_ready' and x.ref_id = q.id and x.state <> 'failed'
       and x.created_at > now() - make_interval(secs => v_hours * 3600)
     order by x.created_at desc limit 1;
    if o.id is not null then
      return jsonb_build_object('error', 'recent', 'recent', jsonb_build_object('at', o.created_at,
        'by', case when coalesce(o.created_by, 'system') = 'system' then null else o.created_by end));
    end if;
  end if;
  if not v_team and not public.quote_wa_allowed(q.id) then
    return jsonb_build_object('error', 'wa-limit', 'cap', coalesce(public.app_setting('quote_wa_day', v_today), 30));
  end if;
  -- A team's quotation takes its link the first time it is sent.
  if q.access_key is null then
    update public.quotations set access_key = public.new_link_key() where id = q.id returning * into q;
  end if;
  perform public.wa_enqueue('quote_ready', v_wa, v_name,
    jsonb_build_array(v_greet, coalesce(q.contact->>'brand', q.brand), q.ref),
    'quotation', q.id, q.client_id, q.access_key);
  update public.wa_outbox x set created_by = me.name
   where x.purpose = 'quote_ready' and x.ref_id = q.id and x.created_at = now() and x.created_by = 'system';
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || case when v_team then ' link sent on WhatsApp to ' || v_name else ' sent again to the prospect on WhatsApp' end);
  return jsonb_build_object('ok', true, 'key', q.access_key);
end $$;
revoke all on function public.quotation_resend(uuid, boolean) from public, anon;
grant execute on function public.quotation_resend(uuid, boolean) to authenticated;

create or replace function public.quotation_paper(p_id uuid, p_payload jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
  pl jsonb := coalesce(p_payload, '{}'::jsonb);
  c1 jsonb; c2 jsonb;
  v_name text := btrim(regexp_replace(coalesce(pl->'signer'->>'name', ''), '\s+', ' ', 'g'));
  v_role text := btrim(regexp_replace(coalesce(pl->'signer'->>'designation', ''), '\s+', ' ', 'g'));
  v_day  text := btrim(coalesce(pl->>'day', ''));
  v_scan text := nullif(btrim(coalesce(pl->>'scan', '')), '');
  v_at timestamptz;
  v_d  date;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or q.removed_at is not null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- A draft goes nowhere until it is confirmed (QUOTATIONS CONFIRMED, 2026-11-26).
  if q.confirmed_at is null then return jsonb_build_object('error', 'not-confirmed'); end if;
  if q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  if q.signed_at is not null then return jsonb_build_object('error', 'signed'); end if;
  c1 := public.quote_sign_company(pl->'company'); if c1 ? 'error' then return c1; end if;
  c2 := public.quote_sign_contact(pl->'contact'); if c2 ? 'error' then return c2; end if;
  if length(v_name) < 2 or length(v_name) > 80 then return jsonb_build_object('error', 'bad-signer_name'); end if;
  if length(v_role) < 2 or length(v_role) > 80 then return jsonb_build_object('error', 'bad-signer_designation'); end if;
  -- A day that is no date (30 February) is bad-day, never the database's
  -- own refusal (audit 2026-11-04).
  if v_day !~ '^\d{4}-\d{2}-\d{2}$' then return jsonb_build_object('error', 'bad-day'); end if;
  begin
    v_d := v_day::date;
  exception when others then
    return jsonb_build_object('error', 'bad-day');
  end;
  if v_d > (now() at time zone 'Asia/Kuala_Lumpur')::date or v_d < (q.issued_at at time zone 'Asia/Kuala_Lumpur')::date then
    return jsonb_build_object('error', 'bad-day');
  end if;
  if v_scan is not null and v_scan !~ '^https://[^\s"''<>`\\]+$' then return jsonb_build_object('error', 'bad-scan'); end if;
  -- Noon in Malaysia on the day it was signed.
  v_at := (v_d + time '12:00') at time zone 'Asia/Kuala_Lumpur';
  update public.quotations
     set signed_at = v_at,
         signed = jsonb_build_object('via', 'paper', 'company', c1->'company', 'contact', c2->'contact',
           'signer', jsonb_build_object('name', v_name, 'designation', v_role), 'signature', null, 'scan', v_scan,
           'record', jsonb_build_object('at', v_at, 'by', me.name, 'entered_at', now())),
         returned_at = null, return_note = null, returned_by = null
   where id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || ' signed on paper by ' || v_name || ' for ' || (c1->'company'->>'legal_name') || ' on ' ||
          public.register_day(v_d) || ' · keyed in by ' || me.name);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_paper(uuid, jsonb) from public, anon;
grant execute on function public.quotation_paper(uuid, jsonb) to authenticated;

create or replace function public.quotation_offer(p_id uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  v_q public.quotations;
  v_l jsonb;
  v_ids uuid[] := '{}';
  v_id uuid;
begin
  if me.id is null or not (public.allowed('clients.quotes', 'work') and public.allowed('clients.services', 'work')
                           and public.allowed('clients.documents', 'work')) then return jsonb_build_object('error', 'denied'); end if;
  select * into v_q from public.quotations where id = p_id for update;
  if v_q.id is null or v_q.removed_at is not null or not public.client_scope_ok('client', v_q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  -- A draft goes nowhere until it is confirmed (QUOTATIONS CONFIRMED, 2026-11-26).
  if v_q.confirmed_at is null then return jsonb_build_object('error', 'not-confirmed'); end if;
  if v_q.status = 'not_proceeding' then return jsonb_build_object('error', 'not-proceeding'); end if;
  select coalesce(array_agg(s.id order by s.created_at), '{}') into v_ids
    from public.client_services s where s.quotation_id = v_q.id and s.archived_at is null;
  if array_length(v_ids, 1) is not null then return jsonb_build_object('ok', true, 'ids', to_jsonb(v_ids), 'again', true); end if;
  if v_q.valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then return jsonb_build_object('error', 'expired'); end if;
  for v_l in select * from jsonb_array_elements(v_q.lines) loop
    insert into public.client_services (client_id, service_slug, label, qty, rate, unit, state, note,
                                        tenure, term_adjust, term_pct, detail, quotation_id, tax_code)
    values (v_q.client_id,
            case when exists (select 1 from public.services s where s.slug = v_l->>'slug') then v_l->>'slug' end,
            public.quote_line_label(v_q.totals, v_l), (v_l->>'qty')::numeric, (v_l->>'rate')::numeric,
            case when v_l->>'basis' = 'month' then 'Per month' else 'One-time' end, 'quoted',
            'Quotation ' || v_q.ref,
            case when v_l->>'basis' = 'month' then coalesce((v_l->>'months')::int, (v_q.totals->>'term')::int) else 1 end,
            v_l->>'basis' = 'month', case when v_l->>'basis' = 'month' then (v_q.totals->>'term_pct')::numeric else 0 end,
            nullif(array_to_string(array(select jsonb_array_elements_text(coalesce(v_l->'detail', '[]'::jsonb))), E'\n'), ''),
            v_q.id, nullif(v_l->>'tax_code', ''))
    returning id into v_id;
    v_ids := v_ids || v_id;
  end loop;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', v_q.brand, v_q.ref || ' · ' || array_length(v_ids, 1) || ' lines To quote for the Letter of Offer');
  return jsonb_build_object('ok', true, 'ids', to_jsonb(v_ids));
end $$;
revoke all on function public.quotation_offer(uuid) from public, anon;
grant execute on function public.quotation_offer(uuid) to authenticated;

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
  -- Held while it is revised, so a Send meanwhile waits and then reads it
  -- revised (audit 2026-10-30).
  select * into o from public.quotations where id = p_old for update;
  if n.id is null or o.id is null or n.client_id <> o.client_id or n.id = o.id
     or n.removed_at is not null or o.removed_at is not null
     or not public.client_scope_ok('client', n.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if n.source <> 'console' or n.replaces is not null then return jsonb_build_object('error', 'bad-quotation'); end if;
  -- A team's draft is never revised over: it is edited (QUOTATIONS
  -- CONFIRMED, 2026-11-26); a website request waiting for the team may be.
  if o.confirmed_at is null and o.source = 'console' then return jsonb_build_object('error', 'not-confirmed'); end if;
  -- A quotation the client signed is the contract: it is asked again, never
  -- revised over (audit 2026-11-04).
  if o.signed_at is not null or o.reviewed_at is not null then return jsonb_build_object('error', 'signed'); end if;
  -- A draft names what it will revise; it revises it once confirmed, so the
  -- prospect never meets a draft in its place.
  if n.confirmed_at is null then
    update public.quotations set revises = o.id where id = n.id;
    return jsonb_build_object('ok', true, 'draft', true);
  end if;
  update public.quotations set replaces = o.id where id = n.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', n.brand, n.ref || ' revises ' || o.ref);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_replace(uuid, uuid) from public, anon;
grant execute on function public.quotation_replace(uuid, uuid) to authenticated;

create or replace function public.client_email_prepare(p_kind text, p_ref uuid, p_contact uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  me     public.team_members := public.ops_me();
  c      public.clients;
  q      public.quotations;
  o      public.client_documents;
  d      public.documents;
  k      public.client_contacts;
  t      public.client_email_templates;
  v_cid  uuid;
  v_ref  text;
  v_tit  text;
  v_day  date;
  v_val  date;
  v      jsonb;
  ppl    jsonb;
  hours  numeric;
  r      public.client_emails;
  v_cc   text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if not public.send_ok('email') then return jsonb_build_object('error', 'send-off'); end if;
  if p_kind not in ('quotation', 'offer', 'letter') then return jsonb_build_object('error', 'bad-request'); end if;
  if not public.client_email_may(p_kind, 'work') or not public.allowed('clients.contacts', 'view') then
    return jsonb_build_object('error', 'denied');
  end if;
  if coalesce(public.app_setting('client_email_on', (now() at time zone 'Asia/Kuala_Lumpur')::date), 0) <> 1 then
    return jsonb_build_object('error', 'email-off');
  end if;
  if p_kind = 'quotation' then
    select * into q from public.quotations x where x.id = p_ref;
    if q.id is null or q.removed_at is not null then return jsonb_build_object('error', 'not-found'); end if;
    if q.status = 'not_proceeding' then return jsonb_build_object('error', 'void'); end if;
    if q.source = 'website' and q.released_at is null then return jsonb_build_object('error', 'unreleased'); end if;
    if q.confirmed_at is null then return jsonb_build_object('error', 'not-confirmed'); end if;
    if q.no_contact_at is not null then return jsonb_build_object('error', 'no-contact'); end if;
    v_cid := q.client_id; v_ref := q.ref; v_tit := 'Quotation';
    v_day := (q.issued_at at time zone 'Asia/Kuala_Lumpur')::date; v_val := q.valid_until;
  elsif p_kind = 'offer' then
    select * into o from public.client_documents x where x.id = p_ref;
    if o.id is null or o.kind not in ('offer', 'intent', 'cover') then return jsonb_build_object('error', 'not-found'); end if;
    if o.voided_at is not null or o.superseded_by is not null then return jsonb_build_object('error', 'void'); end if;
    v_cid := o.client_id; v_ref := o.number; v_tit := 'Letter of Offer'; v_day := o.issued_at;
  else
    select * into d from public.documents x where x.id = p_ref and x.family = 'client';
    if d.id is null or d.client_id is null then return jsonb_build_object('error', 'not-found'); end if;
    if d.voided_at is not null then return jsonb_build_object('error', 'void'); end if;
    if d.source <> 'portal' then return jsonb_build_object('error', 'no-file'); end if;
    v_cid := d.client_id; v_ref := d.serial; v_tit := coalesce(nullif(d.kind, ''), 'Letter'); v_day := d.issued_at;
  end if;
  select * into c from public.clients x where x.id = v_cid;
  if c.id is null or not public.client_seen(c.id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
  select * into t from public.client_email_templates x where x.kind = p_kind;
  if t.kind is null then return jsonb_build_object('error', 'needs-update'); end if;

  /* The client's contacts holding an email, the billing contact first, then
     the primary, then by name. */
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'name', public.contact_named(x.salutation, x.name),
           'email', btrim(x.email), 'role', x.role, 'billing', coalesce(x.id = c.bill_contact_id, false), 'primary', x.is_primary)
           order by (x.id = c.bill_contact_id) desc nulls last, x.is_primary desc, x.name), '[]'::jsonb)
    into ppl
    from public.client_contacts x
   where x.client_id = c.id and x.archived_at is null and coalesce(btrim(x.email), '') ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$';
  if jsonb_array_length(ppl) = 0 then return jsonb_build_object('error', 'no-email'); end if;
  if p_contact is not null then
    select * into k from public.client_contacts x
     where x.id = p_contact and x.client_id = c.id and x.archived_at is null
       and coalesce(btrim(x.email), '') ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$';
    if k.id is null then return jsonb_build_object('error', 'bad-contact'); end if;
  else
    select * into k from public.client_contacts x where x.id = (ppl->0->>'id')::uuid;
  end if;
  -- The finance email and registered name are Billing's (audit 2026-11-04).
  v_cc := case when public.allowed('clients.billing', 'view') then nullif(btrim(coalesce(c.finance_email, '')), '') end;
  if v_cc is not null and (lower(v_cc) = lower(btrim(k.email)) or v_cc !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then v_cc := null; end if;

  v := jsonb_build_object(
    'contact name', public.contact_named(k.salutation, k.name),
    'client name', c.name,
    'company name', coalesce(case when public.allowed('clients.billing', 'view') then nullif(c.legal_name, '') end, c.name),
    'document title', v_tit, 'document reference', v_ref,
    'document date', case when v_day is null then '' else to_char(v_day, 'FMDD FMMonth YYYY') end,
    'valid until', case when v_val is null then '' else to_char(v_val, 'FMDD FMMonth YYYY') end,
    'sender name', coalesce(me.name, ''));
  hours := coalesce(public.app_setting('wa_repeat_hours', (now() at time zone 'Asia/Kuala_Lumpur')::date), 24);
  if hours > 0 then
    select * into r from public.client_emails x
     where x.kind = p_kind and x.ref_id = p_ref and x.status <> 'failed'
       and x.created_at > now() - make_interval(secs => hours * 3600)
     order by x.created_at desc limit 1;
  end if;
  return jsonb_build_object('ok', true,
    'client_id', c.id, 'client', c.name,
    'contacts', ppl,
    'to', jsonb_build_object('id', k.id, 'name', public.contact_named(k.salutation, k.name), 'email', btrim(k.email)),
    'cc', v_cc,
    'reply_to', nullif(btrim(coalesce(me.email, '')), ''),
    'values', v,
    'subject', public.supplier_email_fill(t.subject, v),
    'body', public.supplier_email_fill(t.body, v),
    'document', jsonb_build_object('id', p_ref, 'kind', p_kind, 'serial', v_ref, 'title', v_tit),
    'recent', case when r.id is null then null else jsonb_build_object('at', r.created_at, 'to', r.to_email,
      'by', (select m.name from public.team_members m where m.id = r.sent_by)) end);
end $$;
revoke all on function public.client_email_prepare(text, uuid, uuid) from public, anon;
grant execute on function public.client_email_prepare(text, uuid, uuid) to authenticated;

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
  t    public.team_members;
  v_n  text;
begin
  if me.id is null then return jsonb_build_object('error', 'denied'); end if;
  if p_purpose not in ('message', 'report', 'feedback', 'creator', 'approval', 'quotation', 'offer', 'representative')
     or p_to_kind not in ('contact', 'creator')
     or (p_purpose in ('report', 'feedback', 'approval', 'quotation', 'offer', 'representative') and p_to_kind <> 'contact')
     or (p_purpose = 'creator' and p_to_kind <> 'creator') then
    return jsonb_build_object('error', 'bad-request');
  end if;
  if not public.wa_may_send(p_purpose, p_to_kind) then return jsonb_build_object('error', 'denied'); end if;
  if p_to_kind = 'contact' then
    select * into k from public.client_contacts x where x.id = p_to and x.archived_at is null;
    if k.id is null then return jsonb_build_object('error', 'not-found'); end if;
    select * into c from public.clients x where x.id = k.client_id;
    if c.id is null or not public.client_seen(c.id, 'view') then return jsonb_build_object('error', 'not-found'); end if;
    /* A feedback request asks a client about work done for them: a lead,
       contacted or proposed, has none (MENU-1, 2026-10-22). */
    if p_purpose = 'feedback' and coalesce(c.stage, 'lead') in ('lead', 'contacted', 'proposal') then
      return jsonb_build_object('error', 'not-client');
    end if;
    /* A representative is named to a lead alone, and is its Sales by
       colleague: active, their namecard on, its short link the button's. */
    if p_purpose = 'representative' then
      if coalesce(c.stage, 'lead') not in ('lead', 'contacted', 'proposal') then
        return jsonb_build_object('error', 'not-lead');
      end if;
      select * into t from public.team_members x where x.id = c.sales_by and x.active and x.removed_at is null;
      if t.id is null then return jsonb_build_object('error', 'no-sales-by'); end if;
      /* A prospect who asked not to be contacted is not introduced either. */
      if exists (select 1 from public.quotations q where q.client_id = c.id and q.source = 'website'
                    and q.no_contact_at is not null) then
        return jsonb_build_object('error', 'no-contact');
      end if;
      if not coalesce(t.card_on, false) or nullif(btrim(coalesce(t.card_slug, '')), '') is null then
        return jsonb_build_object('error', 'no-card', 'rep', t.name);
      end if;
    end if;
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
      if q.confirmed_at is null then return jsonb_build_object('error', 'not-confirmed'); end if;
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
    return jsonb_strip_nulls(jsonb_build_object('ok', true, 'number', v_n, 'name', k.name, 'greeting', public.contact_greeting(k.salutation, k.name),
      'client_id', c.id, 'client', case when r.id is not null then coalesce(nullif(r.brand_name, ''), c.name) else c.name end,
      'subject', c.name, 'ref_kind', case when b.id is not null then 'set' when o.id is not null then 'option'
                       when q.id is not null then 'quotation' when d.id is not null then 'offer' end,
      -- an approval reminder's link button: the page that waits, past the
      -- site's root (the client's review page, the campaign's selection page)
      'link', case when b.id is not null then 'review/?k=' || c.access_token
                   when o.id is not null then 'creators/?k=' || cp.access_token end,
      -- the representative: their name, and their namecard's short link for
      -- the link button
      'rep', t.name, 'code', t.card_slug));
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
  return jsonb_build_object('ok', true, 'number', v_n, 'name', cr.name, 'greeting', public.contact_greeting(null, cr.name),
    'client_id', cp.client_id,
    'campaign', case when cp.id is not null then coalesce(nullif(btrim(cp.title), ''), 'Your campaign') end,
    'code', cr.access_code, 'subject', coalesce(nullif(btrim(cp.title), ''), cr.name));
end $$;
revoke all on function public.wa_compose_prepare(text, uuid, text, uuid) from public, anon;
grant execute on function public.wa_compose_prepare(text, uuid, text, uuid) to authenticated;

create or replace function public.quotation_issued(q public.quotations)
returns boolean language sql stable set search_path = public as $$
  select q.confirmed_at is not null
$$;
revoke all on function public.quotation_issued(public.quotations) from public, anon;
grant execute on function public.quotation_issued(public.quotations) to authenticated;

create or replace function public.id_formats_list()
returns jsonb language sql stable security definer set search_path = public as $$
  select case when public.is_team() then coalesce(jsonb_agg(jsonb_build_object(
           'kind', f.kind, 'prefix', f.prefix, 'width', f.width,
           'next', case when f.kind = 'trip'
                        then coalesce((select m.last from public.outstation_ref_months m
                                        where m.month = to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYYYMM')), 0) + 1
                        else f.next_no end,
           'pattern', f.pattern)
           order by array_position(array['creator', 'campaign', 'job', 'trip', 'request', 'revision'], f.kind)), '[]'::jsonb)
         else '[]'::jsonb end
    from public.id_formats f
$$;
revoke all on function public.id_formats_list() from public, anon;
grant execute on function public.id_formats_list() to authenticated;

create or replace function public.id_format_set(p_kind text, p_prefix text, p_width int, p_next bigint, p_pattern text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  me  public.team_members := public.ops_me();
  f   public.id_formats;
  v_p text := upper(btrim(coalesce(p_prefix, '')));
  v_t text := btrim(coalesce(p_pattern, ''));
  v_top bigint;
  v_moved text[] := '{}';
  v_word text;
begin
  if not public.ops_granted('team.settings', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into f from public.id_formats where kind = p_kind for update;
  if f.kind is null then return jsonb_build_object('error', 'not-found'); end if;
  v_word := case p_kind when 'creator' then 'Creator ID' when 'campaign' then 'Campaign ID' when 'trip' then 'Outstation trip number' when 'request' then 'Quotation request number' when 'revision' then 'Quotation revision' else 'Job reference' end;
  if p_kind = 'job' then
    if length(v_t) > 40 or position('{creator}' in v_t) = 0 or position('{campaign}' in v_t) = 0 then
      return jsonb_build_object('error', 'bad-pattern');
    end if;
    if v_t is distinct from f.pattern then
      update public.id_formats set pattern = v_t, updated_at = now(), updated_by = me.id where kind = p_kind;
      insert into public.activity_log (actor, action, subject, detail)
      values (me.name, 'team.changed', 'Creator and campaign IDs', v_word || ': ' || f.pattern || ' → ' || v_t);
    end if;
    return jsonb_build_object('ok', true);
  end if;
  if v_p !~ '^[A-Z]{1,6}$' then return jsonb_build_object('error', 'bad-prefix'); end if;
  if p_width is null or p_width < (case p_kind when 'revision' then 1 when 'request' then 3 else 2 end)
     or p_width > (case p_kind when 'revision' then 3 else 6 end) then return jsonb_build_object('error', 'bad-width'); end if;
  if p_next is null or p_next < 1 then return jsonb_build_object('error', 'bad-next'); end if;
  -- A creator's payment details reference: its Creator ID and a run of n.
  if p_kind = 'creator' and v_t <> '' and (length(v_t) > 40 or position('{creator}' in v_t) = 0 or v_t !~ '\{n{1,6}\}') then
    return jsonb_build_object('error', 'bad-request-pattern');
  end if;
  -- The next number stays above every number in use under that prefix; a
  -- trip's number counts afresh each month, and a request's letters are
  -- drawn at random, so neither keeps a next number.
  if p_kind in ('trip', 'request', 'revision') then
    v_top := null;
  elsif p_kind = 'creator' then
    select max(substring(c.creator_code from length(v_p) + 1)::bigint) into v_top
      from public.creators c where c.creator_code ~ ('^' || v_p || '[0-9]+$');
  else
    select max(substring(m.campaign_code from length(v_p) + 1)::bigint) into v_top
      from public.campaigns m where m.campaign_code ~ ('^' || v_p || '[0-9]+$');
  end if;
  if v_top is not null and p_next <= v_top then
    return jsonb_build_object('error', 'bad-next', 'top', v_top);
  end if;
  v_moved := array_remove(array[
    case when v_p <> f.prefix then 'prefix ' || f.prefix || ' → ' || v_p end,
    case when p_width <> f.width then 'digits ' || f.width || ' → ' || p_width end,
    case when p_kind not in ('trip', 'request', 'revision') and p_next <> f.next_no then 'next ' || f.next_no || ' → ' || p_next end,
    case when p_kind = 'creator' and v_t <> '' and v_t is distinct from f.pattern
         then 'payment details reference ' || coalesce(f.pattern, 'not set') || ' → ' || v_t end], null);
  if cardinality(v_moved) = 0 then return jsonb_build_object('ok', true); end if;
  update public.id_formats set prefix = v_p, width = p_width, next_no = case when p_kind in ('trip', 'request', 'revision') then f.next_no else p_next end,
    pattern = case when p_kind = 'creator' and v_t <> '' then v_t else pattern end,
    updated_at = now(), updated_by = me.id
   where kind = p_kind;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'team.changed', case when p_kind = 'trip' then 'Outstation trip numbers' when p_kind in ('request', 'revision') then 'Quotation numbers' else 'Creator and campaign IDs' end, v_word || ': ' || array_to_string(v_moved, ', '));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.id_format_set(text, text, int, bigint, text) from public, anon;
grant execute on function public.id_format_set(text, text, int, bigint, text) to authenticated;

-- END OF QUOTATIONS CONFIRMED BEFORE THEY GO ------------------------------------
