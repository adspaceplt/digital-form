-- ===========================================================================
-- CREATOR FILES HELD TO THEIR FOLDER — a creator's handed-in file is the one
-- sign-upload stored for that booking, nothing else. 2026-10-17. Safe to run
-- twice. Rollback at the foot. Mirrored byte for byte in supabase/schema.sql
-- under the same banner; tests/sql.js compares the two.
--
-- WHAT CHANGED (the security audit of 2026-10-16, finding 2)
--   1. `creator_add_file` (anon, a creator's code) stored the address, name
--      and kind as the page sent them, and the console and the selection
--      page draw the address inside src and href: an address holding a
--      quote ran script in a colleague's console with no press. It now takes
--      only the address `sign-upload` gives a creator for that booking
--      (`https://mycdn.adspace.me/content/creator/{booking}/{uuid}.{ext}`,
--      CDN_BASE and S3_PREFIX as set, docs/S3-UPLOAD-SETUP.md), refused
--      `bad-file`; a name of 1 to 255 characters (`bad-name`); and a kind the
--      creator's page sends, image, video or file (`bad-kind`; none is file).
--      The files stored before are left as they are (none fails it but the
--      team's own, under the client's folder, which this function never
--      writes).
--
-- ROLLBACK
--   Run `creator_add_file` again from 2026-09-24-creator-profile.sql (it
--   reopens the finding).
-- ===========================================================================

create or replace function public.creator_add_file(
  p_code text, p_option uuid, p_url text, p_name text, p_kind text, p_bytes bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cr     creators%rowtype;
  o      campaign_options%rowtype;
  new_id uuid;
begin
  select * into cr from creators where access_code = upper(p_code) and active;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  /* Qualified, and the variable is not called `id`. A declared `id` against an
     unqualified `where id = p_option` is ambiguous, which PL/pgSQL raises at
     run time rather than at create time: every upload failed in production
     while the schema applied cleanly and every browser suite stayed green. */
  select * into o from campaign_options co
   where co.id = p_option and co.creator_id = cr.id;
  if not found then return jsonb_build_object('error', 'not-found'); end if;
  if not public.creator_can_deliver(o.state) then
    return jsonb_build_object('error', 'closed');
  end if;
  /* Only the address sign-upload made for this booking: the CDN, the
     creator's folder for this booking, a random name and a short extension.
     Nothing in it can close the attribute a page draws it in (audit 2026-10-16). */
  if p_url is null or p_url !~ ('^https://mycdn\.adspace\.me/content/creator/' || p_option::text
       || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.[a-z0-9]{1,5}$') then
    return jsonb_build_object('error', 'bad-file');
  end if;
  if p_name is null or char_length(btrim(p_name)) not between 1 and 255 then
    return jsonb_build_object('error', 'bad-name');
  end if;
  if p_kind is not null and p_kind not in ('image', 'video', 'file') then
    return jsonb_build_object('error', 'bad-kind');
  end if;
  insert into campaign_deliverables (option_id, url, name, kind, bytes, round)
  values (p_option, p_url, p_name, coalesce(p_kind, 'file'), p_bytes,
          greatest(o.revision_round, 1))
  returning campaign_deliverables.id into new_id;
  return jsonb_build_object('id', new_id);
end $$;
grant execute on function public.creator_add_file(text, uuid, text, text, text, bigint) to anon, authenticated;

-- END OF CREATOR FILES HELD TO THEIR FOLDER ----------------------------------

select public.functions_tidy();
