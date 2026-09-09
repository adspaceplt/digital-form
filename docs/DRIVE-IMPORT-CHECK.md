# Google Drive import — compatibility check

Before building Drive import into the portal we need to confirm Google actually lets us
do it on your folders. This page runs that check.

**`digital.adspace.me/admin/drive-test/`**

It only reads. It changes nothing in Drive and saves nothing anywhere.

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

## Share the test folder

Pick a real content folder in Drive, ideally one with both graphics and a video.
**Share → General access → Anyone with the link → Viewer.**

## Run it

Paste the key and the folder link, click **Run the check**. You get four answers:

| Check | What a failure means |
| --- | --- |
| Folder is readable | The key or the sharing setting is wrong |
| Dimensions from Drive | Placement cannot be auto-detected, you would pick it manually |
| Files can be copied in | We cannot import, only point at Drive, which is the fragile option |
| Previews | The folder is not actually public |

The third one is the important one. If files can be copied in, the whole
"download then re-upload" step disappears and the portal stays self-contained.

Send me the results, or a screenshot, and I will build the real thing against what we
learn. If something fails, the message on screen usually says which of the four setup
steps above to revisit.

## Delete this page afterwards

`admin/drive-test/` exists only to answer this question. Once import is built it should be
removed from the repo.
