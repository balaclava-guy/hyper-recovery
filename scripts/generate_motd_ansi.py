#!/usr/bin/env python3
from __future__ import annotations

import argparse
from PIL import Image


def render_ansi(path: str, width: int) -> str:
    image = Image.open(path).convert("RGB")
    src_w, src_h = image.size

    target_w = max(1, width)
    target_h = max(2, int(src_h * (target_w / src_w)))
    if target_h % 2 != 0:
        target_h += 1

    image = image.resize((target_w, target_h), Image.LANCZOS)
    pixels = image.load()

    lines = []
    for y in range(0, target_h, 2):
        line = []
        for x in range(target_w):
            r1, g1, b1 = pixels[x, y]
            r2, g2, b2 = pixels[x, y + 1]
            line.append(
                f"\x1b[38;2;{r1};{g1};{b1}m\x1b[48;2;{r2};{g2};{b2}m▀"
            )
        line.append("\x1b[0m")
        lines.append("".join(line))

    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Convert a PNG logo to ANSI half-block art for MOTD."
    )
    parser.add_argument("input", help="Path to source PNG")
    parser.add_argument("output", help="Path to output .ansi file")
    parser.add_argument(
        "--width",
        type=int,
        default=80,
        help="Target character width for the output (default: 80)",
    )
    args = parser.parse_args()

    ansi = render_ansi(args.input, args.width)
    with open(args.output, "w", encoding="utf-8") as handle:
        handle.write(ansi)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
