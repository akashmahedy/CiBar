# Performance and verification

Local measurements on 2026-10-05: Apple M1, 8 GiB RAM, macOS 27.0.1. Default HSK4 sequential playback, 45 seconds, smooth fill. macOS `top`, 5-second samples, initial sample excluded. CPU percentages are of one core; memory is physical footprint in MiB.

| Process | Duration | Valid samples | Mean CPU | Peak CPU | Mean memory | Peak memory |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Earlier SwiftBar implementation | 61.43 s | 12 | 31.267% | 32.8% | 59.25 MiB | 71 MiB |
| Earlier animation helper | same interval | 12 | 9.267% | 9.8% | 7.65 MiB | 7.91 MiB |
| Native CíBar 1.0.1 | 305.53 s | 60 | 0.738% | 6.5% | 48.55 MiB | 52 MiB |
| Final 1.0.1 smoke check | 15.69 s | 3 | 0.767% | 1.2% | 50.67 MiB | 52 MiB |

The old two-process mean was 40.534% CPU. CíBar's five-minute app CPU mean was about 98.2% lower and met the intended ≤1% CPU and ≤60 MiB targets on this machine. Sample durations differ; results are indicative and not promises across hardware or settings. Version 1.0.2 adds creator credit without changing playback or animation; these measurements are from 1.0.1.

WindowServer mean CPU was 48.067% for the earlier implementation and 45.805% during the native sample. These whole-desktop values include other apps and UI capture; they do not isolate CíBar's compositor cost. Core Animation uses the compositor. GPU energy, power and battery life were not measured.

Local self-tests cover all 5400 word rows and serials, multilevel ranges, sequence wrapping, random cycles, pause reasons, delay changes, jump, favorites, display fallback, import errors, state/backup roundtrips, recovery-write failure, animation and adaptive/fixed widths. The default supplied palette tests have a minimum text contrast ratio of 4.89:1; wallpaper and custom settings affect perceived contrast.

Real UI checks included appearance controls, word-card examples, library search, favorites, import and backup export/restore. The Apple Silicon app has a valid local ad-hoc signature and is arm64-only. It is not Apple-notarized. Physical Intel hardware, macOS 13 and macOS 28 have not been tested locally. CI results are shown separately in [Actions](https://github.com/akashmahedy/CiBar/actions).
