"""Builds the Browser integration-app design in the open FigCraft document.

Every colour, spacing, radius and fixed size is bound to a `Browser` variable
(see tokens.json). Screens hold component instances only.
"""
from fc import FC

f = FC()
R = f.run

SANS, SERIF = "Source Sans 3", "Source Serif 4"

# 24-unit stroke icons (Lucide-style geometry; glyph geometry stays unbound).
ICONS = {
    "back": "M15 18l-6-6 6-6",
    "forward": "M9 18l6-6-6-6",
    "reload": "M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7",
    "close": "M6 6l12 12M18 6L6 18",
    "plus": "M12 5v14M5 12h14",
    "lock": "M6 11h12v9H6zM8 11V8a4 4 0 0 1 8 0v3",
    "globe": "M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18",
    "menu": "M4 7h16M4 12h16M4 17h16",
    "search": "M11 4a7 7 0 1 0 0 14a7 7 0 1 0 0-14M20 20l-4-4",
    "pip": "M3 5h18v14H3zM12 12h7v5h-7z",
    "download": "M12 4v11M7 10l5 5 5-5M5 20h14",
    "star": "M12 3l2.8 5.7 6.2.9-4.5 4.4 1 6.2L12 17.3 6.5 20.2l1-6.2L3 9.6l6.2-.9z",
    "split": "M3 5h18v14H3zM12 5v14",
    "mirror": "M3 5h18v14H3zM12 5v14M7 12h2M15 12h2",
}


def bind_all(id, **fields):
    for field, var in fields.items():
        if var:
            f.bind(id, field, var)


def frame(parent, name, w=None, h=None, *, layout=None, gap=None, pad=None, fill=None, stroke=None,
          radius=None, sizingH=None, sizingV=None, mainAlign=None, crossAlign=None, x=0, y=0,
          wv=None, hv=None, clip=None, strokeSides=None):
    """Auto-layout frame. pad = 'space/x' or (vert, horiz) token names; w/h numbers, wv/hv tokens."""
    props = {"fill": "#FFFFFF" if fill else None, "layout": layout}
    for k, v in dict(mainAlign=mainAlign, crossAlign=crossAlign, sizingH=sizingH, sizingV=sizingV,
                     clip=clip).items():
        if v is not None:
            props[k] = v
    if stroke:
        props.update(stroke="#000000", strokeWeight=1, strokeAlign="inside")
        if strokeSides:
            props["strokeSides"] = strokeSides
    id = R("node.create", type="frame", name=name, parent=parent, x=x, y=y,
           width=w or 100, height=h or 100, props=props, select=False)["id"]
    bind_all(id, fill=fill, stroke=stroke, cornerRadius=radius, gap=gap, width=wv, height=hv)
    if pad:
        v, hz = (pad, pad) if isinstance(pad, str) else pad
        bind_all(id, paddingTop=v, paddingBottom=v, paddingLeft=hz, paddingRight=hz)
    if fill is None:
        R("node.set", ids=[id], fill=None)
    return id


def text(parent, s, *, size=15, style="Regular", family=SANS, color="text/primary", name=None, fill_w=False,
         wrap=False):
    props = {"fontFamily": family, "fontStyle": style, "fontSize": size, "lineHeight": "140%"}
    if fill_w:
        props.update(sizingH="fill", textAutoResize="height" if wrap else "truncate")
    id = R("node.create", type="text", parent=parent, text=s, name=name or s[:24], props=props,
           select=False)["id"]
    f.bind(id, "fill", color)
    return id


def scale_path(d, k=20 / 24):
    """Scale SVG path data by k, leaving arc flags alone."""
    import re
    out, toks = [], re.findall(r"[A-Za-z]|-?\d*\.?\d+", d)
    cmd, i = None, 0
    for t in toks:
        if t.isalpha():
            cmd, i = t, 0
            out.append(t)
            continue
        flag = cmd in "aA" and i % 7 in (2, 3, 4)
        out.append(t if flag else f"{float(t) * k:.3f}")
        i += 1
    return " ".join(out)


