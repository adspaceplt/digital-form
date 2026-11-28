-- ===========================================================================
-- BY WHOM BY ID (2026-11-28)
-- ===========================================================================
-- WHY: restructure release 2b (docs/MAP.md §G; the user through the
-- coordinator, 28 Nov). Every "by whom" column held the colleague's name or
-- address alone (MAP-INVENTORY A.2.5): a renamed colleague, or two of one
-- name, could not be told apart in the record. A "by whom" field keeps the
-- id beside the name it shows (DESIGN.md §7, layer 1).
-- WHAT IT CHANGES
--   * 57 columns, each `{column}_id` (`updated_by_name` → `updated_by_id`)
--     beside its name on 31 tables: uuid, references team_members, on
--     delete set null. Read where the table is read (quotations by its
--     column grants).
--   * `whom_ids()` (trigger `whom_ids`, before insert or update, its pairs
--     as arguments): a name written takes the caller's own id where it is
--     the caller's name or address, never another colleague's; a name kept
--     keeps its id; a name cleared clears it. A client, a creator, a form
--     or the system keeps none.
--   * `colleague_id_of(text)`: the one colleague holding a name or an
--     address, removed ones included, for the backfill alone.
--   * Backfill: each name held by exactly one colleague, or an address.
-- ORDER: this file, then the pages (which read the ids and show the
-- current name). An open tab served before reads the name as it did.
-- ROLLBACK: drop trigger whom_ids on each of the 31 tables; drop function
-- public.whom_ids(); drop function public.colleague_id_of(text). The
-- columns stay. Safe to run twice.

-- BY WHOM BY ID ------------------------------------------------------------

alter table public.ai_draft_limits add column if not exists set_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.announcements add column if not exists created_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.announcements add column if not exists updated_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.app_flags add column if not exists set_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.campaign_deliverables add column if not exists hidden_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.campaign_options add column if not exists changes_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.campaign_options add column if not exists confirmed_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.campaigns add column if not exists created_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.client_document_deletions add column if not exists actor_id uuid
  references public.team_members(id) on delete set null;
alter table public.client_documents add column if not exists issued_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.client_documents add column if not exists verified_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.client_documents add column if not exists voided_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.client_requests add column if not exists decided_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.client_requests add column if not exists recorded_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.client_touches add column if not exists by_whom_id uuid
  references public.team_members(id) on delete set null;
alter table public.creator_earlier_jobs add column if not exists added_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.creator_earlier_jobs add column if not exists removed_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.creator_profile_changes add column if not exists actor_id uuid
  references public.team_members(id) on delete set null;
alter table public.creators add column if not exists created_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.document_deletions add column if not exists actor_id uuid
  references public.team_members(id) on delete set null;
alter table public.documents add column if not exists issued_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.documents add column if not exists shared_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.documents add column if not exists voided_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.handbook_docs add column if not exists created_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.handbook_versions add column if not exists created_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.hiring_docs add column if not exists returned_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.hiring_docs add column if not exists sealed_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.hiring_docs add column if not exists voided_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.hiring_events add column if not exists actor_id uuid
  references public.team_members(id) on delete set null;
alter table public.link_qrs add column if not exists created_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.links add column if not exists created_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.meta_links add column if not exists updated_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.option_posts add column if not exists entered_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.post_versions add column if not exists replaced_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.quotation_refs_kept add column if not exists deleted_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.quotations add column if not exists confirmed_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.quotations add column if not exists details_asked_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.quotations add column if not exists no_contact_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.quotations add column if not exists released_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.quotations add column if not exists removed_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.quotations add column if not exists returned_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.quotations add column if not exists reviewed_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.quotations add column if not exists sealed_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.quotations add column if not exists withdrawn_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.rate_card_text add column if not exists updated_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.rate_card_versions add column if not exists published_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.sm_report_versions add column if not exists file_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.sm_report_versions add column if not exists published_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.sm_report_versions add column if not exists withdrawn_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.sm_reports add column if not exists sent_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.team_notices add column if not exists withdrawn_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.video_script_scenes add column if not exists photo_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.video_script_scenes add column if not exists shot_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.video_scripts add column if not exists updated_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.video_scripts add column if not exists vo_shot_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.wa_outbox add column if not exists created_by_id uuid
  references public.team_members(id) on delete set null;
