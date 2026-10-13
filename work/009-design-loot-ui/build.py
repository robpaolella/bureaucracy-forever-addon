#!/usr/bin/env python3
"""Builds the design's self-contained version files from src/ and assets/ (art and fonts inlined)."""
import base64, pathlib, re
HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent.parent / "design" / "9-loot-ui" / "versions"
MIME = {".png": "image/png", ".ttf": "font/ttf"}

def inline(text):
    def rep(m):
        f = HERE / "assets" / m.group(1)
        return f"data:{MIME[f.suffix.lower()]};base64," + base64.b64encode(f.read_bytes()).decode()
    return re.sub(r"@@([A-Za-z0-9._-]+)@@", rep, text)

css = (HERE / "src/common.css").read_text()
js = "".join((HERE / "src" / n).read_text() for n in ["common.js", "popup-parts.js", "versions.js"])
OUT.mkdir(parents=True, exist_ok=True)
for v in ["a", "b", "c", "d"]:
    html = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Design #9, version {v.upper()}: loot pop-up and officers' window</title>
<style>{css}</style></head>
<body><div class="proto-bar" id="proto-bar" role="region" aria-label="Prototype controls"></div>
<div class="viewport" id="viewport"><main class="scene" id="scene" aria-label="Game screen mock-up"></main></div>
<script>{js}
boot(VERSIONS["{v}"]);</script></body></html>
"""
    (OUT / f"{v}.html").write_text(inline(html))
    print(v, len(html))