def icon(parent, key, color="text/primary"):
    box = frame(parent, f"icon/{key}", 24, 24)
    R("node.set", ids=[box], fill=None)
    f.bind(box, "width", "size/icon")
    f.bind(box, "height", "size/icon")
    v = R("node.create", type="vector", parent=box, path=scale_path(ICONS[key]), name=key,
          props={"fill": None, "stroke": "#000000", "strokeWeight": 1.75, "strokeCap": "round",
                 "strokeJoin": "round"},
          select=False)["id"]
    f.bind(v, "stroke", color)
    return box


def component(id, name):
    R("node.set", ids=[id], name=name)
    return R("component.create", ids=[id])["id"]


def text_prop(comp, layer, name):
    R("component.addProperty", id=comp, name=name, type="text", layer=layer)


def instance(main, parent, x=0, y=0, **sizing):
    id = R("instance.create", component=main, parent=parent, x=x, y=y)["id"]
    if sizing:
        R("node.set", ids=[id], **sizing)
    return id


# ---------------------------------------------------------------- components
def board(name, x, y, w, h):
    id = R("node.create", type="frame", name=name, x=x, y=y, width=w, height=h, select=False,
           props={"fill": "#FFFFFF"})["id"]
    f.bind(id, "fill", "surface/page")
    return id


def variants(main, prop, default, others):
    """Turn `main` into a set with `prop`=default plus one variant per other value."""
    R("node.set", ids=[main], name=f"{prop}={default}")
    ids = {default: main}
    for v in others:
        ids[v] = R("component.addVariant", id=main, property=prop, value=v)["id"]
    return R("component.properties", id=main)["set"], ids


def named(id, name, **props):
    R("node.set", ids=[id], name=name, **props)
    return id


