"""Generates the tvOS brand assets (layered app icon + top shelf images).

Run from the repository root:  python3 tools/make_icons.py
"""
import json
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = "ClaudeTV/Assets.xcassets"
BRAND = os.path.join(ROOT, "App Icon & Top Shelf Image.brandassets")
INFO = {"author": "xcode", "version": 1}

TOP = (232, 128, 92)
BOTTOM = (122, 52, 34)


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f, indent=2)


def gradient(w, h):
    n = 128
    img = Image.new("RGB", (n, n))
    px = img.load()
    for y in range(n):
        for x in range(n):
            t = (y / n) * 0.75 + (x / n) * 0.25
            px[x, y] = tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
    return img.resize((w, h), Image.BICUBIC)


def bubble(w, h):
    """White speech bubble with three dots, on a transparent layer."""
    scale = 4
    W, H = w * scale, h * scale
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    bw, bh = int(W * 0.46), int(H * 0.50)
    x0, y0 = (W - bw) // 2, int(H * 0.20)
    r = bh // 3
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([x0, y0 + 18 * scale, x0 + bw, y0 + bh + 18 * scale], r, fill=(60, 20, 10, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(12 * scale))
    img.alpha_composite(shadow)
    d.rounded_rectangle([x0, y0, x0 + bw, y0 + bh], r, fill=(255, 250, 245, 255))
    # tail
    tx = x0 + int(bw * 0.24)
    d.polygon([(tx, y0 + bh - 2), (tx + int(bw * 0.16), y0 + bh - 2), (tx - int(bw * 0.05), y0 + bh + int(bh * 0.28))],
              fill=(255, 250, 245, 255))
    # dots
    dr = int(bh * 0.085)
    cy = y0 + bh // 2
    for i in (-1, 0, 1):
        cx = W // 2 + i * int(bw * 0.24)
        d.ellipse([cx - dr, cy - dr, cx + dr, cy + dr], fill=TOP + (255,))
    return img.resize((w, h), Image.LANCZOS)


def imageset(path, files):
    images = []
    for scale, (name, img) in files.items():
        img.save(os.path.join(path, name))
        images.append({"idiom": "tv", "filename": name, "scale": scale})
    write_json(os.path.join(path, "Contents.json"), {"images": images, "info": INFO})


def imagestack(name, sizes):
    stack = os.path.join(BRAND, name + ".imagestack")
    layers = []
    for layer, maker in (("Front", bubble), ("Back", gradient)):
        layer_dir = os.path.join(stack, layer + ".imagestacklayer")
        content = os.path.join(layer_dir, "Content.imageset")
        os.makedirs(content, exist_ok=True)
        files = {scale: (f"{layer.lower()}@{scale}.png", maker(w, h)) for scale, (w, h) in sizes.items()}
        imageset(content, files)
        write_json(os.path.join(layer_dir, "Contents.json"), {"info": INFO})
        layers.append({"filename": layer + ".imagestacklayer"})
    write_json(os.path.join(stack, "Contents.json"), {"layers": layers, "info": INFO})


def top_shelf(name, sizes):
    path = os.path.join(BRAND, name + ".imageset")
    os.makedirs(path, exist_ok=True)
    files = {}
    for scale, (w, h) in sizes.items():
        img = gradient(w, h).convert("RGBA")
        icon = bubble(int(h * 1.667), h)
        img.alpha_composite(icon, ((w - icon.width) // 2, 0))
        files[scale] = (f"shelf@{scale}.png", img.convert("RGB"))
    imageset(path, files)


def main():
    write_json(os.path.join(ROOT, "Contents.json"), {"info": INFO})
    imagestack("App Icon", {"1x": (400, 240), "2x": (800, 480)})
    imagestack("App Icon - App Store", {"1x": (1280, 768)})
    top_shelf("Top Shelf Image", {"1x": (1920, 720), "2x": (3840, 1440)})
    top_shelf("Top Shelf Image Wide", {"1x": (2320, 720), "2x": (4640, 1440)})
    write_json(os.path.join(BRAND, "Contents.json"), {
        "assets": [
            {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
            {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
            {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
            {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
        ],
        "info": INFO,
    })


if __name__ == "__main__":
    main()
