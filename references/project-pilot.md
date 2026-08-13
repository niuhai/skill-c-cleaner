# project-pilot

`project-pilot` is the project-level PDCA controller for this skill. Its state machine is:

`discover → baseline → plan → dispatch → verify → settle → review → next`

Each state must produce evidence:

- `discover`: category scan output and coverage/timeout notes.
- `baseline`: current C-drive space plus path-level snapshot.
- `plan`: ranked actions with risk and expected reclaim bytes.
- `dispatch`: preview or explicitly approved action log.
- `verify`: new free-space value and repeated path measurements.
- `settle`: record of deleted, skipped, regenerated, and inaccessible paths.
- `review`: checklist result and remaining uncertainty.
- `next`: the next target selected from positive growth deltas.

Never declare success because a cleaner returned exit code 0. Success requires measured reclaimed bytes or a documented reason why the candidate was not reclaimable.
