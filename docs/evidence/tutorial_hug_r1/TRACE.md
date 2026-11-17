# TUTORIAL-HUG-FIX r1 — step 11→12 hug trace

Instrument: `EOA_TUTORIAL_HUG_TRACE=50` on `HeadlessTutorial1Test` at tip `12b3db7f` product (30-frame shrink loop + label `reset_size()`), 50× real save→ending and 50× isolated ending. Box: Godot 4.7.1.stable `a13da4feb`.

**Verdict: both hypotheses.** Combined min drops when labels receive their final width (348→410, body 89→66, card 276→253). `_hug_content` then **cannot keep that shrink**: it assigns `size.x = _locked_width` (380), re-wraps the body, and grows y back to 276. e471e125 3-frame hug on real 11→12:

```
f=0 card=438x276 min=276 body=348x89
f=1 card=438x253 min=253 body=410x66   ← shrink works
f=2 card=380x276 min=276 body=352x89   ← lock width flips wrap, y grows back
```

A 30-frame cap still calling `_hug_content` (or `reset_size()` on labels) repeats that fight. After `set_process(false)`, a later unwrap leaves `size.y=276` vs `min=253`.

This cloud run's 50×50 on the 12b3db7f 30-frame+reset_size product settled at frame 1 to 253 (shrink-only skipped later hugs). The box gate still saw the 276 vs 253 miss (2/10). Same +23px extra body line.

## Passing trial (11→12, trial 1)

```
save_h=269.0 save_min=269.0
present n=12 title_len=21 body_len=163
f=0 card=438.0x276.0 min=276.0 proc=true
  keys=sz=312x21 vis=false dont=sz=242x31 vis=true
  title[sz=348x24 min=1x24 cms=348x0 vis=true len=21]
  body[sz=348x89 min=1x89 cms=348x0 vis=true len=163]
  status[sz=348x18 min=1x18 cms=348x0 vis=false len=0]
f=1 card=438.0x253.0 min=253.0 proc=true
  keys=sz=312x21 vis=false dont=sz=410x31 vis=true
  title[sz=410x24 min=1x24 cms=348x0 vis=true len=21]
  body[sz=410x66 min=1x66 cms=348x0 vis=true len=163]
  status[sz=348x18 min=1x18 cms=348x0 vis=false len=0]
RESULT miss=false settled_at=1 size.y=253.0 min.y=253.0
```

At present, wrap is still the fitted 348px slot (`_fit_width` `w-32`). Body is 89px (~4 lines). Combined min 276, hug sets `size.y=276`. Next layout allocates ~410px; body unwraps to 66px (−23); combined min 253.

## Failing shape (box gate, same numbers)

When that unwrap lands *after* the 30-frame `_process` cap:

- During the cap, `size.y` stays ~276 and `combined_min` is still ~276 (or `reset_size()` keeps recomputing wrap at `cms.x=348`).
- After `set_process(false)`, labels expand 348→410, min drops to 253, size stays 276.

```
P1a card hug: step 12 size.y=276.0 > combined_min.y+1 (253.0)
```

## Product follow-through

Drop the frame-cap loop and label `reset_size()`. Shrink-only hug on `minimum_size_changed` (card + title/body/status/checkbox/keys row), deferred. Idle `_process` stays off. Never `reset_size()` / `size.x=0` on the card.
