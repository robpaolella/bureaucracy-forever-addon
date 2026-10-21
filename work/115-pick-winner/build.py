#!/usr/bin/env python3
"""Build design/115-pick-winner/versions/{a,b,c}.html from revision 1's approved index.html (the host)."""
import sys, pathlib

here = pathlib.Path(__file__).parent
out_dir = pathlib.Path(sys.argv[1])
host = (out_dir.parent / "host.html").read_text()
pick_js = (here / "pick.js").read_text()
pick_css = (here / "pick.css").read_text()

def rep(s, old, new, count=1):
    n = s.count(old)
    if n != count:
        raise SystemExit(f"expected {count} of {old[:70]!r}, found {n}")
    return s.replace(old, new)

base = rep(host, "</style>", pick_css + "</style>")
# Switcher lists: only revision 3's states
a = base.index("const GROUPS = [")
b = base.index("const STATE_IDS = GROUPS.flatMap((g) => g[1]);")
base = base[:a] + pick_js + "\nconst GROUPS = PW_GROUPS;\nconst LABELS = PW_LABELS;\n" + base[b:]
base = rep(base, "function sceneFor(state, V) {\n", "function sceneFor(state, V) {\n  if (state.startsWith(\"pick-\")) return pickScene(state, V);\n")
# Revision 1's other tabs and the Test drop button are inert here (their screens are unchanged)
base = rep(base, 'const target = id === "awards" ? (o.readOnly ? "awards-officer" : "awards") : id === "reserves" ? "reserves" : "sync-loaded";',
           'const target = id === "awards" ? "pick-start" : "";')
base = rep(base, 'btn("Test drop", { size: "tiny", goto: "practice" })', 'btn("Test drop", { size: "tiny" })')
base = rep(base, 'data-goto="awards" aria-label="Bureaucracy Forever: open the window"', 'data-goto="pick-start" aria-label="Bureaucracy Forever: open the window"')

for key in sys.argv[2:] or ["a", "b", "c"]:
    s = rep(base, 'boot(VERSIONS["d"]);', f'boot(Object.assign({{}}, VERSIONS.d, PW_V.{key}, {{ pwKey: "{key}", blurb: PW_V.{key}.blurb }}));')
    s = rep(s, "<title>Design #9, version D: loot pop-up and officers' window</title>",
            f"<title>Design #115, version {key.upper()}: Pick winner</title>")
    (out_dir / f"{key}.html").write_text(s)
    print("wrote", out_dir / f"{key}.html", len(s))
