#!/usr/bin/env python3
"""Build the landing page.

    site/template.html  (page body, as the Artifact preview expects)
      → site/index.html  same, with the hero SVGs inlined (preview)
      → docs/index.html  full document for GitHub Pages
"""
import base64
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def data_uri(path):
    with open(os.path.join(ROOT, path), "rb") as fh:
        return "data:image/svg+xml;base64," + base64.b64encode(fh.read()).decode()


body = open(os.path.join(ROOT, "site/template.html"), encoding="utf-8").read()
body = body.replace("{{HERO_EN}}", data_uri("docs/hero-en.svg")).replace("{{HERO_JA}}", data_uri("docs/hero-ja.svg"))
open(os.path.join(ROOT, "site/index.html"), "w", encoding="utf-8").write(body)

page = ("<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, viewport-fit=cover\">\n"
        "<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}"
        "body{margin:0}img{max-width:100%}[hidden]{display:none!important}</style>\n")
head_end = body.index("<style>")
page += body[:head_end] + "</head>\n<body>\n" + body[head_end:] + "\n</body>\n</html>\n"
# On Pages the SVGs sit next to the page; no need to inline them.
page = page.replace(data_uri("docs/hero-en.svg"), "hero-en.svg").replace(data_uri("docs/hero-ja.svg"), "hero-ja.svg")
open(os.path.join(ROOT, "docs/index.html"), "w", encoding="utf-8").write(page)
print("site/index.html, docs/index.html")
