#!/usr/bin/env python3
"""
Generate Ithuriel macOS app icon — 8-pointed asterisk burst on a dark slate background.

Run from repo root:
    python3 scripts/gen-app-icon.py
"""

import math
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    import subprocess
    subprocess.check_call([
        sys.executable, "-m", "pip", "install", "--user", "pillow",
        "--break-system-packages", "--quiet"
    ])
    from PIL import Image, ImageDraw, ImageFilter

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
ACCENT_HEX   = "#7B5BFF"   # Arc violet
BG_TOP_HEX   = "#0A0B14"
BG_BOT_HEX   = "#181826"

SUPER        = 4           # supersampling factor
BASE_SIZE    = 1024        # final 1× master size

SIZES = {
    "icon_16x16.png":      16,
    "icon_16x16@2x.png":   32,
    "icon_32x32.png":      32,
    "icon_32x32@2x.png":   64,
    "icon_128x128.png":    128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png":    256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png":    512,
    "icon_512x512@2x.png": 1024,
}

OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Ithuriel", "Resources", "Assets.xcassets", "AppIcon.appiconset",
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def hex_to_rgb(h: str) -> tuple:
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))


def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def gradient_background(size: int) -> Image.Image:
    top = hex_to_rgb(BG_TOP_HEX)
    bot = hex_to_rgb(BG_BOT_HEX)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    for y in range(size):
        t = y / (size - 1)
        color = lerp_color(top, bot, t) + (255,)
        for x in range(size):
            img.putpixel((x, y), color)
    return img


def draw_petal(draw: ImageDraw.ImageDraw, cx: float, cy: float,
               petal_w: float, petal_h: float, angle_deg: float,
               color: tuple) -> None:
    """
    Draw a single teardrop petal centered at (cx,cy), pointing upward before
    rotation, then rotated by angle_deg.

    The petal is a slim lens/lozenge: pointed at tip, widest at mid, tapered
    at base. Matches the SwiftUI Petal shape (two quad-curves).

    We approximate it with a polygon (lots of points) for crispness.
    """
    angle_rad = math.radians(angle_deg)

    # offset from center to petal body center — petal extends from 0 to -petal_h
    # in local coords (tip at -petal_h, base at 0, centre at -petal_h/2).
    # After rotation the body centre sits at offset (sin*ph/2, -cos*ph/2).
    ph = petal_h
    pw = petal_w

    # Sample petal outline in local space (tip at top = y=0, base at y=ph)
    # Left side: quadratic bezier from (0,0) -> (−pw/2, ph*0.55) -> (0,ph)
    # Right side: quadratic bezier from (0,ph) -> (+pw/2, ph*0.55) -> (0,0)
    def bezier_quad(p0, p1, p2, n=40):
        pts = []
        for i in range(n + 1):
            t = i / n
            x = (1-t)**2 * p0[0] + 2*(1-t)*t * p1[0] + t**2 * p2[0]
            y = (1-t)**2 * p0[1] + 2*(1-t)*t * p1[1] + t**2 * p2[1]
            pts.append((x, y))
        return pts

    # local coords: tip (0,0), base (0,ph), half-width at mid pw/2
    left_pts  = bezier_quad((0, 0), (-pw/2, ph*0.55), (0, ph))
    right_pts = bezier_quad((0, ph), ( pw/2, ph*0.55), (0,  0))
    local_pts = left_pts + right_pts

    # Transform: rotate around tip, then translate so petal extends *outward*
    # from center. In screen coords, "up" = negative y.
    # The petal tip is at distance `offset` from center, base further out.
    offset = ph * 0.35   # how far tip is from icon center

    world_pts = []
    for (lx, ly) in local_pts:
        # ly goes 0 (tip) → ph (base outward); we want tip near center
        dist = offset + ly          # distance from icon center
        # angle: 0° = up in screen (-y direction)
        wx = cx + math.sin(angle_rad) * dist + math.cos(angle_rad) * lx
        wy = cy - math.cos(angle_rad) * dist + math.sin(angle_rad) * lx
        world_pts.append((wx, wy))

    draw.polygon(world_pts, fill=color)


def make_master(size: int) -> Image.Image:
    S = size  # working size (supersampled)

    # --- Background ---
    img = gradient_background(S)
    draw = ImageDraw.Draw(img, "RGBA")

    cx = S / 2
    cy = S / 2

    accent_rgb = hex_to_rgb(ACCENT_HEX)

    # --- Outer glow layer (blurred circle tinted with accent) ---
    glow_radius = int(S * 0.12)
    glow_img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_img)
    glow_color = accent_rgb + (64,)  # ~25% opacity
    r = int(S * 0.39)  # glow extent
    glow_draw.ellipse(
        [cx - r, cy - r, cx + r, cy + r],
        fill=glow_color,
    )
    glow_img = glow_img.filter(ImageFilter.GaussianBlur(radius=glow_radius))
    img = Image.alpha_composite(img, glow_img)
    draw = ImageDraw.Draw(img, "RGBA")

    # --- Petal geometry (mirrors AsteriskBurst.swift) ---
    # In SwiftUI: petal width = side*0.18, petal height = side*0.48
    # offset from center to petal body top = side*0.18
    # We scale so the burst bounding circle ≈ 78% of canvas.
    petal_w = S * 0.13
    petal_h = S * 0.38
    secondary_alpha = int(255 * 0.55)

    for i in range(8):
        angle = i * 45.0
        if i % 2 == 0:
            color = accent_rgb + (255,)
        else:
            color = accent_rgb + (secondary_alpha,)
        draw_petal(draw, cx, cy, petal_w, petal_h, angle, color)

    # --- Soft inner glow on the petals (second pass, lighter) ---
    petal_img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    petal_draw = ImageDraw.Draw(petal_img, "RGBA")
    glow_accent = accent_rgb + (80,)
    for i in range(8):
        draw_petal(petal_draw, cx, cy, petal_w * 0.6, petal_h * 0.6, i * 45.0, glow_accent)
    petal_img = petal_img.filter(ImageFilter.GaussianBlur(radius=int(S * 0.02)))
    img = Image.alpha_composite(img, petal_img)
    draw = ImageDraw.Draw(img, "RGBA")

    # --- Center white dot (3% canvas) ---
    dot_r = S * 0.015
    draw.ellipse(
        [cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r],
        fill=(255, 255, 255, 255),
    )

    return img


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    print(f"Rendering master at {BASE_SIZE * SUPER}×{BASE_SIZE * SUPER}…")
    master_super = make_master(BASE_SIZE * SUPER)

    # Downsample to 1024 with LANCZOS for the largest size
    master = master_super.resize((BASE_SIZE, BASE_SIZE), Image.LANCZOS)

    for filename, px in sorted(SIZES.items(), key=lambda x: -x[1]):
        if px == BASE_SIZE:
            out = master.copy()
        else:
            out = master.resize((px, px), Image.LANCZOS)

        path = os.path.join(OUT_DIR, filename)
        out.convert("RGBA").save(path, "PNG", optimize=True)
        print(f"  wrote {filename:30s} {px}×{px}")

    print(f"\nAll icons written to:\n  {OUT_DIR}")


if __name__ == "__main__":
    main()
