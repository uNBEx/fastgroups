#!/usr/bin/env python3
"""Generate FastGroups textures (Media/*.tga).

Icons are drawn from inline SVG with headless Chromium (Playwright) so they match the HTML
mockup exactly; shapes are drawn with Pillow using 8x supersampling. Output is 32-bit
uncompressed TGA (bottom-left origin), white on transparent so the addon can tint with
SetVertexColor.

Requirements: python3 with playwright (chromium installed) and pillow.
Usage: python3 tools/gen_media.py
"""
import io
import os
import struct

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Media")

# 16x16 viewBox icons, same shapes as the mockup. "currentColor" renders white.
ICONS = {
    "role_tank": '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M8 1.2 2.4 3.3v4.1c0 3.4 2.3 6 5.6 7.4 3.3-1.4 5.6-4 5.6-7.4V3.3z"/></svg>',
    "role_healer": '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M6.2 1.8h3.6v4.4h4.4v3.6H9.8v4.4H6.2V9.8H1.8V6.2h4.4z"/></svg>',
    "role_dps": '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M14.6 1.4v2.8L7.4 11.4 4.6 8.6 11.8 1.4z"/><path d="M2.6 8.2l5.2 5.2-1.1 1.1-1.5-1.5-2.3 2.3-1.3-1.3 2.3-2.3-1.5-1.5z"/></svg>',
    "pos_melee": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><path d="M3 3l10 10M13 3 3 13M2.5 10.5l3 3M13.5 10.5l-3 3"/></svg>',
    "pos_ranged": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><circle cx="8" cy="8" r="5"/><circle cx="8" cy="8" r="1.4" fill="currentColor"/><path d="M8 1v3M8 12v3M1 8h3M12 8h3"/></svg>',
    "pos_unknown": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><path d="M5.5 5.8a2.6 2.6 0 1 1 3.6 2.4c-.7.3-1.1.9-1.1 1.6v.6"/><circle cx="8" cy="13" r=".6" fill="currentColor"/></svg>',
    "nav_groups": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="1.5" y="2" width="5.5" height="12" rx="1.5"/><rect x="9" y="2" width="5.5" height="12" rx="1.5"/></svg>',
    "nav_rosters": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><circle cx="6" cy="5.5" r="2.5"/><path d="M1.5 13.5c.6-2.4 2.3-3.6 4.5-3.6s3.9 1.2 4.5 3.6"/><path d="M10.5 3.3a2.3 2.3 0 0 1 0 4.4M12 9.9c1.3.5 2.1 1.7 2.5 3.6"/></svg>',
    "nav_share": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M8 10V2M5 4.8 8 1.8l3 3"/><path d="M3 8.5v4.2c0 .7.6 1.3 1.3 1.3h7.4c.7 0 1.3-.6 1.3-1.3V8.5"/></svg>',
    "nav_options": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M2 4h7M12 4h2M2 12h2M7 12h7"/><circle cx="10.5" cy="4" r="1.6"/><circle cx="5.5" cy="12" r="1.6"/></svg>',
    "plus": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M8 3v10M3 8h10"/></svg>',
    "search": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><circle cx="7" cy="7" r="4.5"/><path d="M10.5 10.5 14 14"/></svg>',
    "wand": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M2 14 10 6M9 3v2M12 6h2M11.5 3.5l1-1M7 2l.5 1"/><path d="m10 6 1.2-1.2"/></svg>',
    "undo": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5.5 3.5 2.5 6.5l3 3"/><path d="M2.5 6.5H10a3.5 3.5 0 0 1 0 7H7"/></svg>',
    "save": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"><path d="M2.5 2.5h8.5l2.5 2.5v8.5h-11z"/><path d="M5 2.5v3.5h5V2.5M5 13.5V9.5h6v4"/></svg>',
    "play": '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M4.5 2.8v10.4L13 8z"/></svg>',
    "check": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m3 8.5 3 3 7-7"/></svg>',
    "warn": '<svg viewBox="0 0 16 16"><path d="M8 1.5 15 14H1z" fill="currentColor" opacity=".3"/><path d="M7.2 6h1.6l-.2 4.2H7.4zM7.2 11.2h1.6v1.6H7.2z" fill="currentColor"/></svg>',
    "info": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="8" cy="8" r="6.5"/><path d="M8 7v4.5M8 4.6v.1" stroke-linecap="round" stroke-width="1.8"/></svg>',
    "close": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 4l8 8M12 4l-8 8"/></svg>',
    "copy": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="5" y="5" width="8.5" height="8.5" rx="1.5"/><path d="M11 3V2.5c0-.6-.4-1-1-1H3.5c-.6 0-1 .4-1 1V10c0 .6.4 1 1 1H4"/></svg>',
    "trash": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M3 4.5h10M6.5 4.5V3h3v1.5M4.5 4.5l.6 9h5.8l.6-9"/></svg>',
    "chevron": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 3 5 5-5 5"/></svg>',
    "send": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"><path d="M14.5 1.5 7 9M14.5 1.5 10 14.5 7 9 1.5 6z"/></svg>',
    "swap": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M2 5h11l-3-3M14 11H3l3 3"/></svg>',
    "bench": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M2 7h12M3 7v5M13 7v5M2 10h12"/></svg>',
    "edit": '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"><path d="M10.5 2.5l3 3L6 13H3v-3z"/></svg>',
    "crown": '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M2 5l3 3 3-5 3 5 3-3-1.2 8H3.2z"/></svg>',
    "logo": '<svg viewBox="0 0 16 16" fill="currentColor"><rect x="1" y="1" width="6" height="6" rx="1.5"/><rect x="9" y="1" width="6" height="6" rx="1.5" opacity=".55"/><rect x="1" y="9" width="6" height="6" rx="1.5" opacity=".55"/><rect x="9" y="9" width="6" height="6" rx="1.5"/></svg>',
}

