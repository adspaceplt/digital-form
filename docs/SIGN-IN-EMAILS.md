# Sign-in emails

Supabase sends the portal's sign-in emails. Their words are set in the
dashboard, not in this repository: **Authentication → Emails → Templates**.
For each template, paste the subject and the whole body below as it stands,
then **Save**. The variables in double braces are filled in by Supabase.

Every body is the portal's one email layout, as `supplier-mail` draws it
(`layout()` in `supabase/functions/supplier-mail/index.ts`): the white card
on the light grey page, the ADspace wordmark, the heading, the words, then
the company's registration, address and the confidentiality line under the
card. A change to that layout is made in both places.

| Template | Sent when |
|---|---|
| **Magic Link** | A colleague signs in to the console, a client signs in to the client portal, or a colleague unlocks My records. It must print `{{ .Token }}` as well as the link. |
| **Invite user** | Team → Send invitation, for a colleague or a client contact. |
| **Confirm signup** | Not sent today (sign-ups are off); kept in the same layout should it ever be. |
| **Change email address** | Not sent today (an admin changes a colleague's email on the Team page). |
| **Reset password** | Not sent today (nobody signs in with a password). |
| **Reauthentication** | Not sent today; Supabase asks it only before a sensitive change, with a code. |

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
<style>@media (max-width:600px){.card{padding:28px 20px !important;}}</style></head>
<body style="margin:0;padding:0;background:#f5f5f5;-webkit-text-size-adjust:100%;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">Your sign-in code for the ADspace Digital Portal.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f5f5f5;"><tr><td align="center" style="padding:32px 16px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;">
<tr><td class="card" style="background:#ffffff;border-radius:14px;padding:36px 40px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1b1a17;">
<img src="https://mycdn.adspace.me/adspace-brandname.png" alt="ADspace" width="112" style="display:block;width:112px;height:auto;border:0;outline:none;">
<h1 style="margin:28px 0 12px;font-size:21px;line-height:1.3;font-weight:600;letter-spacing:-0.02em;color:#1b1a17;">Your sign-in code</h1>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">Dear Sir or Madam,</p>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">Please enter the following code to sign in to the ADspace Digital Portal:</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f9f9f9;border-radius:10px;margin:4px 0 20px;"><tr><td align="center" style="padding:18px 14px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:28px;line-height:1.2;font-weight:600;letter-spacing:6px;color:#1b1a17;">{{ .Token }}</td></tr></table>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">Alternatively, you may sign in on this device using the button below.</p>
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 24px;"><tr><td style="background:#0071e3;border-radius:10px;"><a href="{{ .ConfirmationURL }}" style="display:inline-block;padding:12px 24px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;">Sign in</a></td></tr></table>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">Yours sincerely,<br>ADspace</p>
<p style="margin:12px 0 0;padding-top:20px;border-top:1px solid #ececec;font-size:13px;line-height:1.55;color:#6b6760;">The code and the link may be used once and expire shortly. If you did not request to sign in, please disregard this email; your account remains secure.</p>
</td></tr>
<tr><td style="padding:20px 8px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.6;color:#6b6760;">
ADSPACE PLT (202304002162)<br>61-02 Jalan Mutiara Emas 2A, Taman Mount Austin, 81100 Johor Bahru, Johor, Malaysia<br>
(60)18 762 5233 · <a href="https://adspacestudios.com" style="color:#6b6760;text-decoration:none;">adspacestudios.com</a>
<p style="margin:12px 0 0;font-size:11px;line-height:1.5;color:#8e8a84;">This email and any attachments are confidential and may be privileged. If you are not the intended recipient, please do not disclose, copy or rely on it; notify the sender and delete it from your system.</p>
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
<style>@media (max-width:600px){.card{padding:28px 20px !important;}}</style></head>
<body style="margin:0;padding:0;background:#f5f5f5;-webkit-text-size-adjust:100%;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">You have been given access to the ADspace Digital Portal.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f5f5f5;"><tr><td align="center" style="padding:32px 16px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;">
<tr><td class="card" style="background:#ffffff;border-radius:14px;padding:36px 40px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1b1a17;">
<img src="https://mycdn.adspace.me/adspace-brandname.png" alt="ADspace" width="112" style="display:block;width:112px;height:auto;border:0;outline:none;">
<h1 style="margin:28px 0 12px;font-size:21px;line-height:1.3;font-weight:600;letter-spacing:-0.02em;color:#1b1a17;">Your access to the ADspace Digital Portal</h1>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">Dear {{ .Data.name }},</p>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">ADspace has given you access to the ADspace Digital Portal. Please use the button below to sign in.</p>
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 24px;"><tr><td style="background:#0071e3;border-radius:10px;"><a href="{{ .ConfirmationURL }}" style="display:inline-block;padding:12px 24px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;">Sign in</a></td></tr></table>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">Thereafter, you may sign in at any time with a code sent to this email address.</p>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">Yours sincerely,<br>ADspace</p>
<p style="margin:12px 0 0;padding-top:20px;border-top:1px solid #ececec;font-size:13px;line-height:1.55;color:#6b6760;">This link may be used once and expires shortly. If you were not expecting this invitation, please disregard this email.</p>
</td></tr>
<tr><td style="padding:20px 8px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.6;color:#6b6760;">
ADSPACE PLT (202304002162)<br>61-02 Jalan Mutiara Emas 2A, Taman Mount Austin, 81100 Johor Bahru, Johor, Malaysia<br>
(60)18 762 5233 · <a href="https://adspacestudios.com" style="color:#6b6760;text-decoration:none;">adspacestudios.com</a>
<p style="margin:12px 0 0;font-size:11px;line-height:1.5;color:#8e8a84;">This email and any attachments are confidential and may be privileged. If you are not the intended recipient, please do not disclose, copy or rely on it; notify the sender and delete it from your system.</p>
</td></tr></table></td></tr></table></body></html>
```

## Confirm signup

Subject:

```
Confirm your email address
```

Body (HTML):

```html
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light"><meta name="supported-color-schemes" content="light">
<meta name="x-apple-disable-message-reformatting"><title>Confirm your email address</title>
<style>@media (max-width:600px){.card{padding:28px 20px !important;}}</style></head>
<body style="margin:0;padding:0;background:#f5f5f5;-webkit-text-size-adjust:100%;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">Confirm your email address for the ADspace Digital Portal.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f5f5f5;"><tr><td align="center" style="padding:32px 16px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;">
<tr><td class="card" style="background:#ffffff;border-radius:14px;padding:36px 40px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1b1a17;">
<img src="https://mycdn.adspace.me/adspace-brandname.png" alt="ADspace" width="112" style="display:block;width:112px;height:auto;border:0;outline:none;">
<h1 style="margin:28px 0 12px;font-size:21px;line-height:1.3;font-weight:600;letter-spacing:-0.02em;color:#1b1a17;">Confirm your email address</h1>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">Dear Sir or Madam,</p>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">Please confirm your email address to complete your registration with the ADspace Digital Portal.</p>
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 24px;"><tr><td style="background:#0071e3;border-radius:10px;"><a href="{{ .ConfirmationURL }}" style="display:inline-block;padding:12px 24px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;">Confirm email address</a></td></tr></table>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">Yours sincerely,<br>ADspace</p>
<p style="margin:12px 0 0;padding-top:20px;border-top:1px solid #ececec;font-size:13px;line-height:1.55;color:#6b6760;">If you did not register with ADspace, please disregard this email.</p>
</td></tr>
<tr><td style="padding:20px 8px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.6;color:#6b6760;">
ADSPACE PLT (202304002162)<br>61-02 Jalan Mutiara Emas 2A, Taman Mount Austin, 81100 Johor Bahru, Johor, Malaysia<br>
(60)18 762 5233 · <a href="https://adspacestudios.com" style="color:#6b6760;text-decoration:none;">adspacestudios.com</a>
<p style="margin:12px 0 0;font-size:11px;line-height:1.5;color:#8e8a84;">This email and any attachments are confidential and may be privileged. If you are not the intended recipient, please do not disclose, copy or rely on it; notify the sender and delete it from your system.</p>
</td></tr></table></td></tr></table></body></html>
```

## Change email address

Subject:

```
Confirm your new email address
```

Body (HTML):

```html
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light"><meta name="supported-color-schemes" content="light">
<meta name="x-apple-disable-message-reformatting"><title>Confirm your new email address</title>
<style>@media (max-width:600px){.card{padding:28px 20px !important;}}</style></head>
<body style="margin:0;padding:0;background:#f5f5f5;-webkit-text-size-adjust:100%;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">Confirm the change of your email address.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f5f5f5;"><tr><td align="center" style="padding:32px 16px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;">
<tr><td class="card" style="background:#ffffff;border-radius:14px;padding:36px 40px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1b1a17;">
<img src="https://mycdn.adspace.me/adspace-brandname.png" alt="ADspace" width="112" style="display:block;width:112px;height:auto;border:0;outline:none;">
<h1 style="margin:28px 0 12px;font-size:21px;line-height:1.3;font-weight:600;letter-spacing:-0.02em;color:#1b1a17;">Confirm your new email address</h1>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">Dear Sir or Madam,</p>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">A request was made to change the email address for your ADspace Digital Portal account from {{ .Email }} to {{ .NewEmail }}. Please confirm the change using the button below.</p>
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 24px;"><tr><td style="background:#0071e3;border-radius:10px;"><a href="{{ .ConfirmationURL }}" style="display:inline-block;padding:12px 24px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;">Confirm change</a></td></tr></table>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">Yours sincerely,<br>ADspace</p>
<p style="margin:12px 0 0;padding-top:20px;border-top:1px solid #ececec;font-size:13px;line-height:1.55;color:#6b6760;">If you did not request this change, please disregard this email and contact ADspace at advertise@adspacestudios.com.</p>
</td></tr>
<tr><td style="padding:20px 8px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.6;color:#6b6760;">
ADSPACE PLT (202304002162)<br>61-02 Jalan Mutiara Emas 2A, Taman Mount Austin, 81100 Johor Bahru, Johor, Malaysia<br>
(60)18 762 5233 · <a href="https://adspacestudios.com" style="color:#6b6760;text-decoration:none;">adspacestudios.com</a>
<p style="margin:12px 0 0;font-size:11px;line-height:1.5;color:#8e8a84;">This email and any attachments are confidential and may be privileged. If you are not the intended recipient, please do not disclose, copy or rely on it; notify the sender and delete it from your system.</p>
</td></tr></table></td></tr></table></body></html>
```

## Reset password

Subject:

```
Reset your password
```

Body (HTML):

```html
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light"><meta name="supported-color-schemes" content="light">
<meta name="x-apple-disable-message-reformatting"><title>Reset your password</title>
<style>@media (max-width:600px){.card{padding:28px 20px !important;}}</style></head>
<body style="margin:0;padding:0;background:#f5f5f5;-webkit-text-size-adjust:100%;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">Reset the password for your ADspace Digital Portal account.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f5f5f5;"><tr><td align="center" style="padding:32px 16px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;">
<tr><td class="card" style="background:#ffffff;border-radius:14px;padding:36px 40px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1b1a17;">
<img src="https://mycdn.adspace.me/adspace-brandname.png" alt="ADspace" width="112" style="display:block;width:112px;height:auto;border:0;outline:none;">
<h1 style="margin:28px 0 12px;font-size:21px;line-height:1.3;font-weight:600;letter-spacing:-0.02em;color:#1b1a17;">Reset your password</h1>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">Dear Sir or Madam,</p>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">A request was made to reset the password for your ADspace Digital Portal account. Please use the button below to choose a new password.</p>
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 24px;"><tr><td style="background:#0071e3;border-radius:10px;"><a href="{{ .ConfirmationURL }}" style="display:inline-block;padding:12px 24px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;">Reset password</a></td></tr></table>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">Yours sincerely,<br>ADspace</p>
<p style="margin:12px 0 0;padding-top:20px;border-top:1px solid #ececec;font-size:13px;line-height:1.55;color:#6b6760;">If you did not request a password reset, please disregard this email; your account remains secure.</p>
</td></tr>
<tr><td style="padding:20px 8px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.6;color:#6b6760;">
ADSPACE PLT (202304002162)<br>61-02 Jalan Mutiara Emas 2A, Taman Mount Austin, 81100 Johor Bahru, Johor, Malaysia<br>
(60)18 762 5233 · <a href="https://adspacestudios.com" style="color:#6b6760;text-decoration:none;">adspacestudios.com</a>
<p style="margin:12px 0 0;font-size:11px;line-height:1.5;color:#8e8a84;">This email and any attachments are confidential and may be privileged. If you are not the intended recipient, please do not disclose, copy or rely on it; notify the sender and delete it from your system.</p>
</td></tr></table></td></tr></table></body></html>
```

## Reauthentication

Subject:

```
Your ADspace verification code
```

Body (HTML):

```html
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light"><meta name="supported-color-schemes" content="light">
<meta name="x-apple-disable-message-reformatting"><title>Your ADspace verification code</title>
<style>@media (max-width:600px){.card{padding:28px 20px !important;}}</style></head>
<body style="margin:0;padding:0;background:#f5f5f5;-webkit-text-size-adjust:100%;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">Your verification code for the ADspace Digital Portal.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f5f5f5;"><tr><td align="center" style="padding:32px 16px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;">
<tr><td class="card" style="background:#ffffff;border-radius:14px;padding:36px 40px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1b1a17;">
<img src="https://mycdn.adspace.me/adspace-brandname.png" alt="ADspace" width="112" style="display:block;width:112px;height:auto;border:0;outline:none;">
<h1 style="margin:28px 0 12px;font-size:21px;line-height:1.3;font-weight:600;letter-spacing:-0.02em;color:#1b1a17;">Your verification code</h1>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">Dear Sir or Madam,</p>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">Please enter the following code to confirm this action in the ADspace Digital Portal:</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f9f9f9;border-radius:10px;margin:4px 0 20px;"><tr><td align="center" style="padding:18px 14px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:28px;line-height:1.2;font-weight:600;letter-spacing:6px;color:#1b1a17;">{{ .Token }}</td></tr></table>
<p style="margin:0 0 16px;font-size:15px;line-height:1.55;color:#524e47;">Yours sincerely,<br>ADspace</p>
<p style="margin:12px 0 0;padding-top:20px;border-top:1px solid #ececec;font-size:13px;line-height:1.55;color:#6b6760;">The code may be used once and expires shortly. If you did not request it, please disregard this email.</p>
</td></tr>
<tr><td style="padding:20px 8px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.6;color:#6b6760;">
ADSPACE PLT (202304002162)<br>61-02 Jalan Mutiara Emas 2A, Taman Mount Austin, 81100 Johor Bahru, Johor, Malaysia<br>
(60)18 762 5233 · <a href="https://adspacestudios.com" style="color:#6b6760;text-decoration:none;">adspacestudios.com</a>
<p style="margin:12px 0 0;font-size:11px;line-height:1.5;color:#8e8a84;">This email and any attachments are confidential and may be privileged. If you are not the intended recipient, please do not disclose, copy or rely on it; notify the sender and delete it from your system.</p>
</td></tr></table></td></tr></table></body></html>
```
