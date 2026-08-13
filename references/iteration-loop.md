# iteration-loop

Use this as the general positive loop for C-drive maintenance:

1. **Discover** multiple sources: drive space, known caches, large files, application data, installed-software candidates, miscellaneous C-drive inventory, system data, and tracked history.
2. **Pool** findings by path, owner, risk, reclaimability, and evidence quality. Do not treat a category total as proof that deletion is useful.
3. **Plan** the next smallest high-value action. Prefer measured growth and reversible migration over blind deletion.
4. **Dispatch** independent scans or previews concurrently when they do not share mutable state. Keep deletion disabled by default.
5. **Verify** with drive free-space delta, NTFS allocated-byte delta, and the same path-level scanner used before the action.
6. **Settle** by recording what changed, what was skipped, and what regenerated.
7. **Review** the result against the three review gates in `code-review-checklist.md`.
8. **Next round** focuses on the largest compatible detail delta, a regenerated cache, a high-confidence unused-software candidate, or an unresolved permission/coverage gap.

Run `..\iteration-loop.ps1 -Mode diagnose -RecordGrowth` for a bounded local round. Use `-IncludeSlowScan` only when the fast evidence is insufficient.
