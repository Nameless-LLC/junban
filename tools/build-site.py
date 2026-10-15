#!/usr/bin/env python3
"""Build the landing page.

    site/template.html  (page body, as the Artifact preview expects)
      → site/index.html  same, with the hero SVGs inlined (preview)
      → docs/index.html  full document for GitHub Pages
"""
import base64
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def data_uri(path, mime="image/svg+xml"):
    with open(os.path.join(ROOT, path), "rb") as fh:
        return f"data:{mime};base64," + base64.b64encode(fh.read()).decode()


body = open(os.path.join(ROOT, "site/template.html"), encoding="utf-8").read()

# The mascot: the call board's eyes. {{FACE id state}}; the first one carries the shared defs.
DEFS = ('<defs><pattern id="jb-led" width="6" height="6" patternUnits="userSpaceOnUse"><path d="M0 0H6M0 0V6" stroke="#121417" stroke-width="1.6" fill="none"/></pattern>'
        '<filter id="jb-glow" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="5"/></filter></defs>')
LIT = "".join('<rect class="eye" x="%d" y="45" width="26" height="60" rx="13" fill="currentColor"/>' % x for x in (63, 111))
EYES = LIT + LIT.replace('fill="currentColor"', 'fill="url(#jb-led)"')


def face(m):
    fid, state = m.group(1), m.group(2)
    defs = DEFS if face.first else ""
    face.first = False
    return ('<svg class="jbm" id="%s-face" viewBox="0 0 200 150" data-state="%s" aria-hidden="true" focusable="false">%s'
            '<rect x="14" y="10" width="172" height="130" rx="32" fill="#262a31"/><rect x="23" y="19" width="154" height="112" rx="25" fill="#0b0c0e"/>'
            '<g class="look"><g class="eyes"><g class="pair"><g class="open"><g filter="url(#jb-glow)" opacity=".5">%s</g>%s</g>'
            '<g class="happy" fill="none" stroke="currentColor" stroke-width="12" stroke-linecap="round"><path d="M64 86 Q76 60 88 86"/><path d="M112 86 Q124 60 136 86"/></g>'
            '</g></g></g></svg>') % (fid, state, defs, LIT, EYES)


face.first = True
body = re.sub(r"\{\{FACE (\w+) (\w+)\}\}", face, body)
template = body
body = body.replace("{{HERO_EN}}", data_uri("docs/hero-en.svg")).replace("{{HERO_JA}}", data_uri("docs/hero-ja.svg"))
body = body.replace("{{FAVICON}}", data_uri("docs/favicon.svg"))
body = body.replace("{{VIDEO_EN}}", data_uri("docs/media/junban-demo-en.mp4", "video/mp4"))
body = body.replace("{{VIDEO_JA}}", data_uri("docs/media/junban-demo-ja.mp4", "video/mp4"))
body = body.replace("{{VIDEO_MOBILE_EN}}", data_uri("docs/media/junban-demo-mobile-en.mp4", "video/mp4"))
body = body.replace("{{VIDEO_MOBILE_JA}}", data_uri("docs/media/junban-demo-mobile-ja.mp4", "video/mp4"))
open(os.path.join(ROOT, "site/index.html"), "w", encoding="utf-8").write(body)
# Pages serves the assets next to the page, so link them instead of inlining.
body = (template.replace("{{FAVICON}}", "favicon.svg").replace("{{HERO_EN}}", "hero-en.svg").replace("{{HERO_JA}}", "hero-ja.svg")
        .replace("{{VIDEO_EN}}", "media/junban-demo-en.mp4").replace("{{VIDEO_JA}}", "media/junban-demo-ja.mp4")
        .replace("{{VIDEO_MOBILE_EN}}", "media/junban-demo-mobile-en.mp4").replace("{{VIDEO_MOBILE_JA}}", "media/junban-demo-mobile-ja.mp4"))

page = ("<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, viewport-fit=cover\">\n"
        "<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}"
        "body{margin:0}img{max-width:100%}[hidden]{display:none!important}</style>\n")
head_end = body.index("<style>")
page += body[:head_end] + "</head>\n<body>\n" + body[head_end:] + "\n</body>\n</html>\n"
open(os.path.join(ROOT, "docs/index.html"), "w", encoding="utf-8").write(page)
print("site/index.html, docs/index.html")
