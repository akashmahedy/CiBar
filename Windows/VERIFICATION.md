# Windows preview verification

The Windows release is **1.1.0-preview.1**, intended for Windows 11 x64. The Mac release stays 1.0.2. Do not promote this preview to stable until the Windows 11 checks below are recorded.

## Automated coverage

The portable C++ tests run locally on macOS and in Windows CI. They check all 5400 entries and original serials, multilevel inclusive ranges, monotonic countdown, overlapping card/sleep/manual pause, delay changes, sequence/previous wrapping, random cycles and cycle boundaries, Favorites intersection, jump constraints, empty selection, CSV quotes/BOM/Unicode, partial examples, invalid serials, malformed imports, atomic persistence, unsupported backups and recovery-write failure.

The compatibility fixture is **synthetic**, exported by the existing Mac `Sources/Model.swift`, with examples, custom words, Favorites and paused progress. Windows reads and re-exports it; the actual Mac Codable model reads that result. The shared date uses seconds since 2001-01-01, matching Swift. No personal backup is committed or uploaded.

Windows CI builds optimized x64 with static C++ runtime, runs the core tests, and attempts an app-owned GUI smoke. That smoke creates compositor surfaces and native Settings/Library/Card windows; **Windows Server CI is not real Windows 11 visual verification**. A smoke failure is reported separately rather than hidden by a passing core-test result.

## Required Windows 11 desktop checks

- Record Windows version/build, CPU, RAM, app version and display scaling.
- First launch places the pill above the primary taskbar. Drag, lock, reset, restart, multi-monitor movement and disconnected-monitor recovery work without covering taskbar buttons.
- Test 100%, 125%, 150% and 200% scaling, light/dark, Reduced Motion and high-contrast. Hanzi and tone marks remain readable; long text ellipsizes; short text shrinks.
- Word changes do not interrupt typing in another app. Smooth fill counts down without a seconds label.
- A fullscreen app, including toggling fullscreen without changing foreground app, hides the pill and pauses. Leaving fullscreen resumes the remaining time.
- Reading card, manual pause, screen lock and sleep overlap safely. Closing a card does not cancel manual pause; restart retains the word and remaining time.
- Check all Study/Appearance controls, library search/Favorites, jump, copy, dictionary/source buttons, CSV/TSV import and backup restore.
- Move a Mac backup to Windows and a Windows backup to Mac; confirm selected word, ranges, Favorites, custom examples and remaining time. Windows position and login startup stay local.
- Optional login startup stays off initially, enables for the current executable path and disables cleanly. App runs without administrator rights.

## Performance

No Windows 11 measurements are claimed yet. Run `tools/measure.ps1 -ProcessId <PID>` with normal HSK4/45-second playback, card/settings/library closed, for five minutes. Target: mean app CPU ≤1% **of one core**, private working set ≤60 MiB. Record average/peaks and raw samples; reported CPU is not Task Manager's all-core-normalized percentage. Compositor/GPU power and battery life require separate measurement and must not be inferred from app CPU.

Attach real Windows 11 screenshots and the measurement JSON to a stable release only after these checks. Until then the downloadable app remains a clearly labelled preview, with build/test results in [GitHub Actions](https://github.com/akashmahedy/CiBar/actions/workflows/windows.yml).