alter table public.wa_templates add column if not exists set_by_id uuid
  references public.team_members(id) on delete set null;
grant select (confirmed_by_id, details_asked_by_id, no_contact_by_id, released_by_id, removed_by_id, returned_by_id, reviewed_by_id, sealed_by_id, withdrawn_by_id) on table public.quotations to authenticated;

/* The one colleague of a name or an address, removed ones included;
   none where two hold the name. */
create or replace function public.colleague_id_of(p_who text)
returns uuid language sql stable security definer set search_path = public as $$
  select coalesce(
    (select min(t.id::text)::uuid from public.team_members t
      where position('@' in coalesce(p_who, '')) > 0 and lower(t.email) = lower(btrim(p_who)) having count(*) = 1),
    (select min(t.id::text)::uuid from public.team_members t
      where nullif(btrim(coalesce(p_who, '')), '') is not null and position('@' in p_who) = 0
        and lower(btrim(t.name)) = lower(btrim(p_who)) having count(*) = 1))
$$;
revoke all on function public.colleague_id_of(text) from public, anon, authenticated;

/* A "by whom" name written takes the caller's own id; its arguments are
   pairs of the name column and its id column. */
create or replace function public.whom_ids()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  n   jsonb := to_jsonb(new);
  o   jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else '{}'::jsonb end;
  p   jsonb := '{}'::jsonb;
  me  public.team_members;
  got boolean := false;
  i   int := 0;
  v   text;
begin
  while i < tg_nargs loop
    v := nullif(btrim(coalesce(n ->> tg_argv[i], '')), '');
    if tg_op = 'UPDATE' and (n ->> tg_argv[i]) is not distinct from (o ->> tg_argv[i]) then
      null;
    elsif v is null then
      p := p || jsonb_build_object(tg_argv[i + 1], null);
    elsif tg_op = 'INSERT' and (n ->> tg_argv[i + 1]) is not null then
      null;
    else
      if not got then me := public.ops_me(); got := true; end if;
      p := p || jsonb_build_object(tg_argv[i + 1],
        case when me.id is not null and (v is not distinct from btrim(me.name) or lower(v) is not distinct from lower(me.email))
             then me.id end);
    end if;
    i := i + 2;
  end loop;
  if p <> '{}'::jsonb then new := jsonb_populate_record(new, p); end if;
  return new;
end $$;
revoke all on function public.whom_ids() from public, anon, authenticated;

drop trigger if exists whom_ids on public.ai_draft_limits;
create trigger whom_ids before insert or update on public.ai_draft_limits
  for each row execute function public.whom_ids('set_by', 'set_by_id');
drop trigger if exists whom_ids on public.announcements;
create trigger whom_ids before insert or update on public.announcements
  for each row execute function public.whom_ids('created_by', 'created_by_id', 'updated_by', 'updated_by_id');
drop trigger if exists whom_ids on public.app_flags;
create trigger whom_ids before insert or update on public.app_flags
  for each row execute function public.whom_ids('set_by', 'set_by_id');
drop trigger if exists whom_ids on public.campaign_deliverables;
create trigger whom_ids before insert or update on public.campaign_deliverables
  for each row execute function public.whom_ids('hidden_by', 'hidden_by_id');
drop trigger if exists whom_ids on public.campaign_options;
create trigger whom_ids before insert or update on public.campaign_options
  for each row execute function public.whom_ids('changes_by', 'changes_by_id', 'confirmed_by', 'confirmed_by_id');
drop trigger if exists whom_ids on public.campaigns;
create trigger whom_ids before insert or update on public.campaigns
  for each row execute function public.whom_ids('created_by', 'created_by_id');
drop trigger if exists whom_ids on public.client_document_deletions;
create trigger whom_ids before insert or update on public.client_document_deletions
  for each row execute function public.whom_ids('actor', 'actor_id');
drop trigger if exists whom_ids on public.client_documents;
create trigger whom_ids before insert or update on public.client_documents
  for each row execute function public.whom_ids('issued_by', 'issued_by_id', 'verified_by', 'verified_by_id', 'voided_by', 'voided_by_id');
