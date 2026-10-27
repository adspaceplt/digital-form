# Sign-in emails

Supabase sends two emails for the portal. Their words are set in the
dashboard, not in this repository: **Authentication → Emails → Templates**.
For each, paste the subject and the whole body below as it stands, then
**Save**. The variables in double braces are filled in by Supabase.

The other templates there (Confirm signup, Reset password, Change email
address, Reauthentication) are never sent: sign-ups are off, nobody holds a
password, and an admin changes a colleague's email on the Team page.

Both bodies are the portal's one email layout, as `supplier-mail` draws it
(`layout()` in `supabase/functions/supplier-mail/index.ts`): the white card
on the light grey page, the ADspace wordmark, the heading (24px, 21 on a
phone), the words in 16px, then the company's registration, address and
the confidentiality line under the card. Every gap is on the design
system's spacing scale (4 to 32), the card's words and the lines under it
share one left edge, and every grey holds 4.5:1 or more. A change to that
layout is made in both places.

| Template | Sent when |
|---|---|
| **Magic Link** | Every sign-in: a colleague signing in to the console, a client signing in to the client portal, and a colleague unlocking My records. It carries the code (`{{ .Token }}`, typed on the page) and the link. |
| **Invite user** | Team → Send invitation, for a colleague or a client contact. |

## Magic Link

Subject:

```
Your ADspace sign-in code
```

Body (HTML):

```html
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light"><meta name="supported-color-schemes" content="light">
<meta name="x-apple-disable-message-reformatting"><title>Your ADspace sign-in code</title>
<style>@media (max-width:600px){.card{padding:24px !important;}.foot{padding:24px 24px 0 !important;}h1{font-size:21px !important;}}</style></head>
<body style="margin:0;padding:0;background:#f5f5f5;-webkit-text-size-adjust:100%;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">Your sign-in code for the ADspace Digital Portal.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f5f5f5;"><tr><td align="center" style="padding:32px 16px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;">
<tr><td class="card" style="background:#ffffff;border-radius:14px;padding:32px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1b1a17;">
<img src="https://mycdn.adspace.me/adspace-brandname.png" alt="ADspace" width="112" style="display:block;width:112px;height:auto;border:0;outline:none;">
<h1 style="margin:24px 0 16px;font-size:24px;line-height:1.3;font-weight:600;letter-spacing:-0.02em;color:#1b1a17;">Your sign-in code</h1>
<p style="margin:0 0 16px;font-size:16px;line-height:1.55;color:#524e47;">Dear Sir or Madam,</p>
<p style="margin:0 0 16px;font-size:16px;line-height:1.55;color:#524e47;">Please enter the following code to sign in to the ADspace Digital Portal:</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f9f9f9;border-radius:10px;margin:4px 0 20px;"><tr><td style="padding:16px 24px;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:28px;line-height:1.2;font-weight:600;letter-spacing:4px;color:#1b1a17;">{{ .Token }}</td></tr></table>
<p style="margin:0 0 16px;font-size:16px;line-height:1.55;color:#524e47;">Alternatively, you may sign in on this device using the button below.</p>
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 24px;"><tr><td style="background:#0071e3;border-radius:10px;"><a href="{{ .ConfirmationURL }}" style="display:inline-block;padding:12px 24px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:16px;font-weight:600;color:#ffffff;text-decoration:none;">Sign in</a></td></tr></table>
<p style="margin:0 0 16px;font-size:16px;line-height:1.55;color:#524e47;">Yours sincerely,<br>ADspace</p>
<p style="margin:8px 0 0;padding-top:16px;border-top:1px solid #ececec;font-size:13px;line-height:1.55;color:#6b6760;">The code and the link may be used once and expire shortly. If you did not request to sign in, please disregard this email; your account remains secure.</p>
</td></tr>
<tr><td class="foot" style="padding:24px 32px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.6;color:#6b6760;">
ADSPACE PLT (202304002162)<br>61-02 Jalan Mutiara Emas 2A, Taman Mount Austin, 81100 Johor Bahru, Johor, Malaysia<br>
(60)18 762 5233 · <a href="https://adspacestudios.com" style="color:#6b6760;text-decoration:none;">adspacestudios.com</a>
<p style="margin:12px 0 0;font-size:11px;line-height:1.5;color:#6b6760;">This email and any attachments are confidential and may be privileged. If you are not the intended recipient, please do not disclose, copy or rely on it; notify the sender and delete it from your system.</p>
</td></tr></table></td></tr></table></body></html>
```

## Invite user

Subject:

```
Your access to the ADspace Digital Portal
```

Body (HTML):

```html
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light"><meta name="supported-color-schemes" content="light">
<meta name="x-apple-disable-message-reformatting"><title>Your access to the ADspace Digital Portal</title>
<style>@media (max-width:600px){.card{padding:24px !important;}.foot{padding:24px 24px 0 !important;}h1{font-size:21px !important;}}</style></head>
<body style="margin:0;padding:0;background:#f5f5f5;-webkit-text-size-adjust:100%;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">You have been given access to the ADspace Digital Portal.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f5f5f5;"><tr><td align="center" style="padding:32px 16px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;">
<tr><td class="card" style="background:#ffffff;border-radius:14px;padding:32px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1b1a17;">
<img src="https://mycdn.adspace.me/adspace-brandname.png" alt="ADspace" width="112" style="display:block;width:112px;height:auto;border:0;outline:none;">
<h1 style="margin:24px 0 16px;font-size:24px;line-height:1.3;font-weight:600;letter-spacing:-0.02em;color:#1b1a17;">Your access to the ADspace Digital Portal</h1>
<p style="margin:0 0 16px;font-size:16px;line-height:1.55;color:#524e47;">Dear {{ .Data.name }},</p>
<p style="margin:0 0 16px;font-size:16px;line-height:1.55;color:#524e47;">ADspace has given you access to the ADspace Digital Portal. Please use the button below to sign in.</p>
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 24px;"><tr><td style="background:#0071e3;border-radius:10px;"><a href="{{ .ConfirmationURL }}" style="display:inline-block;padding:12px 24px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:16px;font-weight:600;color:#ffffff;text-decoration:none;">Sign in</a></td></tr></table>
<p style="margin:0 0 16px;font-size:16px;line-height:1.55;color:#524e47;">Thereafter, you may sign in at any time with a code sent to this email address.</p>
<p style="margin:0 0 16px;font-size:16px;line-height:1.55;color:#524e47;">Yours sincerely,<br>ADspace</p>
<p style="margin:8px 0 0;padding-top:16px;border-top:1px solid #ececec;font-size:13px;line-height:1.55;color:#6b6760;">This link may be used once and expires shortly. If you were not expecting this invitation, please disregard this email.</p>
</td></tr>
<tr><td class="foot" style="padding:24px 32px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.6;color:#6b6760;">
ADSPACE PLT (202304002162)<br>61-02 Jalan Mutiara Emas 2A, Taman Mount Austin, 81100 Johor Bahru, Johor, Malaysia<br>
(60)18 762 5233 · <a href="https://adspacestudios.com" style="color:#6b6760;text-decoration:none;">adspacestudios.com</a>
<p style="margin:12px 0 0;font-size:11px;line-height:1.5;color:#6b6760;">This email and any attachments are confidential and may be privileged. If you are not the intended recipient, please do not disclose, copy or rely on it; notify the sender and delete it from your system.</p>
</td></tr></table></td></tr></table></body></html>
```
