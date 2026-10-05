# CíBar for Windows 11 — Preview

Created by **Akash Mahedy · @akashmahedy**. Native C++20 / Win32, offline, no subscription. This Windows edition is a **prerelease** until real Windows 11 GUI and performance checks are completed. GitHub's Windows Server CI is not Windows 11 desktop validation.

## Install

Download `CiBar-Windows-x64.zip` from [Releases](https://github.com/akashmahedy/CiBar/releases). Extract the entire ZIP to a folder you will keep (for example, Documents/CiBar), then open `CiBar.exe`. Keep the Resources folder beside the executable. Targets Windows 11 on Intel/AMD x64. No administrator rights, .NET, Electron, Windhawk or separate Visual C++ runtime installation is required. The initial preview is unsigned; Windows SmartScreen may prompt. Review the source and publisher credit. No security settings are changed by the app.

The pill starts above the taskbar at the bottom right of the primary monitor. Drag to move it; right-click for **Lock position** or **Reset position**. A tray icon provides **Show/Hide, Settings, Word library, Pause and Quit**. If Windows puts the icon in its overflow area, use the tray arrow to find it.

## Study and appearance

Default: HSK4, sequential, 45 seconds, adaptive width capped at 260. Select HSK 1–4 to include all 2000 words through level 4. The 2025 HSK 3.0 exam-syllabus pack has 5400 entries in levels 1–6; numbering restarts in each level. Ranges are inclusive. Random plays each selected entry once per cycle.

Click the pill for full Hanzi, Pinyin, meaning, example, copy, dictionary and source. Reading pauses playback; closing the card resumes the remaining time. Manual pause remains paused. Sleep, lock, hiding the pill and fullscreen apps also pause the timer. Word changes do not take focus.

Settings has Study, Appearance, and Data & Backup pages. Appearance toggles apply immediately; enter font, width or hex values then click their Apply button. Font 9–18 pt, width 80–600 logical pixels. Presets and fill contrast are configurable. Long text is ellipsized in the pill. Windows Reduced Motion uses one-second updates; high-contrast mode uses system colors and disables the decorative fill for legibility.

Library searches Hanzi/Pinyin/English and can filter Favorites. Open a card to favorite a word. Jump accepts entries inside your current study selection. Optional startup at login is off by default; enable it in Study. Move the app before enabling startup; if you move it later, re-enable startup from the new path.

## Backups and privacy

Local data: `%LOCALAPPDATA%\CiBar\`. No background network calls, analytics or cloud sync. Dictionary/source links open public sites only on click.

**Export backup / Restore backup** uses the same `CiBarBackup` version 1 format as Mac. Vocabulary, custom lists, settings, Favorites, random order and progress transfer; Windows pill position and login startup are local and do not transfer. Recovery backups are saved before restore; failed recovery writes block restore.

Import UTF-8 CSV/TSV with `serial,hanzi,pinyin,english`; optional `example_hanzi,example_pinyin,example_english` must all be filled if an example is provided. Quote CSV commas. Invalid imports are rejected without changing the list.

3071 words have examples. Automatic example Pinyin is labelled and can need correction; examples may use a different sense. Missing examples are stated. Sources and licenses are in Resources/ATTRIBUTIONS.txt. Code and original assets are MIT; third-party vocabulary/examples have separate Creative Commons licenses. JSON library: nlohmann/json 3.12.0, MIT.

## Build and verify

Requires Visual Studio 2022+ C++ desktop build tools, the Windows SDK, CMake 3.24+, and PowerShell. From the repository root:

```powershell
./Windows/tools/build.ps1
./Windows/tools/build.ps1 -Smoke
./Windows/tools/package.ps1
```

The compiler links the C++ runtime statically. The prepared vocabulary and pinned JSON header are bundled; no build-time package download is needed. `cibar-tests` checks playback, validation, persistence and Mac backup compatibility. GUI smoke creates the app's own windows and compositor surfaces; it does not certify appearance on Windows 11. See [verification checklist](VERIFICATION.md) before promoting the preview to stable.
