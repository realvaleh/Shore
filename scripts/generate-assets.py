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


def island_pts(origin, size, neck_w, neck_h, bottom_r, ear, bend=0.66):
    """Housing-width top, one cubic shoulder, squircle chin. Mirrors IslandBlendShape."""
    ox, oy = origin
    w, h = size
    neck = min(max(neck_w, 0), w)
    mid = ox + w / 2
    neck_left = mid - neck / 2
    neck_right = neck_left + neck
    wing = max(0, (w - neck) / 2)
    br = min(max(bottom_r, 8), max(6, w / 2 - 1), h * 0.48)
    y_start = oy + min(max(5, neck_h * 0.46), max(5, h - br - 6))
    opens = wing > 0.8 and (ear > 0.5 or wing > 2)
    y_belly = y_start
    if opens:
        target = oy + neck_h + max(ear, 0)
        y_belly = min(oy + h - br - 2, max(y_start + 8, target))
    right = ox + w
    bottom = oy + h
    pts = [(neck_left, oy), (neck_right, oy), (neck_right, y_start)]
    if opens:
        dy = max(0.01, y_belly - y_start)
        pts += cubic(
            (neck_right, y_start),
            (neck_right, y_start + bend * dy),
            (right, y_belly - bend * dy),
            (right, y_belly),
            28,
        )[1:]
    pts.append((right, bottom - br))
    pts += corner((right, bottom - br), (right, bottom), (right - br, bottom), k=0.55)[1:]
    pts.append((ox + br, bottom))
    pts += corner((ox + br, bottom), (ox, bottom), (ox, bottom - br), k=0.55)[1:]
    side_y = y_belly if opens else y_start
    pts.append((ox, side_y))
    if opens:
        dy = max(0.01, y_belly - y_start)
        pts += cubic(
            (ox, y_belly),
            (ox, y_belly - bend * dy),
            (neck_left, y_start + bend * dy),
            (neck_left, y_start),
            28,
        )[1:]
    pts.append((neck_left, oy))
    return pts


def draw_notch_blend(base, body, ear=22, radius=24, neck=(188, 32), fill=BEZEL):
    """Housing neck + liquid shoulder. `body` is (x0, y0, x1, y1)."""
    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    x0, y0, x1, y1 = body
    pts = island_pts((x0, y0), (x1 - x0, y1 - y0), neck[0], neck[1], radius, ear)
    d.polygon(pts, fill=fill)
    return Image.alpha_composite(base, overlay)


def menu_bar(img):
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 1280, 28), fill=(236, 238, 240, 255))
    d.text((18, 6), "Mon 9:41", font=font(12), fill=(80, 84, 88, 220))
    d.text((1180, 6), "100%", font=font(12), fill=(80, 84, 88, 220))
    return img


def island_collapsed(path: Path):
    img = Image.new("RGBA", (1280, 720), DESK_LIP)
    img = menu_bar(img)
    # Compact capsule: housing-width top, belly holds art + title + waveform.
    img = draw_notch_blend(img, (514, 0, 766, 96), ear=22, radius=24)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((540, 58, 566, 84), radius=7, fill=KELP)
    d.text((576, 62), "Low Tide", font=font(14, True), fill=FOAM)
    d.rectangle((724, 64, 727, 78), fill=FOAM)
    d.rectangle((730, 68, 733, 76), fill=FOAM)
    d.rectangle((736, 62, 739, 80), fill=FOAM)
    d.rectangle((742, 66, 745, 74), fill=FOAM)
    d.text((40, 660), "Design placeholder · Compact capsule growing from the housing", font=font(14), fill=(90, 94, 98, 220))
    img.convert("RGB").save(path, quality=92)


def island_expanded(path: Path):
    img = Image.new("RGBA", (1280, 720), DESK_LIP)
    img = menu_bar(img)
    img = draw_notch_blend(img, (456, 0, 824, 268), ear=36, radius=22)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((484, 76, 548, 140), radius=14, fill=KELP)
    d.text((564, 80), "Low Tide", font=font(18, True), fill=FOAM)
    d.text((564, 106), "Still Harbor · sample", font=font(12), fill=(FOAM[0], FOAM[1], FOAM[2], 150))
    d.rounded_rectangle((484, 156, 790, 160), radius=2, fill=(255, 255, 255, 28))
    d.rounded_rectangle((484, 156, 600, 160), radius=2, fill=SEA)
    d.polygon((520, 188, 508, 196, 520, 204), fill=FOAM)
    d.ellipse((536, 176, 576, 216), fill=FOAM)
    d.polygon((592, 188, 604, 196, 592, 204), fill=FOAM)
    d.rounded_rectangle((680, 184, 728, 208), radius=8, fill=(255, 255, 255, 22))
    d.text((690, 188), "87%", font=font(10), fill=FOAM)
    d.rounded_rectangle((736, 184, 776, 208), radius=8, fill=(255, 255, 255, 22))
    d.text((746, 188), "42", font=font(10), fill=FOAM)
    d.rounded_rectangle((484, 224, 790, 256), radius=12, fill=(255, 255, 255, 16), outline=(*SEA[:3], 180))
    d.text((496, 232), "notes.pdf   ×     shot.png   ×", font=font(11), fill=(FOAM[0], FOAM[1], FOAM[2], 210))
    d.text((40, 660), "Design placeholder · Same path, player below the housing, shelf in the belly", font=font(14), fill=(90, 94, 98, 220))
    img.convert("RGB").save(path, quality=92)


def cove(path: Path):
    img = Image.new("RGBA", (1280, 720), DESK_LIP)
    img = menu_bar(img)
    # Island drop well while a drag is in flight, plus a basket under it — not a Dock tray.
    img = draw_notch_blend(img, (514, 0, 766, 150), ear=22, radius=22)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((540, 58, 566, 84), radius=7, fill=KELP)
    d.text((576, 62), "Low Tide", font=font(14, True), fill=FOAM)
    d.rounded_rectangle((534, 100, 746, 136), radius=12, fill=(255, 255, 255, 28), outline=SEA, width=2)
    d.text((548, 110), "Release to park", font=font(13, True), fill=FOAM)
    d.rounded_rectangle((500, 168, 760, 220), radius=26, fill=BEZEL, outline=SEA, width=2)
    d.text((528, 182), "Park on Shore", font=font(13, True), fill=FOAM)
    d.text((528, 200), "Drop to park on the island", font=font(11), fill=(FOAM[0], FOAM[1], FOAM[2], 150))
    d.text((40, 660), "Design placeholder · Drag-only basket under the island, not a Dock strip", font=font(14), fill=(90, 94, 98, 220))
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
    d.text((478, 258), "Rests as the camera housing.", font=font(12), fill=(90, 94, 98, 255))
    d.text((478, 276), "Hover expands; click-outside dismisses.", font=font(12), fill=(90, 94, 98, 255))
    d.rounded_rectangle((760, 246, 804, 270), radius=12, fill=SEA)
    d.rounded_rectangle((460, 320, 820, 400), radius=14, fill=(236, 236, 236, 255))
    d.text((478, 334), "File shelf", font=font(15, True), fill=INK)
    d.text((478, 358), "Drop on the island. Basket only while you drag.", font=font(12), fill=(90, 94, 98, 255))
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
