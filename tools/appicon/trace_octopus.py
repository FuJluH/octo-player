"""Octo's octopus as vector art: octopus.svg, traced from octopus.png.

  python trace_octopus.py

The painted octopus is 537 px wide, with a dark one-pixel fringe and a
noisy fill, so any icon bigger than that shows the pixels. This traces its
three parts (the body with the eye holes, the headphones, and the darker ear
pads) into smooth curves and fills each with the straight gradient its paint
follows, measured from the painting. The headphones and the eyes are drawn
symmetric, as they were meant to be: the right side, which traces cleanly,
mirrored about the head's own centre line. The SVG keeps octopus.png's own box and
coordinates, so it places exactly as the PNG does.

Needs numpy, scipy, Pillow and potrace on the PATH. Run with PYTHONUTF8=1.
"""
import re
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = Path(__file__).resolve().parent
OCTOPUS = HERE / "octopus.png"
SVG = HERE / "octopus.svg"

# Traced at eight times the painting's size, after a blur of two painted
# pixels: enough to iron out the stair steps and the painting's waver, little
# enough that the tips of the tentacles stay pointed.
SCALE = 8
BLUR = 2.0 * SCALE
PAD_BLUR = 3.5 * SCALE
# How far potrace may move a curve off the traced edge to make it smooth:
# about one painted pixel, enough to iron out the painting's waver.
OPT_TOLERANCE = 1.0 * SCALE

# The ear pads are the headphones' dark paint: luma under the midpoint of
# the cups (~95) and the pads (~55).
CUP_LUMA, PAD_LUMA = 95.0, 55.0


def parts(pixels):
    """The body and the headphones as masks: the two pieces of ink."""
    ink = pixels[..., 3] > 127
    labels, count = ndimage.label(ink)
    sizes = ndimage.sum(ink, labels, range(1, count + 1))
    body, headphones = (labels == i + 1 for i in np.argsort(-sizes)[:2])
    return body, headphones


def pads(pixels, headphones):
    """The two ear pads as a soft mask: read from the paint's darkness away
    from the edge, where the fringe would read as pad too, grown back to the
    edge, and a pixel and a half past it into the background."""
    luma = pixels[..., :3] @ np.array([0.299, 0.587, 0.114])
    inside = ndimage.binary_erosion(headphones, iterations=2)
    dark = inside & (luma < (CUP_LUMA + PAD_LUMA) / 2)
    # Opened enough to drop the shadow where the band meets the cup.
    dark = ndimage.binary_opening(dark, iterations=3)
    labels, count = ndimage.label(dark)
    sizes = ndimage.sum(dark, labels, range(1, count + 1))
    keep = np.isin(labels, [i + 1 for i in np.argsort(-sizes)[:2]])
    # Grown back only into the edge band the erosion skipped, never into the
    # band's shadow above the cup.
    edge = headphones & ~ndimage.binary_erosion(headphones, iterations=3)
    keep = keep | (ndimage.binary_dilation(keep, iterations=3) & edge)
    # Soft where the paint turns from cup to pad, so the trace runs along
    # the middle of that turn rather than along its pixels.
    darkness = np.clip((CUP_LUMA - luma) / (CUP_LUMA - PAD_LUMA), 0, 1)
    soft = np.where(keep & ~ndimage.binary_erosion(keep, iterations=2), darkness, keep * 1.0)
    # Only the background nearer a pad than a cup, so nothing spills along
    # the cup's edge where the two meet.
    to_pad = ndimage.distance_transform_edt(~keep)
    to_cup = ndimage.distance_transform_edt(~(headphones & ~keep))
    beyond = ~headphones & (to_pad <= 1.5) & (to_pad < to_cup)
    return np.where(beyond, 1.0, soft)


def smooth(mask, alpha):
    """A mask at SCALE times the size: the painting's own soft edge where the
    mask meets the background (the mask is grown first so its edge is the
    painting's, not a cut through it), blurred, then cut at half."""
    grown = ndimage.binary_dilation(mask, iterations=3)
    soft = Image.fromarray((grown * alpha).astype(np.float32), "F")
    w, h = soft.size
    big = np.asarray(soft.resize((w * SCALE, h * SCALE), Image.BICUBIC))
    return ndimage.gaussian_filter(big, BLUR) > 127.5


def smooth_pads(pad):
    """The pads at SCALE times the size, from their soft darkness. Where cup
    turns to pad the paint is noisier than any edge, so it is blurred more."""
    soft = Image.fromarray((pad * 255).astype(np.float32), "F")
    w, h = soft.size
    big = np.asarray(soft.resize((w * SCALE, h * SCALE), Image.BICUBIC))
    return ndimage.gaussian_filter(big, PAD_BLUR) > 127.5


def trace(mask):
    """Potrace's curves for a mask, in painted pixels."""
    h, w = mask.shape
    with tempfile.TemporaryDirectory() as tmp:
        pbm = Path(tmp) / "mask.pbm"
        Image.fromarray(np.where(mask, 0, 255).astype(np.uint8)).convert("1").save(pbm)
        out = Path(tmp) / "mask.svg"
        subprocess.run(["potrace", str(pbm), "-s", "--flat", "-a", "1.334", "-O", str(OPT_TOLERANCE), "-t", "64", "-o", str(out)],
                       check=True)
        text = out.read_text()
    d = " ".join(re.findall(r'\sd="([^"]+)"', text))
    # Potrace writes tenths of a pixel with y up from the bottom.
    return bake(d, lambda x, y: (x / 10 / SCALE, (h - y / 10) / SCALE), lambda x, y: (x / 10 / SCALE, -y / 10 / SCALE))


