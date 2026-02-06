"""Generate high-fidelity 90s arcade pixel art assets for Hyper Recovery."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


BASE_DIR = Path(__file__).resolve().parent.parent
FONT_PATH = BASE_DIR / "assets" / "fonts" / "PressStart2P-Regular.ttf"


def _lerp(color_a, color_b, t):
    return tuple(int(color_a[i] + (color_b[i] - color_a[i]) * t) for i in range(3))


def _gradient(size, top_color, bottom_color):
    width, height = size
    gradient = Image.new("RGB", size)
    draw = ImageDraw.Draw(gradient)
    for y in range(height):
        ratio = y / (height - 1) if height > 1 else 0
        draw.line((0, y, width, y), fill=_lerp(top_color, bottom_color, ratio))
    return gradient


def _multi_gradient(size, stops):
    if not stops:
        raise ValueError("Gradient requires at least one stop")
    width, height = size
    canvas = Image.new("RGB", size)
    draw = ImageDraw.Draw(canvas)
    sorted_stops = sorted(stops, key=lambda stop: stop[0])
    for y in range(height):
        ratio = y / (height - 1) if height > 1 else 0
        color = sorted_stops[-1][1]
        if ratio <= sorted_stops[0][0]:
            color = sorted_stops[0][1]
        elif ratio >= sorted_stops[-1][0]:
            color = sorted_stops[-1][1]
        else:
            for lower, upper in zip(sorted_stops, sorted_stops[1:]):
                if lower[0] <= ratio <= upper[0]:
                    local = (ratio - lower[0]) / max(upper[0] - lower[0], 1e-6)
                    color = _lerp(lower[1], upper[1], local)
                    break
        draw.line((0, y, width, y), fill=color)
    return canvas


def _radial_glow(size, center, radius, color, strength=160):
    overlay = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    steps = max(radius // 6, 4)
    for step in range(steps, 0, -1):
        factor = step / steps
        alpha = int(strength * factor * factor)
        current_radius = int(radius * factor)
        draw.ellipse(
            [center[0] - current_radius, center[1] - current_radius, center[0] + current_radius, center[1] + current_radius],
            fill=(*color, alpha),
        )
    return overlay


def _apply_noise(image, intensity=12):
    noise = Image.effect_noise(image.size, 64).convert("L")
    noise = noise.point(lambda value: int(value * intensity / 255))
    overlay = Image.new("RGBA", image.size, (255, 255, 255, 0))
    overlay.putalpha(noise)
    return Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB")


def _draw_gradient_text(canvas, text, font, position, top_color, bottom_color, shadow=(8, 8), highlight_color=(255, 255, 255, 100)):
    canvas = canvas.convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    x, y = position
    if shadow:
        draw.text((x + shadow[0], y + shadow[1]), text, font=font, fill=(0, 0, 0, 180))
    bbox = font.getbbox(text)
    width = bbox[2] - bbox[0]
    height = bbox[3] - bbox[1]
    gradient = _gradient((width, height), top_color, bottom_color).convert("RGBA")
    mask = Image.new("L", (width, height), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.text((-bbox[0], -bbox[1]), text, font=font, fill=255)
    canvas.paste(gradient, (x + bbox[0], y + bbox[1]), mask)
    if highlight_color:
        highlight = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        highlight_draw = ImageDraw.Draw(highlight)
        highlight_draw.text((x + 4, y - 6), text, font=font, fill=highlight_color)
        highlight = highlight.filter(ImageFilter.GaussianBlur(3))
        canvas = Image.alpha_composite(canvas, highlight)
    return canvas


def _draw_scanlines(image, step=6, intensity=12):
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    width, height = image.size
    for y in range(0, height, step):
        alpha = int(min(255, intensity + (step / 2)))
        draw.line((0, y, width, y), fill=(0, 0, 0, alpha))
    return Image.alpha_composite(image.convert("RGBA"), overlay)


def _draw_grid_overlay(image, color, spacing=96):
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    width, height = image.size
    for x in range(0, width, spacing):
        draw.line((x, 0, x, height), fill=color)
    for y in range(0, height, spacing):
        draw.line((0, y, width, y), fill=color)
    return Image.alpha_composite(image.convert("RGBA"), overlay)


def _draw_pixel_sprite(draw, origin, pattern, palette, cell_size=12):
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
            draw.rectangle(
                [x0, y0, x0 + cell_size - 1, y0 + cell_size - 1],
                fill=color,
            )


def _font(size):
    try:
        return ImageFont.truetype(FONT_PATH, size)
    except OSError:
        return ImageFont.load_default()


def create_grub_background(path: Path):
    canvas = _multi_gradient(
        (1920, 1080),
        [
            (0.0, (5, 0, 18)),
            (0.3, (18, 2, 85)),
            (0.55, (200, 5, 158)),
            (0.8, (40, 3, 45)),
            (1.0, (6, 0, 12)),
        ],
    )
    canvas = _apply_noise(canvas, intensity=18)
    glow = _radial_glow(canvas.size, (400, 260), 520, (252, 108, 207), strength=180)
    canvas = Image.alpha_composite(canvas.convert("RGBA"), glow)
    draw = ImageDraw.Draw(canvas)

    draw.rectangle([220, 300, 1700, 380], fill=(18, 5, 40))
    draw.rectangle([0, 520, 1920, 1080], fill=(5, 3, 16))

    fighter_left = [
        "...RRR...",
        "..RROOR..",
        "..RROOR..",
        ".RRROOOR.",
        ".RRROOOR.",
        "RRRRRRRR",
        "..RR..RR",
        "..RR..RR",
        "..RR..RR",
        "..RR..RR",
        "..RR..RR",
    ]
    fighter_right = [
        "...YYY...",
        "..YBBBY..",
        "..YBBBY..",
        ".YYBBBBY.",
        ".YYBBBBY.",
        "YYYYYYYY",
        "..YY..YY",
        "..YY..YY",
        "..YY..YY",
        "..YY..YY",
        "..YY..YY",
    ]
    _draw_pixel_sprite(draw, (200, 530), fighter_left, {"R": (255, 96, 134), "O": (255, 204, 130)})
    _draw_pixel_sprite(draw, (1240, 530), fighter_right, {"Y": (255, 244, 146), "B": (91, 192, 255)})

    canvas = _draw_gradient_text(
        canvas,
        "HYPER",
        _font(110),
        (320, 180),
        (255, 192, 47),
        (255, 69, 164),
        shadow=(12, 12),
        highlight_color=(255, 255, 255, 140),
    )
    canvas = _draw_gradient_text(
        canvas,
        "RECOVERY",
        _font(110),
        (280, 300),
        (255, 255, 255),
        (255, 150, 60),
        shadow=(12, 12),
        highlight_color=(255, 255, 255, 180),
    )

    ticker = "  HYPER RECOVERY • ARCADE SHADOWRIFT •" * 3
    ImageDraw.Draw(canvas).text((0, 940), ticker, font=_font(28), fill=(255, 128, 195))

    shimmer = Image.new("RGBA", canvas.size)
    shimmer_draw = ImageDraw.Draw(shimmer)
    for i in range(0, canvas.width, 240):
        shimmer_draw.line((i, 0, i - 180, canvas.height), fill=(255, 255, 255, 60), width=3)
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shimmer)

    canvas = _draw_grid_overlay(canvas, (93, 9, 168, 110), spacing=128)
    canvas = _draw_scanlines(canvas, step=6, intensity=20)

    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(path)


def create_plymouth_background(path: Path):
    canvas = _multi_gradient(
        (1920, 1080),
        [
            (0.0, (4, 0, 16)),
            (0.25, (10, 6, 65)),
            (0.5, (19, 12, 125)),
            (0.75, (74, 0, 162)),
            (1.0, (12, 3, 28)),
        ],
    )
    canvas = _apply_noise(canvas, intensity=10)
    glow = _radial_glow(canvas.size, (1500, 480), 640, (255, 72, 189), strength=170)
    canvas = Image.alpha_composite(canvas.convert("RGBA"), glow)
    draw = ImageDraw.Draw(canvas)

    draw.rectangle([80, 320, 1840, 460], fill=(15, 5, 34))
    draw.rectangle([0, 520, 1920, 1080], fill=(5, 2, 18))

    crowd = [
        "...........",
        "..GGGGGGG..",
        ".GGRRRRRGG.",
        "GGRRRRRRRGG",
        "GGRRRRRRRGG",
        "GGRRRRRRRGG",
        ".GGRRRRRGG.",
        "..GGGGGGG..",
    ]
    _draw_pixel_sprite(draw, (620, 300), crowd, {"G": (91, 209, 255), "R": (255, 102, 117)}, cell_size=18)

    beam = Image.new("RGBA", canvas.size)
    beam_draw = ImageDraw.Draw(beam)
    beam_draw.polygon([(1200, 320), (1420, 120), (1540, 140), (1280, 390)], fill=(255, 106, 190, 60))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), beam)

    canvas = _draw_gradient_text(
        canvas,
        "HYPER",
        _font(84),
        (420, 540),
        (255, 255, 255),
        (255, 90, 130),
        shadow=(6, 6),
        highlight_color=(255, 255, 255, 120),
    )
    canvas = _draw_gradient_text(
        canvas,
        "RECOVERY",
        _font(84),
        (400, 620),
        (255, 215, 115),
        (255, 82, 197),
        shadow=(6, 6),
        highlight_color=(255, 255, 255, 160),
    )

    draw = ImageDraw.Draw(canvas)
    draw.text((320, 760), "90s RETRO FIGHTER EDITION", font=_font(34), fill=(205, 230, 255))

    canvas = _draw_grid_overlay(canvas, (72, 13, 140, 90), spacing=112)
    canvas = _draw_scanlines(canvas, step=5, intensity=10)

    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(path)


def create_logo(path: Path):
    canvas = Image.new("RGBA", (640, 320), (8, 2, 24, 255))
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((0, 0, 640, 240), fill=(22, 4, 65))
    draw = ImageDraw.Draw(canvas)
    canvas = _draw_gradient_text(
        canvas,
        "HYPER",
        _font(60),
        (30, 30),
        (255, 217, 96),
        (255, 80, 140),
        shadow=(4, 4),
        highlight_color=(255, 255, 255, 110),
    )
    canvas = _draw_gradient_text(
        canvas,
        "RECOVERY",
        _font(76),
        (20, 120),
        (255, 255, 255),
        (255, 150, 60),
        shadow=(4, 4),
        highlight_color=(255, 255, 255, 140),
    )
    draw.rectangle((0, 250, 640, 320), fill=(255, 255, 255, 30))
    canvas.convert("RGBA").save(path)


def create_progress_assets(frame_path: Path, bar_path: Path):
    frame = Image.new("RGBA", (780, 48), (12, 1, 30, 255))
    draw = ImageDraw.Draw(frame)
    draw.rounded_rectangle((0, 0, 780, 48), radius=28, outline=(255, 255, 255, 160), width=4)
    frame.save(frame_path)

    bar = Image.new("RGBA", (732, 28))
    bar_draw = ImageDraw.Draw(bar)
    for i in range(bar.width):
        ratio = i / (bar.width - 1)
        color = _lerp((255, 99, 71), (255, 218, 91), ratio)
        bar_draw.line((i, 0, i, bar.height), fill=color)
    bar = bar.filter(ImageFilter.GaussianBlur(0.8))
    bar.save(bar_path)


def create_glow(path: Path):
    base = Image.new("RGBA", (640, 240), (0, 0, 0, 0))
    draw = ImageDraw.Draw(base)
    center = (320, 120)
    for offset in range(220, 0, -18):
        alpha = int(255 * (1 - offset / 220) * 0.4)
        draw.ellipse(
            [center[0] - offset, center[1] - offset, center[0] + offset, center[1] + offset],
            outline=(255, 110, 195, alpha),
            width=12,
        )
    base = base.filter(ImageFilter.GaussianBlur(9))
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