drop trigger if exists whom_ids on public.client_requests;
create trigger whom_ids before insert or update on public.client_requests
  for each row execute function public.whom_ids('decided_by', 'decided_by_id', 'recorded_by', 'recorded_by_id');
drop trigger if exists whom_ids on public.client_touches;
create trigger whom_ids before insert or update on public.client_touches
  for each row execute function public.whom_ids('by_whom', 'by_whom_id');
drop trigger if exists whom_ids on public.creator_earlier_jobs;
create trigger whom_ids before insert or update on public.creator_earlier_jobs
  for each row execute function public.whom_ids('added_by', 'added_by_id', 'removed_by', 'removed_by_id');
drop trigger if exists whom_ids on public.creator_profile_changes;
create trigger whom_ids before insert or update on public.creator_profile_changes
  for each row execute function public.whom_ids('actor', 'actor_id');
drop trigger if exists whom_ids on public.creators;
create trigger whom_ids before insert or update on public.creators
  for each row execute function public.whom_ids('created_by', 'created_by_id');
drop trigger if exists whom_ids on public.document_deletions;
create trigger whom_ids before insert or update on public.document_deletions
  for each row execute function public.whom_ids('actor', 'actor_id');
drop trigger if exists whom_ids on public.documents;
create trigger whom_ids before insert or update on public.documents
  for each row execute function public.whom_ids('issued_by', 'issued_by_id', 'shared_by', 'shared_by_id', 'voided_by', 'voided_by_id');
drop trigger if exists whom_ids on public.handbook_docs;
create trigger whom_ids before insert or update on public.handbook_docs
  for each row execute function public.whom_ids('created_by', 'created_by_id');
drop trigger if exists whom_ids on public.handbook_versions;
create trigger whom_ids before insert or update on public.handbook_versions
  for each row execute function public.whom_ids('created_by', 'created_by_id');
drop trigger if exists whom_ids on public.hiring_docs;
create trigger whom_ids before insert or update on public.hiring_docs
  for each row execute function public.whom_ids('returned_by', 'returned_by_id', 'sealed_by', 'sealed_by_id', 'voided_by', 'voided_by_id');
drop trigger if exists whom_ids on public.hiring_events;
create trigger whom_ids before insert or update on public.hiring_events
  for each row execute function public.whom_ids('actor', 'actor_id');
drop trigger if exists whom_ids on public.link_qrs;
create trigger whom_ids before insert or update on public.link_qrs
  for each row execute function public.whom_ids('created_by', 'created_by_id');
drop trigger if exists whom_ids on public.links;
create trigger whom_ids before insert or update on public.links
  for each row execute function public.whom_ids('created_by', 'created_by_id');
drop trigger if exists whom_ids on public.meta_links;
create trigger whom_ids before insert or update on public.meta_links
  for each row execute function public.whom_ids('updated_by', 'updated_by_id');
drop trigger if exists whom_ids on public.option_posts;
create trigger whom_ids before insert or update on public.option_posts
  for each row execute function public.whom_ids('entered_by', 'entered_by_id');
drop trigger if exists whom_ids on public.post_versions;
create trigger whom_ids before insert or update on public.post_versions
  for each row execute function public.whom_ids('replaced_by', 'replaced_by_id');
drop trigger if exists whom_ids on public.quotation_refs_kept;
create trigger whom_ids before insert or update on public.quotation_refs_kept
  for each row execute function public.whom_ids('deleted_by', 'deleted_by_id');
drop trigger if exists whom_ids on public.quotations;
create trigger whom_ids before insert or update on public.quotations
  for each row execute function public.whom_ids('confirmed_by', 'confirmed_by_id', 'details_asked_by', 'details_asked_by_id', 'no_contact_by', 'no_contact_by_id', 'released_by', 'released_by_id', 'removed_by', 'removed_by_id', 'returned_by', 'returned_by_id', 'reviewed_by', 'reviewed_by_id', 'sealed_by', 'sealed_by_id', 'withdrawn_by', 'withdrawn_by_id');
drop trigger if exists whom_ids on public.rate_card_text;
create trigger whom_ids before insert or update on public.rate_card_text
  for each row execute function public.whom_ids('updated_by', 'updated_by_id');
