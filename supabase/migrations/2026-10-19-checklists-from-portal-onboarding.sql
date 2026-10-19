-- ===========================================================================
-- CHECKLISTS FROM PORTAL ONBOARDING — the Dashboard asks for the checklists
-- of clients onboarded in the portal alone.
-- 2026-10-19. Safe to run twice. Rollback at the foot. Mirrored byte for
-- byte in supabase/schema.sql under the same banner; tests/sql.js compares
-- the two.
--
-- WHAT CHANGED (the user, 2026-10-19, of Needs attention listing Brew
-- Garten's and Star Living's checklists at 1,092 days: "These shouldnt be
-- inside … since we previously did manually")
--   `client_checklists_due()` lists an Active client's checklist not signed
--   only where the checklist was started in the portal, or the client first
--   became Active on or after 15 Oct 2026 (Malaysia), the day the checklists
--   came to the portal. A client onboarded before then was checked on paper
--   and is not asked again. Everything else it answers is unchanged.
--
-- ROLLBACK
--   Run client_checklists_due from the CLIENT CHECKLISTS section of the
--   schema again (the function before this file).
-- ===========================================================================

create or replace function public.client_checklists_due()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when (public.ops_me()).id is null or not public.allowed('clients', 'view') then '[]'::jsonb else
    coalesce((select jsonb_agg(jsonb_build_object('client_id', c.id, 'name', c.name, 'slug', c.slug, 'owner', c.owner,
              'kind', k.kind, 'status', coalesce(r.status, 'open'), 'started', r.id is not null,
              'since', coalesce(c.stage_since, c.created_at)) order by coalesce(c.stage_since, c.created_at))
       from public.clients c
       cross join (values ('onboarding'), ('pre_ads')) k(kind)
       left join public.client_checklists r on r.client_id = c.id and r.kind = k.kind
      where c.stage = 'active'
        and coalesce(r.status, 'open') <> 'signed'
        and (r.id is not null
             or (select min((e->>'at')::timestamptz) from jsonb_array_elements(coalesce(c.stage_log, '[]'::jsonb)) e
                  where e->>'stage' = 'active' and e->>'at' is not null)
                >= ('2026-10-15'::date)::timestamp at time zone 'Asia/Kuala_Lumpur')
        and public.client_scope_ok('client', c.id, 'view')
        and not exists (select 1 from public.ops_engagement_checks x join public.ops_engagements e on e.id = x.engagement_id
                         where e.client_id = c.id and x.key = k.kind and x.state = 'na')), '[]'::jsonb) end
$$;
revoke all on function public.client_checklists_due() from public, anon;
grant execute on function public.client_checklists_due() to authenticated;

-- END OF CHECKLISTS FROM PORTAL ONBOARDING ----------------------------------
select public.functions_tidy();
