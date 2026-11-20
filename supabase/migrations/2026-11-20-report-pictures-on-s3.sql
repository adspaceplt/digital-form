-- ===========================================================================
-- REPORT PICTURES ON S3 (2026-11-20)
-- ===========================================================================
-- WHY (the user, 2026-11-20: "the total is only 500mb", then "Ok move to
-- s3", choosing S3 with GET added to the bucket's CORS rule)
--   A Social Media Report's post and ad pictures were kept as data in the
--   database (`thumb_data`, a 320px JPEG as a data URL, about 33 KB each) and
--   copied whole into every published version's snapshot: about 45 MB of
--   the database's 95 MB on 2026-11-20 and most of its growth.
--
-- WHAT IT CHANGES
--   * `sm_report_posts.sm_posts_thumb` and `sm_report_ads.sm_ads_thumb`
--     take, beside a data URL (the rows from before, until they are moved),
--     the key of a picture kept on S3: `private/{client}/thumbs/{id}.jpg`
--     (sign-upload's `thumb` purpose writes there). The snapshot functions
--     copy `thumb_data` into `thumb_url` as before, so a version published
--     from now holds the key, never the picture.
--   * `sm_report_thumbs(p_report, p_keys)`: which of the keys asked the
--     caller may read, for sign-download to sign: a colleague at Reports or
--     Clients View whose client scope reaches the report, any key the
--     report's rows or versions name; the client's portal contact, the keys
--     a live version's snapshot names. Every key under the report's own
--     client's folder; never more than 400 asked.
--   * `sm_report_thumb_versions(p_limit)` (the service role alone): the
--     versions whose snapshot still holds a data URL, for the move.
--   The create table bands of 2026-09-25 hold the narrower checks inline;
--   a re-run never adds them again (the tables exist), so the widening is
--   dropped and added here on every run, valid over every row.
--
-- ORDER: GET added to the bucket's CORS (the user), this file, sign-upload
-- and sign-download deployed, then the pages; then `report-thumbs-move`
-- once, to move the pictures already held (docs/S3-STORAGE.md). An open
-- page from before keeps writing data URLs, which this check still takes.
-- Safe to run twice. Rollback: put the two checks back as data URLs alone
-- (only once no row holds a key) and drop `sm_report_thumbs`.
-- ===========================================================================

alter table public.sm_report_posts drop constraint if exists sm_posts_thumb;
alter table public.sm_report_posts add constraint sm_posts_thumb check (thumb_data is null
  or (thumb_data like 'data:image/%' and length(thumb_data) <= 300000)
  or thumb_data ~ '^private/[0-9a-f-]{36}/thumbs/[0-9a-f-]{36}\.jpg$');
alter table public.sm_report_ads drop constraint if exists sm_ads_thumb;
alter table public.sm_report_ads add constraint sm_ads_thumb check (thumb_data is null
  or (thumb_data like 'data:image/%' and length(thumb_data) <= 300000)
  or thumb_data ~ '^private/[0-9a-f-]{36}/thumbs/[0-9a-f-]{36}\.jpg$');

create or replace function public.sm_report_thumbs(p_report uuid, p_keys text[])
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_client uuid;
  v_pre    text;
  v_ok     text[];
begin
  if auth.jwt() ->> 'email' is null then return jsonb_build_object('error', 'not-signed-in'); end if;
  if coalesce(array_length(p_keys, 1), 0) = 0 or array_length(p_keys, 1) > 400 then
    return jsonb_build_object('error', 'bad-keys');
  end if;
  select r.client_id into v_client from public.sm_reports r where r.id = p_report;
  if v_client is null then return jsonb_build_object('error', 'not-found'); end if;
  v_pre := 'private/' || v_client::text || '/thumbs/';
  if public.is_team() then
    if not (public.allowed('reports', 'view') or public.allowed('clients', 'view'))
       or not public.client_seen(v_client, 'view') then
      return jsonb_build_object('error', 'not-found');
    end if;
    select coalesce(array_agg(distinct k), '{}') into v_ok
      from unnest(p_keys) k
     where left(k, length(v_pre)) = v_pre
       and k ~ '^private/[0-9a-f-]{36}/thumbs/[0-9a-f-]{36}\.jpg$'
       and (exists (select 1 from public.sm_report_posts q where q.report_id = p_report and q.thumb_data = k)
         or exists (select 1 from public.sm_report_ads a where a.report_id = p_report and a.thumb_data = k)
         or exists (select 1 from public.sm_report_versions v
                      where v.report_id = p_report and strpos(v.snapshot::text, '"' || k || '"') > 0));
  elsif v_client in (select public.portal_clients()) then
    select coalesce(array_agg(distinct k), '{}') into v_ok
      from unnest(p_keys) k
     where left(k, length(v_pre)) = v_pre
       and k ~ '^private/[0-9a-f-]{36}/thumbs/[0-9a-f-]{36}\.jpg$'
       and exists (select 1 from public.sm_report_versions v
                    where v.report_id = p_report and v.withdrawn_at is null and v.published_at is not null
                      and strpos(v.snapshot::text, '"' || k || '"') > 0);
  else
    return jsonb_build_object('error', 'not-found');
  end if;
  return jsonb_build_object('client', v_client, 'keys', to_jsonb(v_ok));
end $$;
revoke all on function public.sm_report_thumbs(uuid, text[]) from public, anon, authenticated;
grant execute on function public.sm_report_thumbs(uuid, text[]) to authenticated;

/* The versions whose snapshot still holds a picture as a data URL, for
   `report-thumbs-move` alone (the service role): a few at a time and how
   many are left. */
create or replace function public.sm_report_thumb_versions(p_limit integer default 10)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'ids', coalesce((select jsonb_agg(x.id) from (select v.id from public.sm_report_versions v
                       where strpos(v.snapshot::text, '"thumb_url": "data:image/') > 0
                       order by v.published_at limit greatest(1, least(coalesce(p_limit, 10), 50))) x), '[]'::jsonb),
    'left', (select count(*) from public.sm_report_versions v where strpos(v.snapshot::text, '"thumb_url": "data:image/') > 0))
$$;
revoke all on function public.sm_report_thumb_versions(integer) from public, anon, authenticated;

-- END OF REPORT PICTURES ON S3 -----------------------------------------------

select public.functions_tidy();
