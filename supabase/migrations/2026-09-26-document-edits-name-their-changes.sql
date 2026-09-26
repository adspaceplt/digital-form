-- ===========================================================================
-- DOCUMENT EDITS NAME THEIR CHANGES — an edit to a hand-added Documents row
-- records each field it moved, from and to.
-- 2026-09-26. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED, the user's decision of 2026-09-26 (records "too brief"; the
-- example given: "Edited ADHR/AD021/AOR: type Acceptance of Resignation →
-- Offer Letter; date not set → 12 Sept 2026"):
--  1. `register_update` files what moved: the type, the date, the family,
--     the recipient, the client, and whether the note or the file link
--     changed. A save that moved nothing files nothing.
--  2. An HR row keeps its rule: filed under subject `HR`, never the serial,
--     the colleague or the recipient; its detail names the type, the date,
--     the note and the file link only.
--
-- ROLLBACK
--   Re-run register_update from 2026-09-26-an-hr-entry-names-its-colleague.sql.
-- ===========================================================================

create or replace function public.register_day(p_day date)
returns text
language sql immutable set search_path = public as $$
  select case when p_day is null then 'not set'
    else to_char(p_day, 'FMDD') || ' ' ||
         (array['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sept','Oct','Nov','Dec'])[extract(month from p_day)::int]
         || ' ' || to_char(p_day, 'YYYY') end
$$;

create or replace function public.register_update(
  p_doc       uuid,
  p_kind      text,
  p_family    text,
  p_issued_at date,
  p_recipient text,
  p_client    uuid,
  p_note      text,
  p_file_url  text,
  p_member    uuid default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  who   text := lower(auth.jwt() ->> 'email');
  d     public.documents%rowtype;
  v_fam text := coalesce(nullif(btrim(p_family), ''), 'other');
  cl    public.clients%rowtype;
  was_cl public.clients%rowtype;
  tm    public.team_members%rowtype;
  moves text[] := array[]::text[];
  fam_word jsonb := '{"quote_cover":"Quotation Covers","client":"Client Letters","hr":"HR Letters","other":"Other"}'::jsonb;
  v_rec text := coalesce(btrim(p_recipient), '');
  v_note text := nullif(btrim(p_note), '');
  v_file text := nullif(btrim(p_file_url), '');
begin
  select * into d from public.documents where id = p_doc;
  if d.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if d.source <> 'manual' then return jsonb_build_object('error', 'not-manual'); end if;
  if v_fam not in ('quote_cover', 'client', 'hr', 'other') then return jsonb_build_object('error', 'bad-family'); end if;
  if not public.register_may(d.family, 'work') or not public.register_may(v_fam, 'work') then
    return jsonb_build_object('error', 'not-allowed');
  end if;
  if coalesce(btrim(p_kind), '') = '' then return jsonb_build_object('error', 'kind-required'); end if;
  if v_fam = 'hr' then
    if p_member is not null then select * into tm from public.team_members where id = p_member; end if;
  elsif p_client is not null then
    select * into cl from public.clients where id = p_client;
  end if;
  if d.client_id is not null then select * into was_cl from public.clients where id = d.client_id; end if;

  /* What moved, in the order a reader looks: the type, the date, where it is
     filed, who it went to, then whether the note or the file changed. An HR
     row names only its type, date, note and file. */
  if d.kind is distinct from btrim(p_kind) then
    moves := moves || ('type ' || coalesce(d.kind, 'not set') || ' → ' || btrim(p_kind));
  end if;
  if d.issued_at is distinct from p_issued_at then
    moves := moves || ('date ' || public.register_day(d.issued_at) || ' → ' || public.register_day(p_issued_at));
  end if;
  if v_fam <> 'hr' and d.family <> 'hr' then
    if d.family is distinct from v_fam then
      moves := moves || ('filed ' || coalesce(fam_word ->> d.family, d.family) || ' → ' || coalesce(fam_word ->> v_fam, v_fam));
    end if;
    if coalesce(d.recipient ->> 'name', '') is distinct from v_rec then
      moves := moves || ('recipient ' || coalesce(nullif(d.recipient ->> 'name', ''), 'not set') || ' → ' || coalesce(nullif(v_rec, ''), 'not set'));
    end if;
    if d.client_id is distinct from cl.id then
      moves := moves || ('client ' || coalesce(was_cl.name, 'not set') || ' → ' || coalesce(cl.name, 'not set'));
    end if;
  end if;
  if d.note is distinct from v_note then moves := moves || 'note changed'::text; end if;
  if d.file_url is distinct from v_file then moves := moves || 'file link changed'::text; end if;

  update public.documents set
    kind = btrim(p_kind), family = v_fam, issued_at = p_issued_at,
    recipient = jsonb_build_object('name', v_rec),
    client_id = cl.id, member_id = tm.id,
    note = v_note, file_url = v_file
  where id = p_doc;
  if array_length(moves, 1) > 0 then
    insert into public.activity_log (actor, action, subject, detail)
    values (who, 'register.edited',
            case when v_fam = 'hr' or d.family = 'hr' then 'HR' else coalesce(cl.name, nullif(v_rec, ''), d.serial) end,
            case when v_fam = 'hr' or d.family = 'hr' then array_to_string(moves, '; ')
                 else d.serial || ': ' || array_to_string(moves, '; ') end);
  end if;
  return jsonb_build_object('ok', true, 'serial', d.serial);
end $$;
grant execute on function public.register_update(uuid, text, text, date, text, uuid, text, text, uuid) to authenticated;

-- END OF DOCUMENT EDITS NAME THEIR CHANGES -----------------------------------