def bake(d, point, delta):
    """Applies potrace's transform to its path, so the SVG needs none."""
    tokens = re.findall(r"[MmLlCcZz]|-?\d+(?:\.\d+)?", d)
    out, i, command = [], 0, None
    while i < len(tokens):
        t = tokens[i]
        if t.isalpha():
            command = t
            i += 1
            out.append(command)
            if command in "Zz":
                continue
        step = {"M": 2, "m": 2, "L": 2, "l": 2, "C": 6, "c": 6}[command]
        values = [float(v) for v in tokens[i:i + step]]
        i += step
        move = point if command.isupper() else delta
        for j in range(0, step, 2):
            x, y = move(values[j], values[j + 1])
            out.append(f"{x:.2f},{y:.2f}")
        # A moveto's following pairs are linetos.
        if command == "M":
            command = "L"
        elif command == "m":
            command = "l"
    return re.sub(r"\.00\b", "", " ".join(out)).replace(" z", "z")


def axis(mask):
    """The vertical line the mask mirrors best about, in painted pixels from
    the left edge, to a quarter pixel."""
    width = mask.shape[1]
    columns = np.arange(width)

    def overlap(line):
        source = np.round(2 * line - 1 - columns).astype(int)
        inside = (source >= 0) & (source < width)
        mirrored = np.zeros_like(mask)
        mirrored[:, inside] = mask[:, source[inside]]
        return (mask & mirrored).sum() / (mask | mirrored).sum()

    middle = width / 2
    return max(np.arange(middle - 12, middle + 12, 0.25), key=overlap)


def mirrored(big, line):
    """A mask at SCALE times the size with its left side replaced by its
    right side mirrored about `line` (in painted pixels)."""
    width = big.shape[1]
    columns = np.arange(width)
    centre = line * SCALE
    source = np.round(2 * centre - 1 - columns).astype(int)
    left = (columns < centre) & (source >= 0) & (source < width)
    out = big.copy()
    out[:, columns < centre] = False
    out[:, left] = big[:, source[left]]
    return out


def matched_eyes(big, line):
    """The body at SCALE times the size with the left eye replaced by the
    right one mirrored, so the two match the way the headphones do."""
    holes = ndimage.binary_fill_holes(big) & ~big
    labels, count = ndimage.label(holes)
    centre = line * SCALE
    right = np.zeros_like(big)
    out = big.copy()
    for i in range(1, count + 1):
        hole = labels == i
        if np.nonzero(hole)[1].mean() >= centre:
            right |= hole
        else:
            out |= hole
    return out & ~(mirrored(right, line) & ~right)


def gradient(pixels, mask):
    """The straight top-to-bottom gradient that best fits a part's paint: its
    colour at the part's top and bottom, read away from the fringe."""
    inside = ndimage.binary_erosion(mask, iterations=3)
    ys, _ = np.nonzero(inside)
    rgb = pixels[inside][:, :3]
    top, bottom = ys.min(), ys.max()
    stops = []
    for y in (top, bottom):
        colour = [np.polyval(np.polyfit(ys, rgb[:, c], 1), y) for c in range(3)]
        stops.append("#" + "".join(f"{int(np.clip(round(v), 0, 255)):02X}" for v in colour))
    return top, bottom, stops


def main():
    image = Image.open(OCTOPUS).convert("RGBA")
    pixels = np.asarray(image).astype(float)
    alpha = pixels[..., 3]
    body, headphones = parts(pixels)
    pad = pads(pixels, headphones)
    cups = headphones & ~ndimage.binary_dilation(pad > 0.5, iterations=2)

    # The head's centre line: the body above the tentacles.
    rows = np.nonzero(body.any(axis=1))[0]
    head = body & (np.arange(body.shape[0])[:, None] < rows.min() + (rows.max() - rows.min()) * 0.45)
    line = axis(head)

    shapes = [
        ("body", trace(matched_eyes(smooth(body, alpha), line)), gradient(pixels, body)),
        ("headphones", trace(mirrored(smooth(headphones, alpha), line)), gradient(pixels, cups)),
        # The pads reach a little past the headphones' edge, so the cup's own
        # soft edge is under them and no light seam shows there.
        ("pads", trace(mirrored(smooth_pads(pad), line)),
         gradient(pixels, (pad > 0.5) & headphones)),
    ]
    defs, paths = [], []
    for name, d, (top, bottom, (start, stop)) in shapes:
        defs.append(f'    <linearGradient id="{name}-paint" gradientUnits="userSpaceOnUse" x1="0" y1="{top}" x2="0" y2="{bottom}">\n'
                    f'      <stop offset="0" stop-color="{start}"/>\n      <stop offset="1" stop-color="{stop}"/>\n'
                    "    </linearGradient>")
        paths.append(f'  <path id="{name}" fill="url(#{name}-paint)" d="{d}"/>')
    SVG.write_text(
        "<!-- Made by tools/appicon/trace_octopus.py from octopus.png; change that, not this. -->\n"
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{image.width}" height="{image.height}" '
        f'viewBox="0 0 {image.width} {image.height}">\n  <defs>\n' + "\n".join(defs) + "\n  </defs>\n"
        + "\n".join(paths) + "\n</svg>\n",
        encoding="utf-8",
    )
    print("Traced", OCTOPUS.name, "into", SVG.name, "mirrored about x =", line,
          {name: len(d) for name, d, _ in shapes})


if __name__ == "__main__":
    main()
