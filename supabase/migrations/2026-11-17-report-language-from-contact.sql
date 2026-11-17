-- 2026-11-17-report-language-from-contact.sql
-- Safe to run twice. Rollback: drop trigger sm_reports_lang_default on
-- public.sm_reports; drop function public.sm_reports_lang_default();
-- REPORT LANGUAGE FROM THE MAIN CONTACT ---------------------------------------
-- 2026-11-17, the user: a client whose main contact prefers 中文 had its
-- report's Write with AI open on English. New report set the language from
-- the page; a report started from My Work's report task did not. Every new
-- report now takes the main contact's language here, whichever way it is
-- made. The draft language stays the team's to change afterwards.
create or replace function public.sm_reports_lang_default()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.client_contacts cc
              where cc.client_id = new.client_id and cc.is_primary
                and cc.archived_at is null and cc.lang = 'zh') then
    new.lang := 'zh';
  end if;
  return new;
end $$;
revoke all on function public.sm_reports_lang_default() from public, anon, authenticated;

drop trigger if exists sm_reports_lang_default on public.sm_reports;
create trigger sm_reports_lang_default before insert on public.sm_reports
  for each row execute function public.sm_reports_lang_default();

-- END OF REPORT LANGUAGE FROM THE MAIN CONTACT --------------------------------

select public.functions_tidy();