def build_components(B):
    C = {}
    # Icon buttons: one component per glyph, 44x44 target.
    for i, k in enumerate(ICONS):
        b = frame(B, f"Icon button/{k}", 44, 44, layout="horizontal", mainAlign="center",
                  crossAlign="center", radius="radius/sm", wv="size/control/md", hv="size/control/md",
                  x=40 + i * 56, y=40)
        icon(b, k)
        C[k] = component(b, f"Icon button/{k}")

    # Tab: State=Default|Active, Title text.
    t = frame(B, "Tab", 220, 44, layout="horizontal", gap="space/8", pad=("space/4", "space/12"),
              radius="radius/sm", crossAlign="center", wv="tab/width", hv="tabbar/height", x=40, y=120)
    icon(t, "globe", "text/muted")
    title = text(t, "Fixture page", size=14, name="Title", fill_w=True)
    named(instance(C["close"], t), "Close tab")
    c = component(t, "Tab")
    text_prop(c, title, "Title")
    C["tab"], v = variants(c, "State", "Default", ["Active"])
    R("node.set", ids=[v["Active"]], fill="#FFFFFF")
    f.bind(v["Active"], "fill", "surface/tab/active")
    named(C["tab"], "Tab")

    # Address bar: URL text, lock glyph.
    a = frame(B, "Address bar", 480, 44, layout="horizontal", gap="space/8", pad=(None, "space/16"),
              fill="surface/field", stroke="border/hairline", radius="radius/pill", crossAlign="center",
              hv="addressbar/height", x=40, y=200)
    icon(a, "lock", "text/muted")
    url = text(a, "localhost:8080/links.html", name="URL", fill_w=True)
    C["address"] = component(a, "Address bar")
    text_prop(C["address"], url, "URL")

    # Toolbar: back, forward, reload, address bar, page actions.
    tb = frame(B, "Toolbar", 1280, 56, layout="horizontal", gap="space/4", pad=(None, "space/12"),
               fill="surface/chrome", stroke="border/hairline", strokeSides=[0, 0, 1, 0],
               crossAlign="center", wv="shell/width", hv="toolbar/height", x=40, y=280)
    for k, label in [("back", "Back"), ("forward", "Forward"), ("reload", "Reload")]:
        named(instance(C[k], tb), label)
    named(instance(C["address"], tb), "Address bar", sizingH="fill")
    for k, label in [("star", "Bookmark"), ("split", "Open in split"), ("mirror", "Mirror split"),
                     ("pip", "Picture in picture"), ("download", "Downloads"), ("menu", "Menu")]:
        named(instance(C[k], tb), label)
    C["toolbar"] = component(tb, "Toolbar")

    # Chrome: tab strip (slot "Tabs" + new tab button) over the toolbar.
    ch = frame(B, "Chrome", 1280, 100, layout="vertical", fill="surface/chrome", sizingV="hug",
               wv="shell/width", x=40, y=360)
    strip = frame(ch, "Tab strip", 1280, 44, layout="horizontal", gap="space/4", pad=(None, "space/8"),
                  crossAlign="center", hv="tabbar/height", sizingH="fill")
    tabs = frame(strip, "Tabs", 100, 44, layout="horizontal", gap="space/4", sizingH="hug", sizingV="fill")
    named(instance(C["tab"], tabs), "Tab")
    named(instance(C["plus"], strip), "New tab")
    named(instance(C["toolbar"], ch), "Toolbar", sizingH="fill")
    C["chrome"] = component(ch, "Chrome")
    R("component.makeSlot", id=tabs, name="Tabs", preferred=[C["tab"]])

    # Window: a reef window, slot "Content". No focus border: reef draws none.
    w = frame(B, "Window", 600, 360, layout="vertical", fill="surface/page", radius="radius/sm", clip=True,
              x=40, y=500)
    body = frame(w, "Content", 600, 360, layout="vertical", sizingH="fill", sizingV="fill")
    c = component(w, "Window")
    R("component.makeSlot", id=body, name="Content")
    C["window"], v = variants(c, "Focus", "Default", ["Focused"])
    named(C["window"], "Window")

    # Web page: what a fixture page looks like inside a window.
    p = frame(B, "Web page", 600, 360, layout="vertical", gap="space/16", pad="space/40",
              fill="surface/page", x=680, y=500)
    h = text(p, "Links fixture", size=28, style="SemiBold", family=SERIF, name="Heading")
    text(p, "A fixture page served by the test HttpServer. Follow a link to push an entry.",
         color="text/muted", name="Body", fill_w=True)
    link = text(p, "Go to page two", color="accent/default", name="Link")
    R("node.set", ids=[link], textDecoration="underline")
    frame(p, "Block", 520, 120, fill="fixture/block", radius="radius/md", sizingH="fill")
    C["page"] = component(p, "Web page")
    text_prop(C["page"], h, "Heading")
    text_prop(C["page"], link, "Link")

    # Float panel: title bar + slot "Body". Used by PiP, find and downloads.
    fl = frame(B, "Float panel", 320, 200, layout="vertical", fill="surface/float", stroke="border/hairline",
               radius="radius/md", clip=True, x=1320, y=500)
    hd = frame(fl, "Header", 320, 44, layout="horizontal", gap="space/8", pad=(None, "space/12"),
               crossAlign="center", stroke="border/hairline", strokeSides=[0, 0, 1, 0], sizingH="fill",
               hv="size/control/md")
    ft = text(hd, "Find in page", size=14, style="SemiBold", name="Title", fill_w=True)
    named(instance(C["close"], hd), "Close")
    fb = frame(fl, "Body", 320, 156, layout="vertical", gap="space/8", pad="space/12", sizingH="fill",
               sizingV="fill")
    C["float"] = component(fl, "Float panel")
    text_prop(C["float"], ft, "Title")
    R("component.makeSlot", id=fb, name="Body")

    # Dock target: the drop zone shown while dragging a float.
    d = frame(B, "Dock target", 200, 300, layout="vertical", mainAlign="center", crossAlign="center",
              fill="dock/target", stroke="accent/default", radius="radius/md", x=1680, y=500)
    dl = text(d, "Dock left", size=14, style="SemiBold", color="accent/default", name="Label")
    C["dock"] = component(d, "Dock target")
    text_prop(C["dock"], dl, "Label")

    # List row: history / bookmarks / downloads entries.
    r = frame(B, "List row", 560, 48, layout="horizontal", gap="space/12", pad=(None, "space/16"),
              crossAlign="center", hv="size/control/lg", radius="radius/sm", x=40, y=900)
    icon(r, "globe", "text/muted")
    col = frame(r, "Text", 400, 40, layout="vertical", sizingH="fill", sizingV="hug")
    rt = text(col, "Links fixture", size=15, name="Title", fill_w=True)
    ru = text(col, "localhost:8080/links.html", size=13, color="text/muted", name="URL", fill_w=True)
    C["row"] = component(r, "List row")
    text_prop(C["row"], rt, "Title")
    text_prop(C["row"], ru, "URL")

    # Switch (On=false|true) and the toggle row that carries it.
    sw = frame(B, "Switch", 40, 24, layout="horizontal", pad="space/2", fill="border/hairline",
               radius="radius/pill", crossAlign="center", x=640, y=900)
    frame(sw, "Knob", 20, 20, fill="surface/field", radius="radius/pill")
    c = component(sw, "Switch")
    C["switch"], v = variants(c, "On", "false", ["true"])
    f.bind(v["true"], "fill", "accent/default")
    R("node.set", ids=[v["true"]], mainAlign="max")
    named(C["switch"], "Switch")
    tr = frame(B, "Toggle row", 560, 48, layout="horizontal", gap="space/12", pad=(None, "space/16"),
               crossAlign="center", hv="size/control/lg", x=720, y=900)
    tl = text(tr, "Lock settings", name="Label", fill_w=True)
    instance(C["switch"], tr)
    C["toggle"] = component(tr, "Toggle row")
    text_prop(C["toggle"], tl, "Label")

    # Primary button.
    bt = frame(B, "Button", 160, 44, layout="horizontal", pad=(None, "space/20"), fill="accent/default",
               radius="radius/pill", mainAlign="center", crossAlign="center", hv="size/control/md",
               sizingH="hug", x=1320, y=900)
    bl = text(bt, "Open new tab", style="SemiBold", color="accent/on", name="Label")
    C["button"] = component(bt, "Button")
    text_prop(C["button"], bl, "Label")

    # Badge: marks a mirror (shared) view.
    bd = frame(B, "Badge", 80, 24, layout="horizontal", gap="space/4", pad=("space/2", "space/8"),
               fill="surface/selected", radius="radius/pill", crossAlign="center", sizingH="hug", x=1520, y=900)
    bdl = text(bd, "Mirror", size=12, style="SemiBold", color="accent/default", name="Label")
    C["badge"] = component(bd, "Badge")
    text_prop(C["badge"], bdl, "Label")
    return C




