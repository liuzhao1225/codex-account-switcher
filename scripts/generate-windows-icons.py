"""Package the existing logos as Windows ICO resources (requires Pillow)."""
from pathlib import Path
from io import BytesIO
import struct

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "windows" / "CodexAccountSwitcher"
SIZES = [(n, n) for n in (16, 20, 24, 32, 40, 48, 64, 256)]
RESAMPLE = getattr(Image, "Resampling", Image).LANCZOS


def write_icon(image, path):
    frames = []
    for size in SIZES:
        frame = image.resize(size, RESAMPLE)
        data = BytesIO()
        if size[0] == 256:
            frame.save(data, format="PNG")
            frames.append(data.getvalue())
        else:
            frame.save(data, format="ICO", sizes=[size], bitmap_format="bmp")
            encoded = data.getvalue()
            length, offset = struct.unpack_from("<II", encoded, 14)
            frames.append(encoded[offset:offset + length])
    offset = 6 + 16 * len(frames)
    header = struct.pack("<HHH", 0, 1, len(frames))
    for size, frame in zip(SIZES, frames):
        header += struct.pack("<BBBBHHII", size[0] % 256, size[1] % 256, 0, 0, 1, 32, len(frame), offset)
        offset += len(frame)
    path.write_bytes(header + b"".join(frames))

# Application artwork retains its original tile. The notification area uses
# a separate transparent silhouette, with no tile, shadow or app-icon inset.
write_icon(Image.open(ROOT / "assets" / "app-icon-1024.png").convert("RGBA"), OUTPUT / "app.ico")

for theme, filename, color in (
    ("light", "account-switcher-logo.png", (0, 0, 0)),
    ("dark", "account-switcher-logo-white.png", (255, 255, 255)),
):
    source = Image.open(ROOT / "assets" / filename).convert("RGBA")
    alpha = source.getchannel("A")
    # Ignore faint source-image fringe when centering the visible mark.
    bounds = alpha.point(lambda value: 255 if value >= 128 else 0).getbbox()
    alpha = alpha.crop(bounds)
    scale = 252 / max(alpha.size)
    alpha = alpha.resize(tuple(round(side * scale) for side in alpha.size), RESAMPLE)
    mask = Image.new("L", (256, 256))
    mask.paste(alpha, ((256 - alpha.width) // 2, (256 - alpha.height) // 2))
    icon = Image.new("RGBA", (256, 256), (*color, 0))
    icon.putalpha(mask)
    write_icon(icon, OUTPUT / f"tray-{theme}.ico")

print("Packaged application logo and transparent light/dark tray logos at 8 Windows sizes.")
