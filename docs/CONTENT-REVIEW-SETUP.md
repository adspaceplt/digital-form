# Content Review Portal — setup

A client-facing review portal running on the existing static site at `digital.adspace.me`.
The team uploads creative and captions, the client opens one permanent link, sees each post
inside a realistic platform mockup, and approves it or requests changes.

No server to maintain. Supabase handles files, database and team sign in. Hosting stays on
GitHub Pages exactly as it is today.

## What is in the box

| File | What it does |
| --- | --- |
| `review.html` | The client page. One link per client, opened with `?k=<token>` |
| `admin.html` | Team page. Create clients, create content drops, upload creative, write captions |
| `js/config.js` | The only file you edit to connect Supabase |
| `js/mockups.js` | Draws the Instagram, Facebook, TikTok and XiaoHongShu frames |
| `js/api.js` | Talks to Supabase, or serves demo content when nothing is connected |
| `css/portal.css` | All styling |
| `supabase/schema.sql` | Tables, security rules and the two client-facing functions |
| `demo/` | Sample content so the portal works before Supabase is connected |

## See it before you set anything up

Open `https://digital.adspace.me/review.html`. With no Supabase project connected it loads
sample content in demo mode. Nothing is saved, which is the point at this stage.

## Setup, about ten minutes

### 1. Create the Supabase project
Sign up at supabase.com, create a project, pick Singapore as the region so the client pages
load fast in Malaysia and Singapore.

### 2. Run the schema
Dashboard → SQL Editor → New query. Paste the whole of `supabase/schema.sql` and run it.

### 3. Create the storage bucket
Dashboard → Storage → New bucket. Name it exactly `content` and tick **Public bucket**.
Then run `supabase/schema.sql` once more so the storage policies attach to it.

File paths are random UUIDs, so the URLs cannot be guessed, but treat anything in this
bucket as shareable if the link leaks.

### 4. Lock sign in to your team
Dashboard → Authentication → Providers → Email. Turn **Confirm email** on and
**Allow new users to sign up** off. Then add each team member under Authentication → Users.
Only those addresses can reach `admin.html`.

### 5. Connect the site
Dashboard → Project Settings → API. Copy the Project URL and the `anon public` key into
`js/config.js`:

```js
window.ADSPACE_CONFIG = {
  supabaseUrl: 'https://xxxxxxxx.supabase.co',
  supabaseAnonKey: 'eyJhbGciOi...',
  ...
};
```

Commit and push. GitHub Pages redeploys in about a minute.

The anon key is meant to be public. Every table denies anonymous access, and clients only
reach their own data through the token-checked functions in the schema. Never put the
`service_role` key in this repo.

## Day to day

1. Open `digital.adspace.me/admin.html` and sign in.
2. **Add client** once per client. Copy their link and send it. It never changes.
3. **Create drop** for each round, for example "March 2026 Content".
4. Add posts: choose platform and format, upload the creative, paste the caption.
   The preview on the right updates as you type.
5. Tick **visible to client** on the drop when it is ready. Until then they see nothing.
6. The client approves or requests changes per post. Refresh admin to see where things stand.

Multiple files on one post become carousel slides or story frames, in upload order.

## What the client sees

- Their brand name and every drop you have published, newest first
- Each post inside its real platform frame, with the caption in full underneath
- Filters for format and for drop, so they can look at only the Reels, or only March
- **Approve** or **Request changes**, with a required note on changes
- **View on phone** QR code, worth using for Reels and Stories
- **Save as PDF** for anyone who needs to circulate it internally

## Access and privacy

The link is a long random token. Anyone the client forwards it to can open it, so treat
it as semi-public. For accounts where that matters, set an **Access code** when creating
the client and send it separately. Both pages carry `noindex`, so they stay out of search.

## Things worth knowing

- **Approvals are a record, not a lock.** Anyone with the link can approve. It settles
  "we never agreed to this" conversations, it is not a legal signature.
- **Video files.** Supabase free tier gives 1 GB of storage. Compress Reels before
  uploading, 1080p at a sensible bitrate is plenty for review.
- **Deleting a post** removes it from the client view but leaves the file in storage.
  Clear those out from Dashboard → Storage when you do housekeeping.

## Extending it later

The pieces most likely worth adding next, in the order they would pay off:

1. Email or WhatsApp notification when a client approves or requests changes
2. Revision history, so version 2 sits next to version 1 instead of replacing it
3. Scheduled publish date per post, shown to the client as a content calendar
4. Comment threads per post, if the required note on changes turns out to be too thin
