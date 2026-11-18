"""Builds the website's images and fonts from the app's own assets.

Run from app/ after `flutter test tool/generate_screenshots_test.dart` (and
`flutter test tool/generate_app_icon_test.dart`, which draws img/icon-*.png):

    python tool/build_site_assets.py

Writes into ../site:
  img/<screen>.webp   the app screenshots, compressed (the table is cropped to
                      its rows)
  img/share.png       the 1200x630 picture WhatsApp and others show for a link,
                      with the logo from img/logo.png
  fonts/*.woff2       Inter and Barlow Condensed cut down to Latin, with their
                      OFL licences, so the site loads no font from another server

Needs Pillow, fontTools and brotli (pip install pillow fonttools brotli).
"""
from pathlib import Path

from fontTools import subset
from PIL import Image, ImageDraw, ImageFont

APP = Path(__file__).resolve().parent.parent
SHOTS = APP / 'build' / 'screenshots'
FONTS = APP / 'assets' / 'google_fonts'
SITE = APP.parent / 'site'

NIGHT = (8, 16, 8)
PITCH = (31, 63, 23)
NEON = (125, 196, 58)
CHALK = (234, 241, 230)
MUTED = (149, 163, 140)

# Screens and how much of their height to keep (the table ends early).
SCREENS = {'scoring': 1.0, 'home': 1.0, 'team': 1.0, 'result': 1.0, 'scorecard': 1.0, 'charts': 1.0, 'table': 0.52}

# Only the faces and weights the site uses.
WEB_FONTS = [
    'Inter-Regular', 'Inter-SemiBold', 'Inter-ExtraBold',
    'BarlowCondensed-Bold', 'BarlowCondensed-ExtraBold', 'BarlowCondensed-ExtraBoldItalic',
]
LATIN = 'U+0000-00FF,U+0131,U+0152-0153,U+02C6,U+02DA,U+02DC,U+2000-206F,U+2074,U+20AC,U+2122,U+2190-2193,U+2212,U+2215'


def screenshots():
    out = SITE / 'img'
    out.mkdir(parents=True, exist_ok=True)
    for name, keep in SCREENS.items():
        image = Image.open(SHOTS / f'{name}.png').convert('RGB')
        if keep < 1:
            image = image.crop((0, 0, image.width, round(image.height * keep)))
        image.save(out / f'{name}.webp', 'WEBP', quality=82, method=6)
        print(f'img/{name}.webp', (out / f'{name}.webp').stat().st_size // 1024, 'KB')


def fonts():
    out = SITE / 'fonts'
    out.mkdir(parents=True, exist_ok=True)
    for name in WEB_FONTS:
        options = subset.Options()
        options.flavor = 'woff2'
        options.layout_features = ['kern', 'liga', 'tnum', 'lnum']
        font = subset.load_font(str(FONTS / f'{name}.ttf'), options)
        subsetter = subset.Subsetter(options)
        subsetter.populate(unicodes=subset.parse_unicodes(LATIN))
        subsetter.subset(font)
        subset.save_font(font, str(out / f'{name}.woff2'), options)
        print(f'fonts/{name}.woff2', (out / f'{name}.woff2').stat().st_size // 1024, 'KB')
    for licence in ('Inter-OFL.txt', 'BarlowCondensed-OFL.txt'):
        (out / licence).write_bytes((FONTS / licence).read_bytes())


def share_card():
    """The link preview: name, promise, and the live scoring screen."""
    width, height = 1200, 630
    card = Image.new('RGB', (width, height), NIGHT)
    draw = ImageDraw.Draw(card)
    # Floodlight: the pitch colour fading out from the top left.
    for i in range(height):
        t = i / height
        draw.line([(0, i), (width, i)], fill=tuple(round(p * (1 - t) + n * t) for p, n in zip(PITCH, NIGHT)))

    display = ImageFont.truetype(str(FONTS / 'BarlowCondensed-ExtraBoldItalic.ttf'), 132)
    heading = ImageFont.truetype(str(FONTS / 'BarlowCondensed-Bold.ttf'), 48)
    body = ImageFont.truetype(str(FONTS / 'Inter-SemiBold.ttf'), 30)

    logo = Image.open(SITE / 'img' / 'logo.png').convert('RGBA').resize((112, 112), Image.LANCZOS)
    card.paste(logo, (64, 68), logo)
    draw.text((66, 170), 'BNP Scorer', font=display, fill=CHALK)
    draw.text((72, 338), 'Ball-by-ball cricket scoring', font=heading, fill=NEON)
    draw.text((72, 396), 'for local and gully matches', font=heading, fill=NEON)
    draw.text((72, 478), 'Free. Works offline.', font=body, fill=MUTED)
    draw.text((72, 522), 'Your matches stay on your phone.', font=body, fill=MUTED)

    phone = Image.open(SHOTS / 'scoring.png').convert('RGB')
    phone = phone.resize((300, round(phone.height * 300 / phone.width)), Image.LANCZOS)
    frame = Image.new('RGB', (phone.width + 24, phone.height + 24), (31, 42, 36))
    mask = Image.new('L', frame.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *frame.size), radius=44, fill=255)
    frame.paste(phone, (12, 12))
    card.paste(frame, (width - frame.width - 72, 64), mask)
    card.save(SITE / 'img' / 'share.png', optimize=True)
    print('img/share.png', (SITE / 'img' / 'share.png').stat().st_size // 1024, 'KB')


if __name__ == '__main__':
    screenshots()
    fonts()
    share_card()
