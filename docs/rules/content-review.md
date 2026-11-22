<!-- triggers: review/ js/review.js js/mockups.js js/media.js supabase/functions/caption-draft -->
# Content Review (`review/`, `js/review.js`, `js/mockups.js`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-17 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- The client's gallery (`.shell-review`, 1480px, cards from 300px) runs four
  posts across on a desk from about 1400px and three at 1280.
- Mockups per platform:
  - Instagram feed 4:5 (1080×1350); Reels and Stories 9:16 at the cover ratio;
  - TikTok;
  - Facebook feed and carousel (2 side by side; 4 as 2×2; 5 as 2 over 3 with
    `+N` greyed on the fifth);
  - rednote.
- On the mockup:
  - The handle, never the client name.
  - The logo fills the circle, with no border or shadow.
  - A placeholder avatar is an illuminance gradient.
  - Instagram's own concave send dart.
  - Save at the far right (`.mk-act-save`).
  - `more` rides the clamped line over a fade.
  - `br + br` collapses while clamped.
  - Likes, caption and comments sit 4px apart.
  - A story draws no caption on its frame; its words are under Copywriting.
- A video waits on black under one play button (`.mk-play`, `js/mockups.js`)
  and plays in its card; the browser's own bar arrives once it plays. A press
  on the button or the video never opens the canvas (moving a video that has
  just started stops it: Edge spun, Safari opened the canvas); Close carries
  a playing video on in its card.
- The cover image card names itself once, in its head, and ends under its
  decision (`.is-cover`).
- A card's head is the original white head with no platform colour (the
  user, 2026-10-03), one line at every width (the title gives way first),
  and gives the shape as a ratio (`ADspaceMockups.ratio`: the file's size,
  within 3% of a common ratio reads as it), never pixels.
- A reel and its cover are one card (`.cardpair`): the reel's head, Reel and
  Cover as a view strip with each half's state in its tab, then the half on
  show. The cover names its reel (`posts.cover_for`, no foreign key; sent by
  `get_review_feed`, `2026-10-03-reel-cover-pairs.sql`); each half is still its
  own post, decision, round and canvas, the stage strip counts posts, and a
  pair opens on a half that matches the stage, and both tabs always show
  their half (`showHalf`; the user, 2026-10-03: a reel with changes
  requested opened on nothing). A pairing is not a revision.
  Add assets pairs a cover with a video by file name (`launch.mp4`,
  `launch-cover.jpg`), every name first, else the first free video after it
  (every pair the team has made has its video right after its cover), else
  the nearest before it, as a Cover for choice kept by hand. On the set page
  a video and its covers are one linked card (`.saved-pair`: a shaded frame,
  the video's row then the cover's, a line drawn from picture to picture;
  each row keeps its own state, ⋯ and notes; shown while either half is in
  the chosen stage, the other faded); a cover's ⋯ Pair with video changes
  or clears it (`post.edited`), offering only videos no other cover holds.
  A cover waits while it names no video the set holds (one whose video was
  deleted waits again). A video is named by its number in the set (shown on
  its row) and its title, else its caption's first words, else its file.
  While a cover waits, a line over the posts counts them with Pair covers
  (`#pairNote`, Work) opening `#pairSheet`: one card a cover, the cover and
  the proposed video (the same order rule; a video a paired cover holds is
  neither proposed nor offered) side by side at 9:16, the video playable,
  its select and a Pair tick;
  the foot reads Pair n, writes only ticked cards naming a video, refuses
  one video for two covers, files `Covers paired: n`, and draws Undo over
  the posts (`Covers unpaired: n`).
