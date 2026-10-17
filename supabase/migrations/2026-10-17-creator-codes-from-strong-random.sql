-- ===========================================================================
-- CREATOR CODES FROM STRONG RANDOM — a creator's access code is drawn from
-- the cryptographic generator, as every link key is. 2026-10-17. Safe to run
-- twice. Rollback at the foot. Mirrored byte for byte in
-- supabase/schema.sql under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the security audit of 2026-10-16, finding L)
--   1. `new_creator_code` drew its eight characters from `random()`, which
--      is not a cryptographic generator: its sequence can be predicted from
--      enough of its output. The code is the creator's whole sign-in. It now
--      takes `gen_random_bytes`, as `new_link_key` does, keeping the same
--      alphabet of 31 (no 0, O, 1, I or L) and the same length; a byte of
--      248 or over is thrown away so every character stays equally likely.
--      Codes already issued are kept.
--
-- ROLLBACK
--   Run `new_creator_code` again from the CREATOR ACCESS CODE section of
--   supabase/schema.sql as it stood before 2026-10-17 (random()).
-- ===========================================================================

create or replace function public.new_creator_code()
returns text language plpgsql volatile set search_path = public, extensions as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  v_out   text;
  v_bytes bytea;
  v_i     integer;
  v_b     integer;
begin
  loop
    v_out := '';
    while length(v_out) < 8 loop
      v_bytes := gen_random_bytes(16);
      for v_i in 0..15 loop
        v_b := get_byte(v_bytes, v_i);
        /* 248 is 31 × 8: below it every character is equally likely. */
        if v_b < 248 and length(v_out) < 8 then
          v_out := v_out || substr(alphabet, 1 + (v_b % 31), 1);
        end if;
      end loop;
    end loop;
    exit when not exists (select 1 from public.creators c where c.access_code = v_out);
  end loop;
  return v_out;
end $$;

-- END OF CREATOR CODES FROM STRONG RANDOM ------------------------------------

select public.functions_tidy();
