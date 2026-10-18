# Channel approval

App inserts (even an owner/content admin's direct app insert) are normalized to pending/draft/Everyone, the authenticated creator and zero members. A transaction lock serializes each creator's three-request limit. Descriptive fields are editable; review/audience/status/counters/ownership are protected. Only unapproved channels may be deleted by their creator.

The admin panel calls a role-checked database RPC to create approved/published channels. Approval uses owner-only review_channel(channel_id, approve, audience): publish with chosen audience, record reviewer/time and auto-join the creator in one transaction. Rejection keeps the channel draft and private. Privileged writes use a private transaction capability inaccessible to API users, not a client-controlled header or setting.

Existing approved active rows and hidden rows retain their status so installed APKs can still browse existing channels. Read/write gates recognize legacy active alongside published. Every new approval uses published. Existing pending/rejected rows become draft. No payment or subscription logic changes.

Pictures use channel-icons: JPG/PNG/WebP, smaller than 5 MiB, with creator-owned upload paths. Existing pictures in public remain compatible. The app retains optional description/tags.

## Verify
- GitHub SQL suite covers pending/rejected visibility, fourth request rejection, forged creator/reviewer/counters, metadata-only editing, owner-only review, chosen audience, automatic membership, draft posting denial and approved-delete denial.
- Real concurrent REST test submits six requests with one member JWT; exactly three must succeed.
- Flutter checks creation confirmation, guest gate, three-character names, category, optional tags and picture size.
- Browser review exercises actual Approve/Reject server actions, audience/reviewer/membership and immediately approved admin-panel creation.

Deploy the database and server functions before distributing APK 0.3.5+8, because the new form uses the channel-icons bucket and published channels. Existing approved channels stay available to older APKs during rollout.