- The client's page opens on the client portal's name card (`#rvHead`: mark,
  name, handle and post count, `N to review` counted at load); the bar no
  longer names the client. The creator selection page opens on the same card
  (`#campHead`: the client's mark, the campaign, the client).
- A post is revised in place (`2026-09-30-post-revisions.sql`): a change to
  its file, copy or title after the client decided on its round is the next
  round (trigger `posts_revision`; `reviews.round` stamped by
  `reviews_round`), and the round it replaces is kept whole in
  `post_versions` for the team. Before any decision an edit is a
  correction. `get_review_feed` sends the round on show, the decision on it
  only, and `asked` (the request on the round before); never an earlier
  round's file or copy. The client's card heads the request it answers
  `Changes requested by {name} · {date}` (`.reask-head`), the note on its
  own line under it; never "Revision N" or "You asked" (the team's words).
- Both sides list posts under the stage strip (`.tabrow`: Pending,
  Changes requested, Approved, All, each with its count). The client's
  (`#stageStrip`) opens on Pending and is counted at load: a decision
  repaints its card but moves it only on the next load. The console's
  (`#postStages`, drawn once a decision exists) opens on Changes requested.
  On a phone the strip is the column's width, its tabs sharing it and
  Changes requested reading Changes (`.tab-short`).
- The caption is edited where it is read: Edit text beside Copy text at
  the heading's right (`.copyacts`, two small tonal buttons with their
  glyphs; `.copy-pen` hidden the moment a post is approved, shown in every
  other state, never only after a reload) turns each caption into a field in
  place and opens Request changes under it for a note and the name. While
  a request is open Approve and Request changes step away
  (`.approve.is-requesting`), so Cancel and Send request are the only acts;
  a failed send keeps the request and the edit open. A
  request takes a note or a caption edit, sent only where changed and kept
  as `reviews.suggested_caption[_zh]`; the console shows it as Suggested
  caption with Accept caption (the next round), whose Undo puts back the
  round kept in `post_versions` (`review_caption_undo`, refused `moved`
  once that round is decided or its file, title or caption changed since;
  2026-10-15). The noun is caption, never
  copy. The console's Edit replaces the file, uploaded at Save.
- A request not yet answered is changed with Edit request (the Request
  changes button while one stands): it reopens with the note and the
  client's own caption edit (`get_review_feed` sends `suggested_caption[_zh]`
  on the standing decision), and sending again replaces it. Approve over a
  standing request arms first in place (Approve as it is, "Approving
  withdraws your request for changes."), and the console keeps the request
  it replaced in sight (Earlier request). The decision pair and the
  request's Cancel / Send request are equal halves. While the request is
  edited its standing note steps away; leaving it (Cancel, or the armed
  Approve disarming) repaints the decision line, never blanks it. The note
  and the caption fields grow with their words to 60% of the screen.
- Confirm internally (`2026-10-01-review-confirm-internally.sql`) is the
  team's approval on the client's word, in a post's ⋯ in the console only
  (Content Review sets at Work, a published set, not already approved):
  `review_confirm` writes a `reviews` row with `source` team under the
  colleague's name, filed `review.approved` … confirmed internally. The
  console row reads Confirmed internally by {colleague}; the client's page
  reads Confirmed by {client name} on {date} (`by_team`), never the
  colleague; the feed sends a team decision with no reviewer, so the
  colleague's name never reaches the client. Its way back is Revert
  confirmation (`review_revert_confirm`, never asks, filed
  `review.unconfirmed`, Confirmation reverted): the row is kept with
  `undone_at`, only a team approval can be reverted, and the post falls
  back to the decision before it. Every read of `reviews` skips undone
  rows. A client's own approval is asked again with Request re-approval.
  Confirm internally shows only on a published set. The post ⋯ items carry
  their parts (`review.sets:work`; Delete `review.sets:manage`).
  `review.approved` reads Approved (the actor says who).
- A decision is on the version on show (`2026-10-10-approval-as-seen.sql`,
  audit F2): `posts.content_version` moves with the file, copy or title
  (trigger `posts_content_version`, never set by a write), `get_review_feed`
  sends it as `version`, and the page decides through
  `submit_review_seen(… p_version)`, which refuses a post changed since
  (`changed`: "This post was updated after the page opened. Please refresh to
  review the latest version.", with Refresh; a request for changes so
  refused is kept in the tab and reopened after it, its caption edit only
  where the caption stands; 2026-10-27, RVP-3) and keeps what was decided on in
  `reviews.seen`; `ADspaceAPI.submitReview` sends every decision through
  `submit_review_seen` alone (one with no version is refused `changed`),
  and `submit_review` is internal, closed to every browser (audit
  2026-11-15). A revision's `asked` names no colleague: a team request
  reads `by_team`.
- Approve needs a name. Approved reads outlined, with Request changes hidden.
  - The Copywriting label, and the copy control at the top.
  - No Save as PDF.
  - og:title `{client name} Content Review Portal by ADspace`, on `review/`
    only.
- The Review Canvas moves the card's own blocks and puts them back; there is
  one decision control. Prev/next, the arrow keys, Escape and a sideways
  swipe on a phone work. The head is the name (its size under it on a
  phone), then Previous, `n of N` and Next as one group, then Close at the
  right edge, the three filled tonal buttons. Below 860 it is one scroll: the
  post whole, then its copy and the decision; each post opens at its top.
- Console:
  - The list leads each client with its logo (`ADspaceAdmin.clientMark`,
    the Clients list's own mark: initials while none is held or where it
    fails to load, a VIC's ring with the crown; the user, 2026-11-10), as
    do Video Scripts', Reports' (a white-label brand its initials) and
    Creator Campaigns' rows (`.cl-lead`).
  - The client is a record: the mark, name and handles, and one ⋯ (Access
    code as a sheet with one Save, the handles and logo Brand's alone since
    2026-10-29, Reset link, Remove), the review link under it as every record's client link
    (`.rec-linktools`: the address, Copy link, Preview; 2026-10-10), the
    address and Copy link the review page's own link, Preview the page;
    a published set's head adds Copy link (`#copySetLink`, beside
    Publish, equal halves on a phone) for that link with `#s-{first eight
    of the set's id}` (2026-10-12; full links since 2026-10-15); the
    sets are a card a content month (`batches.period`, YYYY-MM, empty for
    Ad hoc; `2026-10-10-sets-by-month.sql`), newest first and open, Ad hoc
    last, a row a set (name, the state at the right, the post count read for
    every set in one request) the page's width. A new set takes this month
    (MYT); the set's ⋯ Content month changes it (last month to six ahead, or
    Ad hoc; filed `set.month` from and to), and the set's head names its
    client, then it, before whether the client sees it. Engagements files a set by its month,
    an Ad hoc one by the day it was made. A post is a row: the placement with the
    client's decision at the right, the file, the copy, and one ⋯ (Edit,
    Request re-approval, Delete); the re-approval note opens under the post.
  - A set is a page of its own (`set=`): its head is the record head (the
    name with the quiet `.rec-pen`, who can see it under it, the state and one
    ⋯ with Delete at the right edge, Publish at its own width below), its
    posts, and a rail (the client's
    review, the tasks naming it). Back returns to the client. Add assets is a
    sheet (`#assetSheet`) that shuts on Add to set.
  - A file over the size cap (S3's `s3.maxUploadMB`, else Supabase's) is
    refused at the pick, by name. A picked or Drive-read file stays on the
    device (an object URL preview) until Add to set, which uploads what is left with progress, then writes
    the posts; a removed file costs nothing. Cancel aborts; a failed upload
    keeps its draft; only uploaded drafts are kept for a reload; leaving
    with a file held asks first. A picture (PNG, JPEG, WebP) picked, read
    from Drive or replaced is drawn down in the browser before it is held
    (`fitImage`): past `s3.reviewImageMax` (2160) on its longer side always,
    else past 2 MB unless that makes it heavier, a JPEG at 0.88 or a PNG
    where it holds transparency; a Drive copy kept heavier than 2 MB is
    read again, never reused (2026-11-03: 8 MB slides drew grey).
  - A video's thumbnail in a console row is its cover frame (`poster`),
    else its first frame (`#t=0.1`, `playsinline`), through `thumbOf()`:
    a bare `<video>` is blank on iPhone Safari until it plays. One whose
    file fails, after the media pass's retry, is a shaded tile with its
    kind's glyph (`.thumb-miss`), never the broken picture.
  - Sets are folded, one open at a time. Opening a set clears the last
    one's strip, covers line, progress and posts (`clearPostView`), and a
    read answered for a set already left is thrown away
    (`tests/crswitch.js`).
  - Publish (blue) / Unpublish (tonal); an empty set draws no Publish and
    Add assets is its blue (2026-10-15). Unpublish asks nothing and draws
    Undo where it happened (Unpublished. The client no longer sees this
    set.), which publishes it again (2026-10-20, REV-1). A client row and a set row count
    the posts whose latest decision is Changes requested (red dot), counted
    by `review_set_counts` in one request, never a read of every post. Add to set is Add assets' sheet foot.
  - Enable client (`#crEnable`, the bar's one action, Content Review
    settings at Work; the user, 2026-10-12, in place of Manage clients):
    drawn only while an Active client is out of Content Review (one read of
    the Active clients serves the list and it), it asks which
    (`ADspaceConfirm`, code first) and puts that client in through the same
    write as Remove's way back (`client.review_on`), Undo where it happened.
  - Resend with a note.
  - Drive import with progress (a folder link only).
  - S3 signed PUT.
  - Active clients only.
  - A set's name grows out of New content set; a title is renamed in place.
