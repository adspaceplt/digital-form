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

## The page template (2026-09-25)

The report wears the ADspace Rate Card & Packages paper, measured off the
v2.0.5 file the user sent. They sent the first design back because the cover
led with the best-performing post and the pages did not follow that template.

| Element | Rate card | Report |
|---|---|---|
| Margin | 54pt | 54pt |
| Head, left | `ADspace`, Optima 16.08pt, baseline 781.7 | Same, every page, cover included |
| Head label | `FOR INTERNAL USE`, Slate Medium 7.92pt caps at x 264.5 | The client's name in the same face and place |
| Cover | Title only, Slate Medium 25.92pt at x 126, baseline 497 | Same title position; client (Slate Regular 14pt) and month (Slate Book 11pt) under it; nothing else |
| Page title | Slate Regular 18pt, baseline 753.8 | Same |
| Sub heading | Slate Regular 11pt | Same |
| Foot, left | `PRIVATE & CONFIDENTIAL` Slate Medium 7.92pt, then `v.2.0.5 exp. 20261231` in Slate Book Italic | Same caption, then `v.1 issued 20260925` or `Draft 20260925` |
| Foot, right | `Page n of N`, Slate Book 7.92pt | Same, on the right margin |
| Ink | #404040 | #404040 |

The best-performing post and the figures now open the executive summary on
page 2, not the cover. Slate Book Italic is not among the portal's font
files, so the reference line is Slate Book slanted; adding
`css/SlateBookItalic.TTF` would make it the real italic.

Three layout faults the SKS render showed were fixed at the same time:
- the executive summary's lists ran into the foot;
- appendix thumbnails ran into the foot;
- a platform page's last two notes spilled onto a page of their own. They now sit side by side where they fit.

## Wording (2026-09-25)

The user asked for corporate, official and straightforward wording, with no
explanatory sentences anywhere, the foot included. The report prints
headings, labels, figures and what the team typed, and nothing else:

- page titles carry no sub-line;
- figure bands carry no notes;
- no sentence is generated for the headline, the top posts or the appendix;
- the methodology is a label and value table.

Section names: Executive summary, Top post, Key findings, Next steps,
Highlights, Areas for improvement, Recommendations, Top posts, Remarks and
recommendations (Highlights, Performance drivers, Underperformance,
Opportunities, Improvements, Action plan), Appendix: all posts, Methodology.

## Structure and charts (2026-09-25, second pass)

