"""Render a Bangla app promo from real Flutter captures and original music.

Requirements: pillow, numpy, uharfbuzz, freetype-py, imageio-ffmpeg.
Run from the repository root: python marketing/render_promo.py
"""
from pathlib import Path
from functools import lru_cache
import math
import subprocess
import wave

import freetype
import imageio_ffmpeg
import numpy as np
import uharfbuzz as hb
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'marketing'
CAPTURES = ROOT / 'build/design-preview'
W, H, FPS = 1920, 1080, 24
FONT = Path('C:/Windows/Fonts/Nirmala.ttf')
BOLD = Path('C:/Windows/Fonts/NirmalaB.ttf')
if not FONT.exists():
    raise SystemExit('Set FONT/BOLD to fonts supporting Bengali before rendering.')
FACES = {}
for bold, path in [(False, FONT), (True, BOLD)]:
    FACES[bold] = (freetype.Face(str(path)), hb.Font(hb.Face(path.read_bytes())))


@lru_cache(maxsize=400)
def text_image(text, size, bold=False, color='#F2FCF8'):
    """HarfBuzz shaping preserves Bengali conjuncts and vowel placement."""
    face, font = FACES[bold]
    face.set_pixel_sizes(0, size)
    font.scale = (size * 64, size * 64)
    hb.ot_font_set_funcs(font)
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(font, buf)
    positions = buf.glyph_positions
    width = math.ceil(sum(p.x_advance for p in positions) / 64) + 12
    result = Image.new('RGBA', (max(width, 1), size * 2))
    baseline = face.size.ascender / 64 + 3
    x = 4.0
    for info, pos in zip(buf.glyph_infos, positions):
        face.load_glyph(info.codepoint, freetype.FT_LOAD_RENDER)
        glyph, bitmap = face.glyph, face.glyph.bitmap
        if bitmap.width and bitmap.rows:
            data = np.array(bitmap.buffer, dtype=np.uint8).reshape(bitmap.rows, abs(bitmap.pitch))
            mask = Image.fromarray(data[:, :bitmap.width])
            ink = Image.new('RGBA', mask.size, color)
            ink.putalpha(mask)
            result.alpha_composite(ink, (
                round(x + pos.x_offset / 64 + glyph.bitmap_left),
                round(baseline - pos.y_offset / 64 - glyph.bitmap_top)))
        x += pos.x_advance / 64
    return result.crop(result.getbbox() or (0, 0, 1, size))


def put_text(canvas, text, xy, size=48, bold=False, color='#F2FCF8', max_width=None):
    image = text_image(text, size, bold, color)
    if max_width and image.width > max_width:
        image = text_image(text, max(12, round(size * max_width / image.width)), bold, color)
    canvas.alpha_composite(image, (int(xy[0]), int(xy[1])))


def rounded(image, radius):
    image = image.convert('RGBA')
    mask = Image.new('L', image.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.width - 1, image.height - 1), radius, fill=255)
    image.putalpha(mask)
    return image


def base_background():
    yy, xx = np.mgrid[0:H, 0:W]
    glow = np.exp(-(((xx - 1550) / 800) ** 2 + ((yy - 340) / 690) ** 2))
    pixels = np.zeros((H, W, 3), dtype=np.uint8)
    for c, base in enumerate([5, 20, 26]):
        pixels[:, :, c] = np.clip(base + glow * [0, 36, 26][c], 0, 255)
    image = Image.fromarray(pixels).convert('RGBA')
    d = ImageDraw.Draw(image)
    for x in [1410, 1620, 1830]:
        d.line((x - 200, H, x + 310, 0), fill=(32, 75, 70), width=2)
    for y in range(0, H, 115):
        d.line((1140, y, W, y - 260), fill=(20, 52, 52), width=1)
    return image


BG = base_background()
LOGO = rounded(Image.open(ROOT / 'assets/icons/app_icon.jpg').resize((104, 104)), 27)


def phone(file, crop=None):
    screen = Image.open(CAPTURES / file).convert('RGBA')
    if crop:
        screen = screen.crop(crop)
    if file.startswith('watch-options'):
        # Keep the real sheet, removing the empty test-harness area above it.
        panel = screen.crop((0, 203, screen.width, screen.height))
        panel = panel.resize((382, 591), Image.Resampling.LANCZOS)
        screen = Image.new('RGBA', (382, 826), '#0B1726' if 'dark' in file else '#F0F5FF')
        screen.alpha_composite(panel, (0, 235))
        screen.alpha_composite(LOGO.resize((70, 70)), (32, 54))
        put_text(screen, 'Rail Pro', (120, 69), 34, True, '#00B48B')
        put_text(screen, 'আপনার আসন বেছে নিন', (32, 156), 27, False, '#87A89C')
    else:
        screen = screen.resize((382, 826), Image.Resampling.LANCZOS)
    plate = Image.new('RGBA', (460, 922))
    d = ImageDraw.Draw(plate)
    d.rounded_rectangle((16, 8, 440, 903), 58, fill='#102C31', outline='#396D65', width=3)
    d.rounded_rectangle((25, 17, 431, 894), 51, fill='#061519')
    plate.alpha_composite(rounded(screen, 35), (37, 45))
    d.rounded_rectangle((176, 24, 279, 35), 6, fill='#244542')
    d.rounded_rectangle((179, 878, 275, 884), 3, fill='#86A89F')
    return plate


