---
status: accepted
---

# A link can say which entries share one mounted page

Amends how windowing keys a window's page (spec §5). ADR 0004 D4 still holds:
the buffer kind is derived from the mounted path.

A window's page is keyed by (window, buffer). Every navigation that changes
the buffer mounts a new page. In the browser, an SPA `pushState` that changes
the path is a new buffer, so the webview is rebuilt and the page reloads. The
history entry is right; remounting the page is wrong.

## Decision

- A link may declare a **page identity**: a function from its route value to
  a value. Two entries of that link with equal identities share one mounted
  page. Without it, the identity is the buffer, so nothing changes for
  existing links.
- The page key becomes (window, page identity). A navigation between entries
  with the same identity keeps the page mounted: the history entry is pushed
  or replaced as usual, and the page reads the new buffer and arguments from
  its window (it rebuilds; it does not remount).
- Such a navigation plays no page transition (ADR 0007), because no page
  enters or leaves.
- Back and forward between entries with the same identity also keep the
  page. The app decides how the page reacts (the browser: a same-document
  `history.go` instead of a reload).

## Considered options

- **Key pages by window only.** Rejected: every navigation would keep the
  page, so pages for different routes would have to handle any buffer, and
  transitions would never play.
- **Leave it, and make pushState query-only.** Rejected: real sites change
  the path, and this app exists to exercise them.

## Consequences

- The browser's `WebPage` declares identity (scheme, host): pushState within
  an origin keeps the webview; a cross-origin navigation remounts.
- A page with an identity must not cache its buffer at build time; it reads
  it from its window.
