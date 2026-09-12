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
/* The issuer printed on quotations and invoices. Blank lines are left out. */
window.ADSPACE_ORG = {
  name: 'ADSPACE PLT',
  regno: '',      // business registration no.
  sst: '',        // SST registration no.
  address: '',
  email: '',
  phone: '',
  bank: '',       // bank, account number and account name, on one line
  // The mark and the brand font on quotations and invoices. PNG or JPG for
  // the logo; TTF or OTF for the fonts, served with CORS. Blank falls back to
  // the wordmark and Helvetica.
  logo: '',
  font: '',
  fontBold: ''
};

window.ADSPACE_CONFIG = {
  supabaseUrl: 'https://hwwuigvdfubuymchsvyx.supabase.co',
  supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh3d3VpZ3ZkZnVidXltY2hzdnl4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg5Mzg4NzIsImV4cCI6MjEwNDUxNDg3Mn0.c4g_r0W3zeA0rmQ-qYFVE2Iw3l4uAg5ub0EfKBgSsUs',
  storageBucket: 'content',

  // Supabase caps uploads per plan. Free is 50 MB and cannot be raised.
  // On Pro you can raise it in Dashboard > Storage > Settings, then change
  // this number to match. Anything bigger should be pasted as a link instead.
  maxUploadMB: 50,

  // Uploads go to S3 behind CloudFront when this is on, which removes the size
  // limit above. Requires the sign-upload edge function to be deployed.
  // Leave enabled false to keep using Supabase storage.
  s3: {
    enabled: true,
    functionName: 'sign-upload'
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

  brandLogo: 'https://mycdn.adspace.me/adspace-brandname.png',
  agencyName: 'ADspace',
  supportEmail: 'adspacestudios@gmail.com',

  // Reply-to on anything the portal sends on the team's behalf.
  accountEmail: 'marketing@adspacestudios.com'

  /* No secret belongs in this file. It is served to the browser on a public
     site, so anything here can be read by anyone who opens the page. The
     deletion code lives in the database instead; supabase/schema.sql says how
     to set it. The Supabase anon key and the Google key above are not secrets:
     both are meant to be public and are held back by their own restrictions. */
};
