# Rail Pro promotional video

`rail-pro-promo-bn-landscape.mp4` is a 31-second Bangla promo in 1920×1080 landscape, 24 fps, H.264/AAC, with an original instrumental music bed. It has animated app previews, crossfades, and Bangla titles. There is no spoken narration.

The search, autocomplete, auto-booking, and reservation previews come from Flutter widget renders. The reservation is demo data, not a real purchase. The notification scene is an illustration of the new notification content; the outer layout varies by Android version and device. The video does not claim guaranteed availability, automatic payment, Railway affiliation, or Google Play availability.

- `poster.jpg`: cover image.
- `storyboard.jpg`: all six scenes.
- `scene-01.png` through `scene-06.png`: full-resolution scene previews.
- `promo-original-music.wav`: original audio source.
- `render_promo.py`: editable render source, including Bangla copy and timings.

To reproduce on Windows, install `pillow numpy uharfbuzz freetype-py imageio-ffmpeg`, regenerate the app captures with `flutter test test/promo_capture_test.dart test/watch_options_design_test.dart`, then run `python marketing/render_promo.py` from the repository root. HarfBuzz and FreeType shape the Bangla text correctly even when Pillow is built without Raqm. On another platform, set `FONT` and `BOLD` to local fonts that support Bengali.
