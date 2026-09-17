#!/usr/bin/env python3
"""Generate the Shore app icon and README screenshot placeholders."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ICON_DIR = ROOT / "Shore" / "Assets.xcassets" / "AppIcon.appiconset"
SHOT_DIR = ROOT / "docs" / "screenshots"

INK = (12, 14, 16, 255)
INK_LIFT = (22, 26, 30, 255)
FOAM = (232, 238, 240, 255)
SEA = (124, 158, 160, 255)
KELP = (61, 90, 84, 255)
SAND = (196, 184, 165, 255)
BEZEL = (0, 0, 0, 255)
DESK = (18, 20, 22, 255)
DESK_LIP = (196, 202, 208, 255)  # light desktop so the black silhouette reads


def rounded_rect(draw, xy, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def make_icon(size: int, opaque: bool = False) -> Image.Image:
    import math

    img = Image.new("RGBA", (size, size), INK if opaque else (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    pad = int(size * 0.09)
    radius = int(size * 0.22)
    box = (pad, pad, size - pad - 1, size - pad - 1)
    draw.rounded_rectangle(box, radius=radius, fill=INK)

    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    left, top, right, bottom = box

    def wave_points(y_ratio: float, amp_ratio: float, freq: float, phase: float):
        y0 = top + (bottom - top) * y_ratio
        amp = (bottom - top) * amp_ratio
        pts = []
        for x in range(int(left), int(right) + 1):
            t = (x - left) / max(1, right - left)
            y = y0 + amp * math.sin(t * math.pi * freq + phase)
            pts.append((x, y))
        return pts

    sea_pts = wave_points(0.58, 0.045, 1.8, 0.4)
    ld.polygon(sea_pts + [(right, bottom), (left, bottom)], fill=(*KELP[:3], 180))
    foam_pts = wave_points(0.64, 0.03, 2.4, 1.1)
    ld.polygon(foam_pts + [(right, bottom), (left, bottom)], fill=INK)
    ld.line(sea_pts, fill=(*SEA[:3], 230), width=max(2, size // 48), joint="curve")
    ld.line(foam_pts, fill=(*FOAM[:3], 210), width=max(2, size // 64), joint="curve")

    r = max(2, size // 26)
    cx, cy = int(size * 0.70), int(size * 0.40)
    ld.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(*FOAM[:3], 220))

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    clipped = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    clipped.paste(layer, mask=mask)
    img = Image.alpha_composite(img, clipped)
    ImageDraw.Draw(img).rounded_rectangle(
        box, radius=radius, outline=(255, 255, 255, 36), width=max(1, size // 256)
    )
    return img


def write_icons():
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    master = make_icon(1024, opaque=True)
    master.convert("RGB").save(ICON_DIR / "AppIcon-1024.png")

    slots = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    images = []
    for px, name in slots:
        make_icon(px).save(ICON_DIR / name)
        scale = "2x" if "@2x" in name else "1x"
        logical = px // (2 if scale == "2x" else 1)
        images.append(
            {
                "filename": name,
                "idiom": "mac",
                "scale": scale,
                "size": f"{logical}x{logical}",
            }
        )
    images.append(
        {
            "filename": "AppIcon-1024.png",
            "idiom": "mac",
            "scale": "1x",
            "size": "1024x1024",
        }
    )
    import json

    (ICON_DIR / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2)
        + "\n"
    )


def font(size, bold=False):
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def draw_pill(base, xy, radius, fill=INK, stroke=(255, 255, 255, 40)):
    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    d.rounded_rectangle(xy, radius=radius, fill=fill, outline=stroke, width=1)
    return Image.alpha_composite(base, overlay)


def cubic(p0, p1, p2, p3, steps=18):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


def corner(start, c, end, k=0.62):
    return cubic(
        start,
        (start[0] + (c[0] - start[0]) * k, start[1] + (c[1] - start[1]) * k),
        (end[0] + (c[0] - end[0]) * k, end[1] + (c[1] - end[1]) * k),
        end,
        steps=12,
    )


def draw_notch_blend(base, notch, body, radius=28, fill=BEZEL):
    """Continuous island silhouette — flush top, S-curve ears, capsule bottom. Not a T."""
    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    nx0, _, nx1, nh = notch
    bx0, by0, bx1, by1 = body
    nW = nx1 - nx0
    body_w = bx1 - bx0
    body_h = by1 - by0
    nL = (bx0 + bx1) / 2 - nW / 2
    nR = nL + nW
    wing = max(0, (body_w - nW) / 2)
    lip = max(0, body_h - nh)
    rest_like = wing < 1.5 or lip < 2
    ear_k = 0.58

    if rest_like:
        r = min(max(radius, body_h * 0.48), body_w / 2, body_h / 2)
        y0f = by1 - r
        y1f = y0f
        bottom_r = r
    else:
        bottom_r = min(max(radius, min(lip * 0.36, 36)), body_w / 2, body_h / 2)
        stem = min(nh * 0.58, max(8, nh - 8))
        y0f = by0 + stem
        flare_h = min(max(40, 22), 46, lip * 0.62, max(8, by1 - bottom_r - y0f))
        y1f = y0f + flare_h
        if y1f > by1 - 8:
            y1f = by1 - 8
        bottom_r = min(bottom_r, max(12, by1 - y1f))
    dy = max(0, y1f - y0f)

    pts = [(nL, by0), (nR, by0), (nR, y0f)]
    pts += cubic((nR, y0f), (nR, y0f + ear_k * dy), (bx1, y1f - ear_k * dy), (bx1, y1f), 22)[1:]
    pts.append((bx1, by1 - bottom_r))
    pts += corner((bx1, by1 - bottom_r), (bx1, by1), (bx1 - bottom_r, by1))[1:]
    pts.append((bx0 + bottom_r, by1))
    pts += corner((bx0 + bottom_r, by1), (bx0, by1), (bx0, by1 - bottom_r))[1:]
    pts.append((bx0, y1f))
    pts += cubic((bx0, y1f), (bx0, y1f - ear_k * dy), (nL, y0f + ear_k * dy), (nL, y0f), 22)[1:]
    pts.append((nL, by0))
    d.polygon(pts, fill=fill)
    return Image.alpha_composite(base, overlay)


def island_collapsed(path: Path):
    img = Image.new("RGBA", (1280, 720), DESK_LIP)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 1280, 32), fill=(236, 238, 240, 255))
    d.text((18, 8), "Mon 9:41", font=font(12), fill=(80, 84, 88, 220))
    d.text((1180, 8), "100%", font=font(12), fill=(80, 84, 88, 220))
    img = draw_notch_blend(img, (548, 0, 732, 32), (466, 0, 814, 100), radius=28, fill=BEZEL)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((488, 42, 512, 66), radius=6, fill=KELP)
    d.text((522, 42), "Low Tide", font=font(14, True), fill=FOAM)
    d.text((522, 60), "Still Harbor", font=font(11), fill=(FOAM[0], FOAM[1], FOAM[2], 150))
    d.rounded_rectangle((742, 46, 766, 64), radius=8, fill=(255, 255, 255, 22))
    d.rounded_rectangle((772, 46, 796, 64), radius=8, fill=(255, 255, 255, 22))
    d.text((40, 660), "Design placeholder · Organic compact island from the hardware notch", font=font(14), fill=(90, 94, 98, 220))
    img.convert("RGB").save(path, quality=92)


def island_expanded(path: Path):
    img = Image.new("RGBA", (1280, 720), DESK_LIP)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 1280, 32), fill=(236, 238, 240, 255))
    d.text((18, 8), "Mon 9:41", font=font(12), fill=(80, 84, 88, 220))
    img = draw_notch_blend(img, (548, 0, 732, 32), (426, 0, 854, 250), radius=32, fill=BEZEL)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((448, 48, 532, 132), radius=14, fill=KELP)
    d.text((548, 52), "Low Tide", font=font(20, True), fill=FOAM)
    d.text((548, 80), "Still Harbor · sample", font=font(13), fill=(FOAM[0], FOAM[1], FOAM[2], 150))
    d.rounded_rectangle((548, 112, 780, 116), radius=2, fill=(255, 255, 255, 28))
    d.rounded_rectangle((548, 112, 628, 116), radius=2, fill=SEA)
    d.polygon((488, 168, 476, 176, 488, 184), fill=FOAM)
    d.ellipse((506, 156, 548, 198), fill=FOAM)
    d.polygon((566, 168, 578, 176, 566, 184), fill=FOAM)
    d.rounded_rectangle((620, 164, 668, 188), radius=8, fill=(255, 255, 255, 22))
    d.text((628, 168), "87%", font=font(10), fill=FOAM)
    d.rounded_rectangle((676, 164, 720, 188), radius=8, fill=(255, 255, 255, 22))
    d.text((684, 168), "42", font=font(10), fill=FOAM)
    d.rounded_rectangle((448, 204, 832, 236), radius=10, fill=(255, 255, 255, 18))
    d.text((460, 212), "Shelf   notes.pdf    shot.png", font=font(11), fill=(FOAM[0], FOAM[1], FOAM[2], 180))
    d.text((40, 660), "Design placeholder · Organic island silhouette from the notch", font=font(14), fill=(90, 94, 98, 220))
    img.convert("RGB").save(path, quality=92)


def cove(path: Path):
    img = Image.new("RGBA", (1280, 720), DESK)
    d = ImageDraw.Draw(img)
    # Fake dock
    d.rounded_rectangle((360, 640, 920, 704), radius=18, fill=(28, 30, 32, 230))
    for i, x in enumerate(range(390, 900, 70)):
        color = SEA if i == 3 else (90, 96, 100, 255)
        d.rounded_rectangle((x, 652, x + 44, 696), radius=10, fill=color)
    # File cove tray
    d.rounded_rectangle((400, 552, 880, 628), radius=16, fill=BEZEL, outline=SEA, width=1)
    d.text((424, 566), "Cove", font=font(12, True), fill=FOAM)
    d.text((820, 566), "Clear", font=font(11), fill=(FOAM[0], FOAM[1], FOAM[2], 140))
    d.rounded_rectangle((424, 590, 548, 616), radius=10, fill=(255, 255, 255, 22))
    d.text((436, 594), "notes.pdf", font=font(11), fill=FOAM)
    d.rounded_rectangle((560, 590, 676, 616), radius=10, fill=(255, 255, 255, 22))
    d.text((572, 594), "shot.png", font=font(11), fill=FOAM)
    d.rounded_rectangle((688, 590, 800, 616), radius=10, fill=(255, 255, 255, 22))
    d.text((700, 594), "reel.mov", font=font(11), fill=FOAM)
    d.text((40, 40), "Design placeholder · Dock Cove file tray", font=font(14), fill=(160, 166, 170, 200))
    img.convert("RGB").save(path, quality=92)


def settings(path: Path):
    img = Image.new("RGBA", (1280, 720), (32, 34, 36, 255))
    panel = Image.new("RGBA", (1280, 720), (0, 0, 0, 0))
    d = ImageDraw.Draw(panel)
    d.rounded_rectangle((430, 90, 850, 630), radius=18, fill=(246, 246, 246, 255))
    d.text((460, 120), "Shore", font=font(26, True), fill=INK)
    d.text((460, 154), "Quiet extras for the Mac.", font=font(13), fill=(80, 84, 88, 255))
    d.rounded_rectangle((460, 200, 820, 280), radius=14, fill=(236, 236, 236, 255))
    d.text((478, 214), "Island", font=font(15, True), fill=INK)
    d.text((478, 238), "True-black notch hug.", font=font(12), fill=(90, 94, 98, 255))
    d.text((478, 256), "Hover expands; click-outside dismisses.", font=font(12), fill=(90, 94, 98, 255))
    d.rounded_rectangle((760, 226, 804, 250), radius=12, fill=SEA)
    d.rounded_rectangle((460, 300, 820, 380), radius=14, fill=(236, 236, 236, 255))
    d.text((478, 314), "File shelf", font=font(15, True), fill=INK)
    d.text((478, 338), "Drop files onto the island to park them.", font=font(12), fill=(90, 94, 98, 255))
    d.rounded_rectangle((760, 326, 804, 350), radius=12, fill=SEA)
    d.rounded_rectangle((460, 400, 820, 480), radius=14, fill=(236, 236, 236, 255))
    d.text((478, 414), "Dock Cove", font=font(15, True), fill=INK)
    d.text((478, 438), "File tray above the Dock. Drop in, drag out.", font=font(12), fill=(90, 94, 98, 255))
    d.rounded_rectangle((760, 426, 804, 450), radius=12, fill=SEA)
    d.text((478, 510), "Sample media when idle", font=font(14, True), fill=INK)
    img = Image.alpha_composite(img, panel)
    d = ImageDraw.Draw(img)
    d.text((40, 660), "Design placeholder · Settings", font=font(14), fill=(180, 184, 188, 200))
    img.convert("RGB").save(path, quality=92)


def main():
    write_icons()
    SHOT_DIR.mkdir(parents=True, exist_ok=True)
    island_collapsed(SHOT_DIR / "island-collapsed.png")
    island_expanded(SHOT_DIR / "island-expanded.png")
    cove(SHOT_DIR / "cove.png")
    settings(SHOT_DIR / "settings.png")
    print("Wrote icons and screenshot placeholders")


if __name__ == "__main__":
    main()
