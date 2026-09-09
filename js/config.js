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
  supabaseUrl: '',
  supabaseAnonKey: '',
  storageBucket: 'content',
  brandLogo: 'https://mycdn.adspace.me/adspace-brandname.png',
  agencyName: 'ADspace',
  supportEmail: 'adspacestudios@gmail.com'
};
