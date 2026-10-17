# Account and channel changes

Log in is the default account action. Sign up is a separate labelled choice; anonymous account upgrades still preserve identity/history internally. Duplicate email errors guide the user back to Log in, and no guest-ID switch or technical exception is shown.

Channels has Create channel, Discover and My channels. The form supports a required name, optional description, up to ten comma-separated tags, and an optional photo. Creators can edit these details and replace/remove the photo from My channels. Pending submissions remain Under review; the page does not mention owner approval. Existing RLS and review guards remain authoritative.

Android opens the system photo chooser without broad gallery permissions. Images are bounded to 20 MB input, sampled/resized to 1024 px, orientation-corrected and re-encoded as JPEG with metadata removed. Storage writes use the logged-in user's own prefix and unique filenames. Failed channel saves clean up newly uploaded images; replacing/removing a photo cleans up the old owned image after the row update succeeds.

The additive tags migration validates tag count, length and non-empty entries in the database. Existing channels receive an empty tags list. Run database tests and Flutter tests before merging. Deploy the migration through the main Supabase workflow before installing the new APK. Physical Android photo selection and email delivery require a phone smoke test.
