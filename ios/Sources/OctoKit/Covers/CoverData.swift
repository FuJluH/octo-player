// The covers' design as the other apps and the server read it: cover-design.json, and the painted
// backgrounds' library, backgrounds/backgrounds.json.

let coverDesignJSON = #"""
{
  "version": 1,
  "about": "Octo's designed playlist covers, read by the phone, the desktop and the server so all three draw the same thing. Positions and sizes are shares of the cover's side (0 to 1, origin top left, y down) unless named Px. Colours are sRGB hex. Words are always white.",
  "fonts": {
    "family": "Inter 4.1 (rsms/inter v4.1, OFL-1.1), static Display cut",
    "title": "InterDisplay-SemiBold.ttf",
    "line": "InterDisplay-Light.ttf",
    "footer": "InterDisplay-Medium.ttf"
  },
  "layout": {
    "margin": 0.08,
    "contrast": 4.5,
    "tinyBelowPx": 72,
    "tiny": "Below tinyBelowPx a cover is its artwork only: no words, no letter, no veil. tinyMargin and tinySize are kept for older readers and are not used.",
    "tinyMargin": 0.1,
    "tinySize": 0.56,
    "title": {
      "top": 0.1,
      "weight": 600,
      "size": 0.16,
      "oneLineDownTo": 0.09,
      "oneLineMinPx": 12,
      "wrapSize": 0.115,
      "wrapMinPx": 13,
      "minSize": 0.07,
      "minPx": 9,
      "maxLines": 3,
      "lineHeight": 1.08,
      "tracking": 0
    },
    "line": {
      "weight": 300,
      "shareOfTitle": 0.83,
      "minPx": 9,
      "lineHeight": 1.15,
      "tracking": 0,
      "showFromPx": 120
    },
    "footer": {
      "weight": 500,
      "size": 0.06,
      "minPx": 9,
      "bottom": 0.08,
      "opacity": 0.85,
      "lineHeight": 1.2,
      "tracking": 0,
      "showFromPx": 160
    }
  },
  "background": {
    "about": "Which painted background (backgrounds/backgrounds.json) a list gets, always the same for the same list and music. With no covers, only grey ones, or music whose colour has chroma below lowChromaAsGrey: backgrounds[(coverPick(id) >>> 7) mod count], coverPick being FNV-1a 64 over the id's UTF-8 (offset 0xcbf29ce484222325, prime 0x100000001b3), then MurmurHash3's fmix64 (k ^= k >>> 33; k *= 0xff51afd7ed558ccd; k ^= k >>> 33; k *= 0xc4ceb9fe1a85ec53; k ^= k >>> 33), then >>> 1. (FNV-1a alone barely moves those bits when ids differ only in their last letter, as numbered ids do.) With music: the music's colour is the strongest colour among its first covers' swatches (score sqrt(share / number of covers) x (0.3 + 5 C), counting only C >= 0.035 and 0.15 <= L <= 0.97), rounded (hue to the degree, C and L to 0.001). A background's distance from it is the least, over its hues i (strongest first), of hueDistance / 180 + hueStep x i + (greyPenalty when that hue's C < greyBelow) + chromaWeight x |C - music C|, plus lightnessWeight x |meanLightness - music L|. The nearest few (ties in file order) are the candidates, and the list takes candidates[(coverPick(id) >>> 7) mod nearest]. Every list then turns its background by orientation: v = (coverPick(id) >>> shift) mod count, the background (at the cover's size) rotated (v mod 4) x 90 degrees clockwise, then mirrored left-right if v >= 4, before the veil (so the veil still guarantees contrast; backgrounds.json's textArea figures describe the file unturned and are only for reporting). Sizes other than the file's: halved, each pixel (a + b + c + d + 2) / 4, while that leaves at least the size wanted (so 600 is exactly the reference's), then each output pixel the mean of the area it covers. Below tinyBelowPx the background alone is the cover.",
    "nearest": 8,
    "lowChromaAsGrey": 0.07,
    "hueStep": 0.08,
    "greyBelow": 0.04,
    "greyPenalty": 0.5,
    "chromaWeight": 1.5,
    "lightnessWeight": 0.8,
    "orientation": { "shift": 11, "count": 8, "rule": "rotate (v mod 4) x 90 clockwise, then mirror left-right if v >= 4" }
  },
  "veil": {
    "about": "Under the words the background is darkened only where it is too bright for white words, and only by lightness: hue and chroma stay, so a bright cover deepens instead of greying. tools/cover-art/reference.py is the reference; its golden/ covers are what ports are checked against.",
    "space": "Per pixel, from 8-bit sRGB: linear sRGB (the sRGB curve), luminance Y = 0.2126 R + 0.7152 G + 0.0722 B, and OKLab (Ottosson 2020) with OKLCH hue h in degrees and chroma C = hypot(a, b).",
    "regions": "Each block of words has a box, in pixels, from its corner of the cover to the words' far edges plus pad (a share of the side): the title block (title and second line together) from the top-left corner to the widest line's right edge and the block's bottom; the footer from the bottom-left corner up to the footer's top and across to its right edge. For right-to-left words the boxes start from the right-hand corners instead. A pixel's weight w is 1 inside a box and 1 - smoothstep(0, 1, d) outside, where d = hypot(dx / (falloff[0] x side), dy / (falloff[1] x side)) and dx, dy are its distances from the box across and down, measured at pixel centres.",
    "rule": "limit = min(max(aim, Y x (1 - maxDrop)), least), where aim and least are the luminances at which white words reach aimContrast and minContrast (1.05 / ratio - 0.05), each lowered by margin. Each region keeps the share 1 - w x (1 - min(1, limit / Y)) of the pixel's luminance, and the shares of all regions multiply: wanted = Y x product, so the veil stays smooth where regions meet. The footer's ink is white at the footer's opacity, laid over the background in sRGB, so its limit is the grey luminance at which that ink reaches contrast (0.141 before margin at 85%).",
    "lightness": "The new pixel keeps its OKLab a and b (after the yellow turn) and takes lightness L x cbrt(wanted / Y), then refine times: settle the colour (OKLab to linear sRGB, gamut mapped as below) and scale L by cbrt(wanted / its luminance).",
    "gamut": "Out-of-gamut colours: chroma is reduced toward grey at the same lightness (halving search, 12 steps, finding the largest in-gamut share) and the result blended with a plain per-channel clip by smoothstep(0, 0.05, how far the colour lay outside [0, 1]), so colours only just outside are clipped and never jump.",
    "yellowRule": "Darkened yellows turn toward amber so they read golden, never olive: with drop = 1 - wanted / Y, the hue moves toward a target by the share clamp(turnPerDrop x drop, 0, 1) x wy (h + (target - h) x share, no wrapping). The target is chosen once per cover: the mean hue of the whole cover weighted by wy x C x reach (reach = the largest region weight at the pixel); at or under split the target is towards[0] (amber), above it towards[1] (green), so a yellow cover deepens to gold and a lime one to deep green, never olive, with no seam inside a cover, and chroma grows by chromaLift x drop x wy, where wy = smoothstep(hues[0], hues[1], h) x (1 - smoothstep(hues[2], hues[3], h)) x clamp(C / chromaFrom, 0, 1). Greens past hues[3] keep their hue.",
    "margin": 0.03,
    "refine": 3,
    "title": { "pad": 0.04, "falloff": [0.5, 0.45], "aimContrast": 4.5, "minContrast": 3.0, "maxDrop": 0.6 },
    "footer": { "pad": 0.05, "falloff": [0.6, 0.4], "contrast": 4.5 },
    "yellow": { "hues": [55, 72, 128, 150], "split": 112, "towards": [66, 148], "turnPerDrop": 2.0, "chromaFrom": 0.06, "chromaLift": 0.5 }
  },
  "glyphs": {
    "about": "Lists Octo marks for what they are (Liked Songs, Review, Duplicates) get a painted background with one white glyph in the middle and no words. The glyph sits in a square `box` of the cover's side, centred; every point and width below is a share of that box (origin top left, y down). Shapes are filled; a stroke is centred on its outline. The glyph is white at full opacity over a soft shadow: the same shape in black at shadow.alpha, once at each of shadow.offsets (shares of the side, straight down). The veil darkens under the box grown by veilGrow (about its centre) with the title's numbers.",
    "box": 0.36,
    "veilGrow": 0.15,
    "shadow": { "alpha": 0.1, "offsets": [0.004, 0.006, 0.008] },
    "heart": { "from": [0.5, 0.88], "lobe": [[0.06, 0.55], [0.06, 0.18], [0.5, 0.3]], "rule": "a cubic from `from` through lobe's two control points to its end, then the same mirrored left to right back to `from`" },
    "magnifier": { "center": [0.42, 0.42], "radius": 0.3, "stroke": 0.09, "handle": [[0.64, 0.64], [0.88, 0.88]], "handleWidth": 0.11, "rule": "a ring of `radius` stroked `stroke` wide, and a line `handleWidth` wide with round ends" },
    "copies": { "side": 0.56, "radius": 0.08, "back": [0.3, 0.1], "front": [0.12, 0.3], "stroke": 0.09, "gap": 0.06, "rule": "two rounded squares `side` wide with corners of `radius`, placed by their top left corners: the back one stroked `stroke` wide, the front one filled; the back's stroke is cut away within `gap` of the front square" }
  }
}