def notification_card(title, subtitle, action, color):
    card = Image.new('RGBA', (650, 225))
    d = ImageDraw.Draw(card)
    d.rounded_rectangle((0, 0, 649, 224), 27, fill='#F0F6F3', outline='#C5DAD1', width=2)
    card.alpha_composite(LOGO.resize((57, 57)), (565, 37))
    d.ellipse((26, 25, 40, 39), fill=color)
    put_text(card, 'Rail Pro', (50, 20), 25, True, '#294A40')
    put_text(card, title, (26, 61), 31, True, '#092C23', 520)
    put_text(card, subtitle, (26, 111), 22, False, '#426258', 570)
    d.rounded_rectangle((23, 161, 200, 203), 12, fill=color)
    put_text(card, action, (37, 170), 21, True, '#FFFFFF', 150)
    return card


def notifications():
    stack = Image.new('RGBA', (700, 840))
    for i, args in enumerate([
        ('আসন পাওয়া গেছে', 'SNIGDHA · 08-Oct-2026 · ২ আসন', 'বুক করুন', '#008B69'),
        ('ওটিপি যাচাই করুন', 'ফোনে পাঠানো ওটিপি যাচাই করুন।', 'ওটিপি যাচাই', '#0089B1'),
        ('আসন সংরক্ষিত · পেমেন্ট করুন', 'সময় শেষ হওয়ার আগে পেমেন্ট করুন।', 'পেমেন্ট করুন', '#AC7720'),
    ]):
        stack.alpha_composite(notification_card(*args), (18, 15 + i * 246))
    put_text(stack, 'নোটিফিকেশন প্রিভিউ', (25, 770), 24, False, '#92B8AB')
    return stack


SCENES = [
    (4, ['ট্রেনের টিকিট খোঁজা', 'এবার আরও সহজ'], 'আপনার যাত্রার স্মার্ট সহকারী', 'promo-search-bn.png'),
    (5, ['স্টেশন বেছে নিন', 'যাত্রা খুঁজুন'], 'দ্রুত অনুসন্ধান · সহজ স্টেশন নির্বাচন', 'promo-stations-bn.png'),
    (6, ['আসন খুঁজবে', 'Rail Pro'], 'ট্রেন, শ্রেণি ও আসন বেছে অটো-বুকিং শুরু করুন', 'watch-options-bn-dark.png'),
    (6, ['প্রয়োজনের সময়', 'স্পষ্ট নোটিফিকেশন'], 'আসন · ওটিপি · পেমেন্ট', None),
    (5, ['ওটিপি যাচাই করুন', 'পেমেন্ট সম্পন্ন করুন'], 'আসন নিশ্চিত করতে পেমেন্ট করতে হবে', 'promo-payment-bn.png'),
    (5, ['আপনার পরবর্তী যাত্রায়', 'সঙ্গে থাকুক Rail Pro'], 'খুঁজুন · যাচাই করুন · পেমেন্ট করুন', 'promo-search-bn.png'),
]
DURATION = sum(s[0] for s in SCENES)
PLATES = []
for duration, lines, subtitle, file in SCENES:
    PLATES.append(phone(file) if file else notifications())


SHADOW_BACKGROUNDS = []
for i, plate in enumerate(PLATES):
    x = 1394 - plate.width // 2 if i == 3 else 1490 - plate.width // 2
    y = 96 if i == 3 else 75
    shadow = Image.new('RGBA', BG.size)
    ImageDraw.Draw(shadow).rounded_rectangle((x + 12, y + 20, x + plate.width, y + plate.height),
        48, fill=(0, 0, 0, 100))
    SHADOW_BACKGROUNDS.append(Image.alpha_composite(BG, shadow.filter(ImageFilter.GaussianBlur(22))))


