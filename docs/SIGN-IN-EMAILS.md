# Sign-in emails

Supabase sends two emails for the portal. Their words are set in the
dashboard, not in this repository: **Authentication → Emails → Templates**
(Supabase may call it Email Templates). Paste each subject and body below
as it stands, then **Save**. Nothing else changes: the variables in double
braces are filled in by Supabase.

| Template | Sent when |
|---|---|
| **Magic Link** | A colleague signs in to the console, a client signs in to the client portal, or a colleague unlocks My records. It must print `{{ .Token }}` (the code typed on the page) as well as the link. |
| **Invite user** | Team → Send invitation, for a colleague or a client contact. |

Confirm signup, Reset password and Change email address are not used by
the portal (sign-ups are off, nobody holds a password, and an admin changes
a colleague's email on the Team page).

## Magic Link

Subject:

```
Your ADspace sign-in code
```

Body (HTML):

```html
<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:15px;line-height:1.55;color:#1b1a17;max-width:520px">
  <p>Dear Sir or Madam,</p>
  <p>Please use the following code to sign in to the ADspace Digital Portal:</p>
  <p style="font-size:26px;font-weight:600;letter-spacing:4px;margin:20px 0">{{ .Token }}</p>
  <p>Alternatively, you may sign in on this device using the button below.</p>
  <p style="margin:20px 0"><a href="{{ .ConfirmationURL }}" style="display:inline-block;background:#0071e3;color:#ffffff;text-decoration:none;padding:10px 20px;border-radius:10px;font-weight:600">Sign in</a></p>
  <p>The code and the link may be used once and expire shortly. If you did not request to sign in, please disregard this email; your account remains secure.</p>
  <p>Yours sincerely,<br>ADspace</p>
  <p style="font-size:12px;color:#6b6760">ADSPACE PLT · advertise@adspacestudios.com · adspacestudios.com</p>
</div>
```

## Invite user

Subject:

```
Your access to the ADspace Digital Portal
```

Body (HTML):

```html
<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:15px;line-height:1.55;color:#1b1a17;max-width:520px">
  <p>Dear {{ .Data.name }},</p>
  <p>ADspace has given you access to the ADspace Digital Portal. Please use the button below to sign in.</p>
  <p style="margin:20px 0"><a href="{{ .ConfirmationURL }}" style="display:inline-block;background:#0071e3;color:#ffffff;text-decoration:none;padding:10px 20px;border-radius:10px;font-weight:600">Sign in</a></p>
  <p>The link may be used once and expires shortly. Thereafter, you may sign in at any time with a code sent to this email address. If you were not expecting this invitation, please disregard this email.</p>
  <p>Yours sincerely,<br>ADspace</p>
  <p style="font-size:12px;color:#6b6760">ADSPACE PLT · advertise@adspacestudios.com · adspacestudios.com</p>
</div>
```
