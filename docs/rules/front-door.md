<!-- triggers: index.html img/front-door -->
# The front door (`/`, `index.html`)

Rules for this area, moved from CLAUDE.md §2 on 2026-11-22 and read before the area is changed (a hook names this file on the first edit of a matching path). One place per fact, as CLAUDE.md §0.

- `/` is the front door and the host's one listed page, a visitor card after
  Apple's visitor centre page (`body.lp`):
  - one centred column (`--lp-col` 980px, 560 at 900 and under; `--lp-gut`
    24px) holds the content but the photograph: the name, the ticks, the
    hours and address, so the content has one left and one right edge at
    every width (`tests/seo.js` asserts the markup; the edges are measured
    by hand at 390, 768, 1045, 1280, 1440); the bar and the foot run to the
    screen's edges as on every page (the mark 24px from the left);
  - the chrome header and footer, the kicker reading Creative Advertising
    Agency on `/` alone (16px/400, 14 on a phone, kept on a phone); no menu,
    no sign-in, no list of rooms;
  - the name centred: `h1.lp-title` ADspace in Optima (`--font-mark`,
    `css/fonts/mark.ttf` after `local('Optima')`, never preloaded: it swaps in), over the tagline
    `advertising | marketing | branding` in Slate Regular (`.lp-tagline`);
    never an opening status (a studio, not a shop). ADspace alone, never
    "ADspace Studio";
  - the website's ways in as ticks: Home, About us (`/about`), Our services
    (`/services`), Our works (`/project`), Contact us (`/contact`) on
    adspacestudios.com, five across the column with the first at its left
    edge, the last at its right and equal gaps (`max-content` tracks,
    `space-between`); the ticks in the brand's monochrome (`--fill` with an
    `--on-fill` tick);
  - one photograph, whole at 16:9 and full width up to 1920
    (`img/front-door-{800,1200,2000,2560}`, WebP with a JPEG fallback, each
    URL stamped `?v=` so a replaced photo is fetched again), which is also the
    og:image; it offers no drag, right-click menu or iPhone Save to Photos
    (a screenshot cannot be stopped);
  - above 900: the name, the ticks, the photograph; at 900 and under (the
    ticks as a list): the name, the photograph, the list
    (`.lp-band, .lp-duo { order: 1 }`), the markup keeping the desk's order;
  - Service hours: a dated week from today in Malaysia time, Monday to
    Friday 10:00 to 18:00, redrawn every minute and on return to the tab,
    the page's own and never the team's Working hours setting (the user,
    2026-11-20: "keep the website front page same");
    a public holiday on the list reads Closed with its name under the date
    (`public_holidays_between`, read once a visit, a fortnight ahead; a
    failed read leaves the hours);
  - Visit: the address and Get directions (the Google Maps listing);
  - How can we help?: one sentence, then Chat on WhatsApp opening
    `wa.me/adspace` (the blue one); a tonal `.btn-sm` Chat on WhatsApp
    under the tagline puts it in the first screen (2026-10-15); the number
    is never on the page or in its business details;
  - the head: the title and descriptions name ADspace as adspacestudios.com
    does (Digital Marketing Agency in Johor Bahru & Singapore), Open Graph
    and a large-image card, and one JSON-LD graph (the Organization, the
    ProfessionalService office with its hours and address, the WebSite);
  - white to the edge (`--card`, `theme-color #ffffff`, `color-scheme: light`).