def frame(scene, t):
    canvas = SHADOW_BACKGROUNDS[scene].copy()
    canvas.alpha_composite(LOGO.resize((70, 70)), (108, 90))
    put_text(canvas, 'Rail Pro', (198, 109), 39, True)
    ImageDraw.Draw(canvas).rounded_rectangle((108, 258, 318, 300), 18, fill='#0C493B')
    put_text(canvas, 'আপনার যাত্রা', (128, 266), 25, True, '#A4F0D3')
    rise = round(14 * (1 - min(t / .7, 1)) ** 3)
    _, lines, subtitle, _ = SCENES[scene]
    for i, line in enumerate(lines):
        put_text(canvas, line, (108, 359 + i * 120 + rise), 88, True,
            '#EAFBF2' if i == 0 else '#36D3A6', 980)
    put_text(canvas, subtitle, (112, 641 + rise), 34, False, '#A4C4BA', 980)
    put_text(canvas, 'অ্যাপ প্রিভিউ', (114, 917), 24, False, '#72978C')
    if scene == 5:
        put_text(canvas, 'বাংলাদেশ রেলওয়ের অফিসিয়াল অ্যাপ নয়', (114, 960), 23, False, '#72978C')
    plate = PLATES[scene]
    scale = 1 + .015 * math.sin(t / SCENES[scene][0] * math.pi)
    plate = plate.resize((round(plate.width * scale), round(plate.height * scale)), Image.Resampling.BICUBIC)
    x = 1394 - plate.width // 2 if scene == 3 else 1490 - plate.width // 2
    y = 96 if scene == 3 else 75
    y += round(math.sin(t * 1.3) * 5)
    canvas.alpha_composite(plate, (x, y))
    d = ImageDraw.Draw(canvas)
    elapsed = sum(s[0] for s in SCENES[:scene]) + t
    d.rounded_rectangle((108, 1034, W - 108, 1040), 3, fill='#24453F')
    d.rounded_rectangle((108, 1034, 108 + round((W - 216) * elapsed / DURATION), 1040), 3, fill='#24C89D')
    return canvas.convert('RGB')


def music():
    sr = 44100
    times = np.arange(round(DURATION * sr)) / sr
    signal = np.zeros(len(times))
    beat = 60 / 108
    chords = [[220, 261.63, 329.63], [174.61, 220, 261.63], [130.81, 164.81, 196], [196, 246.94, 293.66]]
    for start in np.arange(0, DURATION, beat * 4):
        chord = chords[int(start / (beat * 4)) % len(chords)]
        mask = (times >= start) & (times < start + beat * 4)
        t = times[mask] - start
        env = np.minimum(t / .12, 1) * np.minimum((beat * 4 - t) / .3, 1)
        for freq in chord:
            signal[mask] += .026 * env * np.sin(2 * math.pi * freq * t)
        signal[mask] += .032 * env * np.sin(2 * math.pi * chord[0] / 2 * t)
    for i, start in enumerate(np.arange(0, DURATION, beat)):
        mask = (times >= start) & (times < start + .20)
        t = times[mask] - start
        signal[mask] += .11 * np.exp(-t * 25) * np.sin(2 * math.pi * (54 * t + 35 * t * np.exp(-t * 30)))
        if i % 2 == 1:
            mask = (times >= start) & (times < start + .65)
            t = times[mask] - start
            freq = [440, 523.25, 659.25, 587.33][(i // 2) % 4]
            signal[mask] += .031 * np.exp(-t * 5) * (np.sin(2 * math.pi * freq * t) + .3 * np.sin(2 * math.pi * freq * 2 * t))
    signal *= np.minimum(times / 1.1, 1) * np.minimum((DURATION - times) / 1.8, 1)
    data = (np.clip(signal, -1, 1) * 32767).astype('<i2')
    path = OUT / 'promo-original-music.wav'
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sr)
        output.writeframes(data.tobytes())
    return path


def render():
    OUT.mkdir(exist_ok=True)
    audio = music()
    video = OUT / 'rail-pro-promo-bn-landscape.mp4'
    command = [imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-f', 'rawvideo', '-vcodec', 'rawvideo',
        '-s', f'{W}x{H}', '-pix_fmt', 'rgb24', '-r', str(FPS), '-i', '-', '-i', str(audio),
        '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '19', '-pix_fmt', 'yuv420p',
        '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2',
        '-af', 'loudnorm=I=-16:TP=-1.5:LRA=9',
        '-movflags', '+faststart', '-t', str(DURATION), str(video)]
    contact = Image.new('RGB', (1440, 540), '#06191E')
    for i in range(len(SCENES)):
        preview = frame(i, 2)
        preview.save(OUT / f'scene-{i+1:02d}.png')
        contact.paste(preview.resize((480, 270)), ((i % 3) * 480, (i // 3) * 270))
    contact.save(OUT / 'storyboard.jpg', quality=92)
    frame(0, 2).save(OUT / 'poster.jpg', quality=94)
    with (OUT / 'encode-log.txt').open('w') as log:
        proc = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=log)
        for scene, (duration, *_rest) in enumerate(SCENES):
            print(f'Rendering scene {scene + 1}/6', flush=True)
            for n in range(duration * FPS):
                t = n / FPS
                image = frame(scene, t)
                if scene > 0 and t < .4:
                    previous = frame(scene - 1, SCENES[scene - 1][0] - .1)
                    image = Image.blend(previous, image, t / .4)
                if scene == 0 and t < .5:
                    image = Image.blend(Image.new('RGB', (W, H), '#06191E'), image, t / .5)
                proc.stdin.write(image.tobytes())
        proc.stdin.close()
        if proc.wait() != 0:
            raise SystemExit('Encoding failed; see marketing/encode-log.txt')
    print(f'Created {video}: {DURATION}s, {W}x{H}, {FPS}fps', flush=True)


if __name__ == '__main__':
    render()