drop trigger if exists whom_ids on public.rate_card_versions;
create trigger whom_ids before insert or update on public.rate_card_versions
  for each row execute function public.whom_ids('published_by', 'published_by_id');
drop trigger if exists whom_ids on public.sm_report_versions;
create trigger whom_ids before insert or update on public.sm_report_versions
  for each row execute function public.whom_ids('file_by', 'file_by_id', 'published_by', 'published_by_id', 'withdrawn_by', 'withdrawn_by_id');
drop trigger if exists whom_ids on public.sm_reports;
create trigger whom_ids before insert or update on public.sm_reports
  for each row execute function public.whom_ids('sent_by', 'sent_by_id');
drop trigger if exists whom_ids on public.team_notices;
create trigger whom_ids before insert or update on public.team_notices
  for each row execute function public.whom_ids('withdrawn_by', 'withdrawn_by_id');
drop trigger if exists whom_ids on public.video_script_scenes;
create trigger whom_ids before insert or update on public.video_script_scenes
  for each row execute function public.whom_ids('photo_by', 'photo_by_id', 'shot_by', 'shot_by_id');
drop trigger if exists whom_ids on public.video_scripts;
create trigger whom_ids before insert or update on public.video_scripts
  for each row execute function public.whom_ids('updated_by_name', 'updated_by_id', 'vo_shot_by', 'vo_shot_by_id');
drop trigger if exists whom_ids on public.wa_outbox;
create trigger whom_ids before insert or update on public.wa_outbox
  for each row execute function public.whom_ids('created_by', 'created_by_id');
drop trigger if exists whom_ids on public.wa_templates;
create trigger whom_ids before insert or update on public.wa_templates
  for each row execute function public.whom_ids('set_by', 'set_by_id');

/* Backfill: each name or address one colleague holds, with the table's
   own triggers off for it alone (a sealed or published row's guards, its
   updated_at), so the backfill neither is refused nor moves a row's clock. */
