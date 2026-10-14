#!/usr/bin/env python3
"""Build design/44-sync-raids/versions/{a,b,c}.html from revision 1's approved index.html (the host)."""
import sys, pathlib

here = pathlib.Path(__file__).parent
out_dir = pathlib.Path(sys.argv[1])
host = (out_dir.parent / "host.html").read_text()
sync_js = (here / "sync.js").read_text()
sync_css = (here / "sync.css").read_text()
out_dir = pathlib.Path(sys.argv[1])

def rep(s, old, new, count=1):
    n = s.count(old)
    if n != count:
        raise SystemExit(f"expected {count} of {old[:70]!r}, found {n}")
    return s.replace(old, new)

base = host
base = rep(base, "</style>", sync_css + "</style>")
# Switcher lists: only revision 2's states
a = base.index("const GROUPS = [")
b = base.index("const STATE_IDS = GROUPS.flatMap((g) => g[1]);")
base = base[:a] + sync_js + "\nconst GROUPS = SYNC_GROUPS;\nconst LABELS = SYNC_LABELS;\n" + base[b:]
base = rep(base, "function sceneFor(state, V) {\n", "function sceneFor(state, V) {\n  if (state.startsWith(\"ask-\") || state.startsWith(\"sync-\")) return syncScene(state, V);\n")
# Revision 1's other tabs and the Test drop button are inert here (their screens are unchanged, in revision 1)
base = rep(base, 'const target = id === "awards" ? (o.readOnly ? "awards-officer" : "awards") : id === "reserves" ? "reserves" : "sync-loaded";',
           'const target = id === "sync" ? "sync-chosen" : "";')
base = rep(base, 'btn("Test drop", { size: "tiny", goto: "practice" })', 'btn("Test drop", { size: "tiny" })')
base = rep(base, '<div class="zone">Molten Core</div>', '<div class="zone">${esc(o.zone || "Molten Core")}</div>')
base = rep(base, 'data-goto="awards" aria-label="Bureaucracy Forever: open the window"', 'data-goto="sync-chosen" aria-label="Bureaucracy Forever: open the window"')

for key in ["a", "b", "c"]:
    s = rep(base, 'boot(VERSIONS["d"]);', f'boot(Object.assign({{}}, VERSIONS.d, SYNC_V.{key}, {{ syncKey: "{key}" }}));')
    s = rep(s, "<title>Design #9, version D: loot pop-up and officers' window</title>",
            f"<title>Design #44, version {key.upper()}: the raid question and the Sync tab</title>")
    (out_dir / f"{key}.html").write_text(s)
    print("wrote", out_dir / f"{key}.html", len(s))
