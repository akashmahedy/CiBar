# CíBar project website

Static HTML/CSS with a small optional theme selector. No framework, external fonts, analytics, account flow or build step. Published from this directory by `.github/workflows/pages.yml`.

## Preview

From the repository root:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory website
```

Open http://127.0.0.1:8765/. Check the full page in light, dark and system appearance; keyboard navigation; reduced motion; widths 320, 390, 768, 1024 and 1440. The video is user-controlled and does not autoplay.

## Assets

- `pill-*.webp` and `word-card*.webp`: captures from CíBar’s real native AppKit views, with isolated bundled vocabulary rather than personal data.
- `demo.mp4`: the existing 25-second native-UI demonstration, with shortened timing and no audio. A descriptive transcript is in the page.
- `demo-poster.png`: sharing preview; WebP version used for the video poster.
- `study-desk*.webp`: AI-generated supporting editorial photograph, not an app screenshot. Responsive sizes are 600 and 1200 pixels wide.

## Content safeguards

Preserve the homepage canonical URL, Google verification token, SoftwareApplication schema identity, original anchors (`main`, `features`, `alternatives`, `download`), navigation labels and security/license disclosures. Mac is stable; Windows is a preview with Windows 11 GUI/resource tests pending. Confirm release URLs against the uploaded assets before changing downloads. Counts come from `Resources/words.json`; the source caveats remain visible. Comparisons link to the developers’ official listings and describe workflow differences rather than complete feature parity.

Appearance follows the system by default. An explicit choice is saved only in the browser’s local storage. The page, download links and disclosures work without JavaScript.