The first pass took the rate card's head and foot and left the pages as loose
text and blue charts. Sent back by the user ("plain", "doesn't follow the design
theories and visualizations", "why blue, we're monochrome"). The rules now:

| Rule | Where it applies |
|---|---|
| **Monochrome.** One ink (#404040) for every word and every mark that carries a value; #a6a6a6 for a second series and the ordinary bars; #cccccc for a third. No accent colour anywhere; the report no longer reads `rep.accent`. | Every page |
| **Data is set in the rate card's table.** Header row #f2f2f2, white rows, every cell edged 0.48pt in #f2f2f2, text vertically centred with 5.3pt either side, a label column in #f2f2f2 where the table reads by row, 18.24pt minimum row. A row that no longer fits starts a new page and the header is drawn again; a list row may split, the label repeating with (cont.). | Figures, by platform, followers, top five, remarks, appendix, methodology |
| **Headline figures are a two-row table**, the label over the value in Slate Medium. | Executive summary, platform pages |
| **One chart a question.** Views by week (stacked by platform, the week's total over each column) answers how the month moved; views by post (posting order, the best post in ink with its value, the average as a dashed line) answers which posts beat the month's own mean. The previous per-day bar chart put two scales of post on one date axis and read as noise. | Executive summary, platform pages |
| **Each fact once.** The top post, the most viewed three, the most interacted three and a top-five bar list were four views of one ranking; they are one table (rank, thumbnail, post, views with a data bar, engagements, rate). Key findings and next steps are the Highlights and Action plan fields, so the remarks table under them carries only the other four fields and no separate remarks page is drawn. | Executive summary, platform pages |
| **A post without a title is named** by its format and date (`Reel, 5 Aug (2)`), never "Untitled post". | Everywhere a post is named |
| **Thumbnails sit in a fixed frame** in the header grey, the image whole inside it, so a column of them is one column. | Top five, top posts, appendix |
| **The appendix is a table**, about twelve posts a page with a total row per platform, where it was three posts a page. | Appendix |
| **The chart gives up height** (160pt down to 110pt) so the executive summary finishes on its page rather than leaving one row on a page of its own. | Executive summary |

The fixture report is nine pages where the first pass drew eighteen, with the
same content.

## The name (2026-09-25)

The report is the **Social Media Report**: the cover title, the PDF title and
the file name (`{Client}-Social-Media-Report-{Mon}-{YYYY}-v{n}.pdf`). "Social
Media Accounts Report" was the previous vendor's name; the user asked for a
more modern and straightforward one.

## Sections, margins and the golden ratio (2026-09-25, third pass)

Sent back by the user: a report with little in it was squeezed onto part of a
page, and the 54pt margin left too much white paper. The rules now:

| Rule | Where it applies |
|---|---|
| **Every section starts its own page**: Executive summary, Findings and recommendations, one page per platform, Top posts, one appendix page per platform, Methodology. A section with nothing in it is not drawn. A thin report is shorter by whole sections, never by squeezing. | Every page |
| **A chart keeps one height**: views by week is the text column over φ² (201.9pt), views by post half a step shorter (158.8pt). Nothing shrinks to fit. | Executive summary, platform pages |
| **One scale for everything**: 10pt times √φ step by step (6.18, 7.86, 10, 12.72, 16.18, 20.58, 26.18, 33.3, 42.36). The margin is S(5), 33.3pt, which widens the text column from 487pt to 529pt. Page title S(3), block title S(1), body and table text S(0), captions S(−1). A table line is S(1), a row at least S(3). A heading sits S(2) above its content, blocks S(4) apart. | Every page |
| **The head and foot stay the rate card's**: the Optima wordmark (S(2), the rate card's 16pt) top left, the client's name right, PRIVATE & CONFIDENTIAL and the reference at the foot, the page count on the right. | Every page |

## Publishing to the client (2026-09-25)

The report is prepared on the client record's **Reports** pane and reaches the
client only once it is finished and confirmed internally, as the user asked:
Draft → Submit for review → Confirm (a manager who did not submit it) →
Publish to client. Publishing freezes the report as a numbered version; the
client portal reads only that version. Revise makes the next version a draft
while the client keeps reading the published one; Unpublish takes it off the
portal with a reason. The rules are in
`supabase/migrations/2026-09-25-social-media-reports.sql`.

## The advertising report (2026-09-25)

Built from the team's two templates, *Social Media Ads Report* (First) and
the later-month one, and the Waringin report of August 2026 made from them.
The template's content is kept; the layout is the social report's scale,
grid and furniture, and the page does what the template left to the reader.

| Template | The report now |
|---|---|
| "How to Read This" boxes on the Ad Performance page, in both templates' first month | The **first month** (`sm_reports.first_month`, set when the report is made) carries two reading notes, one on cost per result, reach and frequency, one on the video figures, each where it is first needed. A later month carries only the glossary line. |
| Current Period and Previous Period columns, empty in a first month | A first month shows the four account figures; a later month shows **this period, the previous period and the change** in one table, the previous period carried forward from the last advertising report. |
| Group by objectives: Reach, Engagements, Messaging/Leads, each with its spend | **Results by objective**: the result, the spend, the cost per result (and the previous month's beside it) and the share of spend as a bar. |
| The tax footnote naming both markets | The note names the client's market only: WHT and SST in Malaysia, DCC and GST in Singapore. |
| One card per ad in the order they were typed, the objective as a coloured cell | Ads are **grouped by objective**, because the template's own guidance is to compare cost per result only between ads of the same goal; each group opens on a table ranking its ads by cost per result, the cheapest in weight where the results are of one kind. |
| Six age cells under each ad | The age split is a **chart**, the largest band in ink. |
| Hook rate, hold rate, average playtime, and an empty "Audience Retention Curve" | The three figures, and **the retention curve drawn** from the plays at 25, 50, 75, 95 and 100 per cent where they are known. |
| What Worked, What to Fix, Recommended Focus, numbered with lettered sub-points | The same three tables; a line starting with a dash is a lettered sub-point. |

Cost per result is Ads Manager's own figure where it is typed or pasted; a
reach result is priced per 1,000 people, as Ads Manager prices it.
