-- ===========================================================================
-- VERIFY SEALED FILES (2026-11-17)
-- ===========================================================================
-- WHY: the user, 2026-11-17 (digital-form-tests specs/SEAL-SPEC.md, decision
-- 6): /verify/ answers a quotation's reference as it answers a letter's,
-- and checks a file against the sealed copy. The Record page's QR code
-- leads there.
--
-- WHAT IT CHANGES
--   * `verify_count()`: the one count of lookups from a connection (30 an
--     hour, `verify_tries`, as VERIFY LOOKUPS COUNTED); answers the minutes
--     left while locked, else 0. Never a colleague, nor a session with no
--     request. Closed to every caller: only the two verify functions ask it.
--   * `verify_serial` answers a quotation sent out or signed: kind
--     Quotation, Valid, Void (cancelled), Replaced (revised), Expired (its
--     validity passed unsigned), the day issued, signed and confirmed, and
--     its Document ID once sealed; never the signer, an email, an address,
--     a device, the company or an amount. Every other answer is unchanged.
--   * `verify_file(p_serial, p_sha)` (anon): whether a file's SHA-256, worked
--     out in the visitor's browser, is the sealed copy's (`match`), counted
--     with the lookups; `none` where the reference holds no sealed copy.
--     The file never leaves the browser.
--
-- ORDER: 2026-10-07-function-hygiene.sql again (`verify_file` joins
-- `open_to_anon`), this file (connector), then the pages. A page from
-- before reads a quotation's answer as any other. Safe to run twice.
--
-- ROLLBACK: run verify_serial from VERIFY LOOKUPS COUNTED again; the pages
-- from before. `verify_file` and `verify_count` may stay.
-- ===========================================================================


-- VERIFY SEALED FILES — /verify/ answers a quotation and checks a sealed file.

create or replace function public.verify_count()
returns integer
language plpgsql volatile set search_path = public as $$
declare
  v_ip text := public.request_ip();
  v_n integer;
  v_since timestamptz;
begin
  if v_ip = '' or public.is_team() then return 0; end if;
  insert into public.verify_tries as v (ip, n, since) values (v_ip, 1, now())
  on conflict (ip) do update
    set n = case when v.since < now() - interval '1 hour' then 1 else v.n + 1 end,
        since = case when v.since < now() - interval '1 hour' then now() else v.since end
  returning v.n, v.since into v_n, v_since;
  if v_n > 30 then
    return greatest(1, ceil(extract(epoch from (v_since + interval '1 hour' - now())) / 60)::integer);
  end if;
  return 0;
end $$;
revoke all on function public.verify_count() from public, anon, authenticated;

