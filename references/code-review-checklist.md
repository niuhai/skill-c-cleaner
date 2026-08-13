# code-review-checklist

Apply three review gates to every change or cleanup round:

## 1. Before-action contract

- Is the path exact and inside the intended root?
- Is the item cache, install residue, user data, or system data?
- Is the risk level explicit?
- Is the expected reclaim amount separated into logical bytes and NTFS allocated bytes?
- Are parent/child paths excluded from aggregate double counting?
- Is the process-closed requirement satisfied?

## 2. After-action self-check

- Did the command finish without timeout or hidden access errors?
- Did C-drive free space increase by approximately the measured allocated-byte reclaim?
- Did the target disappear or shrink as expected?
- Did an application immediately regenerate the same cache, and is a later 5m/1h/24h checkpoint needed?

## 3. Milestone external review

- Compare the before/after snapshot, not just console text.
- Review positive growth deltas from the last period.
- Account for skipped, inaccessible, protected, and regenerated paths.
- Keep system/user data out of automatic deletion.
- Choose the next iteration from evidence, or state why no safe action exists.
