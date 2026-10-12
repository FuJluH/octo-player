"""Octo's icons and logo, every one drawn from one vector: octopus.svg, the
logo's octopus traced by trace_octopus.py (from octopus.png, the painted
octopus). Nothing here scales a picture, so no size shows pixels.

  python make_app_icon.py              writes the phone's adaptive icon layers
                                       and launch screen's octopus as vector
                                       drawables, the desktop window's opening
                                       octopus, the square store icon,
                                       F-Droid's icon, and the square the
                                       desktop icons are cut from
  python make_app_icon.py ios          writes the iPhone app's icon: the Icon
                                       Composer file Apple's Liquid Glass
                                       draws from, ios/AppIcon.icon, and a
                                       flat ios/Resources/AppIcon.png; and
                                       the octopus's paths for the app to draw
  python make_app_icon.py logo FILE    writes the logo: the octopus alone on a
                                       clear 1024 square, where the painted
                                       logo had it (the server keeps it at
                                       octo/Assets/octo_logo.png)
  python make_app_icon.py take LOGO    copies the painted octopus out of a
                                       logo PNG into octopus.png; run
                                       trace_octopus.py and the lines above after
  python make_app_icon.py preview DIR  writes the icons, plus previews in DIR

Only the tile behind the octopus is drawn here, and the same tile is written
as the adaptive icon's vector background. The launch screen shows the
octopus alone, over the app's own dark background.

After a change, run ./gradlew :desktop:makeIcons to remake desktop/icons.

Needs numpy, Pillow and rsvg-convert. Run with PYTHONUTF8=1.
"""
import functools
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
OCTOPUS = HERE / "octopus.png"
OCTOPUS_SVG = HERE / "octopus.svg"
RES = ROOT / "app/src/main/res"
STORE = ROOT / "app/src/main/ic_launcher-playstore.png"
FDROID = ROOT / "fdroid/octo.png"
# The square the desktop's PNG, ICO and ICNS are cut from: 1024, the size
# of the largest of them (macOS's 512 at 2x).
DESKTOP_SQUARE = ROOT / "desktop/icons/octo-square.png"
# The iPhone app's icon: an Icon Composer file whose layers Apple's Liquid
# Glass lights (Xcode's actool turns it into the app's Assets.car), and a
# flat 1024 square for builds without that. iOS rounds the corners of both.
IOS_ICON_FILE = ROOT / "ios/AppIcon.icon"
IOS_FLAT = ROOT / "ios/Resources/AppIcon.png"
IOS_ART = ROOT / "ios/Sources/Octo/Design/OctopusArt+Paths.swift"
IOS_SIZE = 1024

# The octopus's parts, back to front.
PARTS = ["body", "headphones", "pads"]

# The tile: a lavender, lighter at the top left, with a soft white light
# behind the octopus. A dark tile hid the octopus, and a lighter indigo
# one blends into its violet; on lavender it stands out as painted.
SKY_TOP = "#C9BEFF"
SKY_BOTTOM = "#9C8AF0"
GLOW = "#FFFFFF"
GLOW_ALPHA = 0.45
GLOW_RADIUS = 0.50   # of the side, from the centre

# How far the octopus reaches from the tile's centre, as a share of the side.
# Launchers always show the middle 66 dp circle of the adaptive icon's 108.
ADAPTIVE_REACH = 29 / 108
SQUARE_REACH = 0.44
# Android 12's launch screen draws an icon with no background in a 288 dp
# square and shows only the circle 192 dp across in its middle.
SPLASH_DP = 288
SPLASH_REACH = 0.29
# The desktop window opens on the octopus alone, FrameSize.OpeningMark
# (112 dp) across, drawn sharp up to 300% display scaling.
DESKTOP_OPENING = ROOT / "desktop/src/main/resources/octo-opening.png"
OPENING_PX = 336
OPENING_REACH = 0.48

# The logo: a clear 1024 square with the octopus at its painted size, where
# the painted logo had it (its box's top left corner).
LOGO_SIZE = 1024
LOGO_AT = (242, 210)