ICON_SIZE = 64


def write_tga(img, path):
    """32-bit uncompressed TGA, bottom-left origin, 8 alpha bits."""
    img = img.convert("RGBA")
    w, h = img.size
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    px = img.load()
    body = bytearray()
    for y in range(h - 1, -1, -1):
        for x in range(w):
            r, g, b, a = px[x, y]
            body += bytes((b, g, r, a))
    with open(path, "wb") as f:
        f.write(header)
        f.write(body)


def render_icons():
    from playwright.sync_api import sync_playwright

    out = {}
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 200, "height": 200}, device_scale_factor=1)
        for name, svg in ICONS.items():
            svg = svg.replace("<svg ", '<svg width="%d" height="%d" ' % (ICON_SIZE, ICON_SIZE), 1)
            page.set_content(
                '<html><body style="margin:0;background:transparent">'
                '<div id="i" style="width:%dpx;height:%dpx;color:#fff;display:flex">%s</div></body></html>'
                % (ICON_SIZE, ICON_SIZE, svg)
            )
            png = page.locator("#i").screenshot(omit_background=True)
            out[name] = Image.open(io.BytesIO(png)).convert("RGBA")
        browser.close()
    return out


def supersampled(size, draw_fn, ss=8):
    big = Image.new("L", (size * ss, size * ss), 0)
    draw_fn(ImageDraw.Draw(big), size * ss, ss)
    mask = big.resize((size, size), Image.LANCZOS)
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    img.putalpha(mask)
    return img


def shapes():
    res = {}
    # rounded fill, radius 6 in a 32px texture, sliced with 8px margins
    res["round6"] = supersampled(32, lambda d, s, k: d.rounded_rectangle([0, 0, s - 1, s - 1], radius=6 * k, fill=255))
    # 1px ring with the same radius
    def ring(d, s, k):
        d.rounded_rectangle([0, 0, s - 1, s - 1], radius=6 * k, fill=255)
        d.rounded_rectangle([k, k, s - 1 - k, s - 1 - k], radius=5 * k, fill=0)
    res["ring6"] = supersampled(32, ring)
    # small radius variants for pills and tiny badges
    res["round3"] = supersampled(16, lambda d, s, k: d.rounded_rectangle([0, 0, s - 1, s - 1], radius=3 * k, fill=255))
    res["circle"] = supersampled(32, lambda d, s, k: d.ellipse([0, 0, s - 1, s - 1], fill=255))
    return res


def main():
    os.makedirs(os.path.join(OUT, "Icons"), exist_ok=True)
    for name, img in render_icons().items():
        write_tga(img, os.path.join(OUT, "Icons", name + ".tga"))
    for name, img in shapes().items():
        write_tga(img, os.path.join(OUT, name + ".tga"))
    print("media written to", OUT)


if __name__ == "__main__":
    main()
