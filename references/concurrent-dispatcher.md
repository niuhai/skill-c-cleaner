# concurrent-dispatcher

Use concurrency only for independent read-only scans or previews. A dispatcher must:

- assign a unique output/report path to each task;
- cap parallel work at three tasks by default, lowering the cap when resource pressure is observed;
- preserve task identity, start/end time, exit code, and captured output;
- fail one task without hiding results from the others;
- never run two cleaners against overlapping paths;
- wait for all tasks before the verify state.

The current `iteration-loop.ps1` keeps dispatch conservative and generates one targeted preview. Future scanners may be fanned out after their output paths are isolated.
