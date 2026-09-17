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


def draw_notch_blend(base, body, ear=12, radius=22, fill=BEZEL):
    """Flush-top island: full-width bezel edge, concave cubic ears, capsule bottom."""
    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    bx0, by0, bx1, by1 = body
    body_w = bx1 - bx0
    body_h = by1 - by0
    ear_k = 0.52
    squircle = 0.55
    ear = min(max(0, ear), body_w * 0.20, body_h * 0.38)
    left = bx0 + ear
    right = bx1 - ear
    bottom_r = min(max(radius, 8), max(6, (body_w / 2) - ear - 1), body_h * 0.5)

    pts = [(bx0, by0), (bx1, by0)]
    if ear > 0.5:
        pts += cubic(
            (bx1, by0),
            (bx1 - ear * ear_k, by0),
            (right, by0 + ear * (1 - ear_k)),
            (right, by0 + ear),
            16,
        )[1:]
    pts.append((right, by1 - bottom_r))
    pts += corner((right, by1 - bottom_r), (right, by1), (right - bottom_r, by1), k=squircle)[1:]
    pts.append((left + bottom_r, by1))
    pts += corner((left + bottom_r, by1), (left, by1), (left, by1 - bottom_r), k=squircle)[1:]
    pts.append((left, by0 + ear))
    if ear > 0.5:
        pts += cubic(
            (left, by0 + ear),
            (left, by0 + ear * (1 - ear_k)),
            (bx0 + ear * ear_k, by0),
            (bx0, by0),
            16,
        )[1:]
    else:
        pts.append((bx0, by0))
    d.polygon(pts, fill=fill)
    return Image.alpha_composite(base, overlay)


def island_collapsed(path: Path):
    img = Image.new("RGBA", (1280, 720), DESK_LIP)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 1280, 32), fill=(236, 238, 240, 255))
    d.text((18, 8), "Mon 9:41", font=font(12), fill=(80, 84, 88, 220))
    d.text((1180, 8), "100%", font=font(12), fill=(80, 84, 88, 220))
    # Compact capsule: full-width flush top, modest width, art + title + waveform.
    img = draw_notch_blend(img, (497, 0, 783, 76), ear=12, radius=22, fill=BEZEL)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((518, 38, 544, 64), radius=7, fill=KELP)
    d.text((556, 42), "Low Tide", font=font(14, True), fill=FOAM)
    d.rectangle((740, 44, 743, 58), fill=FOAM)
    d.rectangle((746, 48, 749, 56), fill=FOAM)
    d.rectangle((752, 42, 755, 60), fill=FOAM)
    d.rectangle((758, 46, 761, 54), fill=FOAM)
    d.text((40, 660), "Design placeholder · Compact capsule growing from the hardware notch", font=font(14), fill=(90, 94, 98, 220))
    img.convert("RGB").save(path, quality=92)


def island_expanded(path: Path):
    img = Image.new("RGBA", (1280, 720), DESK_LIP)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 1280, 32), fill=(236, 238, 240, 255))
    d.text((18, 8), "Mon 9:41", font=font(12), fill=(80, 84, 88, 220))
    img = draw_notch_blend(img, (444, 0, 836, 220), ear=11, radius=24, fill=BEZEL)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((470, 44, 542, 116), radius=14, fill=KELP)
    d.text((558, 48), "Low Tide", font=font(18, True), fill=FOAM)
    d.text((558, 74), "Still Harbor · sample", font=font(12), fill=(FOAM[0], FOAM[1], FOAM[2], 150))
    d.rounded_rectangle((558, 100, 780, 104), radius=2, fill=(255, 255, 255, 28))
    d.rounded_rectangle((558, 100, 638, 104), radius=2, fill=SEA)
    d.polygon((512, 148, 500, 156, 512, 164), fill=FOAM)
    d.ellipse((528, 136, 568, 176), fill=FOAM)
    d.polygon((584, 148, 596, 156, 584, 164), fill=FOAM)
    d.rounded_rectangle((640, 144, 688, 168), radius=8, fill=(255, 255, 255, 22))
    d.text((650, 148), "87%", font=font(10), fill=FOAM)
    d.rounded_rectangle((696, 144, 736, 168), radius=8, fill=(255, 255, 255, 22))
    d.text((706, 148), "42", font=font(10), fill=FOAM)
    d.rounded_rectangle((470, 184, 810, 208), radius=12, fill=(255, 255, 255, 18))
    d.text((482, 190), "notes.pdf    shot.png", font=font(11), fill=(FOAM[0], FOAM[1], FOAM[2], 180))
    d.text((40, 660), "Design placeholder · Same path family, expanded player + island shelf", font=font(14), fill=(90, 94, 98, 220))
    img.convert("RGB").save(path, quality=92)


def cove(path: Path):
    img = Image.new("RGBA", (1280, 720), DESK_LIP)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 1280, 32), fill=(236, 238, 240, 255))
    d.text((18, 8), "Mon 9:41", font=font(12), fill=(80, 84, 88, 220))
    # Compact island while a drag is in flight, plus a drag-only basket — not a Dock tray.
    img = draw_notch_blend(img, (497, 0, 783, 112), ear=12, radius=22, fill=BEZEL)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((518, 38, 544, 64), radius=7, fill=KELP)
    d.text((556, 42), "Low Tide", font=font(14, True), fill=FOAM)
    d.rounded_rectangle((518, 74, 760, 100), radius=12, fill=(255, 255, 255, 18))
    d.text((530, 80), "Drop files to park", font=font(11), fill=(FOAM[0], FOAM[1], FOAM[2], 180))
    d.rounded_rectangle((520, 128, 760, 176), radius=24, fill=BEZEL, outline=SEA, width=1)
    d.text((548, 140), "Park on Shore", font=font(13, True), fill=FOAM)
    d.text((548, 158), "Lives on the island shelf", font=font(11), fill=(FOAM[0], FOAM[1], FOAM[2], 140))
    d.text((40, 660), "Design placeholder · Drag-only file basket (not a Dock cove)", font=font(14), fill=(90, 94, 98, 220))
    img.convert("RGB").save(path, quality=92)


def settings(path: Path):
    img = Image.new("RGBA", (1280, 720), (32, 34, 36, 255))
    panel = Image.new("RGBA", (1280, 720), (0, 0, 0, 0))
    d = ImageDraw.Draw(panel)
    d.rounded_rectangle((430, 110, 850, 590), radius=18, fill=(246, 246, 246, 255))
    d.text((460, 140), "Shore", font=font(26, True), fill=INK)
    d.text((460, 174), "Quiet extras for the Mac.", font=font(13), fill=(80, 84, 88, 255))
    d.rounded_rectangle((460, 220, 820, 300), radius=14, fill=(236, 236, 236, 255))
    d.text((478, 234), "Island", font=font(15, True), fill=INK)
    d.text((478, 258), "Hardware-extension notch hug.", font=font(12), fill=(90, 94, 98, 255))
    d.text((478, 276), "Hover expands; click-outside dismisses.", font=font(12), fill=(90, 94, 98, 255))
    d.rounded_rectangle((760, 246, 804, 270), radius=12, fill=SEA)
    d.rounded_rectangle((460, 320, 820, 400), radius=14, fill=(236, 236, 236, 255))
    d.text((478, 334), "File shelf", font=font(15, True), fill=INK)
    d.text((478, 358), "Park files on the island. Basket only while you drag.", font=font(12), fill=(90, 94, 98, 255))
    d.rounded_rectangle((760, 346, 804, 370), radius=12, fill=SEA)
    d.text((478, 440), "Sample media when idle", font=font(14, True), fill=INK)
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