do $$
begin
  alter table public.ai_draft_limits disable trigger user;
  update public.ai_draft_limits x set set_by_id = public.colleague_id_of(x.set_by)
   where x.set_by_id is null and nullif(btrim(coalesce(x.set_by, '')), '') is not null;
  alter table public.ai_draft_limits enable trigger user;
  alter table public.announcements disable trigger user;
  update public.announcements x set created_by_id = public.colleague_id_of(x.created_by)
   where x.created_by_id is null and nullif(btrim(coalesce(x.created_by, '')), '') is not null;
  update public.announcements x set updated_by_id = public.colleague_id_of(x.updated_by)
   where x.updated_by_id is null and nullif(btrim(coalesce(x.updated_by, '')), '') is not null;
  alter table public.announcements enable trigger user;
  alter table public.app_flags disable trigger user;
  update public.app_flags x set set_by_id = public.colleague_id_of(x.set_by)
   where x.set_by_id is null and nullif(btrim(coalesce(x.set_by, '')), '') is not null;
  alter table public.app_flags enable trigger user;
  alter table public.campaign_deliverables disable trigger user;
  update public.campaign_deliverables x set hidden_by_id = public.colleague_id_of(x.hidden_by)
   where x.hidden_by_id is null and nullif(btrim(coalesce(x.hidden_by, '')), '') is not null;
  alter table public.campaign_deliverables enable trigger user;
  alter table public.campaign_options disable trigger user;
  update public.campaign_options x set changes_by_id = public.colleague_id_of(x.changes_by)
   where x.changes_by_id is null and nullif(btrim(coalesce(x.changes_by, '')), '') is not null;
  update public.campaign_options x set confirmed_by_id = public.colleague_id_of(x.confirmed_by)
   where x.confirmed_by_id is null and nullif(btrim(coalesce(x.confirmed_by, '')), '') is not null;
  alter table public.campaign_options enable trigger user;
  alter table public.campaigns disable trigger user;
  update public.campaigns x set created_by_id = public.colleague_id_of(x.created_by)
   where x.created_by_id is null and nullif(btrim(coalesce(x.created_by, '')), '') is not null;
  alter table public.campaigns enable trigger user;
  alter table public.client_document_deletions disable trigger user;
  update public.client_document_deletions x set actor_id = public.colleague_id_of(x.actor)
   where x.actor_id is null and nullif(btrim(coalesce(x.actor, '')), '') is not null;
  alter table public.client_document_deletions enable trigger user;
  alter table public.client_documents disable trigger user;
  update public.client_documents x set issued_by_id = public.colleague_id_of(x.issued_by)
   where x.issued_by_id is null and nullif(btrim(coalesce(x.issued_by, '')), '') is not null;
  update public.client_documents x set verified_by_id = public.colleague_id_of(x.verified_by)
   where x.verified_by_id is null and nullif(btrim(coalesce(x.verified_by, '')), '') is not null;
  update public.client_documents x set voided_by_id = public.colleague_id_of(x.voided_by)
   where x.voided_by_id is null and nullif(btrim(coalesce(x.voided_by, '')), '') is not null;
  alter table public.client_documents enable trigger user;
  alter table public.client_requests disable trigger user;
  update public.client_requests x set decided_by_id = public.colleague_id_of(x.decided_by)
   where x.decided_by_id is null and nullif(btrim(coalesce(x.decided_by, '')), '') is not null;
  update public.client_requests x set recorded_by_id = public.colleague_id_of(x.recorded_by)
   where x.recorded_by_id is null and nullif(btrim(coalesce(x.recorded_by, '')), '') is not null;
  alter table public.client_requests enable trigger user;
  alter table public.client_touches disable trigger user;
  update public.client_touches x set by_whom_id = public.colleague_id_of(x.by_whom)
   where x.by_whom_id is null and nullif(btrim(coalesce(x.by_whom, '')), '') is not null;
  alter table public.client_touches enable trigger user;
  alter table public.creator_earlier_jobs disable trigger user;
  update public.creator_earlier_jobs x set added_by_id = public.colleague_id_of(x.added_by)
   where x.added_by_id is null and nullif(btrim(coalesce(x.added_by, '')), '') is not null;
  update public.creator_earlier_jobs x set removed_by_id = public.colleague_id_of(x.removed_by)
   where x.removed_by_id is null and nullif(btrim(coalesce(x.removed_by, '')), '') is not null;
  alter table public.creator_earlier_jobs enable trigger user;
  alter table public.creator_profile_changes disable trigger user;
  update public.creator_profile_changes x set actor_id = public.colleague_id_of(x.actor)
   where x.actor_id is null and nullif(btrim(coalesce(x.actor, '')), '') is not null;
  alter table public.creator_profile_changes enable trigger user;
  alter table public.creators disable trigger user;
  update public.creators x set created_by_id = public.colleague_id_of(x.created_by)
   where x.created_by_id is null and nullif(btrim(coalesce(x.created_by, '')), '') is not null;
  alter table public.creators enable trigger user;
  alter table public.document_deletions disable trigger user;
  update public.document_deletions x set actor_id = public.colleague_id_of(x.actor)
   where x.actor_id is null and nullif(btrim(coalesce(x.actor, '')), '') is not null;
  alter table public.document_deletions enable trigger user;
  alter table public.documents disable trigger user;
  update public.documents x set issued_by_id = public.colleague_id_of(x.issued_by)
   where x.issued_by_id is null and nullif(btrim(coalesce(x.issued_by, '')), '') is not null;
  update public.documents x set shared_by_id = public.colleague_id_of(x.shared_by)
   where x.shared_by_id is null and nullif(btrim(coalesce(x.shared_by, '')), '') is not null;
  update public.documents x set voided_by_id = public.colleague_id_of(x.voided_by)
   where x.voided_by_id is null and nullif(btrim(coalesce(x.voided_by, '')), '') is not null;
  alter table public.documents enable trigger user;
  alter table public.handbook_docs disable trigger user;
  update public.handbook_docs x set created_by_id = public.colleague_id_of(x.created_by)
   where x.created_by_id is null and nullif(btrim(coalesce(x.created_by, '')), '') is not null;
  alter table public.handbook_docs enable trigger user;
  alter table public.handbook_versions disable trigger user;
  update public.handbook_versions x set created_by_id = public.colleague_id_of(x.created_by)
   where x.created_by_id is null and nullif(btrim(coalesce(x.created_by, '')), '') is not null;
  alter table public.handbook_versions enable trigger user;
  alter table public.hiring_docs disable trigger user;
  update public.hiring_docs x set returned_by_id = public.colleague_id_of(x.returned_by)
   where x.returned_by_id is null and nullif(btrim(coalesce(x.returned_by, '')), '') is not null;
  update public.hiring_docs x set sealed_by_id = public.colleague_id_of(x.sealed_by)
   where x.sealed_by_id is null and nullif(btrim(coalesce(x.sealed_by, '')), '') is not null;
  update public.hiring_docs x set voided_by_id = public.colleague_id_of(x.voided_by)
   where x.voided_by_id is null and nullif(btrim(coalesce(x.voided_by, '')), '') is not null;
  alter table public.hiring_docs enable trigger user;
  alter table public.hiring_events disable trigger user;
  update public.hiring_events x set actor_id = public.colleague_id_of(x.actor)
   where x.actor_id is null and nullif(btrim(coalesce(x.actor, '')), '') is not null;
  alter table public.hiring_events enable trigger user;
  alter table public.link_qrs disable trigger user;
  update public.link_qrs x set created_by_id = public.colleague_id_of(x.created_by)
   where x.created_by_id is null and nullif(btrim(coalesce(x.created_by, '')), '') is not null;
  alter table public.link_qrs enable trigger user;
  alter table public.links disable trigger user;
  update public.links x set created_by_id = public.colleague_id_of(x.created_by)
   where x.created_by_id is null and nullif(btrim(coalesce(x.created_by, '')), '') is not null;
  alter table public.links enable trigger user;
  alter table public.meta_links disable trigger user;
  update public.meta_links x set updated_by_id = public.colleague_id_of(x.updated_by)
   where x.updated_by_id is null and nullif(btrim(coalesce(x.updated_by, '')), '') is not null;
  alter table public.meta_links enable trigger user;
  alter table public.option_posts disable trigger user;
  update public.option_posts x set entered_by_id = public.colleague_id_of(x.entered_by)
   where x.entered_by_id is null and nullif(btrim(coalesce(x.entered_by, '')), '') is not null;
  alter table public.option_posts enable trigger user;
  alter table public.post_versions disable trigger user;
  update public.post_versions x set replaced_by_id = public.colleague_id_of(x.replaced_by)
   where x.replaced_by_id is null and nullif(btrim(coalesce(x.replaced_by, '')), '') is not null;
  alter table public.post_versions enable trigger user;
  alter table public.quotation_refs_kept disable trigger user;
  update public.quotation_refs_kept x set deleted_by_id = public.colleague_id_of(x.deleted_by)
   where x.deleted_by_id is null and nullif(btrim(coalesce(x.deleted_by, '')), '') is not null;
  alter table public.quotation_refs_kept enable trigger user;
  alter table public.quotations disable trigger user;
  update public.quotations x set confirmed_by_id = public.colleague_id_of(x.confirmed_by)
   where x.confirmed_by_id is null and nullif(btrim(coalesce(x.confirmed_by, '')), '') is not null;
  update public.quotations x set details_asked_by_id = public.colleague_id_of(x.details_asked_by)
   where x.details_asked_by_id is null and nullif(btrim(coalesce(x.details_asked_by, '')), '') is not null;
  update public.quotations x set no_contact_by_id = public.colleague_id_of(x.no_contact_by)
   where x.no_contact_by_id is null and nullif(btrim(coalesce(x.no_contact_by, '')), '') is not null;
  update public.quotations x set released_by_id = public.colleague_id_of(x.released_by)
   where x.released_by_id is null and nullif(btrim(coalesce(x.released_by, '')), '') is not null;
  update public.quotations x set removed_by_id = public.colleague_id_of(x.removed_by)
   where x.removed_by_id is null and nullif(btrim(coalesce(x.removed_by, '')), '') is not null;
  update public.quotations x set returned_by_id = public.colleague_id_of(x.returned_by)
   where x.returned_by_id is null and nullif(btrim(coalesce(x.returned_by, '')), '') is not null;
  update public.quotations x set reviewed_by_id = public.colleague_id_of(x.reviewed_by)
   where x.reviewed_by_id is null and nullif(btrim(coalesce(x.reviewed_by, '')), '') is not null;
  update public.quotations x set sealed_by_id = public.colleague_id_of(x.sealed_by)
   where x.sealed_by_id is null and nullif(btrim(coalesce(x.sealed_by, '')), '') is not null;
  update public.quotations x set withdrawn_by_id = public.colleague_id_of(x.withdrawn_by)
   where x.withdrawn_by_id is null and nullif(btrim(coalesce(x.withdrawn_by, '')), '') is not null;
  alter table public.quotations enable trigger user;
  alter table public.rate_card_text disable trigger user;
  update public.rate_card_text x set updated_by_id = public.colleague_id_of(x.updated_by)
   where x.updated_by_id is null and nullif(btrim(coalesce(x.updated_by, '')), '') is not null;
  alter table public.rate_card_text enable trigger user;
  alter table public.rate_card_versions disable trigger user;
  update public.rate_card_versions x set published_by_id = public.colleague_id_of(x.published_by)
   where x.published_by_id is null and nullif(btrim(coalesce(x.published_by, '')), '') is not null;
  alter table public.rate_card_versions enable trigger user;
  alter table public.sm_report_versions disable trigger user;
  update public.sm_report_versions x set file_by_id = public.colleague_id_of(x.file_by)
   where x.file_by_id is null and nullif(btrim(coalesce(x.file_by, '')), '') is not null;
  update public.sm_report_versions x set published_by_id = public.colleague_id_of(x.published_by)
   where x.published_by_id is null and nullif(btrim(coalesce(x.published_by, '')), '') is not null;
  update public.sm_report_versions x set withdrawn_by_id = public.colleague_id_of(x.withdrawn_by)
   where x.withdrawn_by_id is null and nullif(btrim(coalesce(x.withdrawn_by, '')), '') is not null;
  alter table public.sm_report_versions enable trigger user;
  alter table public.sm_reports disable trigger user;
  update public.sm_reports x set sent_by_id = public.colleague_id_of(x.sent_by)
   where x.sent_by_id is null and nullif(btrim(coalesce(x.sent_by, '')), '') is not null;
  alter table public.sm_reports enable trigger user;
  alter table public.team_notices disable trigger user;
  update public.team_notices x set withdrawn_by_id = public.colleague_id_of(x.withdrawn_by)
   where x.withdrawn_by_id is null and nullif(btrim(coalesce(x.withdrawn_by, '')), '') is not null;
  alter table public.team_notices enable trigger user;
  alter table public.video_script_scenes disable trigger user;
  update public.video_script_scenes x set photo_by_id = public.colleague_id_of(x.photo_by)
   where x.photo_by_id is null and nullif(btrim(coalesce(x.photo_by, '')), '') is not null;
  update public.video_script_scenes x set shot_by_id = public.colleague_id_of(x.shot_by)
   where x.shot_by_id is null and nullif(btrim(coalesce(x.shot_by, '')), '') is not null;
  alter table public.video_script_scenes enable trigger user;
  alter table public.video_scripts disable trigger user;
  update public.video_scripts x set updated_by_id = public.colleague_id_of(x.updated_by_name)
   where x.updated_by_id is null and nullif(btrim(coalesce(x.updated_by_name, '')), '') is not null;
  update public.video_scripts x set vo_shot_by_id = public.colleague_id_of(x.vo_shot_by)
   where x.vo_shot_by_id is null and nullif(btrim(coalesce(x.vo_shot_by, '')), '') is not null;
  alter table public.video_scripts enable trigger user;
  alter table public.wa_outbox disable trigger user;
  update public.wa_outbox x set created_by_id = public.colleague_id_of(x.created_by)
   where x.created_by_id is null and nullif(btrim(coalesce(x.created_by, '')), '') is not null;
  alter table public.wa_outbox enable trigger user;
  alter table public.wa_templates disable trigger user;
  update public.wa_templates x set set_by_id = public.colleague_id_of(x.set_by)
   where x.set_by_id is null and nullif(btrim(coalesce(x.set_by, '')), '') is not null;
  alter table public.wa_templates enable trigger user;
end $$;

-- END OF BY WHOM BY ID --------------------------------------------------------

select public.functions_tidy();
