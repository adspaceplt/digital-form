/*
 * ADspace Content Review Portal — configuration
 *
 * Paste your Supabase project URL and anon (public) key below.
 * Dashboard > Project Settings > API.
 *
 * Leave them blank to run the portal in DEMO MODE, which loads sample content
 * from /demo/sample.json so you can review the design without any backend.
 *
 * The anon key is safe to publish. Every table is protected by row level
 * security and clients can only reach data through the token-checked functions.
 */
/* The agency profile: docs/rules/mechanisms.md. */
window.ADspaceAgency = {
  trading_name: 'ADspace',
  legal_name: 'ADSPACE PLT',
  reg_no: '202304002162',
  tax_no: 'J31-2401-32100002',
  address: '61-02 Jalan Mutiara Emas 2A\nTaman Mount Austin\n81100 Johor Bahru\nJohor, Malaysia',
  phone: '60187625233',
  website: 'adspacestudios.com',
  map_url: 'https://hi.adspace.me/map',
  portal_domain: 'digital.adspace.me',
  link_domain: 'hi.adspace.me',
  sender_domain: 'sc.adspace.me',
  cdn_base: 'https://mycdn.adspace.me',
  wordmark_url: 'https://mycdn.adspace.me/adspace-brandname.png',
  monogram_url: '/css/adspace-mark.png',
  favicon_url: '/favicon.ico',
  touch_icon_url: '/img/apple-touch-icon.png',
  icon_url: '/img/icon-512.png',
  font_text: '/css/fonts/text.ttf',
  font_bold: '/css/fonts/bold.ttf',
  font_medium: '/css/fonts/medium.ttf',
  font_mark: '/css/fonts/mark.ttf',
  verify_url: 'digital.adspace.me/verify',
  service_terms_url: 'hi.adspace.me/svc-terms',
  ink_token: '--ink',
  accent_token: '--action',
  ground_token: '--page',
  email: 'advertise@adspacestudios.com'
};

window.ADspaceAgency.alias = function (obj, map) {
  var A = window.ADspaceAgency;
  Object.keys(map).forEach(function (f) {
    Object.defineProperty(obj, f, { enumerable: true, configurable: true,
      get: function () { return A[map[f]]; }, set: function (v) { A[map[f]] = v; } });
  });
  return obj;
};

/* The issuer printed on the Letter of Intent. Blank lines are left out. */
window.ADSPACE_ORG = window.ADspaceAgency.alias({
  bank: '',       // bank, account number and account name, on one line
  // The KOC job form a creator fills in for payment, named on their own page
  // once their work has been approved.
  ap01: '/ap01.html',
  // The letterhead's faces are the profile's (font_text, font_bold,
  // font_medium, font_mark, aliased below): the monogram top right (the
  // letterhead only), the wordmark in the mark face, the text in the text
  // face, the heavier lines in the bold one, the letters' headings in the
  // medium one (blank, they take the bold). Files, not font names, same
  // origin or served with CORS; blank fonts fall back to Helvetica.
  // The brand faces carry no Chinese, so a letter with a Chinese block embeds this
  // face for that block alone. Fetched only when a Chinese block is drawn,
  // and refused by name when it cannot be, rather than drawing boxes.
  fontCjk: '/css/NotoSansSC-Regular.ttf'
}, { name: 'legal_name', regno: 'reg_no', sst: 'tax_no', address: 'address', email: 'email', phone: 'phone',
     website: 'website', map: 'map_url', logo: 'monogram_url', verifyUrl: 'verify_url',
     font: 'font_text', fontBold: 'font_bold', fontMed: 'font_medium', fontMark: 'font_mark' });