def take(logo_path):
    """The octopus, cropped out of the logo. Alpha under 4 of 255 is stray
    specks and the trace of the glow, so it is cleared."""
    image = Image.open(logo_path).convert("RGBA")
    pixels = np.asarray(image).copy()
    pixels[pixels[..., 3] < 4] = 0
    ys, xs = np.nonzero(pixels[..., 3])
    pad = 2
    crop = pixels[ys.min() - pad:ys.max() + pad + 1, xs.min() - pad:xs.max() + pad + 1]
    Image.fromarray(crop).save(OCTOPUS, optimize=True)
    print("Took the octopus from", logo_path, "into", OCTOPUS.relative_to(ROOT), f"({crop.shape[1]}x{crop.shape[0]})")


@functools.cache
def octopus():
    """octopus.svg's parts: each one's path data and its gradient (the line
    it runs along and its two colours), and the box they are drawn in."""
    text = OCTOPUS_SVG.read_text(encoding="utf-8")
    width, height = (float(v) for v in re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', text).groups())
    parts = {}
    for name in PARTS:
        d = re.search(rf'<path id="{name}"[^>]* d="([^"]+)"', text).group(1)
        paint = re.search(rf'<linearGradient id="{name}-paint"(.*?)</linearGradient>', text, re.S).group(1)
        line = [float(re.search(rf'{k}="([\d.-]+)"', paint).group(1)) for k in ("x1", "y1", "x2", "y2")]
        colours = re.findall(r'stop-color="(#[0-9A-Fa-f]{6})"', paint)
        parts[name] = (d, line, colours)
    return parts, width, height


def svg(size, share, names=PARTS, fill=None, at=None, scale=None):
    """The named parts on a clear square `size` wide: centred with the ink
    reaching `share` of the side, or at `at` and `scale` when given. With
    `fill`, every part is that one colour."""
    parts, width, height = octopus()
    if scale is None:
        scale = size * share / reach()
    x, y = at if at is not None else ((size - width * scale) / 2, (size - height * scale) / 2)
    defs, paths = [], []
    for name in names:
        d, (x1, y1, x2, y2), (start, stop) = parts[name]
        if fill is None:
            defs.append(f'    <linearGradient id="{name}-paint" gradientUnits="userSpaceOnUse" '
                        f'x1="{x1:g}" y1="{y1:g}" x2="{x2:g}" y2="{y2:g}">\n'
                        f'      <stop offset="0" stop-color="{start}"/>\n      <stop offset="1" stop-color="{stop}"/>\n'
                        "    </linearGradient>")
        paths.append(f'    <path fill="{fill or f"url(#{name}-paint)"}" d="{d}"/>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">\n'
            + ("  <defs>\n" + "\n".join(defs) + "\n  </defs>\n" if defs else "")
            + f'  <g transform="translate({x:.3f} {y:.3f}) scale({scale:.6f})">\n' + "\n".join(paths) + "\n  </g>\n</svg>\n")


def render(svg_text, size):
    """An SVG drawn at `size` pixels square."""
    with tempfile.TemporaryDirectory() as tmp:
        source, png = Path(tmp) / "art.svg", Path(tmp) / "art.png"
        source.write_text(svg_text, encoding="utf-8")
        subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(source), "-o", str(png)], check=True)
        return Image.open(png).convert("RGBA")


@functools.cache
def reach():
    """How far the octopus's ink goes from its box's centre, in the SVG's
    units, measured on a drawing four times its size."""
    _, width, height = octopus()
    side = int(max(width, height) * 4)
    alpha = np.asarray(render(svg(side, 0, at=(0, 0), scale=4), side))[..., 3]
    ys, xs = np.nonzero(alpha > 127)
    cx, cy = width * 2, height * 2
    return float(np.sqrt((xs + 0.5 - cx) ** 2 + (ys + 0.5 - cy) ** 2).max()) / 4


def placed(size, share):
    """The octopus centred on a clear square `size` wide, its ink reaching
    `share` of the side from the centre."""
    return render(svg(size, share), size)


def rgb(hex_colour):
    h = hex_colour.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float)


