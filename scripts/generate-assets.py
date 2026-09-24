#!/usr/bin/env python3
"""Generate the Shore app icon and README screenshot placeholders."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from island_silhouette import polygon, shoulder_fit

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


def draw_notch_blend(base, body, ear=18, radius=22, neck=(188, 32), fill=BEZEL):
    """Housing neck + cubic shoulder. `body` is (x0, y0, x1, y1)."""
    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    x0, y0, x1, y1 = body
    pts = polygon((x0, y0), (x1 - x0, y1 - y0), neck[0], neck[1], radius, ear)
    d.polygon(pts, fill=fill)
    return Image.alpha_composite(base, overlay)


def menu_bar(img):
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 1280, 28), fill=(236, 238, 240, 255))
    d.text((18, 6), "Mon 9:41", font=font(12), fill=(80, 84, 88, 220))
    d.text((1180, 6), "100%", font=font(12), fill=(80, 84, 88, 220))
    return img


def _body(neck_w, growth, height):
    width = neck_w + growth
    x0 = (1280 - width) / 2
    return (x0, 0, x0 + width, height), width


def island_collapsed(path: Path):
    img = Image.new("RGBA", (1280, 720), DESK_LIP)
    img = menu_bar(img)
    # Compact capsule, shelf off: neck through the camera, media in the belly.
    neck = (188, 32)
    body, _width = _body(neck[0], 64, 33 + 74)
    img = draw_notch_blend(img, body, ear=18, radius=22, neck=neck)
    fit = shoulder_fit((body[0], body[1], body[2] - body[0], body[3] - body[1]), neck[0], neck[1], 22, 18)
    y = fit["y_belly"] + 8
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((body[0] + 18, y, body[0] + 46, y + 28), radius=8, fill=KELP)
    d.text((body[0] + 56, y + 6), "Low Tide", font=font(14, True), fill=FOAM)
    bx = body[2] - 36
    for i, h in enumerate((12, 7, 14, 8, 10)):
        d.rectangle((bx + i * 5, y + 16 - h, bx + 2 + i * 5, y + 16), fill=SEA)
    d.text((40, 660), "Design placeholder · Compact capsule, shoulder below the camera housing", font=font(14), fill=(90, 94, 98, 220))
    img.convert("RGB").save(path, quality=92)


def island_expanded(path: Path):
    img = Image.new("RGBA", (1280, 720), DESK_LIP)
    img = menu_bar(img)
    neck = (188, 32)
    width = max(368, neck[0] + 160)
    x0 = (1280 - width) / 2
    body = (x0, 0, x0 + width, 33 + 208 + 44)
    img = draw_notch_blend(img, body, ear=30, radius=26, neck=neck)
    fit = shoulder_fit((body[0], body[1], width, body[3]), neck[0], neck[1], 26, 30)
    y = fit["y_belly"] + 8
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((x0 + 18, y, x0 + 82, y + 64), radius=14, fill=KELP, outline=(255, 255, 255, 46))
    d.text((x0 + 96, y + 8), "Low Tide", font=font(18, True), fill=FOAM)
    d.text((x0 + 96, y + 34), "Still Harbor · sample", font=font(12), fill=(FOAM[0], FOAM[1], FOAM[2], 160))
    seek_y = y + 78
    d.rounded_rectangle((x0 + 18, seek_y, body[2] - 18, seek_y + 5), radius=2, fill=(255, 255, 255, 36))
    d.rounded_rectangle((x0 + 18, seek_y, x0 + 150, seek_y + 5), radius=2, fill=SEA)
    play_y = seek_y + 22
    d.polygon((x0 + 36, play_y + 6, x0 + 24, play_y + 14, x0 + 36, play_y + 22), fill=FOAM)
    d.ellipse((x0 + 52, play_y, x0 + 88, play_y + 36), fill=FOAM)
    d.polygon((x0 + 108, play_y + 6, x0 + 120, play_y + 14, x0 + 108, play_y + 22), fill=FOAM)
    d.rounded_rectangle((body[2] - 118, play_y + 6, body[2] - 70, play_y + 30), radius=10, fill=(255, 255, 255, 22))
    d.text((body[2] - 108, play_y + 10), "87%", font=font(10), fill=FOAM)
    d.rounded_rectangle((body[2] - 62, play_y + 6, body[2] - 18, play_y + 30), radius=10, fill=(255, 255, 255, 22))
    d.text((body[2] - 50, play_y + 10), "42", font=font(10), fill=FOAM)
    shelf_y = body[3] - 12 - 44
    d.rounded_rectangle((x0 + 18, shelf_y, body[2] - 18, shelf_y + 40), radius=12, fill=(255, 255, 255, 18))
    d.rounded_rectangle((x0 + 28, shelf_y + 8, x0 + 168, shelf_y + 32), radius=12, fill=(255, 255, 255, 28))
    d.text((x0 + 40, shelf_y + 12), "notes.pdf   ×", font=font(11), fill=FOAM)
    d.rounded_rectangle((x0 + 176, shelf_y + 8, x0 + 300, shelf_y + 32), radius=12, fill=(255, 255, 255, 28))
    d.text((x0 + 188, shelf_y + 12), "shot.png   ×", font=font(11), fill=FOAM)
    d.text((40, 660), "Design placeholder · Player and dense shelf sit in the belly, not the shoulder", font=font(14), fill=(90, 94, 98, 220))
    img.convert("RGB").save(path, quality=92)


def cove(path: Path):
    img = Image.new("RGBA", (1280, 720), DESK_LIP)
    img = menu_bar(img)
    # Empty well turns sea-glass while a drag is in flight. Basket is separate, not a Dock tray.
    neck = (188, 32)
    body, _width = _body(neck[0], 64, 33 + 74 + 44)
    img = draw_notch_blend(img, body, ear=18, radius=22, neck=neck)
    fit = shoulder_fit((body[0], body[1], body[2] - body[0], body[3] - body[1]), neck[0], neck[1], 22, 18)
    y = fit["y_belly"] + 8
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((body[0] + 18, y, body[0] + 46, y + 28), radius=8, fill=KELP)
    d.text((body[0] + 56, y + 6), "Low Tide", font=font(14, True), fill=FOAM)
    well_y = body[3] - 8 - 44
    d.rounded_rectangle(
        (body[0] + 16, well_y, body[2] - 16, well_y + 40),
        radius=12,
        fill=(*SEA[:3], 70),
        outline=SEA,
        width=2,
    )
    d.text((body[0] + 32, well_y + 11), "Release to park", font=font(13, True), fill=FOAM)
    basket_y = body[3] + 18
    d.rounded_rectangle((500, basket_y, 760, basket_y + 52), radius=26, fill=BEZEL, outline=SEA, width=2)
    d.text((528, basket_y + 10), "Park on Shore", font=font(13, True), fill=FOAM)
    d.text((528, basket_y + 28), "Drop to park on the island", font=font(11), fill=(FOAM[0], FOAM[1], FOAM[2], 150))
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
