"""Edit the supplied recording into a Bangla 1080p landscape tutorial.

Run: python marketing/render_recorded_tutorial.py [source.mp4]
Dependencies and Bengali shaping helpers are shared with render_promo.py.
Install edge-tts as well for the Bengali narration (network access required).
The source soundtrack is intentionally replaced with original instrumental music.
"""
from pathlib import Path
import subprocess
import sys
import json
import asyncio
import re
import edge_tts
from PIL import Image, ImageDraw
import imageio_ffmpeg
import render_promo as design

OUT = Path(__file__).resolve().parent
WORK = OUT / 'tutorial-edit'
WORK.mkdir(exist_ok=True)
SOURCE = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r'C:\Users\MIS-PC\Videos\Recording 2026-10-05 154129.mp4')
FF = imageio_ffmpeg.get_ffmpeg_exe()
# Actual recording time ranges; exclude the failed OTP, personal profile,
# downloads and previous tickets, which are unrelated to this reservation.
SCENES = [
    (192, 3, 'আপনার যাত্রার সহকারী', ['ট্রেনের টিকিট খোঁজা', 'এবার আরও সহজ'], ['ট্রেন খুঁজুন, আসনের খোঁজ রাখুন।', 'পেমেন্টের শেষ ধাপ আপনার হাতে।']),
    (0, 6, 'ধাপ ১ · স্টেশন', ['কোথা থেকে', 'কোথায় যাবেন?'], ['স্টেশনের নাম লিখুন।', 'তালিকা থেকে সঠিক স্টেশন বেছে নিন।']),
    (6, 10, 'ধাপ ২ · যাত্রা', ['তারিখ ও শ্রেণি', 'বেছে নিন'], ['যাত্রার দিন এবং আসনের শ্রেণি ঠিক করুন।', 'তারপর ট্রেন অনুসন্ধান করুন।']),
    (23, 9, 'ধাপ ৩ · ট্রেন', ['আপনার ট্রেন', 'বেছে নিন'], ['সময়, ভাড়া ও আসনের সংখ্যা দেখুন।', 'পছন্দের ট্রেনের অটো-বুকিং খুলুন।']),
    (33, 7, 'ধাপ ৪ · অটো-বুকিং', ['কতটি আসন', 'প্রয়োজন?'], ['শ্রেণি ও আসনের সংখ্যা বেছে নিন।', 'তারপর অটো-বুকিং শুরু করুন।']),
    (59, 5, 'ধাপ ৫ · অপেক্ষা', ['আসনের খোঁজ', 'রাখবে Rail Pro'], ['অটো-বুকিংয়ের অগ্রগতি দেখুন।', 'পরের ধাপের নির্দেশনা অনুসরণ করুন।']),
    (48, 5, 'প্রয়োজনে · নিরাপত্তা যাচাই', ['যাচাই প্রয়োজন?', 'অ্যাপে ফিরে আসুন'], ['মানব যাচাই চাইলে তা সম্পন্ন করুন।', 'এরপর বুকিং প্রক্রিয়া এগিয়ে যাবে।']),
    (82, 8, 'ধাপ ৬ · ওটিপি', ['ওটিপি', 'যাচাই করুন'], ['ফোনে আসা ওটিপি দিয়ে যাচাই করুন।', 'অনুমতি দিলে স্বয়ংক্রিয় যাচাই ব্যবহার করুন।']),
    (126, 4, 'ধাপ ৭ · চেকআউট', ['যাচাই সফল', 'এবার পেমেন্ট'], ['পেমেন্টের পাতা খুলবে।', 'সময় শেষ হওয়ার আগেই এগিয়ে যান।']),
    (134, 7, 'ধাপ ৮ · পেমেন্ট', ['পেমেন্ট পদ্ধতি', 'বেছে নিন'], ['মোট ভাড়া ও শর্ত দেখে নিন।', 'আপনার পছন্দের মাধ্যমে পেমেন্ট করুন।']),
    (148, 4, 'শেষ ধাপ · আপনার হাতে', ['পেমেন্ট সম্পন্ন হলে', 'টিকিট নিশ্চিত হবে'], ['পেমেন্টের তথ্য দিন এবং নিশ্চিত করুন।', 'এই ডেমোতে পেমেন্ট সম্পন্ন করা হয়নি।']),
    (192, 3, 'Rail Pro · আপনার পরবর্তী যাত্রায়', ['খুঁজুন। যাচাই করুন।', 'পেমেন্ট করুন।'], ['সহজ অনুসন্ধান থেকে পেমেন্ট পর্যন্ত।', 'আপনার যাত্রায় সঙ্গে থাকুক Rail Pro।']),
]
NARRATION = [
    'ট্রেনের টিকিট খোঁজা এবার আরও সহজ।',
    'কোথা থেকে কোথায় যাবেন? স্টেশনের নাম লিখে তালিকা থেকে বেছে নিন।',
    'যাত্রার তারিখ এবং আসনের শ্রেণি ঠিক করুন। তারপর ট্রেন অনুসন্ধান করুন।',
    'ট্রেনের সময়, ভাড়া এবং আসনের সংখ্যা দেখুন। পছন্দের ট্রেনের অটো বুকিং খুলুন।',
    'আসনের শ্রেণি এবং সংখ্যা বেছে নিন। এবার অটো বুকিং শুরু করুন।',
    'রেল প্রো আসনের খোঁজ রাখবে। অ্যাপে অগ্রগতি দেখুন।',
    'মানব যাচাই প্রয়োজন হলে অ্যাপে ফিরে তা সম্পন্ন করুন।',
    'ফোনে আসা ওটিপি যাচাই করুন। অনুমতি দিলে স্বয়ংক্রিয় যাচাই ব্যবহার করতে পারবেন।',
    'ওটিপি যাচাই সফল। এবার পেমেন্টের ধাপ।',
    'মোট ভাড়া এবং শর্ত দেখে পেমেন্ট পদ্ধতি বেছে নিন।',
    'পেমেন্ট সম্পন্ন করলেই টিকিট নিশ্চিত হবে।',
    'আপনার পরবর্তী যাত্রায় সঙ্গে থাকুক রেল প্রো।',
]

