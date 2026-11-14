"""Lists solid paints with no bound variable under the Components board and screens."""
import json
from fc import FC

f = FC()
C = json.load(open("ids.json"))
bad = []


def walk(n, path):
    bv = n.get("boundVariables", {})
    for kind in ("fills", "strokes"):
        for i, p in enumerate(n.get(kind) or []):
            if p.get("type") == "solid" and p.get("visible", True) is not False:
                if not any(k.startswith(kind[:-1]) for k in bv):
                    bad.append(f"{path}/{n['name']} {kind}[{i}] {p.get('color')}")
    for c in n.get("children", []):
        walk(c, f"{path}/{n['name']}")


for root in [C["board"], *C["screens"].values()]:
    walk(f.node(root), "")
print("\n".join(bad) or "all solid paints bound")