"""#

let coverBackgroundsJSON = #"""
{
  "version": 1,
  "about": "Octo's cover backgrounds, made by tools/cover-art (python cover_art.py finals). Each is 1200x1200 WebP. Hues are OKLCH (l 0..1, c, h degrees), strongest first. textArea measures the box (shares of the side: x0, y0, x1, y1) where the title sits: darkness is 1 minus its mean OKLab lightness; whiteContrastP50 and P95 are white text against the box's median and 95th percentile luminance; veilFor3 and veilFor4_5 are the black overlay opacities that bring the P95 contrast to 3:1 (large text) and 4.5:1.",
  "size": 1200,
  "backgrounds": [
    {
      "file": "periwinkle.webp",
      "name": "Periwinkle",
      "family": "liquid",
      "palette": "bluebell",
      "seed": 1404,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.599,
          "c": 0.212,
          "h": 277.5
        }
      ],
      "meanLightness": 0.601,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.571,
        "darkness": 0.429,
        "p50Luminance": 0.1473,
        "p95Luminance": 0.3492,
        "whiteContrastP50": 5.32,
        "whiteContrastP95": 2.63,
        "veilFor3": 0.141,
        "veilFor4_5": 0.475
      }
    },
    {
      "file": "northern-lights.webp",
      "name": "Northern Lights",
      "family": "liquid",
      "palette": "borealis",
      "seed": 1031,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.811,
          "c": 0.178,
          "h": 142.5
        },
        {
          "l": 0.251,
          "c": 0.045,
          "h": 232.5
        }
      ],
      "meanLightness": 0.457,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.31,
        "darkness": 0.69,
        "p50Luminance": 0.0153,
        "p95Luminance": 0.3267,
        "whiteContrastP50": 16.07,
        "whiteContrastP95": 2.79,
        "veilFor3": 0.082,
        "veilFor4_5": 0.439
      }
    },
    {
      "file": "bubblegum.webp",
      "name": "Bubblegum",
      "family": "liquid",
      "palette": "candy",
      "seed": 1008,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.626,
          "c": 0.198,
          "h": 272.5
        }
      ],
      "meanLightness": 0.636,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.659,
        "darkness": 0.341,
        "p50Luminance": 0.2637,
        "p95Luminance": 0.4258,
        "whiteContrastP50": 3.35,
        "whiteContrastP95": 2.21,
        "veilFor3": 0.295,
        "veilFor4_5": 0.569
      }
    },
    {
      "file": "citrus.webp",
      "name": "Citrus",
      "family": "liquid",
      "palette": "citrus",
      "seed": 1390,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.692,
          "c": 0.197,
          "h": 37.5
        }
      ],
      "meanLightness": 0.732,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.743,
        "darkness": 0.257,
        "p50Luminance": 0.3803,
        "p95Luminance": 0.641,
        "whiteContrastP50": 2.44,
        "whiteContrastP95": 1.52,
        "veilFor3": 0.532,
        "veilFor4_5": 0.714
      }
    },
    {
      "file": "cobalt.webp",
      "name": "Cobalt",
      "family": "liquid",
      "palette": "cobalt",
      "seed": 1223,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.573,
          "c": 0.199,
          "h": 262.5
        }
      ],
      "meanLightness": 0.573,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.587,
        "darkness": 0.413,
        "p50Luminance": 0.2736,
        "p95Luminance": 0.3726,
        "whiteContrastP50": 3.24,
        "whiteContrastP95": 2.48,
        "veilFor3": 0.195,
        "veilFor4_5": 0.508
      }
    },
    {
      "file": "coral.webp",
      "name": "Coral",
      "family": "liquid",
      "palette": "coral",
      "seed": 1081,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.751,
          "c": 0.145,
          "h": 32.5
        }
      ],
      "meanLightness": 0.75,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.772,
        "darkness": 0.228,
        "p50Luminance": 0.4383,
        "p95Luminance": 0.5429,
        "whiteContrastP50": 2.15,
        "whiteContrastP95": 1.77,
        "veilFor3": 0.447,
        "veilFor4_5": 0.662
      }
    },
    {
      "file": "tangerine.webp",
      "name": "Tangerine",
      "family": "liquid",
      "palette": "tangerine",
      "seed": 5008,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.819,
          "c": 0.139,
          "h": 67.5
        }
      ],
      "meanLightness": 0.811,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.791,
        "darkness": 0.209,
        "p50Luminance": 0.4802,
        "p95Luminance": 0.6356,
        "whiteContrastP50": 1.98,
        "whiteContrastP95": 1.53,
        "veilFor3": 0.528,
        "veilFor4_5": 0.712
      }
    },
    {
      "file": "dusk.webp",
      "name": "Dusk",
      "family": "liquid",
      "palette": "dusk",
      "seed": 1242,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.555,
          "c": 0.13,
          "h": 357.5
        },
        {
          "l": 0.348,
          "c": 0.106,
          "h": 317.5
        }
      ],
      "meanLightness": 0.441,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.479,
        "darkness": 0.521,
        "p50Luminance": 0.1312,
        "p95Luminance": 0.2091,
        "whiteContrastP50": 5.79,
        "whiteContrastP95": 4.05,
        "veilFor3": 0.0,
        "veilFor4_5": 0.123
      }
    },
    {
      "file": "magma.webp",
      "name": "Magma",
      "family": "liquid",
      "palette": "ember",
      "seed": 1030,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.436,
          "c": 0.146,
          "h": 32.5
        }
      ],
      "meanLightness": 0.435,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.464,
        "darkness": 0.536,
        "p50Luminance": 0.0746,
        "p95Luminance": 0.2368,
        "whiteContrastP50": 8.42,
        "whiteContrastP95": 3.66,
        "veilFor3": 0.0,
        "veilFor4_5": 0.226
      }
    },
    {
      "file": "firewave.webp",
      "name": "Firewave",
      "family": "liquid",
      "palette": "firewave",
      "seed": 1044,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.548,
          "c": 0.261,
          "h": 302.5
        },
        {
          "l": 0.673,
          "c": 0.203,
          "h": 32.5
        }
      ],
      "meanLightness": 0.619,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.671,
        "darkness": 0.329,
        "p50Luminance": 0.2725,
        "p95Luminance": 0.3944,
        "whiteContrastP50": 3.26,
        "whiteContrastP95": 2.36,
        "veilFor3": 0.239,
        "veilFor4_5": 0.535
      }
    },
    {
      "file": "jungle.webp",
      "name": "Jungle",
      "family": "liquid",
      "palette": "jungle",
      "seed": 1119,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.757,
          "c": 0.183,
          "h": 137.5
        }
      ],
      "meanLightness": 0.732,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.667,
        "darkness": 0.333,
        "p50Luminance": 0.3313,
        "p95Luminance": 0.5542,
        "whiteContrastP50": 2.75,
        "whiteContrastP95": 1.74,
        "veilFor3": 0.459,
        "veilFor4_5": 0.669
      }
    },
    {
      "file": "lagoon.webp",
      "name": "Lagoon",
      "family": "liquid",
      "palette": "lagoon",
      "seed": 1041,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.576,
          "c": 0.208,
          "h": 257.5
        },
        {
          "l": 0.798,
          "c": 0.144,
          "h": 182.5
        }
      ],
      "meanLightness": 0.706,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.678,
        "darkness": 0.322,
        "p50Luminance": 0.3354,
        "p95Luminance": 0.594,
        "whiteContrastP50": 2.72,
        "whiteContrastP95": 1.63,
        "veilFor3": 0.495,
        "veilFor4_5": 0.691
      }
    },
    {
      "file": "lilac.webp",
      "name": "Lilac",
      "family": "liquid",
      "palette": "lilac",
      "seed": 1093,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.771,
          "c": 0.123,
          "h": 302.5
        }
      ],
      "meanLightness": 0.772,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.762,
        "darkness": 0.238,
        "p50Luminance": 0.4188,
        "p95Luminance": 0.4741,
        "whiteContrastP50": 2.24,
        "whiteContrastP95": 2.0,
        "veilFor3": 0.367,
        "veilFor4_5": 0.613
      }
    },
    {
      "file": "magenta.webp",
      "name": "Magenta",
      "family": "liquid",
      "palette": "magenta",
      "seed": 1047,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.663,
          "c": 0.258,
          "h": 342.5
        }
      ],
      "meanLightness": 0.658,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.675,
        "darkness": 0.325,
        "p50Luminance": 0.2507,
        "p95Luminance": 0.3984,
        "whiteContrastP50": 3.49,
        "whiteContrastP95": 2.34,
        "veilFor3": 0.247,
        "veilFor4_5": 0.54
      }
    },
    {
      "file": "night-swim.webp",
      "name": "Night Swim",
      "family": "liquid",
      "palette": "midnight",
      "seed": 1342,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.374,
          "c": 0.173,
          "h": 272.5
        }
      ],
      "meanLightness": 0.374,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.249,
        "darkness": 0.751,
        "p50Luminance": 0.0133,
        "p95Luminance": 0.0447,
        "whiteContrastP50": 16.58,
        "whiteContrastP95": 11.09,
        "veilFor3": 0.0,
        "veilFor4_5": 0.0
      }
    },
    {
      "file": "mint.webp",
      "name": "Mint",
      "family": "liquid",
      "palette": "mint",
      "seed": 1196,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.835,
          "c": 0.081,
          "h": 277.5
        },
        {
          "l": 0.888,
          "c": 0.081,
          "h": 182.5
        }
      ],
      "meanLightness": 0.852,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.84,
        "darkness": 0.16,
        "p50Luminance": 0.5844,
        "p95Luminance": 0.705,
        "whiteContrastP50": 1.66,
        "whiteContrastP95": 1.39,
        "veilFor3": 0.574,
        "veilFor4_5": 0.74
      }
    },
    {
      "file": "nightshade.webp",
      "name": "Nightshade",
      "family": "liquid",
      "palette": "nightshade",
      "seed": 1203,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.359,
          "c": 0.186,
          "h": 297.5
        }
      ],
      "meanLightness": 0.389,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.316,
        "darkness": 0.684,
        "p50Luminance": 0.0164,
        "p95Luminance": 0.1633,
        "whiteContrastP50": 15.82,
        "whiteContrastP95": 4.92,
        "veilFor3": 0.0,
        "veilFor4_5": 0.0
      }
    },
    {
      "file": "opal.webp",
      "name": "Opal",
      "family": "liquid",
      "palette": "opal",
      "seed": 1131,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.885,
          "c": 0.062,
          "h": 352.5
        },
        {
          "l": 0.856,
          "c": 0.076,
          "h": 307.5
        }
      ],
      "meanLightness": 0.881,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.869,
        "darkness": 0.131,
        "p50Luminance": 0.6506,
        "p95Luminance": 0.7258,
        "whiteContrastP50": 1.5,
        "whiteContrastP95": 1.35,
        "veilFor3": 0.587,
        "veilFor4_5": 0.747
      }
    },
    {
      "file": "peach.webp",
      "name": "Peach",
      "family": "liquid",
      "palette": "peach",
      "seed": 1127,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.838,
          "c": 0.084,
          "h": 32.5
        }
      ],
      "meanLightness": 0.848,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.864,
        "darkness": 0.136,
        "p50Luminance": 0.6387,
        "p95Luminance": 0.7332,
        "whiteContrastP50": 1.52,
        "whiteContrastP95": 1.34,
        "veilFor3": 0.591,
        "veilFor4_5": 0.75
      }
    },
    {
      "file": "tropic.webp",
      "name": "Tropic",
      "family": "liquid",
      "palette": "tropic",
      "seed": 1365,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.755,
          "c": 0.156,
          "h": 57.5
        },
        {
          "l": 0.831,
          "c": 0.139,
          "h": 112.5
        }
      ],
      "meanLightness": 0.769,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.726,
        "darkness": 0.274,
        "p50Luminance": 0.3653,
        "p95Luminance": 0.5673,
        "whiteContrastP50": 2.53,
        "whiteContrastP95": 1.7,
        "veilFor3": 0.471,
        "veilFor4_5": 0.677
      }
    },
    {
      "file": "neon-tide.webp",
      "name": "Neon Tide",
      "family": "liquid",
      "palette": "neon",
      "seed": 1191,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.573,
          "c": 0.24,
          "h": 287.5
        },
        {
          "l": 0.824,
          "c": 0.142,
          "h": 192.5
        }
      ],
      "meanLightness": 0.649,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.734,
        "darkness": 0.266,
        "p50Luminance": 0.4757,
        "p95Luminance": 0.674,
        "whiteContrastP50": 2.0,
        "whiteContrastP95": 1.45,
        "veilFor3": 0.555,
        "veilFor4_5": 0.728
      }
    },
    {
      "file": "aurora.webp",
      "name": "Aurora",
      "family": "liquid",
      "palette": "aurora",
      "seed": 1042,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.594,
          "c": 0.224,
          "h": 277.5
        },
        {
          "l": 0.73,
          "c": 0.154,
          "h": 237.5
        },
        {
          "l": 0.643,
          "c": 0.246,
          "h": 332.5
        }
      ],
      "meanLightness": 0.686,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.759,
        "darkness": 0.241,
        "p50Luminance": 0.4592,
        "p95Luminance": 0.585,
        "whiteContrastP50": 2.06,
        "whiteContrastP95": 1.65,
        "veilFor3": 0.487,
        "veilFor4_5": 0.687
      }
    },
    {
      "file": "limelight.webp",
      "name": "Limelight",
      "family": "liquid",
      "palette": "lime",
      "seed": 1360,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.643,
          "c": 0.189,
          "h": 252.5
        },
        {
          "l": 0.85,
          "c": 0.204,
          "h": 142.5
        }
      ],
      "meanLightness": 0.743,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.731,
        "darkness": 0.269,
        "p50Luminance": 0.4082,
        "p95Luminance": 0.6176,
        "whiteContrastP50": 2.29,
        "whiteContrastP95": 1.57,
        "veilFor3": 0.514,
        "veilFor4_5": 0.703
      }
    },
    {
      "file": "mercury.webp",
      "name": "Mercury",
      "family": "liquid",
      "palette": "slate",
      "seed": 1033,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.494,
          "c": 0.061,
          "h": 267.5
        }
      ],
      "meanLightness": 0.494,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.504,
        "darkness": 0.496,
        "p50Luminance": 0.1305,
        "p95Luminance": 0.3202,
        "whiteContrastP50": 5.82,
        "whiteContrastP95": 2.84,
        "veilFor3": 0.063,
        "veilFor4_5": 0.427
      }
    },
    {
      "file": "sunset.webp",
      "name": "Sunset",
      "family": "liquid",
      "palette": "sunset",
      "seed": 1144,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.689,
          "c": 0.195,
          "h": 27.5
        }
      ],
      "meanLightness": 0.698,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.692,
        "darkness": 0.308,
        "p50Luminance": 0.2832,
        "p95Luminance": 0.4372,
        "whiteContrastP50": 3.15,
        "whiteContrastP95": 2.16,
        "veilFor3": 0.314,
        "veilFor4_5": 0.581
      }
    },
    {
      "file": "garnet.webp",
      "name": "Garnet",
      "family": "liquid",
      "palette": "garnet",
      "seed": 1244,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.358,
          "c": 0.135,
          "h": 7.5
        }
      ],
      "meanLightness": 0.357,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.457,
        "darkness": 0.543,
        "p50Luminance": 0.0797,
        "p95Luminance": 0.1536,
        "whiteContrastP50": 8.1,
        "whiteContrastP95": 5.16,
        "veilFor3": 0.0,
        "veilFor4_5": 0.0
      }
    },
    {
      "file": "clear-sky.webp",
      "name": "Clear Sky",
      "family": "liquid",
      "palette": "ice",
      "seed": 3017,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.805,
          "c": 0.097,
          "h": 242.5
        }
      ],
      "meanLightness": 0.805,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.818,
        "darkness": 0.182,
        "p50Luminance": 0.5466,
        "p95Luminance": 0.6804,
        "whiteContrastP50": 1.76,
        "whiteContrastP95": 1.44,
        "veilFor3": 0.559,
        "veilFor4_5": 0.731
      }
    },
    {
      "file": "lemonade.webp",
      "name": "Lemonade",
      "family": "liquid",
      "palette": "lemon",
      "seed": 3012,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.869,
          "c": 0.165,
          "h": 102.5
        }
      ],
      "meanLightness": 0.869,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.873,
        "darkness": 0.127,
        "p50Luminance": 0.6875,
        "p95Luminance": 0.7733,
        "whiteContrastP50": 1.42,
        "whiteContrastP95": 1.28,
        "veilFor3": 0.612,
        "veilFor4_5": 0.763
      }
    },
    {
      "file": "sea-glass.webp",
      "name": "Sea Glass",
      "family": "liquid",
      "palette": "seaglass",
      "seed": 3026,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.84,
          "c": 0.076,
          "h": 187.5
        }
      ],
      "meanLightness": 0.841,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.816,
        "darkness": 0.184,
        "p50Luminance": 0.5492,
        "p95Luminance": 0.7158,
        "whiteContrastP50": 1.75,
        "whiteContrastP95": 1.37,
        "veilFor3": 0.581,
        "veilFor4_5": 0.744
      }
    },
    {
      "file": "raspberry.webp",
      "name": "Raspberry",
      "family": "liquid",
      "palette": "berry",
      "seed": 5015,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.511,
          "c": 0.18,
          "h": 352.5
        },
        {
          "l": 0.253,
          "c": 0.113,
          "h": 282.5
        }
      ],
      "meanLightness": 0.426,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.487,
        "darkness": 0.513,
        "p50Luminance": 0.1192,
        "p95Luminance": 0.1788,
        "whiteContrastP50": 6.21,
        "whiteContrastP95": 4.59,
        "veilFor3": 0.0,
        "veilFor4_5": 0.0
      }
    },
    {
      "file": "teal-drift.webp",
      "name": "Teal Drift",
      "family": "silk",
      "palette": "abyss",
      "seed": 2155,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.679,
          "c": 0.121,
          "h": 182.5
        }
      ],
      "meanLightness": 0.456,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.258,
        "darkness": 0.742,
        "p50Luminance": 0.017,
        "p95Luminance": 0.1007,
        "whiteContrastP50": 15.67,
        "whiteContrastP95": 6.97,
        "veilFor3": 0.0,
        "veilFor4_5": 0.0
      }
    },
    {
      "file": "blue-hour.webp",
      "name": "Blue Hour",
      "family": "silk",
      "palette": "bluebell",
      "seed": 2035,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.59,
          "c": 0.215,
          "h": 277.5
        }
      ],
      "meanLightness": 0.633,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.732,
        "darkness": 0.268,
        "p50Luminance": 0.3952,
        "p95Luminance": 0.5078,
        "whiteContrastP50": 2.36,
        "whiteContrastP95": 1.88,
        "veilFor3": 0.409,
        "veilFor4_5": 0.639
      }
    },
    {
      "file": "ember.webp",
      "name": "Ember",
      "family": "silk",
      "palette": "ember",
      "seed": 2044,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.489,
          "c": 0.153,
          "h": 42.5
        }
      ],
      "meanLightness": 0.489,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.33,
        "darkness": 0.67,
        "p50Luminance": 0.0166,
        "p95Luminance": 0.1622,
        "whiteContrastP50": 15.76,
        "whiteContrastP95": 4.95,
        "veilFor3": 0.0,
        "veilFor4_5": 0.0
      }
    },
    {
      "file": "midnight.webp",
      "name": "Midnight",
      "family": "silk",
      "palette": "midnight",
      "seed": 2153,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.424,
          "c": 0.16,
          "h": 267.5
        }
      ],
      "meanLightness": 0.447,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.641,
        "darkness": 0.359,
        "p50Luminance": 0.2779,
        "p95Luminance": 0.3109,
        "whiteContrastP50": 3.2,
        "whiteContrastP95": 2.91,
        "veilFor3": 0.035,
        "veilFor4_5": 0.41
      }
    },
    {
      "file": "velvet.webp",
      "name": "Velvet",
      "family": "silk",
      "palette": "nightshade",
      "seed": 2014,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.652,
          "c": 0.249,
          "h": 337.5
        },
        {
          "l": 0.314,
          "c": 0.158,
          "h": 302.5
        }
      ],
      "meanLightness": 0.431,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.303,
        "darkness": 0.697,
        "p50Luminance": 0.019,
        "p95Luminance": 0.1259,
        "whiteContrastP50": 15.21,
        "whiteContrastP95": 5.97,
        "veilFor3": 0.0,
        "veilFor4_5": 0.0
      }
    },
    {
      "file": "reef.webp",
      "name": "Reef",
      "family": "silk",
      "palette": "peacock",
      "seed": 2146,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.747,
          "c": 0.126,
          "h": 182.5
        },
        {
          "l": 0.343,
          "c": 0.152,
          "h": 262.5
        }
      ],
      "meanLightness": 0.568,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.741,
        "darkness": 0.259,
        "p50Luminance": 0.5141,
        "p95Luminance": 0.5876,
        "whiteContrastP50": 1.86,
        "whiteContrastP95": 1.65,
        "veilFor3": 0.489,
        "veilFor4_5": 0.688
      }
    },
    {
      "file": "amber-night.webp",
      "name": "Amber Night",
      "family": "silk",
      "palette": "silk-amber",
      "seed": 2022,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.777,
          "c": 0.135,
          "h": 77.5
        },
        {
          "l": 0.337,
          "c": 0.094,
          "h": 262.5
        }
      ],
      "meanLightness": 0.627,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.493,
        "darkness": 0.507,
        "p50Luminance": 0.0915,
        "p95Luminance": 0.454,
        "whiteContrastP50": 7.42,
        "whiteContrastP95": 2.08,
        "veilFor3": 0.339,
        "veilFor4_5": 0.596
      }
    },
    {
      "file": "fern.webp",
      "name": "Fern",
      "family": "silk",
      "palette": "silk-fern",
      "seed": 2105,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.773,
          "c": 0.156,
          "h": 137.5
        }
      ],
      "meanLightness": 0.615,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.713,
        "darkness": 0.287,
        "p50Luminance": 0.4433,
        "p95Luminance": 0.6441,
        "whiteContrastP50": 2.13,
        "whiteContrastP95": 1.51,
        "veilFor3": 0.534,
        "veilFor4_5": 0.715
      }
    },
    {
      "file": "honey.webp",
      "name": "Honey",
      "family": "silk",
      "palette": "silk-gold",
      "seed": 2139,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.657,
          "c": 0.146,
          "h": 62.5
        }
      ],
      "meanLightness": 0.641,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.82,
        "darkness": 0.18,
        "p50Luminance": 0.6247,
        "p95Luminance": 0.6947,
        "whiteContrastP50": 1.56,
        "whiteContrastP95": 1.41,
        "veilFor3": 0.568,
        "veilFor4_5": 0.736
      }
    },
    {
      "file": "orchid.webp",
      "name": "Orchid",
      "family": "silk",
      "palette": "silk-orchid",
      "seed": 2188,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.389,
          "c": 0.198,
          "h": 292.5
        },
        {
          "l": 0.723,
          "c": 0.167,
          "h": 342.5
        }
      ],
      "meanLightness": 0.559,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.418,
        "darkness": 0.582,
        "p50Luminance": 0.0667,
        "p95Luminance": 0.1989,
        "whiteContrastP50": 9.0,
        "whiteContrastP95": 4.22,
        "veilFor3": 0.0,
        "veilFor4_5": 0.078
      }
    },
    {
      "file": "meadow.webp",
      "name": "Meadow",
      "family": "silk",
      "palette": "lime",
      "seed": 7017,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.575,
          "c": 0.218,
          "h": 257.5
        },
        {
          "l": 0.831,
          "c": 0.203,
          "h": 127.5
        }
      ],
      "meanLightness": 0.687,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.598,
        "darkness": 0.402,
        "p50Luminance": 0.2007,
        "p95Luminance": 0.3503,
        "whiteContrastP50": 4.19,
        "whiteContrastP95": 2.62,
        "veilFor3": 0.144,
        "veilFor4_5": 0.477
      }
    },
    {
      "file": "crimson.webp",
      "name": "Crimson",
      "family": "silk",
      "palette": "silk-crimson",
      "seed": 2107,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.58,
          "c": 0.18,
          "h": 22.5
        }
      ],
      "meanLightness": 0.55,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.479,
        "darkness": 0.521,
        "p50Luminance": 0.1031,
        "p95Luminance": 0.1369,
        "whiteContrastP50": 6.86,
        "whiteContrastP95": 5.62,
        "veilFor3": 0.0,
        "veilFor4_5": 0.0
      }
    },
    {
      "file": "tide.webp",
      "name": "Tide",
      "family": "silk",
      "palette": "silk-tide",
      "seed": 2109,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.695,
          "c": 0.118,
          "h": 227.5
        },
        {
          "l": 0.27,
          "c": 0.12,
          "h": 262.5
        }
      ],
      "meanLightness": 0.523,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.683,
        "darkness": 0.317,
        "p50Luminance": 0.4113,
        "p95Luminance": 0.5609,
        "whiteContrastP50": 2.28,
        "whiteContrastP95": 1.72,
        "veilFor3": 0.465,
        "veilFor4_5": 0.673
      }
    },
    {
      "file": "rosewood.webp",
      "name": "Rosewood",
      "family": "silk",
      "palette": "silk-rose",
      "seed": 2136,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.6,
          "c": 0.123,
          "h": 12.5
        }
      ],
      "meanLightness": 0.688,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.602,
        "darkness": 0.398,
        "p50Luminance": 0.1758,
        "p95Luminance": 0.5542,
        "whiteContrastP50": 4.65,
        "whiteContrastP95": 1.74,
        "veilFor3": 0.459,
        "veilFor4_5": 0.669
      }
    },
    {
      "file": "slate.webp",
      "name": "Slate",
      "family": "silk",
      "palette": "slate",
      "seed": 2046,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.593,
          "c": 0.057,
          "h": 262.5
        }
      ],
      "meanLightness": 0.516,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.421,
        "darkness": 0.579,
        "p50Luminance": 0.0964,
        "p95Luminance": 0.3839,
        "whiteContrastP50": 7.17,
        "whiteContrastP95": 2.42,
        "veilFor3": 0.219,
        "veilFor4_5": 0.522
      }
    },
    {
      "file": "iris.webp",
      "name": "Iris",
      "family": "silk",
      "palette": "candy",
      "seed": 7019,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.569,
          "c": 0.24,
          "h": 297.5
        },
        {
          "l": 0.775,
          "c": 0.135,
          "h": 222.5
        }
      ],
      "meanLightness": 0.659,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.573,
        "darkness": 0.427,
        "p50Luminance": 0.1598,
        "p95Luminance": 0.2138,
        "whiteContrastP50": 5.01,
        "whiteContrastP95": 3.98,
        "veilFor3": 0.0,
        "veilFor4_5": 0.143
      }
    },
    {
      "file": "chiffon.webp",
      "name": "Chiffon",
      "family": "silk",
      "palette": "lemon",
      "seed": 4016,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.861,
          "c": 0.143,
          "h": 97.5
        }
      ],
      "meanLightness": 0.858,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.902,
        "darkness": 0.098,
        "p50Luminance": 0.7542,
        "p95Luminance": 0.8421,
        "whiteContrastP50": 1.31,
        "whiteContrastP95": 1.18,
        "veilFor3": 0.644,
        "veilFor4_5": 0.782
      }
    },
    {
      "file": "afterglow.webp",
      "name": "Afterglow",
      "family": "silk",
      "palette": "dusk",
      "seed": 2157,
      "blur": 0.09,
      "hues": [
        {
          "l": 0.692,
          "c": 0.137,
          "h": 32.5
        },
        {
          "l": 0.235,
          "c": 0.089,
          "h": 307.5
        }
      ],
      "meanLightness": 0.474,
      "textArea": {
        "box": [
          0.04,
          0.05,
          0.8,
          0.5
        ],
        "meanLightness": 0.308,
        "darkness": 0.692,
        "p50Luminance": 0.0258,
        "p95Luminance": 0.2279,
        "whiteContrastP50": 13.86,
        "whiteContrastP95": 3.78,
        "veilFor3": 0.0,
        "veilFor4_5": 0.196
      }
    }
  ]
}

"""#
