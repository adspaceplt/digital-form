# Content Review Portal

A client review portal running on the existing site at `digital.adspace.me`.
You upload the creative and captions, the client opens one link, sees each post inside a
realistic platform mockup, and approves it or tells you what to change.

Branding is ADspace throughout. The client's company name appears as a small line in the
header, not as their own branded site.

## The two pages

| Page | Who uses it |
| --- | --- |
| `digital.adspace.me/admin/` | Your team |
| `digital.adspace.me/review/?k=<their-token>` | The client |

## Look before you set anything up

Open **`digital.adspace.me/review/`**. With no Supabase project connected it loads sample
content in demo mode. Nothing saves, which is the point at this stage.

## Setup, about ten minutes, done once

You only need to do this once, ever. If it feels technical, it is the only technical part.

**1. Create the project.** Sign up at supabase.com, create a project, choose **Singapore**
as the region so pages load fast for Malaysia and Singapore clients.

**2. Run the schema.** Dashboard → SQL Editor → New query. Open `supabase/schema.sql` from
this repo, paste the whole thing in, click Run.

**3. Create the storage bucket.** Dashboard → Storage → New bucket. Name it exactly
`content` and tick **Public bucket**. Then run `supabase/schema.sql` once more so the
storage rules attach to it.

**4. Lock sign in to your team.** Dashboard → Authentication → Providers → Email. Turn
**Confirm email** on and **Allow new users to sign up** off. Add each team member under
Authentication → Users. Only those addresses can open `/admin/`.

**5. Point Supabase at your site.** Dashboard → Authentication → URL Configuration.

| Field | Value |
| --- | --- |
| Site URL | `https://digital.adspace.me` |
| Redirect URLs | `https://digital.adspace.me/**` |

Do not skip this. Supabase ships with `http://localhost:3000` as the Site URL, and it
silently ignores any redirect that is not on the allow list. If you skip it, the sign in
email arrives fine but the link drops you on a localhost error page.

**6. Connect the site.** Dashboard → Project Settings → API. Copy the Project URL and the
`anon public` key into `js/config.js`:

```js
window.ADSPACE_CONFIG = {
  supabaseUrl: 'https://xxxxxxxx.supabase.co',
  supabaseAnonKey: 'eyJhbGciOi...',
  ...
};
```

Commit and push. GitHub Pages redeploys in about a minute.

The anon key is meant to be public. Every table denies anonymous access, and clients only
reach their own content through the token-checked functions in the schema. Never put the
`service_role` key in this repo.

## Day to day

1. Open `digital.adspace.me/admin/`. Enter your email, click the link we send, you are in.
2. **Add a client** once per client. Only the name is required.
3. On the client page, hit **New content set**. It suggests the current month.
4. **Drop your files in.** We read each file and work out the placement for you.
   A 9:16 video becomes Reels, a 9:16 image becomes a Story, a 4:5 or square image becomes
   a feed post. If we guess wrong, change it in the dropdown next to the file.
5. Write the caption under each one. Add a Chinese caption if the client needs it.
6. Click **Add to this set**.
7. When the whole set is ready, click **Send to client**. Until you do, the client sees
   nothing. We will warn you if any post is still missing a caption.
8. **Copy link** or **Send on WhatsApp** to get it to them.

Dropped several images at once? A bar appears asking whether they are separate posts or
slides of one carousel. One click either way.

## What the client sees

- ADspace branding, with their company name in the header line
- Every set you have sent them, newest first, so past months stay available
- Each post inside its real platform frame, with the full caption underneath and a
  Copy caption button
- Filters for format and for set, so they can look at only the Reels, or only March
- **Approve** or **Request changes** on each post, with a required note on changes
- **View on phone** QR code, worth using for Reels and Stories
- **Save as PDF** for circulating internally

Their answers come straight back into `/admin/`, shown against each post.

## Links and access

Client links look like `digital.adspace.me/review/?k=8f2a9c1b4e6d`. The token is random
and permanent, so one link per client covers every month you ever send them. You never
type it, the admin page hands you Copy link and Send on WhatsApp.

