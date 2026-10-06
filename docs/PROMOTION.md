# CíBar demo media

These assets show the Mac edition. The Mac edition is stable; Windows 11 remains a preview with real-device GUI and performance checks pending.

- [README GIF](assets/demo.gif): 960 × 540, 12.5 seconds, looping.
- [Landscape video](assets/demo-landscape.mp4): 1280 × 720, 25 seconds, H.264 MP4, 30 fps.
- [Portrait video](assets/demo-vertical.mp4): 1080 × 1920, 25 seconds, H.264 MP4, 30 fps.

The videos have no audio and use on-screen captions. They show a shrinking fill, the full word card with its sourced example, then the next word and download link.

## What the demo represents

The media renderer uses the app's real `PillView` and `WordCardController`, with bundled vocabulary, in an isolated temporary store. This is a rendered native UI demonstration, not a desktop screen recording. Timing is shortened and the click indicator is editorial. It does not change the installed app's preferences or playback. The footer states this distinction.

The displayed word card retains its data attribution: HearMandarin (CC BY 4.0), and Tatoeba sentence #323249 by CK / #845449 by Martha, selected by ManyThings.org (CC BY 2.0 France). Sentence Pinyin is automatically generated and the app's caution is visible. See [data documentation](DATA.md).

## Reproduce on macOS

With Apple Command Line Tools installed, run from the repository root:

```sh
zsh Tools/render_demo.sh
```

Outputs are placed in `../outputs/promo/`. The native renderer uses AppKit, AVFoundation and ImageIO; no additional media package is needed. The accelerated GIF uses the same scenes as the videos.

## Sharing

Link to https://akashmahedy.github.io/CiBar/ for platform downloads and installation instructions. Disclose that you created the project. Keep Windows labelled as a preview. Respect each community's promotion and AI-writing rules; do not post the same announcement repeatedly. These assets are ready for sharing, but only the destinations explicitly requested by the owner should receive posts.
