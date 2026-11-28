-- ===========================================================================
-- A REQUEST NUMBER WHILE ANY IS FREE (2026-11-28)
-- ===========================================================================
-- WHY: `public_request_ref` drew at random and gave up after 200 clashes,
-- so a month holding a few free numbers answered "no free number" by
-- chance (`reqrefsql`, 28 Nov: the month filled but for 300 of 8,000, one
-- run in a hundred). A public submission refused while a number stood free.
-- WHAT IT CHANGES
--   * `public_request_ref(at)` walks every code of the month's width once,
--     in an order drawn afresh each call (a random first code, then a
--     random step sharing no factor with the count of codes, so every code
--     is met exactly once): the first code is as random as before, and
--     "no free number" is answered only once every code is held. The deny
--     list, the lock, the tables checked and the shape are unchanged.
-- ORDER: this file alone; no page or function changes. Safe to run twice.
-- ROLLBACK: restate `public_request_ref` from
--   2026-11-26-public-request-ref.sql (its last definition before this).
--   Holds no drop or delete.
-- ===========================================================================

-- A REQUEST NUMBER WHILE ANY IS FREE ------------------------------------------

/* One generator for every public submission: consonants alone, so it never
   spells a word nor tells how many came in. Every code of the width is met
   once, in a random order, so a free one is always found. */
create or replace function public.public_request_ref(p_at timestamptz)
returns text language plpgsql volatile set search_path = public, extensions as $$
declare
  alphabet constant text := 'BCDFGHJKLMNPQRSTVWXZ';
  deny constant text[] := array['FCK', 'FKN', 'SHT', 'KKK', 'XXX', 'WTF', 'STD', 'NGR', 'PKM', 'BBW', 'DCK', 'CNT', 'PSS', 'TTS'];
  f public.id_formats;
  v_n int; v_total bigint; v_at bigint; v_step bigint; v_x bigint; v_seen bigint := 0;
  v_out text; v_ref text; v_head text; v_bytes bytea; v_i int;
begin
  -- One draw at a time until the caller's transaction ends, so two
  -- submissions in the same moment never take one number.
  perform pg_advisory_xact_lock(hashtext('public_request_ref'));
  select * into f from public.id_formats where kind = 'request';
  v_n := greatest(3, least(6, coalesce(f.width, 3)));
  v_total := power(length(alphabet), v_n)::bigint;
  v_head := 'ADP/' || coalesce(nullif(f.prefix, ''), 'REQ') || to_char(p_at at time zone 'Asia/Kuala_Lumpur', 'YYMM') || '-';
  -- The order: a random first code, a random step prime to the count.
  v_bytes := gen_random_bytes(8);
  v_at := 0; v_step := 0;
  for v_i in 0..3 loop
    v_at := v_at * 256 + get_byte(v_bytes, v_i);
    v_step := v_step * 256 + get_byte(v_bytes, v_i + 4);
  end loop;
  v_at := v_at % v_total;
  v_step := 1 + v_step % (v_total - 1);
  while gcd(v_step, v_total) <> 1 loop v_step := 1 + v_step % (v_total - 1); end loop;
  loop
    if v_seen >= v_total then raise exception 'public_request_ref: no free number'; end if;
    v_seen := v_seen + 1;
    v_out := ''; v_x := v_at;
    for v_i in 1..v_n loop
      v_out := v_out || substr(alphabet, 1 + (v_x % length(alphabet))::int, 1);
      v_x := v_x / length(alphabet);
    end loop;
    v_at := (v_at + v_step) % v_total;
    continue when v_out = any (deny);
    v_ref := v_head || v_out;
    exit when not exists (select 1 from public.quotations q where q.ref = v_ref or q.request_ref = v_ref)
          and not exists (select 1 from public.quotation_refs_kept k where k.ref = v_ref)
          and not exists (select 1 from public.client_detail_forms d where d.request_ref = v_ref)
          and not exists (select 1 from public.supplier_forms s where s.request_ref = v_ref)
          and not exists (select 1 from public.hiring_candidates h where h.request_ref = v_ref)
          and not exists (select 1 from public.client_requests r where r.request_ref = v_ref)
          and not exists (select 1 from public.feedback_responses b where b.request_ref = v_ref);
  end loop;
  return v_ref;
end $$;
revoke all on function public.public_request_ref(timestamptz) from public, anon, authenticated;

-- END OF A REQUEST NUMBER WHILE ANY IS FREE -------------------------------------

select public.functions_tidy();
