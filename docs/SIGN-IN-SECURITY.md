# Sign-in security: what to set outside the code

The portal signs people in with Supabase Auth's emailed link or code, on
three screens: the console (`/admin/`), the client portal (`/client/`) and
My performance (the email code). There is no login server of ours to harden.
What protects these screens is set in the Supabase dashboard and in DNS.

The code side is already done:

- The console and the client portal never say whether an email has an
  account. A known and an unknown address both read "If this address is
  registered, a link (and a code) has been sent".
- `portal-login` gives the same answer for every address. **Redeploy it**:
  `supabase functions deploy portal-login` (Verify JWT stays off).
- No page can create an account (`shouldCreateUser: false` everywhere).
- A captcha is wired to every sign-in email. The site key is set, so every
  sign-in carries a Turnstile token; Supabase checks it only once step 3 is done.

Supabase's own sign-in endpoint can still reveal whether an address exists
to somebody who calls it directly. Nothing on our side can stop that. The
rate limits and the captcha below are what make it slow and costly.

## 1. Supabase: Authentication settings

Dashboard → project `hwwuigvdfubuymchsvyx` → **Authentication**.

| Where | Setting | Value |
|---|---|---|
| Sign In / Providers → Email | Allow new users to sign up | **Off** (already off; keep it off) |
| Sign In / Providers → Email | Confirm email | On |
| Sign In / Providers → Email | Email OTP expiration | **600** seconds (10 minutes) |
| Sign In / Providers → Email | Email OTP length | 6 to 8 (the code fields take 6 to 10) |
| Sign In / Providers → Email | Minimum interval between emails per user | **60** seconds |
| Rate Limits | Emails sent per hour | **30** (you can raise this only with custom SMTP, step 4) |
| Rate Limits | Sign-ups and sign-ins per 5 minutes per IP | **20** |
| Rate Limits | Token verifications per 5 minutes per IP | **15** |
| URL Configuration | Site URL | `https://digital.adspace.me` |
| URL Configuration | Redirect URLs | `https://digital.adspace.me/admin/`, `https://digital.adspace.me/client/` |
| Email Templates → Magic Link | Body | Must print `{{ .Token }}` as well as the link (already done for My performance) |

Supabase may rename these settings. If one is missing, look for it under
**Attack Protection** or **Rate Limits**.

## 2. Cloudflare Turnstile: create the widget

1. Cloudflare dashboard → ADspace account → **Turnstile** → **Add widget**.
2. Name: `ADspace Digital Portal sign-in`.
3. Hostnames: `digital.adspace.me`.
4. Widget mode: **Managed**.
5. Copy the **Site key** and the **Secret key**.

**Done 2026-09-26**: the site key is in `js/config.js` (`turnstileSiteKey`).
It is public by design. **Never send the secret key in chat.** It goes only
into Supabase, in step 3.

## 3. Supabase: switch the captcha on, after the site key is live

Do this only after the push carrying the site key shows as deployed. If you
switch it on first, every sign-in is refused until the key is live.

Authentication → **Attack Protection** → **Enable CAPTCHA protection** →
provider **Turnstile** → paste the **secret key** → Save.

Then check all three:

- sign in to `/admin/`;
- send a code from My performance;
- sign in to `/client/` as a test contact.

To undo, switch the captcha off in Supabase. The pages keep working without it.

## 4. Email delivery: SPF, DKIM, DMARC

Sign-in emails that land in spam are a sign-in that fails. Supabase's built-in
sender is rate-limited and sends from a shared domain. For real use:

1. **Custom SMTP.** Authentication → Emails → SMTP Settings. Use a provider
   (for example Resend, Postmark or Amazon SES) and a sender on your own
   domain, such as `no-reply@adspacestudios.com`.
2. **SPF.** The domain has **one** SPF TXT record listing every sender.
   - Google Workspace alone: `v=spf1 include:_spf.google.com ~all`.
   - Add the SMTP provider's include to that same record. Never create a
     second SPF record.
3. **DKIM.** Add the CNAME or TXT records the SMTP provider gives you.
   Confirm the provider shows the domain as verified. Keep Google
   Workspace's own DKIM switched on too.
4. **DMARC.** One TXT record at `_dmarc.adspacestudios.com`:
   - Start with `v=DMARC1; p=none; rua=mailto:dmarc@adspacestudios.com; adkim=s; aspf=s`.
   - Read the reports for two to four weeks.
   - Once every legitimate sender passes, move to `p=quarantine`, then later to `p=reject`.
5. **Test.** Send a sign-in email to a Gmail and an Outlook address. In the
   message headers, confirm `spf=pass`, `dkim=pass` and `dmarc=pass`.

## 5. What each setting protects against

| Risk | Protection |
|---|---|
| Learning who the clients or colleagues are | Neutral pages and `portal-login` (code); the per-IP sign-in limit and the captcha (Supabase) |
| Guessing a code | 10-minute expiry, the per-IP verification limit, codes of 6 to 8 digits |
| Flooding somebody's inbox | Per-user email interval, per-hour email limit, captcha |
| Making accounts | Sign-ups off; no page asks for an account to be created |
| Sign-in mail marked as spam or spoofed | Custom SMTP, SPF, DKIM, DMARC |
