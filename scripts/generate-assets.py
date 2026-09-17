#!/usr/bin/env python3
"""Generate the Shore app icon and README screenshot placeholders."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ICON_DIR = ROOT / "Shore" / "Assets.xcassets" / "AppIcon.appiconset"
SHOT_DIR = ROOT / "docs" / "screenshots"

INK = (12, 14, 16, 255)
INK_LIFT = (22, 26, 30, 255)
FOAM = (232, 238, 240, 255)
SEA = (124, 158, 160, 255)
KELP = (61, 90, 84, 255)
SAND = (196, 184, 165, 255)


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


def island_collapsed(path: Path):
    img = Image.new("RGBA", (1280, 720), (18, 20, 22, 255))
    d = ImageDraw.Draw(img)
    # Menu bar flanking a hardware notch
    d.rectangle((0, 0, 1280, 32), fill=(20, 22, 24, 255))
    d.text((18, 8), "Mon 9:41", font=font(12), fill=(200, 204, 208, 180))
    d.text((1180, 8), "100%", font=font(12), fill=(200, 204, 208, 180))
    # Camera housing — true black, flush with the top bezel
    d.rectangle((548, 0, 732, 32), fill=(0, 0, 0, 255))
    # Lip grown FROM the notch (no gap, concave shoulders)
    lip = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(lip)
    # Body below the housing
    ld.rounded_rectangle((470, 32, 810, 84), radius=18, fill=INK)
    # Fill the inverted corners so the lip reads as attached, not a floating pill
    ld.rectangle((548, 24, 732, 40), fill=INK)
    img = Image.alpha_composite(img, lip)
    d = ImageDraw.Draw(img)
    d.rectangle((548, 0, 732, 32), fill=(0, 0, 0, 255))
    d.rounded_rectangle((488, 42, 512, 66), radius=6, fill=KELP)
    d.text((522, 42), "Low Tide", font=font(14, True), fill=FOAM)
    d.text((522, 60), "Still Harbor", font=font(11), fill=(FOAM[0], FOAM[1], FOAM[2], 150))
    d.rounded_rectangle((742, 46, 766, 64), radius=8, fill=INK_LIFT)
    d.rounded_rectangle((772, 46, 796, 64), radius=8, fill=INK_LIFT)
    d.text((40, 660), "Design placeholder · Island hugging the hardware notch", font=font(14), fill=(160, 166, 170, 200))
    img.convert("RGB").save(path, quality=92)


def island_expanded(path: Path):
    img = Image.new("RGBA", (1280, 720), (18, 20, 22, 255))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 1280, 32), fill=(20, 22, 24, 255))
    d.text((18, 8), "Mon 9:41", font=font(12), fill=(200, 204, 208, 180))
    # Notch housing stays put; body grows from it
    body = Image.new("RGBA", img.size, (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    bd.rounded_rectangle((426, 32, 854, 248), radius=22, fill=INK)
    bd.rectangle((548, 20, 732, 40), fill=INK)
    img = Image.alpha_composite(img, body)
    d = ImageDraw.Draw(img)
    d.rectangle((548, 0, 732, 32), fill=(0, 0, 0, 255))
    d.rounded_rectangle((448, 48, 532, 132), radius=14, fill=KELP)
    d.text((548, 52), "Low Tide", font=font(20, True), fill=FOAM)
    d.text((548, 80), "Still Harbor · sample", font=font(13), fill=(FOAM[0], FOAM[1], FOAM[2], 150))
    d.rounded_rectangle((548, 112, 780, 116), radius=2, fill=(255, 255, 255, 28))
    d.rounded_rectangle((548, 112, 628, 116), radius=2, fill=SEA)
    d.polygon((488, 168, 476, 176, 488, 184), fill=FOAM)
    d.ellipse((506, 156, 548, 198), fill=FOAM)
    d.polygon((566, 168, 578, 176, 566, 184), fill=FOAM)
    d.rounded_rectangle((620, 164, 668, 188), radius=8, fill=INK_LIFT)
    d.text((628, 168), "87%", font=font(10), fill=FOAM)
    d.rounded_rectangle((676, 164, 720, 188), radius=8, fill=INK_LIFT)
    d.text((684, 168), "42", font=font(10), fill=FOAM)
    # File shelf
    d.rounded_rectangle((448, 204, 832, 236), radius=10, fill=INK_LIFT)
    d.text((460, 212), "Shelf   notes.pdf    shot.png", font=font(11), fill=(FOAM[0], FOAM[1], FOAM[2], 180))
    d.text((40, 660), "Design placeholder · Island expanded from the notch + file shelf", font=font(14), fill=(160, 166, 170, 200))
    img.convert("RGB").save(path, quality=92)


def tide_line(path: Path):
    img = Image.new("RGBA", (1280, 720), (18, 20, 22, 255))
    d = ImageDraw.Draw(img)
    # Fake dock
    d.rounded_rectangle((360, 640, 920, 704), radius=18, fill=(40, 44, 48, 210))
    for i, x in enumerate(range(390, 900, 70)):
        color = SEA if i == 3 else (90, 96, 100, 255)
        d.rounded_rectangle((x, 652, x + 44, 696), radius=10, fill=color)
    # Tide line
    d.rounded_rectangle((430, 622, 850, 632), radius=6, fill=(180, 200, 200, 50))
    d.ellipse((590, 618, 670, 636), fill=(FOAM[0], FOAM[1], FOAM[2], 90))
    d.text((40, 40), "Design placeholder · Tide Line above the Dock", font=font(14), fill=(160, 166, 170, 200))
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
    d.text((478, 238), "Now playing in the notch,", font=font(12), fill=(90, 94, 98, 255))
    d.text((478, 256), "or a floating pill on other Macs.", font=font(12), fill=(90, 94, 98, 255))
    d.rounded_rectangle((760, 226, 804, 250), radius=12, fill=SEA)
    d.rounded_rectangle((460, 300, 820, 380), radius=14, fill=(236, 236, 236, 255))
    d.text((478, 314), "File shelf", font=font(15, True), fill=INK)
    d.text((478, 338), "Drop files onto the island to park them.", font=font(12), fill=(90, 94, 98, 255))
    d.rounded_rectangle((760, 326, 804, 350), radius=12, fill=SEA)
    d.rounded_rectangle((460, 400, 820, 480), radius=14, fill=(236, 236, 236, 255))
    d.text((478, 414), "Dock Tide Line", font=font(15, True), fill=INK)
    d.text((478, 438), "A quiet glass shoreline above the Dock.", font=font(12), fill=(90, 94, 98, 255))
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
    tide_line(SHOT_DIR / "tide-line.png")
    settings(SHOT_DIR / "settings.png")
    print("Wrote icons and screenshot placeholders")


if __name__ == "__main__":
    main()
