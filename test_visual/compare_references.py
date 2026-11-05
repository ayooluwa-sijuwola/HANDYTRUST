"""Stage 8 visual comparison: reference screenshot vs implemented screen.

Usage: python test_visual/compare_references.py <reference_dir> <out_dir>

For each screen it crops the reference to the phone area (some exports are
presentation canvases), resizes both images to the same size, and reports:
  - layout similarity: 100 - mean abs difference of grayscale (structure)
  - colour similarity: 100 - mean abs difference of a heavily blurred RGB
    image (palette / large colour areas)
and writes a side-by-side PNG (reference | implementation) for review.
Scores are approximate: fixture text differs from the mockups' sample text,
and features without backend support are intentionally absent.
"""
import os
import sys

from PIL import Image, ImageChops, ImageFilter, ImageStat

# name -> (reference number, crop box in the reference or None)
SHOTS = {
    "discovery_dark": (8, None), "discovery_light": (15, None),
    "artisan_profile_dark": (2, None), "artisan_profile_light": (16, (543, 0, 1058, 1485)),
    "post_job_dark": (3, None), "post_job_light": (17, (543, 30, 1058, 1356)),
    "bookings_dark": (4, None), "bookings_light": (19, None),
    "payments_dark": (5, None), "payments_light": (21, None),
    "profile_dark": (6, None), "profile_light": (22, None),
    "verification_dark": (7, None), "verification_light": (23, None),
    "confirm_pay_dark": (10, None), "confirm_pay_light": (18, (14, 50, 692, 1550)),
    "chat_dark": (11, None), "chat_light": (20, None),
    "notifications_dark": (12, None), "notifications_light": (24, None),
    "onboarding_dark": (13, (565, 115, 1035, 1165)), "onboarding_light": (14, None),
}


def score(a, b):
    size = (130, 340)
    ga = a.convert("L").resize(size)
    gb = b.convert("L").resize(size)
    layout = 100 - ImageStat.Stat(ImageChops.difference(ga, gb)).mean[0] / 255 * 100
    ca = a.convert("RGB").resize((40, 100)).filter(ImageFilter.GaussianBlur(4))
    cb = b.convert("RGB").resize((40, 100)).filter(ImageFilter.GaussianBlur(4))
    d = ImageStat.Stat(ImageChops.difference(ca, cb)).mean
    colour = 100 - (sum(d) / 3) / 255 * 100
    return layout, colour


def main():
    ref_dir, out_dir = sys.argv[1], sys.argv[2]
    gold_dir = os.path.join(os.path.dirname(__file__), "goldens")
    os.makedirs(out_dir, exist_ok=True)
    print(f"{'screen':24s} ref  layout  colour")
    for name, (ref, crop) in SHOTS.items():
        r = Image.open(os.path.join(ref_dir, f"{ref}.png")).convert("RGB")
        if crop:
            r = r.crop(crop)
        g = Image.open(os.path.join(gold_dir, f"{name}.png")).convert("RGB")
        g = g.resize(r.size)
        layout, colour = score(r, g)
        print(f"{name:24s} #{ref:<3d} {layout:6.1f}  {colour:6.1f}")
        side = Image.new("RGB", (r.width * 2 + 20, r.height), (128, 128, 128))
        side.paste(r, (0, 0))
        side.paste(g, (r.width + 20, 0))
        side.thumbnail((1100, 1600))
        side.save(os.path.join(out_dir, f"{name}_side_by_side.png"))


if __name__ == "__main__":
    main()
