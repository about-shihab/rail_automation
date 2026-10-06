# Rail Pro recorded tutorial

The 71-second Bangla landscape tutorial uses selected moving sections of the user-provided `Recording 2026-10-05 154129.mp4` rather than staged screenshots. It introduces the app's purpose and follows station selection, journey options, train results, auto-booking, human verification, OTP and user-completed payment.

## Deliverables

- `rail-pro-tutorial-bn-landscape.mp4`: 1920×1080, 30 fps, H.264/yuv420p, AAC stereo 48 kHz, fast start.
- `tutorial-cover.jpg`: cover taken from the encoded video.
- `tutorial-storyboard.jpg`: twelve chapter previews taken from the encoded chapters.
- `tutorial-bn.srt`: optional Bangla subtitle file, in addition to the on-screen instructions.
- `tutorial-narration-bn.wav`: synthesized Bangla narration; Microsoft Bengali Bangladesh Pradeep voice through edge-tts.
- `tutorial-cuts.json`: original timestamps, instructions and narration for each chapter.
- `render_recorded_tutorial.py`: editable rendering source.

The source microphone audio is excluded. Original instrumental music is mixed quietly beneath the narration. The recording is unchanged. Long waits, the failed OTP attempt, entered OTP codes, passenger contact details, profile phone number, browser downloads and previous tickets are excluded from the final video. Payment is shown up to the blank bKash account input; this recording does not demonstrate a completed payment or a newly confirmed ticket. The video says payment is required and identifies Rail Pro as independent of the official Railway app.

## Rebuild

Requires Python, Pillow, NumPy, uharfbuzz, freetype-py, imageio-ffmpeg and edge-tts. The shared renderer uses Windows Nirmala fonts for Bengali shaping. Narration generation requires network access; generated chapter speech is cached in `tutorial-edit`.

```powershell
python marketing/render_recorded_tutorial.py 'C:\Users\MIS-PC\Videos\Recording 2026-10-05 154129.mp4'
```

This is a separate deliverable from the earlier 31-second screenshot-based promo.