def tile(size):
    """The tile, as the vector background draws it: a diagonal gradient,
    then the glow over it."""
    ys, xs = np.mgrid[0:size, 0:size].astype(float) + 0.5
    t = np.clip((xs + ys) / (2 * size), 0, 1)[..., None]
    sky = rgb(SKY_TOP) * (1 - t) + rgb(SKY_BOTTOM) * t
    d = np.sqrt((xs - size / 2) ** 2 + (ys - size / 2) ** 2) / (size * GLOW_RADIUS)
    glow = (GLOW_ALPHA * np.clip(1 - d, 0, 1))[..., None]
    out = sky * (1 - glow) + rgb(GLOW) * glow
    alpha = np.full((size, size, 1), 255.0)
    return Image.fromarray(np.concatenate([out, alpha], -1).round().astype(np.uint8), "RGBA")


def square(size):
    out = tile(size)
    out.alpha_composite(placed(size, SQUARE_REACH))
    return out


def argb(hex_colour, alpha=1.0):
    return f"#{round(alpha * 255):02X}{hex_colour.lstrip('#').upper()}"


VECTOR_HEAD = ('<?xml version="1.0" encoding="utf-8"?>\n'
               "<!-- Made by tools/appicon/make_app_icon.py; change that, not this. -->\n"
               '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
               '    xmlns:aapt="http://schemas.android.com/aapt"\n')


def background_vector():
    def layer(gradient):
        return ('    <path\n        android:pathData="M0,0H108V108H0Z">\n'
                '        <aapt:attr name="android:fillColor">\n'
                f"            <gradient {gradient} />\n"
                "        </aapt:attr>\n    </path>\n")

    sky = ('android:type="linear" android:startX="0" android:startY="0" android:endX="108" android:endY="108" '
           f'android:startColor="{argb(SKY_TOP)}" android:endColor="{argb(SKY_BOTTOM)}"')
    glow = (f'android:type="radial" android:centerX="54" android:centerY="54" '
            f'android:gradientRadius="{108 * GLOW_RADIUS:g}" '
            f'android:startColor="{argb(GLOW, GLOW_ALPHA)}" android:endColor="{argb(GLOW, 0)}"')
    return (VECTOR_HEAD + '    android:width="108dp"\n    android:height="108dp"\n'
            '    android:viewportWidth="108"\n    android:viewportHeight="108">\n'
            f"{layer(sky)}{layer(glow)}</vector>\n")


def octopus_vector(dp, share, fill=None):
    """The octopus as an Android vector drawable `dp` square, centred with
    its ink reaching `share` of the side. With `fill`, one colour."""
    parts, width, height = octopus()
    scale = dp * share / reach()
    x, y = (dp - width * scale) / 2, (dp - height * scale) / 2
    paths = []
    for name in PARTS:
        d, (x1, y1, x2, y2), (start, stop) = parts[name]
        if fill:
            paths.append(f'        <path\n            android:fillColor="{fill}"\n            android:pathData="{d}" />\n')
        else:
            paths.append(f'        <path\n            android:pathData="{d}">\n'
                         '            <aapt:attr name="android:fillColor">\n'
                         f'                <gradient android:type="linear" android:startX="{x1:g}" android:startY="{y1:g}" '
                         f'android:endX="{x2:g}" android:endY="{y2:g}" '
                         f'android:startColor="{argb(start)}" android:endColor="{argb(stop)}" />\n'
                         "            </aapt:attr>\n        </path>\n")
    return (VECTOR_HEAD + f'    android:width="{dp}dp"\n    android:height="{dp}dp"\n'
            f'    android:viewportWidth="{dp}"\n    android:viewportHeight="{dp}">\n'
            f'    <group\n        android:translateX="{x:.4f}"\n        android:translateY="{y:.4f}"\n'
            f'        android:scaleX="{scale:.6f}"\n        android:scaleY="{scale:.6f}">\n'
            + "".join(paths) + "    </group>\n</vector>\n")


def write():
    drawables = RES / "drawable"
    (drawables / "ic_launcher_background.xml").write_text(background_vector(), encoding="utf-8")
    (drawables / "ic_launcher_foreground.xml").write_text(octopus_vector(108, ADAPTIVE_REACH), encoding="utf-8")
    # Themed icons: the silhouette alone; the launcher tints it.
    (drawables / "ic_launcher_monochrome.xml").write_text(
        octopus_vector(108, ADAPTIVE_REACH, fill="#FFFFFFFF"), encoding="utf-8")
    (drawables / "splash_octopus.xml").write_text(octopus_vector(SPLASH_DP, SPLASH_REACH), encoding="utf-8")
    placed(OPENING_PX, OPENING_REACH).save(DESKTOP_OPENING, optimize=True)
    square(512).convert("RGB").save(STORE, optimize=True)
    square(512).convert("RGB").save(FDROID, optimize=True)
    square(1024).convert("RGB").save(DESKTOP_SQUARE, optimize=True)
    print("Wrote the adaptive icon and launch screen drawables, the desktop's opening octopus,",
          ", ".join(str(p.relative_to(ROOT)) for p in (STORE, FDROID, DESKTOP_SQUARE)))