create or replace function public.verify_serial(p_serial text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s text := upper(btrim(coalesce(p_serial, '')));
  sd text;
  d public.documents%rowtype;
  l public.client_documents%rowtype;
  q public.quotations%rowtype;
  rv public.perf_reviews%rowtype;
  dl public.perf_deleted%rowtype;
  v_wait integer := public.verify_count();
begin
  if v_wait > 0 then
    return jsonb_build_object('found', false, 'locked', true, 'minutes', v_wait);
  end if;
  if length(s) < 3 or length(s) > 40 then return jsonb_build_object('found', false); end if;
  sd := replace(s, '/', '-');
  select * into d from public.documents
   where upper(serial) = s or replace(upper(serial), '/', '-') = sd
   order by (upper(serial) = s) desc, (voided_at is null) desc, created_at desc limit 1;
  if d.id is not null then
    return jsonb_build_object('found', true, 'serial', d.serial,
      'kind', case when d.family = 'hr' then 'HR Letter' else d.kind end,
      'issued_at', d.issued_at,
      'state', case when d.voided_at is null then 'valid' else 'voided' end);
  end if;
  select * into l from public.client_documents
   where upper(number) = s or replace(upper(number), '/', '-') = sd
   order by (upper(number) = s) desc limit 1;
  if l.id is not null then
    return jsonb_build_object('found', true, 'serial', l.number, 'kind', 'Letter of Offer',
      'issued_at', l.issued_at,
      'state', case when l.voided_at is not null then 'voided'
                    when l.superseded_by is not null then 'replaced'
                    else 'valid' end);
  end if;
  /* A quotation once it left ADspace (sent out, or signed): what its
     reference stands for and no more (SIGNED DOCUMENT SEAL, decision 6). */
  select * into q from public.quotations x
   where (upper(x.ref) = s or replace(upper(x.ref), '/', '-') = sd)
     and (x.sent_out_at is not null or x.signed_at is not null)
   order by (upper(x.ref) = s) desc, x.issued_at desc limit 1;
  if q.id is not null then
    return jsonb_build_object('found', true, 'serial', q.ref, 'kind', 'Quotation',
      'issued_at', q.issued_at,
      'signed_at', q.signed_at,
      'confirmed_at', q.reviewed_at,
      'document_id', case when q.seal_key is not null then q.id end,
      'sealed', q.seal_key is not null,
      'state', case when q.status = 'not_proceeding' or q.removed_at is not null then 'voided'
                    when exists (select 1 from public.quotations r where r.replaces = q.id and r.removed_at is null) then 'replaced'
                    when q.signed_at is null and q.valid_until is not null
                         and q.valid_until < (now() at time zone 'Asia/Kuala_Lumpur')::date then 'expired'
                    else 'valid' end);
  end if;
  select * into rv from public.perf_reviews pr
   where (upper(pr.serial) = s or replace(upper(pr.serial), '/', '-') = sd)
     and exists (select 1 from public.perf_events pe where pe.review_id = pr.id and pe.kind = 'printed')
   limit 1;
  if rv.id is not null then
    return jsonb_build_object('found', true, 'serial', rv.serial, 'kind', 'HR Letter',
      'issued_at', rv.released_at,
      'state', case when rv.status = 'draft' then 'replaced' else 'valid' end);
  end if;
  select * into dl from public.perf_deleted pd
   where pd.printed and (upper(pd.serial) = s or replace(upper(pd.serial), '/', '-') = sd)
   order by pd.deleted_at desc limit 1;
  if dl.id is not null then
    return jsonb_build_object('found', true, 'serial', dl.serial, 'kind', 'HR Letter',
      'issued_at', dl.released_at, 'state', 'voided');
  end if;
  return jsonb_build_object('found', false);
end $$;
revoke all on function public.verify_serial(text) from public;
grant execute on function public.verify_serial(text) to anon, authenticated;

/* Whether a file is the sealed copy: its SHA-256, worked out in the
   visitor's browser, against the one kept when it was sealed. */
create or replace function public.verify_file(p_serial text, p_sha text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s text := upper(btrim(coalesce(p_serial, '')));
  h text := lower(btrim(coalesce(p_sha, '')));
  q public.quotations%rowtype;
  v_wait integer := public.verify_count();
begin
  if v_wait > 0 then return jsonb_build_object('locked', true, 'minutes', v_wait); end if;
  if length(s) < 3 or length(s) > 40 or h !~ '^[0-9a-f]{64}$' then return jsonb_build_object('error', 'bad-request'); end if;
  select * into q from public.quotations x
   where (upper(x.ref) = s or replace(upper(x.ref), '/', '-') = replace(s, '/', '-'))
     and x.seal_key is not null
   order by (upper(x.ref) = s) desc, x.issued_at desc limit 1;
  if q.id is null then return jsonb_build_object('none', true); end if;
  return jsonb_build_object('match', q.seal_sha = h);
end $$;
revoke all on function public.verify_file(text, text) from public;
grant execute on function public.verify_file(text, text) to anon, authenticated;

-- END OF VERIFY SEALED FILES --------------------------------------------------

select public.functions_tidy();