It is a private link, not a login. Anyone the client forwards it to can open it, so treat
it as semi-public. For accounts where that matters, set an **Access code** when creating
the client and send that separately. Both pages carry `noindex`, so they stay out of search.

## Things worth knowing

- **Approvals are a record, not a lock.** Anyone with the link can approve. It settles
  "we never agreed to this", it is not a legal signature.
- **Video size.** See the section below. Supabase caps single uploads at 50 MB on the free
  plan and that cap cannot be raised on free.
- **Deleting a post** removes it from the client view but leaves the file in storage.
  Clear those from Dashboard → Storage occasionally.

## Videos over 50 MB

Supabase refuses any single file above **50 MB** on the free plan, and that ceiling cannot
be lifted without upgrading. Three ways round it, in the order we would try them.

### 1. Export a review copy, not the master

This is the real fix and it is what agencies do anyway. Nobody needs a ProRes master to
say yes to a Reel. A 30 second vertical video exported properly lands around 15 to 20 MB,
well inside the limit.

| Setting | Value |
| --- | --- |
| Format | H.264 (MP4) |
| Resolution | 1080 x 1920 |
| Bitrate | Target 5 Mbps, VBR 1 pass |
| Audio | AAC, 128 kbps |

In Premiere or Media Encoder, do not use "Match Source High Bitrate", it exports at three
times what you need. Set the target bitrate by hand. In HandBrake, the "Fast 1080p30"
preset at RF 24 gets you there in one click. CapCut exports are usually fine already.

Keep the master in your own archive. The portal is for approval, not delivery.

### 2. Paste a link instead of uploading

Under the drop zone there is a field for a video link. Put the file on
`mycdn.adspace.me` and paste the direct URL. The portal reads the dimensions off the link
and treats it exactly like an uploaded file. No size limit at all, because the file never
touches Supabase.

The link has to point straight at the file, the way `https://mycdn.adspace.me/reel.mp4`
does. A Google Drive or Dropbox share page will not work, those return a web page rather
than the video itself.

### 3. Upgrade Supabase

The Pro plan (around 25 US dollars a month, check current pricing) lets you raise the
limit under Dashboard → Storage → Settings and gives you 100 GB of storage. Worth it once
you are running several clients and the free 1 GB starts filling up. If you do upgrade,
change `maxUploadMB` in `js/config.js` to match whatever you set there, otherwise the
portal will keep refusing files at 50 MB.

## If something goes wrong

**The sign in link opens a localhost error page.**
Step 5 was skipped or the URL does not match. Set Site URL to `https://digital.adspace.me`
and add `https://digital.adspace.me/**` to Redirect URLs, then request a new link. The old
email will not work, magic links are single use.

**The sign in email never arrives.**
Check spam first. Supabase's built in email has a low hourly limit, so if you have been
testing repeatedly it will throttle you. Wait an hour, or connect your own SMTP under
Authentication → Emails.

**"Not connected yet" on /admin/.**
`js/config.js` still has blank keys, or the change has not deployed. GitHub Pages takes
about a minute after a push.

**The client link shows "Link not found".**
The client was deleted, or the token was edited by hand. Open the client in `/admin/` and
copy the link again.

**A client says they see nothing.**
The set is still a draft. Open it and click **Send to client**.

**I switched tabs and lost my place.**
Fixed. The address bar now remembers which client and set you are in, and uploads waiting
to be added are kept on your machine until you add or discard them. If you land back on
the client list, you were signed out rather than reset.

**A video will not upload.**
It is over 50 MB. See the section above. Quickest route is to export a review copy at
1080p and 5 Mbps, or paste a link to the file on your own CDN.

## Bigger files

To lift the 50 MB limit, uploads can go to the ADspace S3 bucket instead of Supabase.
Setup is in `docs/S3-UPLOAD-SETUP.md` and needs nothing installed on your machine.

## What to build next

In the order it would pay off:

1. Email or WhatsApp alert when a client approves or requests changes, so you are not
   refreshing admin to find out
2. Revision history, so version 2 sits beside version 1 instead of replacing it, and you
   can show a client how many rounds they have used
3. Scheduled publish date per post, shown to the client as a content calendar
4. Comment threads, if the single note on changes turns out to be too thin
