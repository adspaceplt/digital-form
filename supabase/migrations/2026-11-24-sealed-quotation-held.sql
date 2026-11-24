-- ===========================================================================
-- SEALED QUOTATION HELD (2026-11-24)
-- ===========================================================================
-- WHY: the code review of 2026-11-24 (release A3). A quotation's sealed
-- copy kept whatever hash the browser declared, and was drawn in the cover
-- words, agency name and Service Terms address of the day it was sealed,
-- never those it was signed under.
--
-- WHAT CHANGED
--   * `quotations.seal_pending` and `quotation_seal_intent(id, key, sha)`
--     (the service role's, asked by sign-upload once it has checked the
--     colleague): the key signed for the sealed copy and the SHA-256 signed
--     into its PUT (`x-amz-checksum-sha256`, so S3 refuses any other body).
--     `quotation_seal` files only that key and that hash (`bad-sha`).
--   * `quotations.signed_words`: the Quotation Cover's words (title,
--     salutation, closing, message) kept by trigger
--     (`quotations_words_at_signing`) whenever the quotation is signed;
--     `quotation_words_keep(id, agency, terms_url)` (Clients: Quotations at
--     Work, in scope) keeps the agency's name and Service Terms address
--     once, at submit, never after sealing. The sealed copy is drawn from
--     them. Quotations signed and not yet sealed keep today's cover as
--     their own from this release.
--
-- ORDER: this file (connector), then sign-upload, then the pages. Between
-- this file and sign-upload no copy is sealed (the page draws it plain and
-- seals at the next Download). Safe to run twice.
-- ROLLBACK: restate `quotation_seal` from its last definition before this
-- banner; the trigger, the functions and the columns may stay.
-- ===========================================================================

alter table public.quotations add column if not exists seal_pending jsonb;
alter table public.quotations add column if not exists signed_words jsonb;
grant select (signed_words) on table public.quotations to authenticated;

/* The Quotation Cover's words as they stand when the quotation is signed. */
create or replace function public.quotation_words_at_signing()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.signed_at is not null and new.signed_at is distinct from old.signed_at then
    new.signed_words := coalesce(new.signed_words, '{}'::jsonb) - 'cover' || jsonb_build_object('cover',
      (select jsonb_build_object('title', d.title, 'salutation', d.salutation, 'closing', d.closing, 'body_en', d.body_en)
         from public.doc_types d where d.id = 'quote_cover'));
  end if;
  return new;
end $$;
revoke all on function public.quotation_words_at_signing() from public, anon, authenticated;
create or replace trigger quotations_words_at_signing before update of signed_at on public.quotations
  for each row execute function public.quotation_words_at_signing();

-- Those signed and not yet sealed keep today's cover as their own.
update public.quotations q
   set signed_words = jsonb_build_object('cover', (select jsonb_build_object('title', d.title, 'salutation', d.salutation,
         'closing', d.closing, 'body_en', d.body_en) from public.doc_types d where d.id = 'quote_cover'))
 where q.signed_at is not null and q.seal_key is null and q.signed_words is null;

/* The agency's name and Service Terms address the quotation was signed
   under, kept once (the colleague's page at submit). */
create or replace function public.quotation_words_keep(p_id uuid, p_agency text, p_terms_url text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'work') then return jsonb_build_object('error', 'not-found'); end if;
  if q.signed_at is null then return jsonb_build_object('error', 'not-signed'); end if;
  if q.seal_key is not null or coalesce(q.signed_words, '{}'::jsonb) ? 'agency' then return jsonb_build_object('ok', true, 'same', true); end if;
  if coalesce(btrim(p_agency), '') !~ '^.{1,80}$'
     or (p_terms_url is not null and btrim(p_terms_url) !~ '^[A-Za-z0-9./:_?=&%-]{3,200}$') then
    return jsonb_build_object('error', 'bad-request');
  end if;
  update public.quotations set signed_words = coalesce(signed_words, '{}'::jsonb)
         || jsonb_build_object('agency', btrim(p_agency), 'terms_url', nullif(btrim(coalesce(p_terms_url, '')), ''))
   where id = q.id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_words_keep(uuid, text, text) from public, anon;
grant execute on function public.quotation_words_keep(uuid, text, text) to authenticated;

/* The sealed copy's key and hash, as sign-upload signed them (the service
   role's: sign-upload asks it once it has checked the colleague). */
create or replace function public.quotation_seal_intent(p_id uuid, p_key text, p_sha text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare q public.quotations;
begin
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null then return jsonb_build_object('error', 'not-found'); end if;
  if q.reviewed_at is null then return jsonb_build_object('error', 'not-reviewed'); end if;
  if q.seal_key is not null then return jsonb_build_object('error', 'sealed'); end if;
  if coalesce(p_key, '') !~ ('^private/' || q.client_id::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.pdf$')
     or coalesce(p_sha, '') !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('error', 'bad-request');
  end if;
  update public.quotations set seal_pending = jsonb_build_object('key', p_key, 'sha', p_sha, 'at', now()) where id = q.id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.quotation_seal_intent(uuid, text, text) from public, anon, authenticated;
grant execute on function public.quotation_seal_intent(uuid, text, text) to service_role;

create or replace function public.quotation_seal(p_id uuid, p_key text, p_sha text, p_pages_sha text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  me public.team_members := public.ops_me();
  q  public.quotations;
begin
  if me.id is null or not public.allowed('clients.quotes', 'work') then return jsonb_build_object('error', 'denied'); end if;
  select * into q from public.quotations x where x.id = p_id for update;
  if q.id is null or not public.client_scope_ok('client', q.client_id, 'work') then
    return jsonb_build_object('error', 'not-found');
  end if;
  if q.reviewed_at is null then return jsonb_build_object('error', 'not-reviewed'); end if;
  if q.seal_key is not null then return jsonb_build_object('ok', true, 'kept', true, 'sha', q.seal_sha); end if;
  if coalesce(p_key, '') !~ ('^private/' || q.client_id::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.pdf$') then
    return jsonb_build_object('error', 'bad-key');
  end if;
  if coalesce(p_sha, '') !~ '^[0-9a-f]{64}$' or coalesce(p_pages_sha, '') !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('error', 'bad-sha');
  end if;
  -- The file S3 holds is the one its hash was signed for (2026-11-24).
  if q.seal_pending is null or q.seal_pending->>'key' is distinct from p_key or q.seal_pending->>'sha' is distinct from p_sha then
    return jsonb_build_object('error', 'bad-sha');
  end if;
  update public.quotations
     set seal_key = p_key, seal_sha = p_sha, seal_pages_sha = p_pages_sha, sealed_at = now(), sealed_by = me.name, seal_pending = null
   where id = q.id;
  insert into public.activity_log (actor, action, subject, detail)
  values (me.name, 'client.quotation', q.brand,
          q.ref || ' · signed copy sealed · SHA-256 ' || left(p_sha, 4) || '…' || right(p_sha, 4));
  return jsonb_build_object('ok', true, 'sha', p_sha);
end $$;
revoke all on function public.quotation_seal(uuid, text, text, text) from public, anon;
grant execute on function public.quotation_seal(uuid, text, text, text) to authenticated;

-- END OF SEALED QUOTATION HELD ----------------------------------------------

select public.functions_tidy();
