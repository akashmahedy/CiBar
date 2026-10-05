# Contributing

Please open an issue before a large change. Keep changes focused and explain the user-visible behavior.

Build on an Apple Silicon Mac with `zsh Tools/build.sh`; self-tests run automatically. For Intel, use `zsh Tools/build.sh --intel` and run the resulting app's `--self-test` on Intel hardware. Check the actual menu-bar UI after display changes, including long meanings, large fonts, pause/resume and light/dark appearance.

For vocabulary corrections, include level, serial, Hanzi, proposed Pinyin/English and a reliable source. Keep third-party attribution and licenses intact. Never imply that an automatically generated sentence reading was independently checked.

Do not commit personal state, exported backups, raw local source snapshots, credentials or unrelated screenshots. Public release ZIPs must contain only the app and its bundled resources. `Tools/release.sh` does not access the user's data folder.