window.ADSPACE_CONFIG = {
  supabaseUrl: 'https://hwwuigvdfubuymchsvyx.supabase.co',
  supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh3d3VpZ3ZkZnVidXltY2hzdnl4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg5Mzg4NzIsImV4cCI6MjEwNDUxNDg3Mn0.c4g_r0W3zeA0rmQ-qYFVE2Iw3l4uAg5ub0EfKBgSsUs',
  storageBucket: 'content',

  // Loading said on the page (js/api.js, js/state.js): the loading line after
  // showAfter, Still loading… after slowAfter, a read given up at
  // giveUpAfter (milliseconds).
  loading: { showAfter: 300, slowAfter: 8000, giveUpAfter: 20000 },

  // /verify/ (js/verify.js): a QR code's Document ID opens the details, and
  // a refresh in that tab keeps them for passMinutes after the scan; a link
  // shared on never carries it.
  // page is the address a sealed copy's QR code and Record page name, with
  // the reference after `?s=` (js/quotes.js, js/hiring.js, js/hrdocs.js).
  // The address is ADSPACE_ORG.verifyUrl's, so a sealed copy, its QR code
  // and every letter's foot name one page.
  verify: { passMinutes: 30, page: 'https://' + window.ADspaceAgency.verify_url + '/' },

  // Supabase caps uploads per plan. Free is 50 MB and cannot be raised.
  // On Pro you can raise it in Dashboard > Storage > Settings, then change
  // this number to match. Anything bigger should be pasted as a link instead.
  maxUploadMB: 50,

  // Uploads go to S3 behind CloudFront when this is on, which removes the size
  // limit above. Requires the sign-upload edge function to be deployed.
  // Leave enabled false to keep using Supabase storage.
  s3: {
    enabled: true,
    functionName: 'sign-upload',

    // What one file may weigh, on the creator's page and in the console's
    // draft upload alike. Video, so it is generous (raised from 300 MB on
    // 2026-09-22 at the user's request); the edge function's own ceiling is
    // 2 GB, and this is the figure the page refuses on, before a single byte
    // moves.
    maxUploadMB: 1024,

    // A picture added to Content Review (picked, or read from Google Drive)
    // is drawn down to this many pixels on its longer side before it goes
    // up, and kept as a JPEG unless it holds transparency (2026-11-03: a
    // carousel of 4500px PNGs, 8 MB a slide, drew grey on the client's
    // page). Twice Instagram's 1080, so it stays sharp on a phone's screen.
    reviewImageMax: 2160,

    // A campaign's invoice PDF goes under `private/` and opens through a
    // five-minute link from sign-download. On since 2026-10-03, once the
    // bucket policy and the upload key's private/* permission were in place
    // (docs/S3-STORAGE.md §5).
    privateInvoices: true,

    // Everything under `content/` (Content Review files, creator drafts)
    // opens only with the CloudFront pass `media-pass` hands a page that has
    // proved its link, code or sign-in (js/media.js). On since 2026-10-03,
    // once CloudFront held the portal's key (docs/S3-STORAGE.md §6); the pass
    // is set on `mediaCookieDomain` so mycdn.adspace.me receives it.
    privateMedia: true,
    mediaCookieDomain: 'adspace.me'
  },
  /* Google Drive import.

     This one is meant to be here. It is a browser key: the browser is what
     calls Google, so the key travels with the request whatever we do with it.
     Moving it into the database would only mean reading it from the network
     tab instead of from this file.

     What keeps it safe is restriction, not hiding, and both are set in the
     Google Cloud Console under Credentials:
       Application restrictions  Websites, listing digital.adspace.me/*
       API restrictions          Google Drive API only
     So restricted, the key is useless to anyone who copies it off this page.
     Check those two settings before treating it as safe.

     Blank hides the Drive section in admin. */
  googleApiKey: 'AIzaSyDKzn17TE3wimfU-nKlikwKta4pi8RKtNc',

  /* The script, selection and creator links are written as short links
     (/s/, /c/, /p/ on the host above), answered by the links Worker
     (workers/links/worker.js, live 2026-10-13); false writes the long link. */
  /* Off since 2026-10-15 (the user: "full links everywhere except
     namecards"): Copy link and the address give each page's full link. The
     links Worker still answers every short link already sent, and a
     colleague's namecard keeps its short link (printed QR codes). */
  shareLinks: false,
  /* The letters re-set on 2026-10-15 (the user): selection /s/, Video
     Scripts /v/, /c the client portal. True once the links Worker that
     answers them is live in Cloudflare; until then the console writes /c/
     and /s/ as before (the new Worker answers both). */
  shareLetters: false,

  /* Cloudflare Turnstile SITE key for the sign-in captcha (js/captcha.js).
     Public by design, like the anon key; the SECRET key lives only in the
     Supabase dashboard (Authentication, Attack Protection). Leave blank until
     both are set together: see docs/SIGN-IN-SECURITY.md. */
  /* The digits of the code a sign-in email carries (Supabase's Email OTP
     length); js/otp.js draws one box each. */
  signCodeDigits: 8,
  turnstileSiteKey: '0x4AAAAAAFEI21WUxApWeD2V',
  /* The agency's social pages, offered on /feedback/ once a client has
     answered (CLIENT FEEDBACK, 2026-11-24). */
  socialLinks: [
    { name: 'Facebook', url: 'https://www.facebook.com/adspacestudios' },
    { name: 'Instagram', url: 'https://www.instagram.com/adspace.advertising' },
    { name: 'LinkedIn', url: 'https://www.linkedin.com/company/adspacestudios' }
  ],
  // The quotation website's Chat on WhatsApp (2026-10-14), the front door's own.
  quoteWhatsApp: 'https://wa.me/adspace',
  /* The agency's own domain and accounts, named as a field's example (a
     placeholder: an email, a website, a profile link). */
  examples: {
    domain: 'adspace.me',
    instagram: 'https://www.instagram.com/adspace.advertising',
    tiktok: 'https://www.tiktok.com/@adspace.advertising',
    facebook: 'https://www.facebook.com/adspace.advertising'
  },
  // Directions to a place: the map's search, the place's words after it.
  mapSearch: 'https://www.google.com/maps/search/?api=1&query='

  /* No secret belongs in this file. It is served to the browser on a public
     site, so anything here can be read by anyone who opens the page. The
     deletion code lives in the database instead; supabase/schema.sql says how
     to set it. The Supabase anon key and the Google key above are not secrets:
     both are meant to be public and are held back by their own restrictions. */
};
window.ADspaceAgency.alias(window.ADSPACE_CONFIG, { brandLogo: 'wordmark_url', agencyName: 'trading_name',
  serviceTermsUrl: 'service_terms_url', supportEmail: 'email', accountEmail: 'email', linkHost: 'link_domain' });
