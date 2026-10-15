#!/usr/bin/env python3
"""Turn real tmux screen captures (ANSI) into one animated SVG.

    ansi2svg.py out.svg frame1.ans [frame2.ans ...] [--hold 2.6]

Each character is placed on its own grid cell (CJK and emoji take two), so the
picture matches the terminal exactly whatever font the viewer has. Frames cross-
fade in a loop with pure CSS, which GitHub renders inside <img>.
"""
import html
import re
import sys
import unicodedata

CW, CH, FS = 8.4, 18, 14
BG = "#1e2127"
FG = "#abb2bf"
BASE16 = ["#1e2127", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#abb2bf",
          "#5c6370", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#ffffff"]


def xterm256(n):
    if n < 16:
        return BASE16[n]
    if n < 232:
        n -= 16
        steps = [0, 95, 135, 175, 215, 255]
        return "#%02x%02x%02x" % (steps[n // 36], steps[n // 6 % 6], steps[n % 6])
    v = 8 + (n - 232) * 10
    return "#%02x%02x%02x" % (v, v, v)


def width(ch):
    if unicodedata.combining(ch):
        return 0
    if unicodedata.east_asian_width(ch) in "WF" or ord(ch) in (0x270B, 0x1F4A1):
        return 2
    return 1


SGR = re.compile(r"\x1b\[([0-9;:]*)m")


def parse(text):
    """→ list of rows, each a list of (col, char, fg, bg, bold, dim)."""
    rows = []
    fg, bg, bold, dim = None, None, False, False
    for line in text.split("\n"):
        col, cells, pos = 0, [], 0
        for m in list(SGR.finditer(line)) + [None]:
            end = m.start() if m else len(line)
            for ch in line[pos:end]:
                w = width(ch)
                if w:
                    cells.append((col, ch, fg, bg, bold, dim, w))
                    col += w
            if not m:
                break
            pos = m.end()
            codes = [int(c) if c.isdigit() else 0 for c in re.split("[;:]", m.group(1) or "0")]
            i = 0
            while i < len(codes):
                c = codes[i]
                if c == 0:
                    fg, bg, bold, dim = None, None, False, False
                elif c == 1:
                    bold = True
                elif c == 2:
                    dim = True
                elif c == 22:
                    bold = dim = False
                elif 30 <= c <= 37:
                    fg = BASE16[c - 30]
                elif 90 <= c <= 97:
                    fg = BASE16[c - 90 + 8]
                elif c == 39:
                    fg = None
                elif 40 <= c <= 47:
                    bg = BASE16[c - 40]
                elif c == 49:
                    bg = None
                elif c in (38, 48) and i + 1 < len(codes):
                    if codes[i + 1] == 5 and i + 2 < len(codes):
                        val, i = xterm256(codes[i + 2]), i + 2
                    elif codes[i + 1] == 2 and i + 4 < len(codes):
                        val, i = "#%02x%02x%02x" % tuple(codes[i + 2:i + 5]), i + 4
                    else:
                        val = None
                    if c == 38:
                        fg = val
                    else:
                        bg = val
                i += 1
        rows.append(cells)
    while rows and not rows[-1]:
        rows.pop()
    return rows


def frame_svg(rows, cols):
    """Backgrounds as rects; text as runs of same-styled narrow cells (spaces
    kept), each anchored to its own column. Monospace fonts agree on a 0.6em
    advance, so a run cannot drift far; wide glyphs (CJK, emoji) are placed
    one by one because fonts disagree about them."""
    out = []
    for y, cells in enumerate(rows):
        for col, ch, fg, bg, bold, dim, w in cells:
            if bg:
                out.append(f'<rect x="{col * CW:.1f}" y="{y * CH}" width="{w * CW + .6:.1f}" height="{CH}" fill="{bg}"/>')
        runs = []
        for col, ch, fg, bg, bold, dim, w in cells:
            style = (fg, bold, dim)
            last = runs[-1] if runs else None
            if (w == 1 and last and last["w"] == 1 and last["style"] == style
                    and last["col"] + len(last["text"]) == col):
                last["text"] += ch
            else:
                runs.append({"col": col, "text": ch, "style": style, "w": w})
        for run in runs:
            text = run["text"].rstrip()
            lead = len(text) - len(text.lstrip())
            text = text.lstrip()
            if not text:
                continue
            fg, bold, dim = run["style"]
            x = (run["col"] + lead + (1 if run["w"] == 2 else 0)) * CW  # wide: centre of 2 cells
            attrs = f'x="{x:.1f}" y="{y * CH + 13.5}"'
            if run["w"] == 2:
                attrs += ' text-anchor="middle"'
            if fg:
                attrs += f' fill="{fg}"'
            if bold:
                attrs += ' font-weight="700"'
            if dim:
                attrs += ' opacity=".55"'
            out.append(f"<text {attrs}>{html.escape(text)}</text>")
    return "".join(out)


def main():
    args = sys.argv[1:]
    hold = 2.6
    if "--hold" in args:
        i = args.index("--hold")
        hold = float(args[i + 1])
        del args[i:i + 2]
    out, frames = args[0], [parse(open(f, encoding="utf-8").read()) for f in args[1:]]
    cols = max(max((c[0] + c[6] for c in r), default=0) for f in frames for r in f)
    nrows = max(len(f) for f in frames)
    pad, bar = 16, 30
    W, H = cols * CW + pad * 2, nrows * CH + pad * 2 + bar
    n = len(frames)
    total = hold * n
    css = [f"text{{font:{FS}px ui-monospace,'SF Mono',Menlo,'Cascadia Mono','Noto Sans Mono CJK JP',monospace;"
           "white-space:pre}"]
    if n > 1:
        for i in range(n):
            a, b = i / n * 100, (i + 1) / n * 100
            fade = 0.4 / total * 100
            css.append(f"@keyframes f{i}{{0%,{max(a - fade, 0):.2f}%{{opacity:0}}"
                       f"{a:.2f}%,{b - fade:.2f}%{{opacity:1}}{b:.2f}%,100%{{opacity:0}}}}"
                       f".f{i}{{opacity:{1 if i == 0 else 0};animation:f{i} {total}s infinite}}")
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" xml:space="preserve" viewBox="0 0 {W:.0f} {H:.0f}" width="{W:.0f}" height="{H:.0f}">',
             f"<style>{''.join(css)}</style>",
             f'<rect width="100%" height="100%" rx="10" fill="{BG}"/>',
             f'<rect width="100%" height="{bar}" rx="10" fill="#2c313c"/><rect y="{bar - 10}" width="100%" height="10" fill="#2c313c"/>',
             '<circle cx="20" cy="15" r="6" fill="#ff5f57"/><circle cx="40" cy="15" r="6" fill="#febc2e"/><circle cx="60" cy="15" r="6" fill="#28c840"/>']
    for i, f in enumerate(frames):
        parts.append(f'<g class="f{i}" fill="{FG}" transform="translate({pad},{bar + pad})">{frame_svg(f, cols)}</g>')
    parts.append("</svg>")
    open(out, "w", encoding="utf-8").write("\n".join(parts))


if __name__ == "__main__":
    main()
