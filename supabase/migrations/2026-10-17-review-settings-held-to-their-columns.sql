-- ===========================================================================
-- REVIEW SETTINGS HELD TO THEIR COLUMNS — Content Review: Client settings
-- changes a client's review link, logo, passcode, handles and Drive folder,
-- and nothing else of the client. 2026-10-17. Safe to run twice. Rollback
-- at the foot. Mirrored byte for byte in supabase/schema.sql under the same
-- banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the security audit of 2026-10-16, finding D)
--   1. `clients_update` lets a write through at Clients Work or at Content
--      Review: Client settings Work, because Content Review writes the
--      client's handles, logo, passcode, review key and whether it is in
--      Content Review. A policy cannot name columns, so a group holding the
--      Content Review part alone could change the whole row: the name, the
--      stage, the Client ID, the person in charge. Trigger
--      `client_review_columns` refuses, for a caller without Clients at Work,
--      a write from the page (the table reached as `authenticated`, never a
--      function) that changes any column but `handle_ig`, `handle_fb`,
--      `handle_tiktok`, `handle_xhs`, `logo_url`, `passcode`,
--      `access_token`, `review_hidden`, `drive_folder` and `updated_at`
--      (`review-columns`). It is named to run before every other trigger on
--      the table, so it reads the columns as the caller sent them, before a
--      trigger stamps its own. The billing guard is unchanged.
--
-- ROLLBACK
--   drop trigger if exists client_review_columns on public.clients;
--   drop function if exists public.client_review_columns();
-- ===========================================================================

create or replace function public.client_review_columns()
returns trigger language plpgsql set search_path = public as $$
declare
  v_mine constant text[] := array['handle_ig', 'handle_fb', 'handle_tiktok', 'handle_xhs',
    'logo_url', 'passcode', 'access_token', 'review_hidden', 'drive_folder', 'updated_at'];
begin
  /* A function writing the row runs as its owner and has asked its own
     permission; a cascade is not a person. Only a write made on the table
     through the API (as `authenticated`) is held. */
  if pg_trigger_depth() > 1 or current_user <> 'authenticated' then
    return new;
  end if;
  if public.allowed('clients', 'work') then return new; end if;
  if (to_jsonb(new) - v_mine) is distinct from (to_jsonb(old) - v_mine) then
    raise exception 'review-columns: Content Review settings change only the review link, logo, passcode, handles and Drive folder.'
      using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.client_review_columns() from public, anon;

create or replace trigger client_review_columns before update on public.clients
  for each row execute function public.client_review_columns();

-- END OF REVIEW SETTINGS HELD TO THEIR COLUMNS -------------------------------

select public.functions_tidy();
