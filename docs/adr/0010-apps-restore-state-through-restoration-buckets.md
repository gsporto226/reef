---
status: accepted
---

# Apps restore their own state through restoration buckets

Generalises the windowing record's `extra` (spec §11). Modelled on Flutter's
restoration framework (`RestorationBucket`, `RestorableProperty`,
`RestorationMixin`).

`controller.extra` is one JSON value the app reads and writes by hand. Apps
need many independent pieces of state (bookmarks, settings, a panel's open
state) restored after the OS kills the app, without one owner coordinating
them.

## Decision

- reef gives a tree of **restoration buckets**. A bucket has an id, holds
  JSON-encodable values by key, and has child buckets. The root bucket is
  saved in the `HibernationStore` under a reserved id, next to the
  windowing record, and loaded before the first frame.
- Widgets claim a child bucket by id through a mixin, like
  `RestorationMixin`, and register **restorable values** (typed, with a
  codec and a default). A value restores from the bucket when it is
  claimed and writes back when it changes.
- State that is not tied to a widget claims a bucket from the controller,
  by id.
- Saving is debounced: changes are written once per frame.
- A bucket whose values fail to decode is dropped and the defaults are
  used, like a bad windowing record (spec §11).
- `controller.extra` becomes a value in a reserved bucket and is
  deprecated, then removed once callers move over.

## Considered options

- **Flutter's own restoration framework.** Rejected: it restores only
  through the engine's restoration data on platforms that send it (Android,
  iOS), not on desktop, and not into reef's `HibernationStore`.
- **Keep `extra`.** Rejected: one blob means one owner for unrelated state.

## Consequences

- Bookmarks in the browser are a restorable value in a `browser` bucket.
- Bucket ids are part of saved data; renaming one drops its state, as a
  path rename does for buffers (ADR 0004 D4).
