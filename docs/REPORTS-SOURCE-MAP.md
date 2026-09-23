# Social media report generator — the source, mapped

The reference is `SKS City Mall JBCC - Social Media Accounts Report (Aug
2026).pdf`, seven A4 pages, attached by the user on 2026-09-23. Every piece
of information on it is listed here with the database column it is kept in,
the editor field it is typed in, and where the redesigned PDF prints it.
Nothing on the source may disappear because the visual structure changed;
this table is what that claim is checked against.

## The source, page by page

| Page | What is on it |
|---|---|
| 1 | Cover: the previous vendor's mark, `SOCIAL MEDIA ACCOUNTS REPORT`, `SKS City Mall JBCC`, `Aug 2026`, `Private & Confidential`, `Page 1`. |
| 2 | `Dear valued client,` and one paragraph introducing the report. A Meta band: `/ Facebook + Instagram`, `Followers Growth for the month: Facebook 81, Instagram 110`. A table headed Post · Posting Date · Impressions/Views · Interactions, five rows. |
| 3 | Eight more rows of the same table. |
| 4 | Four more rows (seventeen in all), then `Remarks/Suggestions/Improvements` with three numbered points, the first carrying three lettered sub-points. |
| 5 | A TikTok band: `/ TikTok`, `Followers Growth for the month: 23`. A table headed Post · Posting Date · Views · Engagements, six rows. |
| 6 | Seven more rows. |
| 7 | Two more rows (fifteen in all), then `Remarks/Suggestions/Improvements` with three numbered points. |

Every page carries `Private & Confidential` and `Page n` in the foot. The
post cells are thumbnails only: the source carries **no titles, no captions,
no post links and no content types**. The remarks name four posts by name.

## The map

| Source information | Column | Editor field | Redesigned PDF |
|---|---|---|---|
| Report title | `sm_reports.title` | Overview · Title | Cover, running header |
| Client name | `clients.name` through `sm_reports.client_id` | Overview · Client (fixed once created) | Cover, running header, every page foot |
| Reporting period (`Aug 2026`) | `sm_reports.period_start`, `period_end` | Overview · Period | Cover, running header, executive summary |
| `Private & Confidential` | constant | none | Cover foot and every page foot |
| Page number | derived | none | Every page foot, `Page n of N` |
| Introductory paragraph | `sm_reports.intro` | Overview · Introduction | Executive summary, under the headline |
| Platforms (`Facebook + Instagram`, `TikTok`) | `sm_report_platforms.platform`, one row per account; `group_key` / `group_label` join Facebook and Instagram as the source reports them | Platforms · Platform, Report together as | Platform performance pages, every post's context line |
| Account names | `sm_report_platforms.account_name`, `handle`, `url` | Platforms · Account | Platform page head |
| Follower growth (`Facebook 81`, `Instagram 110`, `TikTok 23`) | `followers_start`, `followers_end`, growth derived; where the source gives growth alone, `growth_override` with `growth_reason` and `growth_override_by` | Platforms · Followers at start, at end, Recorded growth override | Executive summary band (net growth), platform page KPI band per account |
| Post thumbnails (17 + 15) | `sm_report_posts.thumb_path` (private bucket) or `thumb_url`; `thumb_w`, `thumb_h` | Posts · Thumbnail | Executive summary featured post, platform page top lists, top posts, appendix |
| Posting dates | `sm_report_posts.posted_on` | Posts · Date | Charts by date, top lists, appendix context line |
| `Impressions/Views` (Meta) | `sm_report_posts.views`; the source's label is kept in `sm_report_platforms.metric_notes` | Posts · Views | KPI bands, charts, top lists, appendix metric band, methodology |
| `Interactions` (Meta) | `sm_report_posts.interactions` | Posts · Interactions | Same |
| `Views` (TikTok) | `sm_report_posts.views` | Posts · Views | Same |
| `Engagements` (TikTok) | `sm_report_posts.engagements` | Posts · Engagements | Same |
| Reach, impressions, likes, comments, shares, saves | their own columns, null where the platform did not provide them | Posts · metrics | Printed only where the platform reports them; `Not available` where reported but missing |
| Full post captions | `sm_report_posts.caption` (none in the source) | Posts · Caption editor | Excerpt on top posts, in full in the appendix |
| Post title, content type, theme, link | `title`, `content_type`, `theme`, `url` (titles read off the thumbnails; the rest blank in the source) | Posts | Context lines, appendix |
| Remarks 1a, 1b (best performance) | `sm_report_posts.notable` on the posts named; `sm_report_platforms.worked` | Posts · Why notable; Platforms · What worked | Top posts, platform page |
| Remark 1c (the tenant collaboration) | `sm_report_platforms.worked`, and `notable` on Sarawak Taste | Platforms · What worked | Platform page, top posts |
| Remark 2 (local culture, lifestyle) | `sm_report_platforms.improve` and `sm_reports.insights.opportunities` | Platforms · Opportunities; Insights · Opportunities | Platform page, remarks page |
| Remark 3 (moving forward) | `sm_report_platforms.actions` and `insights.next_actions` | Platforms · Next actions; Insights · Actions for the following month | Platform page, remarks page, executive summary (first three) |
| TikTok remarks 1 and 2 (highest views, highest engagement) | `notable` on the two posts; `worked` on the TikTok account | Posts · Why notable; Platforms · What worked | Top posts, platform page |
| TikTok remark 3 | `actions` on the TikTok account; `insights.next_actions` | Platforms · Next actions | Platform page, remarks page |
| Meta's mark and TikTok's mark | none | none | Not drawn; the platform is named in words |
| The previous vendor's mark | none | none | The report carries ADspace's mark |

## What the redesign adds that the source lacked

An executive summary (headline, the month's totals, one chart, the featured
post, three observations and three next actions), a platform narrative per
account group (dominant message, KPI band, views by date, engagement
comparison, most viewed and most engaged), a ranked top posts section, a
detailed appendix with full captions, and a methodology page naming each
metric and the engagement-rate denominator. Every figure on those pages is
derived from the same rows the source data was transcribed into; nothing is
typed twice.

## Transcription notes

- The source labels Meta's column `Impressions/Views`; the figures are
  stored as `views` and the label is preserved in the account's metric
  note so the methodology page can state it.
- The source gives follower growth without a start or an end, so each
  account carries the figure as a recorded override with the reason.
- Titles were read off the thumbnails (`Freedom 250: Celebrating the Triumph
  of the American Spirit`, `Sarawak Taste: Malaysia Quiz Challenge`, …) and
  are editable. The remarks call the TikTok quiz post `Merdeka Quiz
  Challenge: Sarawak Taste`; both names are kept, one as the title and one
  in the remark.
- Totals derived from the transcription: Facebook and Instagram 17 posts,
  30,036 views, 185 interactions; TikTok 15 posts, 6,208 views, 56
  engagements. The calculation tests assert these against the fixture.
