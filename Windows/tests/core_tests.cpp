#include "core.hpp"
#include <iostream>
using namespace cibar;
void check(bool value, const std::string &name) {
  require(value, "TEST FAILED: " + name);
}
template <class F> bool rejects(F f) {
  try {
    f();
    return false;
  } catch (...) {
    return true;
  }
}
int main(int argc, char **argv) {
  try {
    require(argc >= 2, "Resources path required.");
    fs::path resource = argv[1];
    auto words =
        json::parse(readText(resource / "words.json")).get<std::vector<Word>>();
    validateWords(words);
    check(words.size() == 5400, "5400 public words");
    int counts[] = {0, 300, 200, 500, 1000, 1600, 1800};
    for (int l = 1; l <= 6; l++) {
      int serial = 1;
      for (auto &w : words)
        if (w.level == l)
          check(w.serial == serial++, "level-local serials");
      check(serial - 1 == counts[l], "level count");
    }
    Settings s;
    s.levels = {3, 4};
    s.ranges = {{"3", {20, 22}}, {"4", {100, 101}}};
    s.validate();
    check(s.key() == "hsk2025|3:20-22,4:100-101|false|false",
          "Swift selection key");
    auto selected = Playback::select(words, s, {});
    check(selected.size() == 5 && selected[0].serial == 20 &&
              selected[4].serial == 101,
          "inclusive multiple ranges");
    double time = 100;
    Playback p([&] { return time; });
    p.configure(selected, s, std::nullopt);
    time += 7;
    check(p.left() == 38, "monotonic timer");
    p.block("card", true);
    p.block("sleep", true);
    p.block("card", false);
    time += 50;
    check(p.paused() && p.left() == 38, "overlapping blockers");
    p.toggle();
    p.block("sleep", false);
    check(p.paused() && p.manual, "manual pause survives card/sleep");
    p.changeInterval(90);
    check(p.left() == 76, "interval fraction");
    for (int i = 0; i < 5; i++)
      p.advance();
    check(p.current()->id == selected[0].id, "sequential wrap");
    p.advance(-1);
    check(p.current()->id == selected.back().id, "previous wrap");
    check(!p.jump("outside") && p.jump(selected[2].id),
          "jump selection constraint");
    auto snap = p.snapshot();
    Playback resumed([&] { return time; });
    resumed.configure(selected, s, snap);
    check(resumed.current()->id == p.current()->id && resumed.manual,
          "saved session");
    s.random = true;
    p.configure(selected, s, std::nullopt);
    std::set<std::string> seen;
    for (int i = 0; i < 5; i++) {
      seen.insert(p.current()->id);
      p.advance();
    }
    check(seen.size() == 5, "random cycle unique");
    auto last = p.current()->id;
    for (int i = 0; i < 4; i++)
      p.advance();
    last = p.current()->id;
    p.advance();
    check(p.current()->id != last, "random cycle boundary");
    s.favoritesOnly = true;
    check(Playback::select(words, s, {selected[1].id}).size() == 1,
          "favorite intersection");
    p.configure({}, s, std::nullopt);
    p.advance();
    check(!p.current() && !p.jump("outside"), "empty selection");
    auto imported =
        importWords("\xef\xbb\xbfserial,hanzi,pinyin,english,example_hanzi,"
                    "example_pinyin,example_english\r\n1,你好,nǐ hǎo,\"hello, "
                    "hi\",你好。,Nǐ hǎo.,Hello.\r\n",
                    ',', "custom-test");
    check(imported.size() == 1 && imported[0].english == "hello, hi" &&
              imported[0].example->english == "Hello.",
          "quoted UTF-8 CSV / BOM");
    check(rejects([&] {
            importWords(
                "serial,hanzi,pinyin,english\n1,好,hǎo,good\n1,好,hǎo,good",
                ',', "test");
          }),
          "duplicate serial rejected");
    check(rejects([&] {
            importWords("serial,hanzi,pinyin,english\n1,好,hǎo,\"broken", ',',
                        "test");
          }),
          "broken CSV");
    check(rejects([&] {
            importWords("serial,hanzi,pinyin,english,example_hanzi,example_"
                        "pinyin,example_english\n1,好,hǎo,good,,hǎo,good",
                        ',', "test");
          }),
          "partial example");
    check(rejects([&] {
            importWords("serial,hanzi,pinyin,english\n1x,好,hǎo,good", ',',
                        "test");
          }),
          "noninteger serial");
    check(rejects([&] {
            importWords(std::string("serial,hanzi,pinyin,english\n1,") +
                            char(0xff) + ",hao,good",
                        ',', "test");
          }),
          "malformed UTF-8 rejected before import");
    auto invalid = Settings{};
    invalid.interval = std::nan("");
    check(rejects([&] { invalid.validate(); }), "nonfinite settings");
    Settings display;
    display.showLevel = display.showSerial = display.showHanzi =
        display.showPinyin = display.showMeaning = false;
    check(display.title(words[0]) == "CíBar", "empty display fallback");
    auto dir = fs::temp_directory_path() / ("CiBar-test-" + Store::stamp());
    fs::create_directories(dir);
    Store store(dir, resource);
    store.data.customWords = imported;
    store.data.settings = s;
    store.data.favorites = {selected[1].id};
    store.data.sessions[s.key()] = snap;
    store.save();
    Store read(dir, resource);
    check(json(read.data) == json(store.data), "atomic persistent state");
    auto backup = store.backup();
    auto decoded = decodeBackup(json(backup));
    check(json(decoded.data) == json(store.data) &&
              decoded.words.size() == 5400,
          "backup roundtrip");
    check(std::abs(decoded.createdAt -
                   (std::chrono::duration<double>(
                        std::chrono::system_clock::now().time_since_epoch())
                        .count() -
                    978307200.0)) < 5,
          "Swift reference date");
    auto before = json(store.data);
    check(rejects([&] {
            store.restore(json(backup),
                          [](const fs::path &, const std::string &) {
                            throw std::runtime_error("disk full");
                          });
          }),
          "recovery failure blocks restore");
    check(json(store.data) == before &&
              readText(dir / "state.json") == json(store.data).dump(2),
          "rejected restore untouched");
    auto bad = json(backup);
    bad["version"] = 99;
    check(rejects([&] { store.restore(bad); }), "unknown version rejected");
    auto fractional = json(backup);
    fractional["data"]["settings"]["levels"] = {4.5};
    check(rejects([&] { store.restore(fractional); }),
          "fractional JSON level rejected");
    auto overflowing = json(backup);
    overflowing["version"] = 4294967297ULL;
    check(rejects([&] { store.restore(overflowing); }),
          "oversized JSON integer rejected");
    auto changed = backup;
    changed.data.settings.interval = 90;
    changed.licenses = "Restored fixture licenses";
    check(rejects([&] {
            store.restore(
                json(changed), [](const fs::path &p, const std::string &t) {
                  if (p.filename() == "state.json")
                    throw std::runtime_error("mid-restore disk failure");
                  atomicText(p, t);
                });
          }),
          "mid-restore failure rejected");
    check(json(store.data) == before &&
              !fs::exists(dir / "restored-words.json") &&
              !fs::exists(dir / "restore-pending.json"),
          "mid-restore rolls back active files and memory");
    store.restore(json(changed));
    check(fs::exists(dir / "restored-words.json"),
          "restore persists vocabulary");
    Store reopened(dir, resource);
    check(reopened.licenses == changed.licenses &&
              reopened.data.settings.interval == 90,
          "restored licenses and state survive restart");
    auto recovery = dir / "before-restore-simulated-crash.json";
    atomicText(recovery, json(changed).dump(2));
    atomicText(dir / "restore-pending.json",
               json{{"recovery", recovery.filename().string()},
                    {"hadWords", true},
                    {"hadLicenses", true}}
                   .dump());
    atomicText(dir / "state.json", json(backup.data).dump());
    atomicText(dir / "restored-licenses.txt", "partial replacement");
    Store recovered(dir, resource);
    check(recovered.data.settings.interval == 90 &&
              recovered.licenses == changed.licenses &&
              !fs::exists(dir / "restore-pending.json"),
          "startup recovers interrupted transaction");
    if (argc >= 3) {
      auto mac = decodeBackup(json::parse(readText(argv[2])));
      check(mac.data.settings.key() == "hsk2025|1:1-300,4:1-1000|false|false",
            "Mac-produced backup key");
      check(mac.data.customWords[0].example->pinyin == "Nǐ hǎo.",
            "Mac example Unicode");
      check(mac.data.sessions.at(mac.data.settings.key()).remaining == 17.5,
            "Mac saved remaining");
      if (argc >= 4)
        atomicText(argv[3], json(mac).dump(2));
    }
    fs::remove_all(dir);
    std::cout << "CíBar core tests passed: data, playback, CSV, persistence, "
                 "restore safety, Mac contract.\n";
    return 0;
  } catch (const std::exception &e) {
    std::cerr << e.what() << "\n";
    return 1;
  }
}