def colour(hex_colour):
    r, g, b = rgb(hex_colour) / 255
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def ios():
    """The iPhone icon. Two glass groups, so the system lights and lifts them
    apart: the headphones in front, the octopus behind them. The tile is Icon
    Composer's own gradient fill, lighter at the top left; the glass lighting
    takes the place of the white glow the flat icons draw."""
    assets = IOS_ICON_FILE / "Assets"
    assets.mkdir(parents=True, exist_ok=True)
    (assets / "headphones.svg").write_text(svg(IOS_SIZE, SQUARE_REACH, ["headphones", "pads"]), encoding="utf-8")
    (assets / "octopus.svg").write_text(svg(IOS_SIZE, SQUARE_REACH, ["body"]), encoding="utf-8")

    def group(name):
        return {
            "layers": [{"glass": True, "image-name": f"{name}.svg", "name": name}],
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "specular": True,
            "translucency": {"enabled": True, "value": 0.3},
        }

    icon = {
        "fill": {
            "linear-gradient": [colour(SKY_TOP), colour(SKY_BOTTOM)],
            "orientation": {"start": {"x": 0, "y": 0}, "stop": {"x": 1, "y": 1}},
        },
        "groups": [group("headphones"), group("octopus")],
        "supported-platforms": {"squares": "shared"},
    }
    (IOS_ICON_FILE / "icon.json").write_text(json.dumps(icon, indent=2) + "\n", encoding="utf-8")
    IOS_FLAT.parent.mkdir(parents=True, exist_ok=True)
    square(IOS_SIZE).convert("RGB").save(IOS_FLAT, optimize=True)

    # The octopus inside the app, drawn by SwiftUI from the same paths.
    parts, width, height = octopus()
    lines = [f'        Part(\n            top: 0x{start[1:].upper()}, bottom: 0x{stop[1:].upper()}, from: {y1:g}, to: {y2:g},\n'
             f'            path: "{d}"\n        ),'
             for d, (_, y1, _, y2), (start, stop) in (parts[name] for name in PARTS)]
    IOS_ART.write_text(
        "// Made by tools/appicon/make_app_icon.py from octopus.svg; change that, not this.\n\n"
        "import CoreGraphics\n\n"
        "extension OctopusArt {\n"
        f"    static let size = CGSize(width: {width:g}, height: {height:g})\n\n"
        "    /// Back to front: the body, the headphones, the ear pads.\n"
        "    static let parts: [Part] = [\n" + "\n".join(lines) + "\n    ]\n}\n",
        encoding="utf-8",
    )
    print("Wrote", IOS_ICON_FILE.relative_to(ROOT), IOS_FLAT.relative_to(ROOT), "and", IOS_ART.relative_to(ROOT))


def logo(out):
    """The logo: the octopus at its own size on a clear square."""
    render(svg(LOGO_SIZE, 0, at=LOGO_AT, scale=1), LOGO_SIZE).save(out, optimize=True)
    print("Wrote the logo to", out)


def preview(out):
    out.mkdir(parents=True, exist_ok=True)
    square(1024).save(out / "square.png")
    adaptive = tile(432)
    adaptive.alpha_composite(placed(432, ADAPTIVE_REACH))
    adaptive.save(out / "adaptive.png")
    print("Previews in", out)


def main():
    args = sys.argv[1:]
    if args[:1] == ["take"]:
        take(args[1])
        return
    if args[:1] == ["ios"]:
        ios()
        return
    if args[:1] == ["logo"]:
        logo(Path(args[1]))
        return
    write()
    if args[:1] == ["preview"]:
        preview(Path(args[1]))


if __name__ == "__main__":
    main()
