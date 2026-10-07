-- ===========================================================================
-- DELETE AT ITS LEVEL — a row is deleted at the level the page deletes it,
-- never at View.
-- 2026-10-08. Safe to run twice. Rollback at the foot. Mirrored byte for byte
-- in supabase/schema.sql under the same banner; tests/sql.js compares the
-- two. Holds `drop policy`, so it is run in the SQL Editor (CLAUDE.md §3).
--
-- WHAT CHANGED
--   Six tables carried one policy for every action, reading at View and
--   writing at Work. A delete is checked against a policy's USING alone, so
--   anybody who could read a client's service lines, letters and requests,
--   or a draft report's accounts, posts and ads, could delete them through
--   the API, although no page offers it (the user's delete audit,
--   2026-10-07). Each policy is now its four actions, as every other section
--   table's: select at View, insert and update at Work, and delete at Manage
--   for the client's lines, letters and requests (the pages remove them
--   softly or through a function that asks its own level), at Work for a
--   draft report's rows, which the report's own steps remove (a report
--   past its draft still refuses them by trigger).
--
-- ROLLBACK
--   Drop the four policies of each table and restore its single one:
--     create policy client_services_rw on public.client_services for all to authenticated
--       using (public.allowed('clients.services', 'view')) with check (public.allowed('clients.services', 'work'));
--     create policy client_documents_rw on public.client_documents for all to authenticated
--       using (public.allowed('clients.documents', 'view')) with check (public.allowed('clients.documents', 'work'));
--     create policy client_requests_team on public.client_requests for all to authenticated
--       using (public.allowed('clients.requests', 'view')) with check (public.allowed('clients.requests', 'work'));
--     create policy sm_platforms_all on public.sm_report_platforms for all to authenticated
--       using (public.allowed('reports', 'view')) with check (public.allowed('reports', 'work'));
--     create policy sm_posts_all on public.sm_report_posts for all to authenticated
--       using (public.allowed('reports', 'view')) with check (public.allowed('reports', 'work'));
--     create policy sm_ads_all on public.sm_report_ads for all to authenticated
--       using (public.allowed('reports', 'view')) with check (public.allowed('reports', 'work'));
-- ===========================================================================

drop policy if exists client_services_rw on public.client_services;
drop policy if exists client_services_read on public.client_services;
drop policy if exists client_services_write on public.client_services;
drop policy if exists client_services_edit on public.client_services;
drop policy if exists client_services_del on public.client_services;
create policy client_services_read on public.client_services for select to authenticated
  using (public.allowed('clients.services', 'view'));
create policy client_services_write on public.client_services for insert to authenticated
  with check (public.allowed('clients.services', 'work'));
create policy client_services_edit on public.client_services for update to authenticated
  using (public.allowed('clients.services', 'work')) with check (public.allowed('clients.services', 'work'));
create policy client_services_del on public.client_services for delete to authenticated
  using (public.allowed('clients.services', 'manage'));

drop policy if exists client_documents_rw on public.client_documents;
drop policy if exists client_documents_read on public.client_documents;
drop policy if exists client_documents_write on public.client_documents;
drop policy if exists client_documents_edit on public.client_documents;
drop policy if exists client_documents_del on public.client_documents;
create policy client_documents_read on public.client_documents for select to authenticated
  using (public.allowed('clients.documents', 'view'));
create policy client_documents_write on public.client_documents for insert to authenticated
  with check (public.allowed('clients.documents', 'work'));
create policy client_documents_edit on public.client_documents for update to authenticated
  using (public.allowed('clients.documents', 'work')) with check (public.allowed('clients.documents', 'work'));
create policy client_documents_del on public.client_documents for delete to authenticated
  using (public.allowed('clients.documents', 'manage'));

drop policy if exists client_requests_team on public.client_requests;
drop policy if exists client_requests_read on public.client_requests;
drop policy if exists client_requests_write on public.client_requests;
drop policy if exists client_requests_edit on public.client_requests;
drop policy if exists client_requests_del on public.client_requests;
create policy client_requests_read on public.client_requests for select to authenticated
  using (public.allowed('clients.requests', 'view'));
create policy client_requests_write on public.client_requests for insert to authenticated
  with check (public.allowed('clients.requests', 'work'));
create policy client_requests_edit on public.client_requests for update to authenticated
  using (public.allowed('clients.requests', 'work')) with check (public.allowed('clients.requests', 'work'));
create policy client_requests_del on public.client_requests for delete to authenticated
  using (public.allowed('clients.requests', 'manage'));

drop policy if exists sm_platforms_all on public.sm_report_platforms;
drop policy if exists sm_report_platforms_read on public.sm_report_platforms;
drop policy if exists sm_report_platforms_write on public.sm_report_platforms;
drop policy if exists sm_report_platforms_edit on public.sm_report_platforms;
drop policy if exists sm_report_platforms_del on public.sm_report_platforms;
create policy sm_report_platforms_read on public.sm_report_platforms for select to authenticated
  using (public.allowed('reports', 'view'));
create policy sm_report_platforms_write on public.sm_report_platforms for insert to authenticated
  with check (public.allowed('reports', 'work'));
create policy sm_report_platforms_edit on public.sm_report_platforms for update to authenticated
  using (public.allowed('reports', 'work')) with check (public.allowed('reports', 'work'));
create policy sm_report_platforms_del on public.sm_report_platforms for delete to authenticated
  using (public.allowed('reports', 'work'));

drop policy if exists sm_posts_all on public.sm_report_posts;
drop policy if exists sm_report_posts_read on public.sm_report_posts;
drop policy if exists sm_report_posts_write on public.sm_report_posts;
drop policy if exists sm_report_posts_edit on public.sm_report_posts;
drop policy if exists sm_report_posts_del on public.sm_report_posts;
create policy sm_report_posts_read on public.sm_report_posts for select to authenticated
  using (public.allowed('reports', 'view'));
create policy sm_report_posts_write on public.sm_report_posts for insert to authenticated
  with check (public.allowed('reports', 'work'));
create policy sm_report_posts_edit on public.sm_report_posts for update to authenticated
  using (public.allowed('reports', 'work')) with check (public.allowed('reports', 'work'));
create policy sm_report_posts_del on public.sm_report_posts for delete to authenticated
  using (public.allowed('reports', 'work'));

drop policy if exists sm_ads_all on public.sm_report_ads;
drop policy if exists sm_report_ads_read on public.sm_report_ads;
drop policy if exists sm_report_ads_write on public.sm_report_ads;
drop policy if exists sm_report_ads_edit on public.sm_report_ads;
drop policy if exists sm_report_ads_del on public.sm_report_ads;
create policy sm_report_ads_read on public.sm_report_ads for select to authenticated
  using (public.allowed('reports', 'view'));
create policy sm_report_ads_write on public.sm_report_ads for insert to authenticated
  with check (public.allowed('reports', 'work'));
create policy sm_report_ads_edit on public.sm_report_ads for update to authenticated
  using (public.allowed('reports', 'work')) with check (public.allowed('reports', 'work'));
create policy sm_report_ads_del on public.sm_report_ads for delete to authenticated
  using (public.allowed('reports', 'work'));

-- END OF DELETE AT ITS LEVEL ------------------------------------------------
