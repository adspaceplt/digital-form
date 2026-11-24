-- ===========================================================================
-- OFFER CODE TRIES BY THE DAY TYPED (2026-11-24)
-- ===========================================================================
-- WHY: the audit of 2026-11-24 (the user: "fix all except 2").
-- `hiring_doc_wrong_today` summed the tries of codes made today, so the
-- wrong tries typed after midnight on a code made before it were not
-- counted: a code asked for at 11:59pm gave five tries that counted
-- against no day.
--
-- WHAT IT CHANGES
--   * `hiring_doc_wrong_days` (doc, Malaysian day, n; closed to every
--     page): each wrong code is counted on the day it was typed.
--   * `careers_doc_open` counts there; `hiring_doc_wrong_today` reads it.
--     Wrong codes typed today before this file runs are not counted.
--
-- ORDER: this file alone. Safe to run twice.
-- ROLLBACK: run `hiring_doc_wrong_today` and `careers_doc_open` from
-- CAREERS DECIDED AND OFFER CODES again; the table may stay.
-- ===========================================================================

-- OFFER CODE TRIES BY THE DAY TYPED -----------------------------------------

create table if not exists public.hiring_doc_wrong_days (
  doc_id uuid not null references public.hiring_docs(id) on delete cascade,
  day    date not null,
  n      integer not null default 0,
  primary key (doc_id, day)
);
alter table public.hiring_doc_wrong_days enable row level security;
revoke all on public.hiring_doc_wrong_days from public, anon, authenticated;

/* The wrong codes typed for one document this Malaysian day. Internal. */
create or replace function public.hiring_doc_wrong_today(p_doc uuid)
returns integer language sql stable security definer set search_path = public as $$
  select coalesce((select w.n from public.hiring_doc_wrong_days w
                    where w.doc_id = p_doc and w.day = (now() at time zone 'Asia/Kuala_Lumpur')::date), 0)
$$;
revoke all on function public.hiring_doc_wrong_today(uuid) from public, anon, authenticated;

create or replace function public.careers_doc_open(p_key text, p_doc uuid, p_code text, p_device text)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  d public.hiring_docs := public.careers_doc_of(p_key, p_doc);
  s public.hiring_doc_codes;
  v_tok text;
begin
  if d.id is null then return jsonb_build_object('error', 'not_found'); end if;
  perform 1 from public.hiring_docs where id = d.id for update;
  -- Ten wrong codes a document a Malaysian day, whatever code they were
  -- typed against (review 2026-11-24: a new code every hour gave five more).
  if public.hiring_doc_wrong_today(d.id) >= 10 then return jsonb_build_object('error', 'locked-today'); end if;
  select * into s from public.hiring_doc_codes x where x.doc_id = d.id and x.used_at is null
   order by x.created_at desc limit 1 for update;
  if s.id is null then return jsonb_build_object('error', 'no-code'); end if;
  if s.expires_at <= now() then return jsonb_build_object('error', 'code-expired'); end if;
  if s.tries >= 5 then return jsonb_build_object('error', 'locked'); end if;
  if regexp_replace(coalesce(p_code, ''), '\s+', '', 'g') !~ '^[0-9]{6}$'
     or crypt(regexp_replace(p_code, '\s+', '', 'g'), s.code_hash) <> s.code_hash then
    update public.hiring_doc_codes set tries = tries + 1 where id = s.id;
    -- counted on the Malaysian day it was typed, whenever its code was made
    insert into public.hiring_doc_wrong_days as w (doc_id, day, n)
    values (d.id, (now() at time zone 'Asia/Kuala_Lumpur')::date, 1)
    on conflict (doc_id, day) do update set n = w.n + 1;
    return jsonb_build_object('error', 'wrong', 'left', greatest(0, 4 - s.tries));
  end if;
  v_tok := encode(gen_random_bytes(24), 'hex');
  update public.hiring_doc_codes set used_at = now(), view_hash = encode(digest(v_tok, 'sha256'), 'hex'),
    view_until = now() + interval '30 minutes' where id = s.id;
  insert into public.signing_steps (doc_kind, doc_id, step, email, ip, country, device)
  values ('hiring_doc', d.id, 'opened', s.email, nullif(public.request_ip(), ''), nullif(public.request_country(), ''), public.seal_device(p_device));
  return public.careers_doc_json(d) || jsonb_build_object('view', v_tok);
end $$;
revoke all on function public.careers_doc_open(text, uuid, text, text) from public;
grant execute on function public.careers_doc_open(text, uuid, text, text) to anon, authenticated;

-- END OF OFFER CODE TRIES BY THE DAY TYPED ----------------------------------

select public.functions_tidy();