async def voices():
    limit = asyncio.Semaphore(3)
    async def create(index, text):
        async with limit:
            path = WORK / f'voice-{index:02}.mp3'
            if not path.exists():
                await edge_tts.Communicate(text, 'bn-BD-PradeepNeural', rate='+5%').save(str(path))
    await asyncio.gather(*(create(i, t) for i, t in enumerate(NARRATION)))

def narration_audio():
    asyncio.run(voices())
    for index, scene in enumerate(SCENES):
        path = WORK / f'voice-{index:02}.mp3'
        probe = subprocess.run([FF, '-i', str(path)], capture_output=True).stderr.decode(errors='replace')
        match = re.search(r'Duration: (\d+):(\d+):([\d.]+)', probe)
        h, m, s = map(float, match.groups())
        seconds = h * 3600 + m * 60 + s
        target = scene[1]
        tempo = max(1, seconds / (target - .25))
        run(['-i', str(path), '-af', f'atempo={tempo:.5f},adelay=100:all=1,apad',
             '-t', str(target), '-ar', '48000', '-ac', '2', str(WORK / f'voice-{index:02}.wav')])
    listing = WORK / 'voice-files.txt'
    listing.write_text(''.join(f"file '{(WORK / f'voice-{i:02}.wav').as_posix()}'\n" for i in range(len(SCENES))), encoding='utf-8')
    audio = OUT / 'tutorial-narration-bn.wav'
    run(['-f', 'concat', '-safe', '0', '-i', str(listing), '-c:a', 'pcm_s16le', str(audio)])
    return audio