def tidy_sets(C):
    """Lay variant sets out in a row so variants don't overlap their neighbours."""
    for k in ("tab", "window", "switch"):
        R("node.set", ids=[C[k]], layout="horizontal", sizingH="hug", sizingV="hug", stroke=None)
        bind_all(C[k], gap="space/16", paddingTop="space/16", paddingBottom="space/16",
                 paddingLeft="space/16", paddingRight="space/16")
    at = {"tab": (40, 100), "address": (600, 120), "toolbar": (40, 200), "chrome": (40, 280),
          "window": (40, 420), "float": (1340, 420), "dock": (1700, 420), "page": (40, 840),
          "row": (680, 840), "toggle": (680, 920), "switch": (1280, 840), "button": (680, 1000),
          "badge": (900, 1010)}
    for k, (x, y) in at.items():
        R("node.set", ids=[C[k]], x=x, y=y)


# ---------------------------------------------------------------- page components
def build_pages(B, C):
    """Internal pages and float bodies, as components so screens hold instances only."""
    # Let screens set the URL: Address bar exposed in Toolbar, Toolbar exposed in Chrome.
    R("component.exposeInstance", id=f.find(C["toolbar"], "Address bar")[0])
    R("component.exposeInstance", id=f.find(C["chrome"], "Toolbar")[0])

    def page(name, x, y, heading, center=False):
        p = frame(B, name, 600, 400, layout="vertical", gap="space/16", pad="space/40",
                  fill="surface/page", x=x, y=y, crossAlign="center" if center else None,
                  mainAlign="center" if center else None)
        text(p, heading, size=28, style="SemiBold", family=SERIF, name="Heading")
        return p

    def row(parent, title, url):
        r = instance(C["row"], parent)
        R("instance.setProperties", ids=[r], properties={"Title": title, "URL": url})
        R("node.set", ids=[r], sizingH="fill")
        return r

    P = {}
    p = page("Page/New tab", 40, 1300, "New tab", center=True)
    s = instance(C["address"], p)
    R("instance.setProperties", ids=[s], properties={"URL": "Search or type a URL"})
    R("node.set", ids=[s], name="Address bar")
    f.bind(s, "width", "newtab/search/width")
    P["newtab"] = component(p, "Page/New tab")

    for key, heading, rows in [
        ("history", "History", [("Page two", "localhost:8080/two.html"),
                                ("Links fixture", "localhost:8080/links.html"),
                                ("SPA fixture", "localhost:8080/spa.html#/b"),
                                ("Redirect target", "localhost:8080/target.html")]),
        ("bookmarks", "Bookmarks", [("Links fixture", "localhost:8080/links.html"),
                                    ("SPA fixture", "localhost:8080/spa.html")]),
    ]:
        p = page(f"Page/{heading}", 680 if key == "history" else 1320, 1300, heading)
        for t, u in rows:
            row(p, t, u)
        P[key] = component(p, f"Page/{heading}")

    p = page("Page/Settings", 40, 1760, "Settings")
    t = instance(C["toggle"], p)
    R("instance.setProperties", ids=[t], properties={"Label": "Restore session on start"})
    R("node.set", ids=[t], sizingH="fill")
    text(p, "Settings is guarded: while it is locked from the menu, opening it redirects to the new tab page.",
         size=14, color="text/muted", name="Guard note", fill_w=True, wrap=True)
    P["settings"] = component(p, "Page/Settings")

    p = page("Page/Not found", 680, 1760, "Page not found", center=True)
    pt = text(p, "/nope", color="text/muted", name="Path")
    b = instance(C["button"], p)
    R("node.set", ids=[b], name="Open new tab")
    P["notfound"] = component(p, "Page/Not found")
    text_prop(P["notfound"], pt, "Path")

    # Float bodies.
    fb = frame(B, "Body/Find", 296, 100, layout="vertical", sizingV="hug", gap="space/8", x=1320, y=1760)
    s = instance(C["address"], fb)
    R("instance.setProperties", ids=[s], properties={"URL": "page two"})
    R("node.set", ids=[s], name="Find field", sizingH="fill")
    text(fb, "2 of 5 matches", size=13, color="text/muted", name="Matches")
    P["find"] = component(fb, "Body/Find")

    db = frame(B, "Body/Downloads", 296, 100, layout="vertical", sizingV="hug", x=1660, y=1760)
    row(db, "report.pdf", "Done · 1.2 MB")
    row(db, "fixture.zip", "Done · 340 KB")
    P["downloads"] = component(db, "Body/Downloads")

    mb = frame(B, "Body/Menu", 296, 100, layout="vertical", sizingV="hug", x=1320, y=1960)
    for label in ("History", "Bookmarks", "Settings"):
        r = instance(C["row"], mb)
        R("instance.setProperties", ids=[r], properties={"Title": label, "URL": "/" + label.lower()})
        R("node.set", ids=[r], sizingH="fill", name=label)
    t = instance(C["toggle"], mb)
    R("node.set", ids=[t], sizingH="fill", name="Lock settings")
    P["menu"] = component(mb, "Body/Menu")
    return P


