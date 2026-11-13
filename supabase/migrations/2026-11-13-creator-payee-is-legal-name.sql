-- ===========================================================================
-- CREATOR PAYEE IS THE LEGAL NAME — a creator's account holder is their legal
-- name, and every word of it opens on a capital (2026-11-13)
-- ===========================================================================
-- WHY (the user, 2026-11-13: "force the creator payment Legal name to be
-- first letter always capital … Lim Raymond not Lim raymond"; "the account
-- holder, make it read only copy the Legal name, as we only can issue bill
-- and transfer to this person with the same bank account name as legal
-- name"): a set read "Wong chun seng", and the account holder could be
-- anybody's.
--
-- WHAT CHANGED
--   * `creator_pay_check` (the one check of every set: the creator's page,
--     the team's Add details) opens every word of the legal name on a
--     capital, the rest as typed (LIM RAYMOND stays, lim raymond reads Lim
--     Raymond), and sets the account holder to the legal name whatever was
--     sent.
--
-- ORDER: this file (connector), then the pages (the field read only). A page
-- served before still sends a payee; it is replaced. Safe to run twice.
--
-- ROLLBACK: restate creator_pay_check from CREATOR PAYMENT DETAILS in
-- schema.sql.
-- ===========================================================================

-- CREATOR PAYEE IS THE LEGAL NAME -------------------------------------------

create or replace function public.creator_pay_check(p jsonb)
returns jsonb language plpgsql immutable set search_path = public as $$
declare
  v_kind text := btrim(coalesce(p->>'bill_kind', ''));
  v_id   text := upper(regexp_replace(coalesce(p->>'id_no', ''), '[\s-]', '', 'g'));
  v_name text := btrim(regexp_replace(coalesce(p->>'legal_name', ''), '\s+', ' ', 'g'));
  v_tin  text := upper(regexp_replace(coalesce(p->>'tin', ''), '\s', '', 'g'));
  v_addr text := btrim(coalesce(p->>'address', ''));
  v_cur  text := upper(btrim(coalesce(p->>'currency', '')));
  v_meth text := btrim(coalesce(p->>'method', ''));
  v_bank text := btrim(coalesce(p->>'bank', ''));
  v_acct text := upper(regexp_replace(coalesce(p->>'account', ''), '[\s-]', '', 'g'));
  v_pay  text := btrim(regexp_replace(coalesce(p->>'payee', ''), '\s+', ' ', 'g'));
  v_mail text := lower(btrim(coalesce(p->>'email', '')));
  v_wa   text := regexp_replace(coalesce(p->>'whatsapp', ''), '\D', '', 'g');
  v_w    text;
  v_banks constant text[] := array['Maybank', 'CIMB', 'Hong Leong Bank', 'RHB', 'BSN', 'UOB', 'OCBC', 'AmBank', 'Bank Islam',
    'Public Bank', 'Alliance Bank', 'Standard Chartered Bank', 'Touch N Go Digital', '[SG] DBS/POSB', '[SG] OCBC', '[SG] UOB',
    '[SG] CIMB', '[SG] Maybank', '[SG] Bank of China'];
begin
  if v_kind not in ('nric', 'passport', 'brn') then return jsonb_build_object('field', 'bill_kind'); end if;
  if v_kind = 'nric' and v_id !~ '^\d{12}$' then return jsonb_build_object('field', 'id_no'); end if;
  if v_kind = 'brn' and v_id !~ '^\d{12}$' then return jsonb_build_object('field', 'id_no'); end if;
  if v_kind = 'passport' and v_id !~ '^[A-Z0-9]{5,20}$' then return jsonb_build_object('field', 'id_no'); end if;
  if v_kind = 'nric' then v_id := substr(v_id, 1, 6) || '-' || substr(v_id, 7, 2) || '-' || substr(v_id, 9, 4); end if;
  if length(v_name) < 2 or length(v_name) > 120 then return jsonb_build_object('field', 'legal_name'); end if;
  -- every word of the name opens on a capital, the rest as typed
  select string_agg(upper(left(w, 1)) || substr(w, 2), ' ' order by n) into v_w
    from regexp_split_to_table(v_name, ' ') with ordinality as t(w, n);
  v_name := v_w;
  -- the bill is issued and paid to the legal name, so the account holder is it
  v_pay := v_name;
  if v_tin <> '' and v_tin !~ '^[A-Z0-9]{5,20}$' then return jsonb_build_object('field', 'tin'); end if;
  if length(v_addr) < 5 or length(v_addr) > 300 then return jsonb_build_object('field', 'address'); end if;
  if v_cur not in ('MYR', 'SGD') then return jsonb_build_object('field', 'currency'); end if;
  if not ((v_cur = 'MYR' and v_meth in ('bank', 'duitnow', 'tng')) or (v_cur = 'SGD' and v_meth in ('bank', 'paynow'))) then
    return jsonb_build_object('field', 'method');
  end if;
  if v_meth = 'bank' then
    if not (v_bank = any (v_banks)) or ((v_cur = 'SGD') <> (v_bank like '[SG]%')) then
      return jsonb_build_object('field', 'bank');
    end if;
  else
    v_bank := '';
  end if;
  if v_acct !~ '^[A-Z0-9]{6,34}$' then return jsonb_build_object('field', 'account'); end if;
  if length(v_pay) < 2 or length(v_pay) > 120 then return jsonb_build_object('field', 'payee'); end if;
  if v_mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_mail) > 160 then return jsonb_build_object('field', 'email'); end if;
  if length(v_wa) < 8 or length(v_wa) > 15 then return jsonb_build_object('field', 'whatsapp'); end if;
  if coalesce(p->>'confirm', '') not in ('true', 'on', '1') then return jsonb_build_object('field', 'confirm'); end if;
  return jsonb_build_object('values', jsonb_build_object('bill_kind', v_kind, 'id_no', v_id, 'legal_name', v_name,
    'tin', nullif(v_tin, ''), 'address', v_addr, 'currency', v_cur, 'method', v_meth, 'bank', nullif(v_bank, ''),
    'account', v_acct, 'payee', v_pay, 'email', v_mail, 'whatsapp', v_wa));
end $$;
revoke all on function public.creator_pay_check(jsonb) from public, anon, authenticated;

-- END OF CREATOR PAYEE IS THE LEGAL NAME ------------------------------------

select public.functions_tidy();
