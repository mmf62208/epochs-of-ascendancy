---
name: eoa-map-director
description: >
  Director for the Epochs of Ascendancy map. Monitors origin/main and open
  draft pull requests, keeps the next slice on the world-class map bar, and
  builds one draft slice when a real gap remains. Use when the user says
  continue building the map, finish the map, world-class map, keep the
  project on task, or runs /eoa-map-director.
---

# EOA map director

You keep the Epochs of Ascendancy map on the world-class bar. Each run is one slice, then stop. You do not merge.

## Load first

1. Load skill `eoa-full-test` and obey it. Godot is `tools/run_godot.sh`. Never set `EOA_SKIP_TITLE`. Never renumber `world_full` IDs.
2. Read `docs/GAME_STATUS_SNAPSHOT.md` from fetched `origin/main`, not from a dirty checkout or another worktree.
3. Read `docs/WORLD_CLASS_MAP_REVIEW.md` section 7. That file is what "world-class" means. `WORLD_CLASS_MAP_ROADMAP_AND_DELIVERABLES.md` is not the live board.

## Monitor

Do this before any edit. Record the results in the run report.

1. `git fetch origin main` from a repo that has `origin`. Record the `origin/main` SHA. On this machine the chip checkout is `/home/featherstone/Projects/epochs-of-ascendancy`.
2. List open pull requests on `mmf62208/epochs-of-ascendancy`. Record number, title, head ref, head SHA, draft, and merged. Use the GitHub connection. `gh` is unauthenticated.
3. Do not commit on a checkout that belongs to another open draft. A bare `git` in the chip checkout runs there. Always `git -C` the worktree you mean.
4. Leave portrait `*.png.import`, `*.uid`, and dirt in other worktrees unstaged.

## Bar

Machine bar, from the review: M0–M5 are landed on the ~3520 `world_accurate` board. M6 human 20-day and 60-day notes stay human. A soft 30fps miss on the map-tick proxy stays an honest fail. Museum borders, 13k provinces, densify, and a `world_full` renumber are out of scope.

Diary bar for this map push. A still of Europe Home, then Search Köln, then Rhineland mid and close, lets a stranger name a country, a city, an obvious road, the Rhine, and an airfield, and the coast reads as a shore. Europe Home stays clean political.

A gap counts only when it is missing on `origin/main`. An open draft is not main, and it is not a license to stack.

## One slice

When the monitor finds a gap that shows in those frames, is not already an open pull request, and is not forbidden:

1. `git -C <chip> worktree add -b eoa/<slice> <new-path> origin/main`, then immediately `git -C <new> branch --unset-upstream`.
2. Change only that slice. Lock it with a test that calls the real function, plus a headless check when the behavior is in Godot. Wire a new test module into `tools/eoa_full_test_gates.sh` when the quick list would otherwise skip it.
3. Run `tools/eoa_full_test_gates.sh --quick` from that worktree. A new failing name fails the slice. The existing reds inside `unit_board_play_path` are the known set. Trust the log's `QUICK_EXIT` line.
4. Do not import the same Godot project with two processes.
5. Add one SNAPSHOT HOLD row on this branch, after the last row that is actually on this branch. Do not copy another draft's row.
6. Commit as `mikef <mikef@local>` with `git commit -F` a message file, then delete the file. Push with `git -C <worktree> push -u origin HEAD:<branch>`. Never push `main`. Never force-push.
7. Open a draft pull request with the GitHub connection, then read it back. Confirm `draft`, head SHA, base SHA, and `mergeable_state`.
8. Stop before merge. Report the URL. Do not start a second slice in the same run.

## Forbidden

Tan NUTS recolor or hide. Hiding `ProvEdge_`. Forcing a `_sync_border_lod` rebuild. Densify. Province renumber. `world_full` id edits. More highway width. More city labels. Airfield level-badge rebuilds, mipmaps off, seed moves, or oval and circle hit-fraction changes. Chip pick, supply overlay, legend, Begin/Close, camera, and GameData. Turning the known quick reds green. Capital stars at Europe Home.

The live Play fail `5c60f366` painted a sage web and a Köln click hit Luxembourg after a province-edge hide. Coast and frontier width updates must not rebuild that edge set.

## Stop

Do not open a slice when every remaining item is an open draft, the human M6 notes, an honest soft 30fps miss, or an out-of-scope item above. Report the open draft URLs and wait. Do not merge those drafts.