# ---------------------------------------------------------------- screens
def build_screens(C, x0=0, y0=2500):
    S = {}
    col = [0]

    def screen(name, tabs, url):
        """A 1280x800 shell: chrome (tabs, toolbar with `url`) over a workspace."""
        i = len(S)
        s = frame(None, name, 1280, 800, layout="vertical", fill="surface/chrome", clip=True,
                  wv="shell/width", hv="shell/height", x=x0 + (i % 3) * 1400, y=y0 + (i // 3) * 920)
        ch = named(instance(C["chrome"], s), "Chrome", sizingH="fill")
        for j, (title, active) in enumerate(tabs):
            t = R("instance.slotInsert", id=ch, slot="Tabs", component=C["tab"], replace=j == 0)["id"]
            R("instance.setProperties", ids=[t],
              properties={"Title": title, "State": "Active" if active else "Default"})
            R("node.set", ids=[t], name=f"Tab: {title}")
        addr = [n["id"] for n in R("instance.exposed", id=ch)["instances"] if n["name"] == "Address bar"]
        R("instance.setProperties", ids=addr, properties={"URL": url})
        ws = frame(s, "Workspace", 1280, 700, layout="horizontal", gap="space/8", pad="space/8",
                   sizingH="fill", sizingV="fill")
        S[name] = s
        return s, ws

    def window(ws, content, focused=True, props=None, name="Window"):
        w = named(instance(C["window"], ws), name, sizingH="fill", sizingV="fill")
        R("instance.setProperties", ids=[w], properties={"Focus": "Focused" if focused else "Default"})
        c = R("instance.slotInsert", id=w, slot="Content", component=content, replace=True)["id"]
        R("node.set", ids=[c], sizingH="fill", sizingV="fill")
        if props:
            R("instance.setProperties", ids=[c], properties=props)
        return w

    def float_(s, title, body, x, y, w=None, h=None, name=None, wv=None, hv=None, page_props=None):
        fl = named(instance(C["float"], s), name or f"Float: {title}", absolute=True, x=x, y=y)
        R("instance.setProperties", ids=[fl], properties={"Title": title})
        if w:
            R("node.set", ids=[fl], width=w, height=h)
        if not hv:
            R("node.set", ids=[fl], sizingV="hug")
        for field, v in (("width", wv), ("height", hv)):
            if v:
                f.bind(fl, field, v)
        b = R("instance.slotInsert", id=fl, slot="Body", component=body, replace=True)["id"]
        R("node.set", ids=[b], sizingH="fill", sizingV="fill" if body == C["page"] else "hug")
        if page_props:
            R("instance.setProperties", ids=[b], properties=page_props)
        return fl

    LINKS = "localhost:8080/links.html"
    TWO = "localhost:8080/two.html"
    links = {"Heading": "Links fixture", "Link": "Go to page two"}
    two = {"Heading": "Page two", "Link": "Back to links"}

    s, ws = screen("01 New tab", [("New tab", True)], "")
    window(ws, C["newtab"])

    s, ws = screen("02 Web page", [("Links fixture", True), ("New tab", False)], LINKS)
    window(ws, C["page"], props=links)

    s, ws = screen("03 Split", [("Links fixture", True)], TWO)
    window(ws, C["page"], focused=False, props=links, name="Window: left")
    window(ws, C["page"], props=two, name="Window: right (focused)")

    s, ws = screen("04 Mirror split", [("Links fixture", True)], LINKS)
    window(ws, C["page"], focused=False, props=links, name="Window: mirror A")
    window(ws, C["page"], props=links, name="Window: mirror B (focused)")
    for x in (24, 664):
        named(instance(C["badge"], s), "Mirror badge", absolute=True, x=x, y=124)

    s, ws = screen("05 Floating windows", [("Links fixture", True)], LINKS)
    window(ws, C["page"], props=links)
    float_(s, "Find in page", C["find"], 940, 120, name="Float (window scope): Find")
    float_(s, "Downloads", C["downloads"], 860, 104, name="Float (tab scope): Downloads")
    float_(s, "Picture in picture", C["page"], 900, 560, wv="float/pip/width", hv="float/pip/height",
           name="Float (shell scope): PiP", page_props=two)
    R("node.set", ids=f.find(s, "Float (window scope): Find"), x=24, y=120)

    s, ws = screen("06 Dock", [("Links fixture", True)], LINKS)
    window(ws, C["page"], props=links)
    for label, x in (("Dock left", 16), ("Dock right", 1064)):
        d = named(instance(C["dock"], s), label, absolute=True, x=x, y=116)
        R("instance.setProperties", ids=[d], properties={"Label": label})
        R("node.set", ids=[d], height=668)
    float_(s, "Picture in picture", C["page"], 460, 300, wv="float/pip/width", hv="float/pip/height",
           name="Float (shell scope): PiP, dragging", page_props=two)

    s, ws = screen("07 History", [("History", True)], "/history")
    window(ws, C["history"])
    s, ws = screen("08 Bookmarks", [("Bookmarks", True)], "/bookmarks")
    window(ws, C["bookmarks"])
    s, ws = screen("09 Settings and menu", [("Settings", True)], "/settings")
    window(ws, C["settings"])
    float_(s, "Menu", C["menu"], 940, 104, name="Float (tab scope): Menu")
    s, ws = screen("10 Not found", [("Not found", True)], "/nope")
    window(ws, C["notfound"])
    return S


if __name__ == "__main__":
    import json
    # Builds everything into the open document; run on an empty file.
    B = board("Components", 0, 0, 2000, 2300)
    C = build_components(B)
    tidy_sets(C)
    C.update(build_pages(B, C))
    C["board"] = B
    C["screens"] = build_screens(C)
    json.dump(C, open("ids.json", "w"), indent=1)
