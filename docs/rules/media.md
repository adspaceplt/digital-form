<!-- triggers: js/media.js supabase/functions/media-pass -->
# Media: the video player and the media pass (`js/media.js`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-22 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- `js/media.js` (`ADspaceMedia.tag(url, attrs)`, `attach(video, url)`) is
  every video player: it names the H.264 copy `name.web.mp4` first (typed
  MP4) and the original after, so a browser plays the copy once it exists
  and the original until then. Never `<video src>` for an uploaded file.
  A thumbnail of a video is `ADspaceMedia.still(url)`, its first frame
  (`#t=0.1`; iPhone Safari draws a bare video blank until it plays): a
  console row, and the selection page's post rows (the user, 2026-10-10).
  It also holds the media pass (`ADspaceMedia.pass(proof)`, 2026-10-03):
  with `ADSPACE_CONFIG.s3.privateMedia` on, a page that has proved its link
  (`{review}`, `{campaign}` with the passcode), a creator's code
  (`{creator}`) or a sign-in (`{}`: a colleague, or a client contact with
  live portal access, the client portal asking before it draws; 2026-10-08)
  asks `media-pass` for CloudFront's three
  signed cookies before it draws a file, set on
  `mediaCookieDomain` (adspace.me) for twelve hours and asked again under two
  left (load, return to the tab). A pass is held to the folders its caller
  may see (audit F3, 2026-10-10): `passes`, one policy a folder, each set on
  that folder's own cookie path so the browser sends it there alone: the
  review link its client's `content/{clientId}/`, the selection link that and
  each booking's `content/creator/{optionId}/`, a creator their bookings'
  drafts alone, a client's contact each client they hold access at, a
  colleague the whole of `content/` (path `/content/`), only while
  `is_team()` answers for them as the caller (active is not enough: held
  overseas, or access passed before the expiry run; audit 2026-10-29). A client page's pass
  takes away a root pass left by an earlier page, and is fresh only for the
  proof it was asked with (`adspace-media-for`). Every pass keeps the folders
  it set (`adspace-media-paths`, this browser) and the next pass takes them
  away: CloudFront refuses a file sent two passes, which a client's link
  opened beside the console left (2026-10-12); a file refused on a folder
  another page left a pass on loads again once it is taken away
  (`ADspaceMedia.renew`). A colleague's pass is never taken away by a client
  page: a client page opened while a colleague's pass is live (the team
  previewing a link in the console's browser) sets no pass of its own and
  draws on the colleague's, and the console takes away every folder a client
  page left each time it asks, fresh or not (2026-10-15, the second outage:
  the fix of 2026-10-12 covered the client page first, never the console
  first; `tests/mediapass.js` holds both orders). Add assets' check that the CDN serves a stored
  file reads it with the pass, asked again once; with the pass on, a file
  S3 took is never refused by that check. An answer in the earlier
  shape (one pass over `content/`, no `passes`) is set on the root as before,
  so a page served before `media-pass` is deployed keeps its media. A file under `content/` that fails asks
  again once and reloads (a video at its second), the page's own `onerror`
  held until the answer; a `.web.mp4` copy not made yet never asks. Stored
  addresses never change. A refused or slow pass (6s) never holds a page.
  Signing out takes the pass with it (`ADspaceMedia.forget()`: the three
  cookies on the root, content/ and every remembered folder, and the
  pass's marks): the console's Sign out, which also removes the browser's
  `adspace-*-notes:`, `adspace-*-inputs:` and `adspace_drafts_` keys, the
  client portal's, and the creator's Forget this device (`{ client: true }`,
  leaving a colleague's live pass alone).