- Arrange posts (the set's ⋯, `review.sets:work`, two posts or more; the
  user, 2026-11-03: posts kept their upload order, a Drive import the
  folder's): `#postArrangeSheet`, the set's posts as Arrange sections'
  list (its place, a picture, its placement and title, the grip), a row
  dragged by its grip or moved with the arrow keys on it; Save writes
  `position` for each post whose place moved (`.select('id')`, filed
  `post.edited` Posts arranged), the order the client's page reads, with
  Undo over the posts. A carousel's slides are ordered in its Edit.
- Select posts (the set's ⋯, `review.sets:work`): a tick stands where each
  post's ⋯ was (`.saved-pick`), the row its target; the bar under the stage
  strip (`#postBulk`) counts the ticked posts shown and offers, each through
  what one post takes and refused against its post: Confirm internally (a
  published set, posts not approved; asked, `review_confirm`, Undo
  reverting each), Request re-approval (posts the client approved; one
  reason for all, filed per post) and Delete (`review.sets:manage`, red,
  the count typed back, `.select('id')`). A set opened afresh holds no
  ticks.
- Deleting a set is `can_remove` / Manage, drawn behind it
  (`body.no-remove #deleteSet`). Both deletes take `.select('id')`.
- Remove (the Content Review client's ⋯) hides the client and nothing else
  (`clients.review_hidden`, Content Review settings at Work, asked in warn
  with nothing typed): every set, post and approval is kept, Undo is drawn
  over the list, and Enable Content Review on the client's record is the way
  back later, with the same link. While hidden the link opens nothing
  (`get_review_feed`, `submit_review` answer `not_found`;
  `2026-10-03-hidden-from-content-review.sql`).
- A new lead or client starts outside Content Review (`review_hidden`
  defaults to true, `2026-10-19-content-review-by-hand.sql`; the user,
  2026-10-19: "make it manually"): it joins only when a colleague enables
  it (Enable client in Content Review, Enable Content Review on the
  record); a client standing before kept its place.
- Every everyday write leaves an activity row. An edit names the fields it
  changed.
- Write with AI (2026-10-08, one caption from 2026-10-10; the user: "one
  post only allowed one caption"): under a post's caption field in Add
  assets' drafts and a saved post's Edit, at Content Review: Sets at Work
  (`.capwrite`, `writeCaption()`, the AI mark before the words). A post has
  one caption; the 中文 field is drawn only on a saved post that already
  holds Chinese. It asks first (`ADspaceConfirm`: n captions left today;
  Language, a select of English, Bahasa Melayu, 中文, English and 中文
  (`CAP_LANGS`; both languages in the one caption, English first), from the
  main contact's preferred language; XHS Safe Mode on a
  rednote post alone, unticked until the colleague ticks it; Notes for the
  caption, kept in this browser under `adspace-caption-notes:{post id}` or
  `{set id}:{draft key}`, else the brief of a task naming the set), then
  `caption-draft` (Verify JWT off, as `report-draft`: it asks
  `allowed('review.sets', 'work')`, reads the set and client as the caller,
  claims `ai_caption_claim(p_batch)` before Claude, marks `ai_draft_done`,
  keeps tokens through `ai_draft_tokens`; secrets `ANTHROPIC_API_KEY`,
  `CAPTION_MODEL`, unset `claude-opus-5-5`; sends the placement, the set's
  and post's titles, the notes, industry and market, never an image, a
  contact or the client's name: the name reads `{brand}` and a handle
  `{handle}`, filled on the page with the name and the platform's `@handle`).
  The words go into `caption` in place, saved only by the post's own Save
  (Add to set for a draft), with Undo where it happened (Written by AI. Read
  before saving.) putting the earlier words back; a refusal is one line
  under the button. Saving words written with AI asks the declaration
  first (`ADspaceConfirm.ai.declare`: Written with AI, read in full, the
  person who confirms is responsible and an error may be raised in their
  performance review; a tick that refuses until ticked), filed with the
  save (… written with AI, read and confirmed). Words typed by hand ask
  nothing.
  The house style (benefit first, a hook, an emoji and bold title where it
  suits, one CTA, no dashes, MY/SG context, Chinese written as Chinese, the
  platform's own voice, brand names exactly) and XHS Safe Mode's rules live
  in the function's `SYSTEM` and `SAFE`.

## Components

Moved from DESIGN.md §4 on 2026-11-22.

| Need | Component |
|---|---|
| Content Review's clients (v3, 2026-11-12) | `.cr-cards`, a `button.cr-client-row.cr-card` a client (three across, two under 1100, one narrow; white, the large corner, an inset `--card-edge`): the logo and name over its Client ID, Access code as a grey tag where set, the chevron; its latest set's title and month, its posts as one bar (approved `--dot-ok`, changes `--dot-late`, waiting `--dot-wait`, the rest `--line`), where it stands (Changes requested, Waiting on client, Approved, Published, Draft) with n posts · n approved; then the sets line under a hairline. The latest set and its counts come from the list's one read of sets and one `review_set_counts` |
