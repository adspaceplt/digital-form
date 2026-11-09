-- WHY: a creator's code signed any number of 1 GB uploads into their
--   booking's folder (security audit 2026-11-09, needs-validation lead 2):
--   a leaked or misused code could fill the bucket with nothing to stop it.
-- WHAT: sign-upload asks creator_upload_claim before it signs a creator's
--   upload: the code, the booking and the step as creator_may_upload asks,
--   then fifty files and 25 GB a booking a Malaysian day, counted in one row
--   a booking (creator_upload_counts, RLS on, no policy, no grant), refused
--   `too-many`. The service role's alone.
-- ORDER: this file, then sign-upload, then the pages.
-- ROLLBACK: sign-upload from before this file; then, in the SQL Editor,
--   drop function public.creator_upload_claim(text, uuid, bigint) and
--   drop table public.creator_upload_counts.

-- ===========================================================================

-- CREATOR UPLOADS COUNTED --------------------------------------------------

/* A creator's signed uploads are counted a booking a day (security audit
   2026-11-09): fifty files and 25 GB a Malaysian day, then `too-many`. */
create table if not exists public.creator_upload_counts (
  option_id uuid primary key,
  day       date not null,
  files     integer not null default 0,
  bytes     bigint not null default 0
);
alter table public.creator_upload_counts enable row level security;
revoke all on public.creator_upload_counts from public, anon, authenticated;

create or replace function public.creator_upload_claim(p_code text, p_option uuid, p_size bigint)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_day   date := (now() at time zone 'Asia/Kuala_Lumpur')::date;
  v_row   public.creator_upload_counts;
begin
  if p_size is null or p_size < 1 or not public.creator_may_upload(p_code, p_option) then
    return 'not-allowed';
  end if;
  insert into public.creator_upload_counts (option_id, day) values (p_option, v_day)
    on conflict (option_id) do nothing;
  select * into v_row from public.creator_upload_counts where option_id = p_option for update;
  if v_row.day <> v_day then
    v_row.files := 0; v_row.bytes := 0;
  end if;
  if v_row.files >= 50 or v_row.bytes + p_size > 25::bigint * 1024 * 1024 * 1024 then
    return 'too-many';
  end if;
  update public.creator_upload_counts
     set day = v_day, files = v_row.files + 1, bytes = v_row.bytes + p_size
   where option_id = p_option;
  return 'ok';
end $$;
revoke all on function public.creator_upload_claim(text, uuid, bigint) from public, anon, authenticated;
grant execute on function public.creator_upload_claim(text, uuid, bigint) to service_role;

-- END OF CREATOR UPLOADS COUNTED -------------------------------------------


select public.functions_tidy();
