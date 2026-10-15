#!/usr/bin/env python3
"""Build the landing page.

    site/template.html  (page body, as the Artifact preview expects)
      → site/index.html  same, with the hero SVGs inlined (preview)
      → docs/index.html  full document for GitHub Pages
"""
import base64
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def data_uri(path, mime="image/svg+xml"):
    with open(os.path.join(ROOT, path), "rb") as fh:
        return f"data:{mime};base64," + base64.b64encode(fh.read()).decode()


body = open(os.path.join(ROOT, "site/template.html"), encoding="utf-8").read()
template = body
body = body.replace("{{HERO_EN}}", data_uri("docs/hero-en.svg")).replace("{{HERO_JA}}", data_uri("docs/hero-ja.svg"))
body = body.replace("{{VIDEO_EN}}", data_uri("docs/media/junban-demo-en.mp4", "video/mp4"))
body = body.replace("{{VIDEO_JA}}", data_uri("docs/media/junban-demo-ja.mp4", "video/mp4"))
body = body.replace("{{VIDEO_MOBILE_EN}}", data_uri("docs/media/junban-demo-mobile-en.mp4", "video/mp4"))
body = body.replace("{{VIDEO_MOBILE_JA}}", data_uri("docs/media/junban-demo-mobile-ja.mp4", "video/mp4"))
open(os.path.join(ROOT, "site/index.html"), "w", encoding="utf-8").write(body)
# Pages serves the assets next to the page, so link them instead of inlining.
body = (template.replace("{{HERO_EN}}", "hero-en.svg").replace("{{HERO_JA}}", "hero-ja.svg")
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
