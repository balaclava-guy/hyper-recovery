"""Generate a neon Street Fighter II / arcade-inspired Hyper Recovery art set."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


BASE_DIR = Path(__file__).resolve().parent.parent
RETRO_FONT_PATH = BASE_DIR / "assets" / "fonts" / "PressStart2P-Regular.ttf"
SF2_FONT_PATH = BASE_DIR / "assets" / "fonts" / "Street-Fighter-II.ttf"


def _retro_font(size: int):
    try:
        return ImageFont.truetype(RETRO_FONT_PATH, size)
    except OSError:
        return ImageFont.load_default()


def _logo_font(size: int):
    try:
        return ImageFont.truetype(SF2_FONT_PATH, size)
    except OSError:
        return _retro_font(size)


def _lerp(color_a, color_b, t):
    return tuple(int(color_a[i] + (color_b[i] - color_a[i]) * t) for i in range(3))


def _gradient(size, top_color, bottom_color):
    width, height = size
    canvas = Image.new("RGB", size)
    draw = ImageDraw.Draw(canvas)
    for y in range(height):
        ratio = y / (height - 1) if height > 1 else 0
        draw.line((0, y, width, y), fill=_lerp(top_color, bottom_color, ratio))
    return canvas


def _multi_gradient(size, stops):
    width, height = size
    canvas = Image.new("RGB", size)
    draw = ImageDraw.Draw(canvas)
    stops = sorted(stops, key=lambda stop: stop[0])
    for y in range(height):
        ratio = y / (height - 1) if height > 1 else 0
        for idx in range(len(stops) - 1):
            lower, upper = stops[idx], stops[idx + 1]
            if lower[0] <= ratio <= upper[0]:
                local = (ratio - lower[0]) / max(upper[0] - lower[0], 1e-6)
                color = _lerp(lower[1], upper[1], local)
                draw.line((0, y, width, y), fill=color)
                break
        else:
            if ratio <= stops[0][0]:
                draw.line((0, y, width, y), fill=stops[0][1])
            else:
                draw.line((0, y, width, y), fill=stops[-1][1])
    return canvas


def _radial_glow(size, center, radius, color, strength=170):
    overlay = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    steps = max(radius // 8, 4)
    for step in range(steps, 0, -1):
        factor = step / steps
        alpha = int(strength * factor * factor)
        current = int(radius * factor)
        draw.ellipse([
            center[0] - current,
            center[1] - current,
            center[0] + current,
            center[1] + current,
        ], fill=(*color, alpha))
    return overlay


def _apply_noise(image, intensity=14):
    noise = Image.effect_noise(image.size, 64).convert("L")
    noise = noise.point(lambda value: int(value * intensity / 255))
    overlay = Image.new("RGBA", image.size, (255, 255, 255, 0))
    overlay.putalpha(noise)
    return Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB")


def _draw_gradient_text(canvas, text, font, position, top_color, bottom_color, shadow=(6, 6), highlight_color=(255, 255, 255, 90)):
    canvas = canvas.convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    x, y = position
    if shadow:
        draw.text((x + shadow[0], y + shadow[1]), text, font=font, fill=(0, 0, 0, 200))
    bbox = font.getbbox(text)
    width = bbox[2] - bbox[0]
    height = bbox[3] - bbox[1]
    gradient = _gradient((width, height), top_color, bottom_color).convert("RGBA")
    mask = Image.new("L", (width, height), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.text((-bbox[0], -bbox[1]), text, font=font, fill=255)
    canvas.paste(gradient, (x + bbox[0], y + bbox[1]), mask)
    if highlight_color:
        highlight = Image.new("RGBA", canvas.size)
        highlight_draw = ImageDraw.Draw(highlight)
        highlight_draw.text((x + 4, y - 8), text, font=font, fill=highlight_color)
        canvas = Image.alpha_composite(canvas, highlight.filter(ImageFilter.GaussianBlur(3)))
    return canvas


def _draw_scanlines(image, step=5, intensity=12):
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    width, height = image.size
    for y in range(0, height, step):
        alpha = int(min(255, intensity + (step // 2)))
        draw.line((0, y, width, y), fill=(0, 0, 0, alpha))
    return Image.alpha_composite(image.convert("RGBA"), overlay)


def _draw_grid_overlay(image, color, spacing=80):
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    width, height = image.size
    for x in range(0, width, spacing):
        draw.line((x, 0, x, height), fill=color)
    for y in range(0, height, spacing):
        draw.line((0, y, width, y), fill=color)
    return Image.alpha_composite(image.convert("RGBA"), overlay)


def _draw_pixel_sprite(draw, origin, pattern, palette, cell_size=16):
    ox, oy = origin
    for y, row in enumerate(pattern):
        for x, token in enumerate(row):
            if token == ".":
                continue
            color = palette.get(token)
            if not color:
                continue
            x0 = ox + x * cell_size
            y0 = oy + y * cell_size
            draw.rectangle([x0, y0, x0 + cell_size - 1, y0 + cell_size - 1], fill=color)


def _pad_pattern(pattern, width=20):
    return [row.ljust(width, ".")[:width] for row in pattern]


def _fighter_patterns():
    left = [
        "....................",
        "....LLLLLLLLLL....",
        "...LLSSSSSSSSLL...",
        "..LLSSSSSSSSSLL..",
        "..LSSSSSCCCSSSSL..",
        ".LSSSSSCCWCCCSSSL.",
        ".LSSSSCCCCCCCCCSS.",
        ".LLSSCCSCCSCCSSLL.",
        ".LLSSCCSCCSCCSSLL.",
        ".LLSSCCSCCSCCSSLL.",
        ".LLSSCCSCCSCCSSLL.",
        ".LLSSCCSCCSCCSSLL.",
        ".LLSSCCSCCSCCSSLL.",
        "..LLSSCCSCCCCSLL..",
        "..LLSSSSSSSSSSLL..",
        "...LLLLSSLLLLL...",
        "....LLRRRRRLL....",
        "....LSSRRRSSL....",
        "....LSSRRRSSL....",
        ".....LSSRRSL.....",
        "......LLLL.......",
    ]
    right = [
        "....................",
        "....HHHHHHHHHH....",
        "...HHKKKKKKKKHH...",
        "...HKPPPPPPPHH...",
        "..HKKPYYYYHPKH..",
        "..HKPPYYYYPPKHH..",
        ".HKKPPYYLLLLPPK.",
        ".HKKPPYYLLLLPPK.",
        ".HKKPPYYLLLLPPK.",
        ".HKKPPYYLLLLPPK.",
        ".HKKPPYYLLLLPPK.",
        ".HKPPPPPPPPPKHH.",
        "..HKPPPPPPPPKH..",
        "...HKPPPPKKHH...",
        "...HHKKKKHH.....",
        ".....HHHHH......",
        ".....HBPPBH.....",
        "....HBBPPBBH....",
        "....HBBBBBH....",
        "....HBBBBBH....",
    ]
    return _pad_pattern(left), _pad_pattern(right)


def create_grub_background(path: Path):
    canvas = _multi_gradient(
        (1920, 1080),
        [
            (0.0, (5, 0, 24)),
            (0.25, (18, 3, 83)),
            (0.5, (239, 46, 131)),
            (0.75, (35, 0, 70)),
            (1.0, (8, 0, 18)),
        ],
    )
    canvas = _apply_noise(canvas, intensity=22)
    glow = _radial_glow(canvas.size, (420, 220), 580, (255, 88, 186), strength=210)
    canvas = Image.alpha_composite(canvas.convert("RGBA"), glow)
    draw = ImageDraw.Draw(canvas)

    draw.rectangle([180, 320, 1740, 420], fill=(18, 5, 52))
    draw.polygon([(220, 420), (400, 520), (1520, 520), (1700, 420)], fill=(18, 5, 40))
    draw.rectangle([0, 600, 1920, 1080], fill=(5, 3, 16))
    for y in range(620, 720, 6):
        draw.line((0, y, 1920, y), fill=(12, 12, 35, 120))

    left_pattern, right_pattern = _fighter_patterns()
    palette_left = {
        "L": (45, 11, 74),
        "S": (254, 218, 182),
        "C": (210, 27, 49),
        "W": (255, 236, 141),
        "R": (16, 46, 102),
    }
    palette_right = {
        "H": (11, 123, 215),
        "K": (255, 132, 51),
        "P": (255, 224, 99),
        "Y": (254, 209, 157),
        "L": (25, 9, 55),
        "B": (19, 18, 36),
    }
    _draw_pixel_sprite(draw, (220, 520), left_pattern, palette_left, cell_size=20)
    _draw_pixel_sprite(draw, (1210, 520), right_pattern, palette_right, cell_size=20)

    canvas = _draw_gradient_text(
        canvas,
        "HYPER",
        _logo_font(140),
        (270, 120),
        (255, 206, 42),
        (255, 79, 143),
        shadow=(14, 14),
        highlight_color=(255, 255, 255, 190),
    )
    draw = ImageDraw.Draw(canvas)
    canvas = _draw_gradient_text(
        canvas,
        "RECOVERY",
        _logo_font(140),
        (230, 260),
        (255, 255, 255),
        (255, 165, 48),
        shadow=(14, 14),
        highlight_color=(255, 255, 255, 210),
    )
    draw = ImageDraw.Draw(canvas)

    draw.text((420, 600), "STREET FIGHTER II · HYPER RECOVERY ARENA", font=_retro_font(26), fill=(255, 196, 130))
    draw.text((420, 640), "FULL RESTORE MODE ENABLED", font=_retro_font(26), fill=(122, 231, 255))

    canvas = _draw_grid_overlay(canvas, (92, 7, 165, 128), spacing=140)
    canvas = _draw_scanlines(canvas, step=6, intensity=20)

    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(path)


def create_plymouth_background(path: Path):
    canvas = _multi_gradient(
        (1920, 1080),
        [
            (0.0, (4, 0, 15)),
            (0.3, (16, 5, 76)),
            (0.6, (91, 18, 160)),
            (0.9, (5, 0, 32)),
            (1.0, (2, 0, 8)),
        ],
    )
    canvas = _apply_noise(canvas, intensity=16)
    glow = _radial_glow(canvas.size, (1520, 360), 520, (255, 92, 196), strength=190)
    canvas = Image.alpha_composite(canvas.convert("RGBA"), glow)
    draw = ImageDraw.Draw(canvas)

    draw.rectangle([100, 340, 1820, 460], fill=(16, 5, 32))
    draw.rectangle([0, 580, 1920, 1080], fill=(5, 2, 16))
    for y in range(600, 720, 8):
        draw.line((0, y, 1920, y), fill=(23, 10, 45, 60))

    left_pattern, right_pattern = _fighter_patterns()
    _draw_pixel_sprite(draw, (220, 520), left_pattern, {
        "L": (30, 7, 51),
        "S": (255, 225, 198),
        "C": (195, 26, 46),
        "W": (255, 244, 160),
        "R": (12, 38, 97),
    }, cell_size=14)
    _draw_pixel_sprite(draw, (1210, 520), right_pattern, {
        "H": (16, 118, 210),
        "K": (255, 130, 60),
        "P": (255, 230, 110),
        "Y": (255, 210, 170),
        "L": (19, 9, 44),
        "B": (12, 11, 32),
    }, cell_size=14)

    canvas = _draw_gradient_text(
        canvas,
        "HYPER",
        _logo_font(82),
        (360, 480),
        (255, 255, 255),
        (255, 73, 136),
        shadow=(6, 6),
        highlight_color=(255, 255, 255, 160),
    )
    draw = ImageDraw.Draw(canvas)
    canvas = _draw_gradient_text(
        canvas,
        "RECOVERY",
        _logo_font(82),
        (340, 560),
        (255, 210, 110),
        (255, 76, 179),
        shadow=(6, 6),
        highlight_color=(255, 255, 255, 180),
    )
    draw = ImageDraw.Draw(canvas)

    draw.text((380, 680), "90s ARCADE PIXEL FAREWELL", font=_retro_font(30), fill=(238, 153, 255))
    draw.text((380, 720), "RECOVERY COMBATS RESTORED", font=_retro_font(30), fill=(255, 215, 165))

    canvas = _draw_grid_overlay(canvas, (92, 7, 165, 110), spacing=110)
    canvas = _draw_scanlines(canvas, step=5, intensity=14)

    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(path)


def create_logo(path: Path):
    canvas = Image.new("RGBA", (1100, 420), (8, 2, 28, 255))
    canvas = _draw_gradient_text(
        canvas,
        "HYPER",
        _logo_font(160),
        (140, 80),
        (255, 207, 57),
        (255, 75, 159),
        shadow=(12, 12),
        highlight_color=(255, 255, 255, 220),
    )
    canvas = _draw_gradient_text(
        canvas,
        "RECOVERY",
        _logo_font(160),
        (110, 220),
        (255, 255, 255),
        (255, 140, 60),
        shadow=(14, 14),
        highlight_color=(255, 255, 255, 230),
    )
    headline = ImageDraw.Draw(canvas)
    headline.rectangle((80, 320, 1020, 385), fill=(255, 255, 255, 40))
    headline.text((220, 330), "HYPER FIGHTER RECOVERY MODE", font=_retro_font(32), fill=(255, 255, 255))
    canvas = _draw_scanlines(canvas, step=5, intensity=16)
    canvas = _draw_grid_overlay(canvas, (90, 8, 150, 140), spacing=90)
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGBA").save(path)


def create_progress_assets(frame_path: Path, bar_path: Path):
    frame = Image.new("RGBA", (780, 48), (11, 3, 34, 255))
    draw = ImageDraw.Draw(frame)
    draw.rounded_rectangle((0, 0, 780, 48), radius=26, outline=(255, 255, 255, 180), width=4)
    draw.rectangle((12, 12, 768, 36), fill=(7, 7, 24))
    frame.save(frame_path)

    bar = Image.new("RGBA", (732, 28))
    bar_draw = ImageDraw.Draw(bar)
    for i in range(bar.width):
        ratio = i / (bar.width - 1)
        color = _lerp((255, 102, 53), (255, 236, 104), ratio)
        bar_draw.line((i, 0, i, bar.height), fill=color)
    bar = bar.filter(ImageFilter.GaussianBlur(0.8))
    bar.save(bar_path)


def create_glow(path: Path):
    base = Image.new("RGBA", (640, 240), (0, 0, 0, 0))
    draw = ImageDraw.Draw(base)
    center = (320, 120)
    for radius in range(220, 0, -18):
        alpha = int(255 * (1 - radius / 220) * 0.45)
        draw.ellipse([
            center[0] - radius,
            center[1] - radius,
            center[0] + radius,
            center[1] + radius,
        ], outline=(255, 108, 188, alpha), width=12)
    base = base.filter(ImageFilter.GaussianBlur(10))
    base.save(path)


def main():
    create_grub_background(BASE_DIR / "assets" / "grub" / "hyper-recovery-grub-bg.png")
    create_plymouth_background(BASE_DIR / "assets" / "plymouth" / "hyper-recovery-bg.png")
    create_logo(BASE_DIR / "assets" / "plymouth" / "hyper-recovery-logo.png")
    create_progress_assets(
        BASE_DIR / "assets" / "plymouth" / "hyper-recovery-progress-frame.png",
        BASE_DIR / "assets" / "plymouth" / "hyper-recovery-progress-bar.png",
    )
    create_glow(BASE_DIR / "assets" / "plymouth" / "hyper-recovery-glow.png")


if __name__ == "__main__":
    main()
