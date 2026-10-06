# Rail Pro website

The landing page defaults to Bengali and supports English through a persistent language switch. It is a compact responsive static website with an animated route illustration, booking walkthrough, four feature cards, optional app screenshots, FAQ, and Android download link. The copy explains returned tickets, added coaches, seat alerts, and optional automatic reservation; payment remains a user step. It requires no build step.

Preview from the repository root:

```powershell
python -m http.server 8765 --bind 127.0.0.1
```

Open http://127.0.0.1:8765/docs/ (or the root page). `docs/index.html` is the GitHub Pages entry point. The root `index.html` mirrors it with adjusted asset paths.

Styles and interaction live in `docs/website.css` and `docs/website.js`. The interactive journey is a demonstration; it makes no Railway requests. Animations respect reduced-motion preferences and pause when the tab is hidden. Images and icons are local; Google Fonts is optional and has system-font fallbacks.

`docs/privacy.html` renders the repository privacy policy. Regenerate it when the source policy changes.

When changing the download destination, update `#download-link` in both HTML entry points. Link to a verified release asset rather than a debug APK.
