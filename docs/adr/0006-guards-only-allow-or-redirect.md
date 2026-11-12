---
status: accepted
---

# Guards only allow or redirect

Amends ADR 0004's guards section. A guard decides **allow** or **redirect**.
There is no block decision.

A block has no good meaning when guards re-run without a navigation (ADR 0004
D8): there is nothing to veto, so the blocked page would stay visible. A
redirect always says where the user goes instead, on a navigation and on a
re-check alike.

## Consequences

- A page that must not be shown redirects to another route, such as login, a
  not-found or a "no access" page the app defines.
- Guards carry no block reason, so `reef_router` drops its `formularium`
  dependency if nothing else needs it.
