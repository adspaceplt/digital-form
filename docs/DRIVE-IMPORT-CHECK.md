# Google Drive import — compatibility check

Drive import is built (Content Review's Add assets). The check page that confirmed Google
lets the portal read the team's folders (`admin/drive-test/`) was removed on 2026-10-17, its
question answered. The key's setup below still applies.

## Get an API key, about five minutes, free

1. Go to `console.cloud.google.com` and create a project. Call it something like
   "ADspace Portal".
2. **APIs & Services → Library**, search **Google Drive API**, click **Enable**.
3. **APIs & Services → Credentials → Create credentials → API key**. Copy it.
4. Click the key to edit it and lock it down:
   - **Application restrictions** → Websites → add `https://digital.adspace.me/*`
   - **API restrictions** → Restrict key → tick **Google Drive API** only

Step 4 matters. Without it the key can be lifted off the page and used against your quota.
With it, the key only works from your own site and only for reading Drive.

## Share the folder

Pick a real content folder in Drive, ideally one with both graphics and a video.
**Share → General access → Anyone with the link → Viewer.**
