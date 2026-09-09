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
| `digital.adspace.me/review/<their-link>` | The client |

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

**5. Connect the site.** Dashboard → Project Settings → API. Copy the Project URL and the
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

Client links look like `digital.adspace.me/review/8f2a9c1b4e6d`. No file extensions, no
query strings. The token is random and permanent, so one link per client covers every
month you ever send them.

It is a private link, not a login. Anyone the client forwards it to can open it, so treat
it as semi-public. For accounts where that matters, set an **Access code** when creating
the client and send that separately. Both pages carry `noindex`, so they stay out of search.

## Things worth knowing

- **Approvals are a record, not a lock.** Anyone with the link can approve. It settles
  "we never agreed to this", it is not a legal signature.
- **Video size.** Supabase free tier gives 1 GB. Compress Reels before uploading. 1080p at
  a sensible bitrate is plenty for review.
- **Deleting a post** removes it from the client view but leaves the file in storage.
  Clear those from Dashboard → Storage occasionally.

## How the clean links work

GitHub Pages cannot route `/review/<token>` on its own, so `404.html` catches that path,
hands the token to the review page, and the pretty URL is restored in the address bar.
The client never sees anything odd. If you ever restructure the site, keep that snippet at
the top of `404.html`.

## What to build next

In the order it would pay off:

1. Email or WhatsApp alert when a client approves or requests changes, so you are not
   refreshing admin to find out
2. Revision history, so version 2 sits beside version 1 instead of replacing it, and you
   can show a client how many rounds they have used
3. Scheduled publish date per post, shown to the client as a content calendar
4. Comment threads, if the single note on changes turns out to be too thin
