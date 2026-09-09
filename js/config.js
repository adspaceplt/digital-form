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
  // Google Drive import. Key from Google Cloud Console, restricted to this
  // site and to the Drive API. Blank hides the Drive section in admin.
  googleApiKey: 'AIzaSyDKzn17TE3wimfU-nKlikwKta4pi8RKtNc',

  brandLogo: 'https://mycdn.adspace.me/adspace-brandname.png',
  agencyName: 'ADspace',
  supportEmail: 'adspacestudios@gmail.com'
};
