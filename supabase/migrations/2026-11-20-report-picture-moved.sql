-- ===========================================================================
-- A REPORT PICTURE MOVED TO S3 (2026-11-20)
-- ===========================================================================
-- WHY (the move of 2026-11-20: `report-thumbs-move` was refused
-- `sm-not-draft` on every row): a report past its draft holds its rows
-- still (`sm_report_child_guard`), and nearly every picture belongs to a
-- published report. Swapping a picture for its own copy on S3 changes no
-- figure and no word a client read, so the server may make that one swap.
--
-- WHAT IT ADDS
--   * `sm_report_thumb_set(p_kind, p_id, p_key)`, the service role's alone
--     (revoked from every page): on a post (`post`) or an ad (`ad`) still
--     holding its picture as data, writes the picture's S3 key
--     (`private/{client}/thumbs/{uuid}.jpg`, the report's own client)
--     through the guard's own way for the database's functions
--     (`adspace.sm_fn`, this transaction alone). Answers true where it
--     changed a row. The guard and every page's refusal are unchanged.
--
-- ORDER: this file, then `report-thumbs-move` v3, which calls it. Safe to
-- run twice. Rollback: drop the function.
-- ===========================================================================

create or replace function public.sm_report_thumb_set(p_kind text, p_id uuid, p_key text)
returns boolean
language plpgsql volatile security definer set search_path = public as $$
declare
  v_client uuid;
  v_n      integer;
begin
  if p_kind not in ('post', 'ad') or p_key is null
     or p_key !~ '^private/[0-9a-f-]{36}/thumbs/[0-9a-f-]{36}\.jpg$' then
    return false;
  end if;
  if p_kind = 'post' then
    select r.client_id into v_client from public.sm_report_posts q join public.sm_reports r on r.id = q.report_id where q.id = p_id;
  else
    select r.client_id into v_client from public.sm_report_ads a join public.sm_reports r on r.id = a.report_id where a.id = p_id;
  end if;
  if v_client is null or left(p_key, 8 + 36) <> 'private/' || v_client::text then return false; end if;
  perform set_config('adspace.sm_fn', 'on', true);
  if p_kind = 'post' then
    update public.sm_report_posts q set thumb_data = p_key where q.id = p_id and q.thumb_data like 'data:image/%';
  else
    update public.sm_report_ads a set thumb_data = p_key where a.id = p_id and a.thumb_data like 'data:image/%';
  end if;
  get diagnostics v_n = row_count;
  perform set_config('adspace.sm_fn', '', true);
  return v_n > 0;
end $$;
revoke all on function public.sm_report_thumb_set(text, uuid, text) from public, anon, authenticated;

-- END OF A REPORT PICTURE MOVED TO S3 ---------------------------------------

select public.functions_tidy();