def run(args):
    result = subprocess.run([FF, '-hide_banner', '-loglevel', 'error', '-y', *args], capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace'))

def background(index, scene):
    _, _, badge, titles, lines = scene
    canvas = design.BG.copy()
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((1240, 69, 1786, 1007), 40, fill='#092024', outline='#396A60', width=3)
    canvas.alpha_composite(design.LOGO.resize((76, 76)), (104, 83))
    design.put_text(canvas, 'Rail Pro', (202, 104), 43, True)
    d.rounded_rectangle((108, 251, 1098, 313), 18, fill='#0B4237')
    design.put_text(canvas, badge, (128, 268), 30, True, '#93E5C7', 920)
    for n, title in enumerate(titles):
        design.put_text(canvas, title, (108, 388 + n * 120), 83, True,
                        '#F2FCF8' if n == 0 else '#32D6A3', 1040)
    for n, line in enumerate(lines):
        design.put_text(canvas, line, (112, 670 + n * 68), 34, False, '#A9C9BE', 1020)
    design.put_text(canvas, 'অ্যাপ ব্যবহার নির্দেশিকা', (112, 917), 27, False, '#83A79A')
    design.put_text(canvas, 'বাংলাদেশ রেলওয়ের অফিসিয়াল অ্যাপ নয়', (112, 967), 23, False, '#789B8F')
    for n in range(len(SCENES)):
        x = 108 + n * 143
        d.rounded_rectangle((x, 1035, x + 129, 1041), 3,
                           fill='#2AD19E' if n <= index else '#29483F')
    return canvas.convert('RGB')

def render():
    if not SOURCE.exists():
        raise FileNotFoundError(SOURCE)
    total = sum(s[1] for s in SCENES)
    previews = []
    for index, scene in enumerate(SCENES):
        start, duration, *_ = scene
        bg = WORK / f'background-{index:02}.png'
        background(index, scene).save(bg)
        clip = WORK / f'chapter-{index:02}.mp4'
        print(f'Chapter {index + 1}/{len(SCENES)}: source {start}–{start + duration}s', flush=True)
        run(['-loop', '1', '-framerate', '30', '-i', str(bg),
             '-ss', str(start), '-t', str(duration), '-i', str(SOURCE),
             '-filter_complex', f'[1:v]setpts=PTS-STARTPTS,setsar=1[screen];[0:v][screen]overlay=1260:90:shortest=1,fade=t=in:st=0:d=0.18,fade=t=out:st={duration-.18}:d=0.18[v]',
             '-map', '[v]', '-an', '-t', str(duration), '-r', '30',
             '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '19', '-pix_fmt', 'yuv420p', str(clip)])
        preview = WORK / f'preview-{index:02}.jpg'
        run(['-ss', str(min(1.5, duration / 2)), '-i', str(clip), '-frames:v', '1', str(preview)])
        previews.append(preview)
    concat = WORK / 'chapters.txt'
    concat.write_text(''.join(f"file '{(WORK / f'chapter-{n:02}.mp4').as_posix()}'\n" for n in range(len(SCENES))), encoding='utf-8')
    design.DURATION = total
    design.OUT = WORK
    music = design.music()
    voice = narration_audio()
    output = OUT / 'rail-pro-tutorial-bn-landscape.mp4'
    run(['-f', 'concat', '-safe', '0', '-i', str(concat), '-i', str(music), '-i', str(voice),
         '-filter_complex', f'[1:a]volume=0.18,afade=t=in:d=1,afade=t=out:st={total-2}:d=2[m];[2:a]loudnorm=I=-16:TP=-2:LRA=8[v];[v][m]amix=inputs=2:normalize=0,alimiter=limit=0.95[a]',
         '-map', '0:v', '-map', '[a]', '-c:v', 'copy',
         '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2', '-t', str(total), '-movflags', '+faststart', str(output)])
    # Regenerate the poster from the encoded recording, not a separate mockup.
    run(['-ss', '1.5', '-i', str(output), '-frames:v', '1', str(OUT / 'tutorial-cover.jpg')])
    sheet = Image.new('RGB', (1440, 1080), '#071C22')
    for n, path in enumerate(previews):
        sheet.paste(Image.open(path).resize((480, 270)), ((n % 3) * 480, (n // 3) * 270))
    sheet.save(OUT / 'tutorial-storyboard.jpg', quality=94)
    (OUT / 'tutorial-cuts.json').write_text(json.dumps({'source': str(SOURCE), 'duration_seconds': total,
        'language': 'bn', 'scenes': [{'source_start': s[0], 'duration': s[1], 'chapter': s[2],
        'title': s[3], 'instruction': s[4], 'narration': NARRATION[i]} for i, s in enumerate(SCENES)]}, ensure_ascii=False, indent=2), encoding='utf-8')
    def timestamp(seconds):
        return f'{seconds // 3600:02}:{seconds // 60 % 60:02}:{seconds % 60:02},000'
    elapsed = 0
    captions = []
    for i, scene in enumerate(SCENES):
        end = elapsed + scene[1]
        captions.append(f'{i + 1}\n{timestamp(elapsed)} --> {timestamp(end)}\n{NARRATION[i]}\n')
        elapsed = end
    (OUT / 'tutorial-bn.srt').write_text('\n'.join(captions), encoding='utf-8')
    print(f'Created {output} ({total}s)', flush=True)

if __name__ == '__main__':
    render()
