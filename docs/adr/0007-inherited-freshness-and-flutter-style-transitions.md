---
status: accepted
---

# Children inherit freshness, and transitions work like Flutter's routes

Amends ADR 0004 D3 and the page transitions from #67.

## Freshness is inherited

ADR 0004 D3 sets freshness in three layers: the tree, the link and the call
site. A child link now inherits its nearest ancestor's setting before its own:
tree, then each ancestor from the root down, then the link, then the call
site. The most specific setting wins, as before. A subtree of drafts is
marked fresh once, at its root.

## Transitions follow Flutter's `PageRoute`

A transition belongs to the route type of the page, as in #67, and it plays
the way a Flutter `PageRoute` does:

- The builder gets a primary animation and a secondary animation, like
  `buildTransitions(context, animation, secondaryAnimation, child)`.
- Push and go play the incoming page's transition forward. The page it covers
  gets the incoming page's animation as its secondary animation.
- Back plays the leaving page's transition in reverse, so the user sees the
  push undone. The page that comes back gets the reverse of its secondary
  animation.
- Replace plays the incoming transition forward, with no reverse for the page
  it replaces.
- A route type without a transition swaps at once.
