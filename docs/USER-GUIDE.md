# CíBar

A free, offline, native macOS menu-bar vocabulary app. Requires macOS 13 or later.
The main CiBar.app is Apple Silicon-only (arm64) and does not need Rosetta.
CiBar-Intel.app is a separate optional build for an Intel Mac. Its self-tests
passed under Rosetta in the earlier universal build; physical Intel hardware
has not been tested. Do not open the Intel build on an Apple Silicon Mac.

## Use

Open CíBar.app. It lives in the menu bar, without a Dock icon. Click the word
for its full Hanzi, Pinyin, English, example, source and controls. Reading
pauses the countdown; closing the card resumes the remaining time. A manual
pause stays paused. Right-click for quick controls, Settings, compact display
or Quit. Reopening the app opens Settings without starting a second instance.

Study settings allow multiple HSK levels, an inclusive serial range for each,
delay in seconds, Sequential or Random, and favorites-only playback. Blank
ranges use the whole level. Sequential sorts by level, then original serial,
then loops. Random visits each selected entry once per cycle. Jump only accepts
words inside the current selection. Sleep and logout pause the remaining time.

Appearance changes apply immediately: Level, Serial, Hanzi, Pinyin, English,
fill and background toggles; adaptive or fixed width; font size 9–18 points;
width cap 80–600 points; Ocean, Sage, Plum, Amber, Graphite or Custom color;
Soft, Balanced or Strong fill contrast. Long text is ellipsized in the bar;
the card always shows the full text. All text toggles off displays CíBar.
Compact display hides the English and caps the width at 160 points. macOS
can still hide an item if the menu bar is too crowded, especially near a notch.

Launch at Login can be enabled in Study settings. macOS may ask for approval
in System Settings → General → Login Items & Extensions. It starts disabled.

## Backup and custom lists

Settings → Data & Backup → Export backup saves a JSON file containing the
vocabulary snapshot, custom lists, settings, favorites and session progress.
Restore this file on another Mac using Restore backup. Before restoring,
CíBar saves the current state as a recovery backup in its data folder.

Custom UTF-8 CSV/TSV must have these header columns:

```text
serial,hanzi,pinyin,english
1,你好,nǐ hǎo,hello
```

Optional columns: example_hanzi, example_pinyin, example_english. All three
must be filled if an example is supplied. Quote CSV cells containing commas.
Imported lists are separate from HSK levels; positive serials must be unique.
An invalid list is rejected without replacing vocabulary.

Runtime data: `~/Library/Application Support/CiBar/`. Settings are local;
there are no analytics, background network calls or accounts. Dictionary and
example-source buttons open public source pages only when clicked.

## Vocabulary and examples

The 2025 HSK 3.0 exam syllabus is used: 300 / 200 / 500 / 1000 / 1600 / 1800
incremental words for levels 1–6, total 5400. Hanzi and level ordering were
matched against the official PDF. Serial numbers are local to each level.
HearMandarin provides the base Pinyin and English; 33 previous HSK4 correction
rows are recorded, with the weight sense of HSK4 两2 clarified.
The previous SwiftBar list is preserved as a separate migration copy.
Headword matching does not certify every translation or contextual sense.

3071 words have offline examples. Bilingual Tatoeba sentences retain sentence
IDs and contributor attribution. Most sentence Pinyin is automatically
transliterated by macOS; polyphonic readings and neutral tones can be wrong,
so the card labels this clearly. Examples may illustrate another sense of the
word. Missing examples are explicitly shown. A small original example set is
editorially checked and labelled. See Resources/ATTRIBUTIONS.txt and the data
review files for source versions, licenses and changes.

## Build and check

Requires Apple Command Line Tools; no package downloads are needed to build
from the prepared Resources/words.json. Run:

```sh
zsh Tools/build.sh
```

This compiles an optimized arm64 app, applies a local ad-hoc signature and
runs the self-tests. Use `zsh Tools/build.sh --intel` only to produce a
separate Intel app; that build is not automatically run on this Mac. The app is not
Apple-notarized or App Store distributed. On another Mac, if macOS blocks
the downloaded archive, review it and use the normal Open Anyway flow in
Privacy & Security. Do not disable Gatekeeper globally.

Core Animation animates one cached fill layer for each word interval. The app
does not encode images or stream animation frames. State is saved on word
changes or user actions. Reduce Motion uses a one-second fill update rather
than continuous animation. Tests cover word counts/serials, multilevel ranges,
looping, random cycles, overlapping pause reasons, delay changes, jump,
favorites filtering, display fallback, import rejection, state/backup
roundtrips and palette contrast. See [Performance](PERFORMANCE.md)
for actual hardware measurements and remaining limits.
