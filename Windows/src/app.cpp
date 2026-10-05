#include "render.hpp"
#include <commctrl.h>
#include <commdlg.h>
#include <iomanip>
#include <shellapi.h>
#include <shlobj.h>
#include <sstream>
#include <tuple>
#include <windowsx.h>
#include <wtsapi32.h>
using namespace cibar;
constexpr UINT TrayMessage = WM_APP + 1, ForegroundMessage = WM_APP + 2,
               ReopenMessage = WM_APP + 3;
constexpr int Next = 10, Previous = 11, Pause = 12, SettingsMenu = 13,
              LibraryMenu = 14, Hide = 15, Lock = 16, Reset = 17, About = 18,
              Quit = 19;
struct Presentation {
  bool positioned = false, locked = false, hidden = false;
  int x = 0, y = 0;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(Presentation, positioned, locked, hidden, x,
                                   y)
struct ControlRect {
  HWND hwnd;
  int x, y, w, h, page;
};
class App;
App *instance = nullptr;
LRESULT CALLBACK windowProc(HWND, UINT, WPARAM, LPARAM);
void CALLBACK foregroundEvent(HWINEVENTHOOK, DWORD, HWND, LONG, LONG, DWORD,
                              DWORD);
void CALLBACK locationEvent(HWINEVENTHOOK, DWORD, HWND, LONG, LONG, DWORD,
                            DWORD);
inline std::wstring windowText(HWND w) {
  int n = GetWindowTextLengthW(w);
  std::wstring s(size_t(n) + 1, L'\0');
  GetWindowTextW(w, s.data(), n + 1);
  s.resize(n);
  return s;
}
inline double number(HWND w) {
  auto s = utf8(windowText(w));
  size_t count;
  double n = std::stod(s, &count);
  require(count == s.size() && std::isfinite(n), "Enter a valid number.");
  return n;
}
inline int integer(HWND w) {
  double n = number(w);
  require(n >= 0 && n <= 1000000 && n == std::floor(n),
          "Enter a whole number.");
  return int(n);
}
inline std::wstring encodeURL(const std::string &s) {
  std::ostringstream out;
  out << std::hex << std::uppercase;
  for (unsigned char c : s) {
    if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~')
      out << c;
    else
      out << '%' << std::setw(2) << std::setfill('0') << int(c);
  }
  return wide(out.str());
}
class App {
public:
  HINSTANCE module;
  HWND pill = nullptr, settings = nullptr, card = nullptr, library = nullptr;
  HFONT uiFont = nullptr;
  fs::path resourceDir, dataDir, exe;
  std::unique_ptr<Store> store;
  Playback playback;
  PillRenderer renderer;
  Presentation presentation;
  std::vector<ControlRect> controls;
  std::vector<std::string> packIDs;
  std::vector<Word> visibleWords;
  std::optional<Word> preview;
  std::map<HWND, HFONT> fonts;
  std::map<HWND, SIZE> contentSizes;
  bool automated = false, failed = false, layingOut = false;
  HFONT fontFor(HWND parent) {
    auto it = fonts.find(parent);
    if (it != fonts.end())
      return it->second;
    auto f = CreateFontW(-MulDiv(10, GetDpiForWindow(parent), 72), 0, 0, 0,
                         FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                         OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                         CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    fonts[parent] = f;
    return f;
  }
  int selectedPage = 0;
  std::wstring libraryCell;
  bool libraryFavorites = false, dark = false, highContrast = false,
       reduced = false, dragging = false, moving = false;
  POINT dragStart{}, windowStart{};
  bool built = false, quitting = false;
  HWINEVENTHOOK foregroundHook = nullptr, locationHook = nullptr;
  bool fullCheckQueued = false;
  UINT taskbarCreated = 0;
  App(HINSTANCE h, fs::path root, fs::path data, fs::path executable)
      : module(h), resourceDir(std::move(root)), dataDir(std::move(data)),
        exe(std::move(executable)) {
    store = std::make_unique<Store>(dataDir, resourceDir);
    if (fs::exists(dataDir / "presentation.json")) {
      try {
        presentation = json::parse(readText(dataDir / "presentation.json"))
                           .get<Presentation>();
      } catch (...) {
        presentation = Presentation{};
      }
    }
  }
  HWND child(HWND parent, const wchar_t *cls, const std::wstring &text, int id,
             int x, int y, int w, int h, DWORD style = 0, int page = -1) {
    float s = GetDpiForWindow(parent) / 96.f;
    HWND c = CreateWindowExW(wcscmp(cls, L"EDIT") == 0 ? WS_EX_CLIENTEDGE : 0,
                             cls, text.c_str(), WS_CHILD | WS_VISIBLE | style,
                             cint(x * s), cint(y * s), cint(w * s), cint(h * s),
                             parent, reinterpret_cast<HMENU>(INT_PTR(id)),
                             module, nullptr);
    require(c != nullptr, "Could not create a Windows control.");
    SendMessageW(c, WM_SETFONT, reinterpret_cast<WPARAM>(fontFor(parent)),
                 TRUE);
    controls.push_back({c, x, y, w, h, page});
    return c;
  }
  static int cint(float x) { return int(std::round(x)); }
  HWND label(HWND p, const std::wstring &t, int x, int y, int w, int h = 24,
             int page = -1) {
    return child(p, L"STATIC", t, 0, x, y, w, h, SS_LEFT, page);
  }
  HWND button(HWND p, const std::wstring &t, int id, int x, int y, int w = 110,
              int h = 30, int page = -1) {
    return child(p, L"BUTTON", t, id, x, y, w, h, WS_TABSTOP | BS_PUSHBUTTON,
                 page);
  }
  HWND check(HWND p, const std::wstring &t, int id, bool value, int x, int y,
             int w, int page = -1) {
    auto c = child(p, L"BUTTON", t, id, x, y, w, 26,
                   WS_TABSTOP | BS_AUTOCHECKBOX, page);
    SendMessageW(c, BM_SETCHECK, value ? BST_CHECKED : BST_UNCHECKED, 0);
    return c;
  }
  HWND edit(HWND p, const std::wstring &t, int id, int x, int y, int w,
            int h = 28, int page = -1, DWORD extra = 0) {
    return child(p, L"EDIT", t, id, x, y, w, h,
                 WS_TABSTOP | ES_AUTOHSCROLL | extra, page);
  }
  HWND combo(HWND p, const std::vector<std::wstring> &items, int id,
             int selection, int x, int y, int w, int page = -1) {
    auto c = child(p, WC_COMBOBOXW, L"", id, x, y, w, 200,
                   WS_TABSTOP | CBS_DROPDOWNLIST | WS_VSCROLL, page);
    for (auto &t : items)
      SendMessageW(c, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(t.c_str()));
    SendMessageW(c, CB_SETCURSEL, selection, 0);
    return c;
  }
  bool checked(HWND p, int id) {
    return SendDlgItemMessageW(p, id, BM_GETCHECK, 0, 0) == BST_CHECKED;
  }
  int choice(HWND p, int id) {
    return int(SendDlgItemMessageW(p, id, CB_GETCURSEL, 0, 0));
  }
  void error(const std::exception &e) {
    if (automated) {
      failed = true;
      OutputDebugStringW(wide(e.what()).c_str());
      try {
        atomicText(dataDir / "smoke-error.json",
                   json{{"error", e.what()}}.dump());
      } catch (...) {
      }
      PostMessageW(pill, WM_CLOSE, 0, 0);
      return;
    }
    MessageBoxW(settings ? settings : pill, wide(e.what()).c_str(), L"CíBar",
                MB_OK | MB_ICONERROR);
  }
  void init() {
    INITCOMMONCONTROLSEX c{sizeof(c), ICC_WIN95_CLASSES | ICC_LISTVIEW_CLASSES |
                                          ICC_TAB_CLASSES};
    InitCommonControlsEx(&c);
    WNDCLASSEXW wc{sizeof(wc)};
    wc.hInstance = module;
    wc.lpfnWndProc = windowProc;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hIcon = LoadIconW(module, MAKEINTRESOURCEW(1));
    wc.hIconSm = wc.hIcon;
    wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    for (auto name :
         {L"CiBarPill", L"CiBarSettings", L"CiBarCard", L"CiBarLibrary"}) {
      wc.lpszClassName = name;
      hr(RegisterClassExW(&wc) ? S_OK : HRESULT_FROM_WIN32(GetLastError()));
    }
    pill = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE |
                               WS_EX_NOREDIRECTIONBITMAP,
                           L"CiBarPill", L"CíBar", WS_POPUP, 0, 0, 260, 32,
                           nullptr, nullptr, module, nullptr);
    require(pill != nullptr, "Could not create the vocabulary pill.");
    uiFont = CreateFontW(-MulDiv(10, GetDpiForWindow(pill), 72), 0, 0, 0,
                         FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
                         OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                         CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    renderer.init(pill);
    taskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");
    addTray();
    WTSRegisterSessionNotification(pill, NOTIFY_FOR_THIS_SESSION);
    foregroundHook =
        SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND,
                        nullptr, foregroundEvent, 0, 0, WINEVENT_OUTOFCONTEXT);
    locationHook = SetWinEventHook(EVENT_OBJECT_LOCATIONCHANGE,
                                   EVENT_OBJECT_LOCATIONCHANGE, nullptr,
                                   locationEvent, 0, 0, WINEVENT_OUTOFCONTEXT);
    applySelection();
    playback.block("hidden", presentation.hidden);
    built = true;
    refresh();
    checkFullscreen();
    if (!store->warning.empty())
      MessageBoxW(pill, wide(store->warning).c_str(), L"CíBar · Recovery",
                  MB_OK | MB_ICONINFORMATION);
  }
  void addTray() {
    NOTIFYICONDATAW n{sizeof(n)};
    n.hWnd = pill;
    n.uID = 1;
    n.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    n.uCallbackMessage = TrayMessage;
    n.hIcon = LoadIconW(module, MAKEINTRESOURCEW(1));
    wcscpy_s(n.szTip, L"CíBar · Chinese vocabulary");
    Shell_NotifyIconW(NIM_ADD, &n);
    n.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &n);
  }
  void savePresentation() {
    atomicText(dataDir / "presentation.json", json(presentation).dump(2));
  }
  void persist() {
    store->data.sessions[store->data.settings.key()] = playback.snapshot();
    store->save();
  }
  void applySelection() {
    auto &s = store->data.settings;
    auto key = s.key();
    auto it = store->data.sessions.find(key);
    playback.configure(
        Playback::select(store->allWords(), s, store->data.favorites), s,
        it == store->data.sessions.end() ? std::nullopt
                                         : std::optional<Snapshot>(it->second));
  }
  void environment() {
    HIGHCONTRASTW hc{sizeof(hc)};
    SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(hc), &hc, 0);
    highContrast = (hc.dwFlags & HCF_HIGHCONTRASTON) != 0;
    BOOL animation = TRUE;
    SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animation, 0);
    reduced = !animation || highContrast;
    DWORD light = 1, sz = sizeof(light);
    RegGetValueW(
        HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &sz);
    dark = light == 0;
  }
  MONITORINFO monitor() {
    POINT p{presentation.x, presentation.y};
    auto m = presentation.positioned
                 ? MonitorFromPoint(p, MONITOR_DEFAULTTONEAREST)
                 : MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO mi{sizeof(mi)};
    GetMonitorInfoW(m, &mi);
    return mi;
  }
  void refresh() {
    if (!built)
      return;
    environment();
    auto text = wide(playback.current()
                         ? store->data.settings.title(*playback.current())
                         : "CíBar · no words");
    SetWindowTextW(pill, text.c_str());
    auto mi = monitor();
    float dpi = float(GetDpiForWindow(pill)), scale = dpi / 96.f;
    auto [w, h] =
        renderer.measure(text, store->data.settings, dpi,
                         (mi.rcWork.right - mi.rcWork.left) / scale - 12);
    int pw = cint(w * scale), ph = cint(h * scale), gap = cint(6 * scale);
    int x =
        presentation.positioned ? presentation.x : mi.rcWork.right - pw - gap;
    int y =
        presentation.positioned ? presentation.y : mi.rcWork.bottom - ph - gap;
    x = std::clamp(x, int(mi.rcWork.left),
                   std::max(int(mi.rcWork.left), int(mi.rcWork.right) - pw));
    y = std::clamp(y, int(mi.rcWork.top),
                   std::max(int(mi.rcWork.top), int(mi.rcWork.bottom) - ph));
    SetWindowPos(pill, HWND_TOPMOST, x, y, pw, ph, SWP_NOACTIVATE);
    if (presentation.positioned) {
      presentation.x = x;
      presentation.y = y;
    }
    renderer.draw(text, store->data.settings, dark, highContrast);
    renderer.countdown(playback.fraction(), playback.left(), playback.paused(),
                       reduced);
    KillTimer(pill, 1);
    KillTimer(pill, 2);
    if (!playback.paused() && playback.current())
      SetTimer(
          pill, 1,
          UINT(std::clamp(std::ceil(playback.left() * 1000), 1.0, 86400000.0)),
          nullptr);
    if (!playback.paused() && reduced && store->data.settings.showFill)
      SetTimer(pill, 2, 1000, nullptr);
    bool visible = !presentation.hidden && !fullscreen;
    ShowWindow(pill, visible ? SW_SHOWNOACTIVATE : SW_HIDE);
    if (card)
      updateCard();
  }
  bool fullscreen = false;
  void checkFullscreen() {
    HWND f = GetForegroundWindow();
    bool full = false;
    if (f) {
      DWORD pid;
      GetWindowThreadProcessId(f, &pid);
      wchar_t cls[128];
      GetClassNameW(f, cls, 128);
      RECT r;
      MONITORINFO mi{sizeof(mi)};
      GetMonitorInfoW(MonitorFromWindow(f, MONITOR_DEFAULTTONEAREST), &mi);
      if (pid != GetCurrentProcessId() && wcscmp(cls, L"Progman") &&
          wcscmp(cls, L"WorkerW") && wcscmp(cls, L"Shell_TrayWnd") &&
          GetWindowRect(f, &r)) {
        auto pm = monitor();
        bool same = mi.rcMonitor.left == pm.rcMonitor.left &&
                    mi.rcMonitor.top == pm.rcMonitor.top;
        full = same && r.left <= mi.rcMonitor.left &&
               r.top <= mi.rcMonitor.top && r.right >= mi.rcMonitor.right &&
               r.bottom >= mi.rcMonitor.bottom;
      }
    }
    if (full != fullscreen) {
      fullscreen = full;
      playback.block("fullscreen", full);
      refresh();
      persist();
    }
  }
  void setBlock(const std::string &key, bool value) {
    playback.block(key, value);
    refresh();
    persist();
  }
  void action(int id) {
    switch (id) {
    case Next:
      preview.reset();
      playback.advance();
      refresh();
      persist();
      break;
    case Previous:
      preview.reset();
      playback.advance(-1);
      refresh();
      persist();
      break;
    case Pause:
      playback.toggle();
      refresh();
      persist();
      break;
    case SettingsMenu:
      openSettings();
      break;
    case LibraryMenu:
      openLibrary();
      break;
    case Hide:
      presentation.hidden = !presentation.hidden;
      savePresentation();
      setBlock("hidden", presentation.hidden);
      break;
    case Lock:
      presentation.locked = !presentation.locked;
      savePresentation();
      break;
    case Reset:
      presentation.positioned = false;
      savePresentation();
      refresh();
      break;
    case About:
      MessageBoxW(pill,
                  L"CíBar for Windows 1.1.0-preview.1\nCreated by Akash Mahedy "
                  L"· @akashmahedy\nNative, offline Chinese vocabulary.\nApp "
                  L"code MIT; data has separate Creative Commons "
                  L"licenses.\nhttps://github.com/akashmahedy/CiBar",
                  L"About CíBar", MB_OK);
      break;
    case Quit:
      quitting = true;
      DestroyWindow(pill);
      break;
    }
  }
  void trayMenu() {
    HMENU m = CreatePopupMenu();
    for (auto [id, text] : std::vector<std::pair<int, std::wstring>>{
             {SettingsMenu, L"Settings…"},
             {LibraryMenu, L"Word library & Favorites…"},
             {Previous, L"Previous word"},
             {Next, L"Next word"},
             {Pause, playback.manual ? L"Resume" : L"Pause"},
             {Hide, presentation.hidden ? L"Show pill" : L"Hide pill"},
             {Lock,
              presentation.locked ? L"Unlock position" : L"Lock position"},
             {Reset, L"Reset position"},
             {About, L"About CíBar"},
             {Quit, L"Quit"}})
      AppendMenuW(m, MF_STRING, id, text.c_str());
    POINT p;
    GetCursorPos(&p);
    SetForegroundWindow(pill);
    int id = TrackPopupMenu(m, TPM_RETURNCMD | TPM_NONOTIFY, p.x, p.y, 0, pill,
                            nullptr);
    DestroyMenu(m);
    PostMessageW(pill, WM_NULL, 0, 0);
    if (id)
      action(id);
  }
  HWND topWindow(const wchar_t *cls, const wchar_t *title, int width,
                 int height) {
    float scale = GetDpiForWindow(pill) / 96.f;
    auto mi = monitor();
    RECT r{0, 0, cint(width * scale), cint(height * scale)};
    AdjustWindowRectExForDpi(&r,
                             WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU |
                                 WS_MINIMIZEBOX | WS_VSCROLL | WS_HSCROLL,
                             FALSE, WS_EX_TOOLWINDOW, GetDpiForWindow(pill));
    auto w = CreateWindowExW(
        WS_EX_TOOLWINDOW, cls, title,
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_VSCROLL |
            WS_HSCROLL,
        mi.rcWork.left + ((mi.rcWork.right - mi.rcWork.left) -
                          std::min(int(r.right - r.left),
                                   int(mi.rcWork.right - mi.rcWork.left))) /
                             2,
        mi.rcWork.top + std::max(0, int(((mi.rcWork.bottom - mi.rcWork.top) -
                                         (r.bottom - r.top)) /
                                        2)),
        std::min(int(r.right - r.left), int(mi.rcWork.right - mi.rcWork.left)),
        std::min(int(r.bottom - r.top), int(mi.rcWork.bottom - mi.rcWork.top)),
        pill, nullptr, module, nullptr);
    require(w != nullptr, "Could not create the app window.");
    contentSizes[w] = {width, height};
    return w;
  }
  void clearControls(HWND parent) {
    for (auto it = controls.begin(); it != controls.end();) {
      if (GetParent(it->hwnd) == parent) {
        DestroyWindow(it->hwnd);
        it = controls.erase(it);
      } else
        ++it;
    }
  }
  void displayPage() {
    for (auto &r : controls)
      if (GetParent(r.hwnd) == settings && r.page >= 0)
        ShowWindow(r.hwnd, r.page == selectedPage ? SW_SHOW : SW_HIDE);
  }
  void openSettings() {
    if (card)
      DestroyWindow(card);
    if (!settings) {
      settings = topWindow(L"CiBarSettings", L"CíBar · Settings", 760, 675);
      buildSettings();
    }
    ShowWindow(settings, SW_SHOW);
    SetForegroundWindow(settings);
  }
  void buildSettings() {
    clearControls(settings);
    auto &s = store->data.settings;
    label(settings, L"CíBar · Created by Akash Mahedy · @akashmahedy", 24, 18,
          710, 28);
    auto tabs = child(settings, WC_TABCONTROLW, L"", 90, 20, 60, 720, 34);
    for (auto t : {L"Study", L"Appearance", L"Data & Backup"}) {
      TCITEMW item{};
      item.mask = TCIF_TEXT;
      item.pszText = const_cast<LPWSTR>(t);
      TabCtrl_InsertItem(tabs, TabCtrl_GetItemCount(tabs), &item);
    }
    TabCtrl_SetCurSel(tabs, selectedPage);
    packIDs = {"hsk2025"};
    std::set<std::string> packs;
    for (auto &w : store->data.customWords)
      packs.insert(w.pack);
    packIDs.insert(packIDs.end(), packs.begin(), packs.end());
    std::vector<std::wstring> names;
    for (auto &id : packIDs) {
      auto it = std::find_if(store->data.customWords.begin(),
                             store->data.customWords.end(),
                             [&](auto &w) { return w.pack == id; });
      names.push_back(
          id == "hsk2025"
              ? L"HSK 3.0 · 2025 syllabus · Levels 1–6"
              : wide(it == store->data.customWords.end() ? id : it->source));
    }
    auto pit = std::find(packIDs.begin(), packIDs.end(), s.pack);
    combo(settings, names, 100, int(pit - packIDs.begin()), 24, 110, 650, 0);
    label(settings, L"Level / new words", 24, 150, 235, 24, 0);
    label(settings, L"Start", 275, 150, 100, 24, 0);
    label(settings, L"End (inclusive)", 395, 150, 160, 24, 0);
    buildRanges();
    combo(settings, {L"Sequential", L"Random · no repeats per cycle"}, 140,
          s.random ? 1 : 0, 24, 424, 340, 0);
    label(settings, L"Seconds per word", 390, 424, 150, 24, 0);
    edit(settings, std::to_wstring(int(s.interval)), 141, 552, 422, 100, 28, 0);
    check(settings, L"Play Favorites only within the selected ranges", 142,
          s.favoritesOnly, 24, 472, 625, 0);
    button(settings, L"Apply study settings", 143, 24, 514, 195, 30, 0);
    label(settings, L"Select HSK 1–4 for all 2000 words through level 4.", 24,
          559, 660, 28, 0);
    check(settings, L"Launch CíBar at login", 144, startupEnabled(), 24, 605,
          500, 0);
    std::vector<std::pair<std::wstring, bool>> toggles{
        {L"Level label", s.showLevel},
        {L"Serial number", s.showSerial},
        {L"Hanzi", s.showHanzi},
        {L"Pinyin", s.showPinyin},
        {L"English meaning", s.showMeaning},
        {L"Smooth countdown fill", s.showFill},
        {L"Highlight background", s.highlight},
        {L"Adaptive width", s.adaptiveWidth}};
    for (int i = 0; i < 8; i++)
      check(settings, toggles[i].first, 200 + i, toggles[i].second,
            24 + (i % 2) * 340, 115 + (i / 2) * 42, 330, 1);
    label(settings, L"Font size (9–18 pt)", 24, 306, 225, 24, 1);
    edit(settings, std::to_wstring(int(s.fontSize)), 210, 264, 302, 90, 28, 1);
    label(settings, L"Width (80–600)", 390, 306, 180, 24, 1);
    edit(settings, std::to_wstring(int(s.width)), 211, 574, 302, 90, 28, 1);
    std::vector<std::wstring> presets{L"Ocean", L"Sage",     L"Plum",
                                      L"Amber", L"Graphite", L"Custom"};
    int pi = 0;
    for (int i = 0; i < 6; i++)
      if (utf8(presets[i]) == s.preset)
        pi = i;
    combo(settings, presets, 212, pi, 24, 362, 300, 1);
    combo(settings, {L"Soft", L"Balanced", L"Strong"}, 213,
          s.contrast == "Soft"       ? 0
          : s.contrast == "Balanced" ? 1
                                     : 2,
          364, 362, 300, 1);
    label(settings, L"Custom color (hex)", 24, 421, 215, 24, 1);
    edit(settings, wide(s.customColor), 214, 264, 417, 150, 28, 1);
    button(settings, L"Choose color…", 215, 455, 417, 160, 30, 1);
    button(settings, L"Apply font / width / hex", 216, 24, 480, 240, 30, 1);
    check(settings, L"Lock pill position", 217, presentation.locked, 24, 540,
          300, 1);
    button(settings, L"Reset pill position", Reset, 364, 540, 225, 30, 1);
    label(settings,
          L"Pill updates immediately. Full text stays in the word "
          L"card.\nReduced Motion and high-contrast preferences are respected.",
          24, 595, 685, 52, 1);
    label(settings, L"Your words, portable", 24, 115, 680, 30, 2);
    label(settings,
          L"5400 HSK words · " +
              std::to_wstring(store->data.customWords.size()) +
              L" custom words · " +
              std::to_wstring(store->data.favorites.size()) + L" Favorites",
          24, 160, 680, 30, 2);
    label(settings,
          L"Offline. No account, subscription or background network "
          L"requests.\nMac / Windows backups share settings, words and study "
          L"progress.\nWindows pill position is saved separately on this PC.",
          24, 207, 680, 85, 2);
    button(settings, L"Import CSV / TSV…", 300, 24, 325, 215, 30, 2);
    button(settings, L"Word library…", LibraryMenu, 275, 325, 200, 30, 2);
    button(settings, L"Export backup…", 301, 24, 388, 215, 30, 2);
    button(settings, L"Restore backup…", 302, 275, 388, 200, 30, 2);
    button(settings, L"Open data folder", 303, 24, 449, 215, 30, 2);
    button(settings, L"Sources & licenses", 304, 275, 449, 200, 30, 2);
    label(
        settings,
        L"Import: serial, hanzi, pinyin, english. Optional "
        L"example_hanzi,\nexample_pinyin, example_english; examples need all "
        L"three columns.\nAutomatic example Pinyin can need correction. "
        L"Missing examples\nare stated explicitly. Meanings depend on context.",
        24, 510, 680, 108, 2);
    label(settings, L"CíBar for Windows 1.1.0-preview.1 · Native x64 app", 24,
          633, 680, 28, 2);
    displayPage();
    layoutControls(settings);
  }
  void buildRanges() {
    for (auto it = controls.begin(); it != controls.end();) {
      int id = GetDlgCtrlID(it->hwnd);
      if (GetParent(it->hwnd) == settings && id >= 110 && id <= 136) {
        DestroyWindow(it->hwnd);
        it = controls.erase(it);
      } else
        ++it;
    }
    int selected = choice(settings, 100);
    if (selected < 0 || selected >= int(packIDs.size()))
      return;
    auto id = packIDs[selected];
    auto &s = store->data.settings;
    auto words = store->allWords();
    for (int l = id == "hsk2025" ? 1 : 0; l <= (id == "hsk2025" ? 6 : 0); l++) {
      int y = 182 + (l == 0 ? 0 : l - 1) * 35;
      int count = int(std::count_if(words.begin(), words.end(), [&](auto &w) {
        return w.pack == id && w.level == l;
      }));
      bool on = id == s.pack ? std::find(s.levels.begin(), s.levels.end(), l) !=
                                   s.levels.end()
                             : true;
      check(settings,
            (l ? L"HSK " + std::to_wstring(l) : L"Custom list") + L" · " +
                std::to_wstring(count) + L" words",
            110 + l, on, 24, y, 235, 0);
      auto it = s.ranges.find(std::to_string(l));
      bool same = id == s.pack && it != s.ranges.end();
      edit(settings, same ? std::to_wstring(it->second.start) : L"", 120 + l,
           275, y, 100, 28, 0);
      edit(settings, same ? std::to_wstring(it->second.end) : L"", 130 + l, 395,
           y, 100, 28, 0);
    }
    displayPage();
  }
  void applyStudy() {
    persist();
    auto s = store->data.settings;
    int p = choice(settings, 100);
    require(p >= 0 && p < int(packIDs.size()), "Choose a word list.");
    s.pack = packIDs[p];
    s.levels.clear();
    s.ranges.clear();
    auto words = store->allWords();
    for (int l = s.pack == "hsk2025" ? 1 : 0;
         l <= (s.pack == "hsk2025" ? 6 : 0); l++)
      if (checked(settings, 110 + l)) {
        s.levels.push_back(l);
        auto a = windowText(GetDlgItem(settings, 120 + l)),
             b = windowText(GetDlgItem(settings, 130 + l));
        if (!a.empty() || !b.empty()) {
          int count =
              int(std::count_if(words.begin(), words.end(), [&](auto &w) {
                return w.pack == s.pack && w.level == l;
              }));
          s.ranges[std::to_string(l)] = {
              a.empty() ? 1 : integer(GetDlgItem(settings, 120 + l)),
              b.empty() ? count : integer(GetDlgItem(settings, 130 + l))};
        }
      }
    s.interval = number(GetDlgItem(settings, 141));
    s.random = choice(settings, 140) == 1;
    s.favoritesOnly = checked(settings, 142);
    s.validate();
    auto old = store->data.settings;
    if (s.key() == old.key() && s.interval != old.interval) {
      auto snap = playback.snapshot();
      snap.remaining = playback.fraction() * s.interval;
      store->data.sessions[s.key()] = snap;
    }
    store->data.settings = s;
    applySelection();
    refresh();
    persist();
    if (!playback.current())
      MessageBoxW(settings,
                  L"No words match this selection. Change the range or "
                  L"Favorites filter.",
                  L"CíBar", MB_OK);
  }
  void applyAppearance() {
    auto s = store->data.settings;
    bool *flags[] = {&s.showLevel,  &s.showSerial,   &s.showHanzi,
                     &s.showPinyin, &s.showMeaning,  &s.showFill,
                     &s.highlight,  &s.adaptiveWidth};
    for (int i = 0; i < 8; i++)
      *flags[i] = checked(settings, 200 + i);
    s.fontSize = number(GetDlgItem(settings, 210));
    s.width = number(GetDlgItem(settings, 211));
    s.preset = utf8(windowText(GetDlgItem(settings, 212)));
    s.contrast = utf8(windowText(GetDlgItem(settings, 213)));
    s.customColor = utf8(windowText(GetDlgItem(settings, 214)));
    s.validate();
    store->data.settings = s;
    refresh();
    persist();
  }
  bool startupEnabled() {
    wchar_t value[32768];
    DWORD size = sizeof(value);
    return RegGetValueW(HKEY_CURRENT_USER,
                        L"Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                        L"CiBar", RRF_RT_REG_SZ, nullptr, value,
                        &size) == ERROR_SUCCESS &&
           std::wstring(value) == L"\"" + exe.wstring() + L"\"";
  }
  void startup(bool value) {
    HKEY key;
    require(
        RegCreateKeyExW(HKEY_CURRENT_USER,
                        L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
                        nullptr, 0, KEY_SET_VALUE, nullptr, &key,
                        nullptr) == ERROR_SUCCESS,
        "Cannot change login startup.");
    LSTATUS result;
    if (value) {
      std::wstring text = L"\"" + exe.wstring() + L"\"";
      result = RegSetValueExW(key, L"CiBar", 0, REG_SZ,
                              reinterpret_cast<const BYTE *>(text.c_str()),
                              DWORD((text.size() + 1) * sizeof(wchar_t)));
    } else {
      result = RegDeleteValueW(key, L"CiBar");
      if (result == ERROR_FILE_NOT_FOUND)
        result = ERROR_SUCCESS;
    }
    RegCloseKey(key);
    require(result == ERROR_SUCCESS, "Cannot change login startup.");
  }
  std::optional<fs::path> chooseFile(bool save, const wchar_t *filter,
                                     const wchar_t *extension,
                                     const wchar_t *name) {
    wchar_t path[32768]{};
    if (name)
      wcscpy_s(path, name);
    OPENFILENAMEW f{sizeof(f)};
    f.hwndOwner = settings ? settings : pill;
    f.lpstrFilter = filter;
    f.lpstrFile = path;
    f.nMaxFile = 32768;
    f.lpstrDefExt = extension;
    f.Flags = OFN_EXPLORER | OFN_NOCHANGEDIR |
              (save ? OFN_OVERWRITEPROMPT : OFN_FILEMUSTEXIST);
    bool chosen = save ? GetSaveFileNameW(&f) : GetOpenFileNameW(&f);
    return chosen ? std::optional<fs::path>(path) : std::nullopt;
  }
  void dataAction(int id) {
    if (id == 300) {
      auto p = chooseFile(
          false, L"Vocabulary CSV / TSV\0*.csv;*.tsv\0All files\0*.*\0\0",
          nullptr, nullptr);
      if (!p)
        return;
      auto pack = "custom-" + Store::stamp();
      auto words = importWords(readText(*p),
                               p->extension() == L".tsv" ? '\t' : ',', pack);
      for (auto &w : words)
        w.source = "User import: " + utf8(p->filename().wstring());
      persist();
      auto s = store->data.settings;
      s.pack = pack;
      s.levels = {0};
      s.ranges.clear();
      s.favoritesOnly = false;
      auto d = store->data;
      d.customWords.insert(d.customWords.end(), words.begin(), words.end());
      d.settings = s;
      validateData(d);
      store->data = std::move(d);
      applySelection();
      refresh();
      persist();
      buildSettings();
      refreshLibrary();
    } else if (id == 301) {
      auto p = chooseFile(true, L"CíBar backup\0*.json\0\0", L"json",
                          L"CiBar-Backup.json");
      if (p) {
        persist();
        atomicText(*p, json(store->backup()).dump(2));
      }
    } else if (id == 302) {
      auto p = chooseFile(false, L"CíBar backup\0*.json\0\0", L"json", nullptr);
      if (!p)
        return;
      auto raw = json::parse(readText(*p));
      decodeBackup(raw);
      if (MessageBoxW(settings,
                      L"Restore this backup? Current data will be preserved in "
                      L"a recovery backup first.",
                      L"Restore CíBar backup",
                      MB_YESNO | MB_ICONQUESTION) != IDYES)
        return;
      persist();
      store->restore(raw);
      preview.reset();
      applySelection();
      refresh();
      persist();
      buildSettings();
      refreshLibrary();
    } else if (id == 303)
      ShellExecuteW(nullptr, L"open", dataDir.c_str(), nullptr, nullptr,
                    SW_SHOWNORMAL);
    else if (id == 304) {
      auto attribution = dataDir / L"Sources-and-licenses.txt";
      atomicText(attribution, store->licenses);
      ShellExecuteW(nullptr, L"open", attribution.c_str(), nullptr, nullptr,
                    SW_SHOWNORMAL);
    }
  }
  const Word *cardWord() { return preview ? &*preview : playback.current(); }
  std::wstring cardText() {
    auto w = cardWord();
    if (!w)
      return L"No word selected.";
    auto s = wide("H" + std::to_string(w->level) + " · " +
                  std::to_string(w->serial) + "\r\n\r\n" + w->hanzi + "\r\n" +
                  w->pinyin + "\r\n\r\n" + w->english + "\r\n\r\n");
    if (w->example) {
      auto &e = *w->example;
      s += wide("EXAMPLE\r\n" + e.hanzi + "\r\n" + e.pinyin + "\r\n" +
                e.english + "\r\n\r\n" +
                (e.pinyinAutomatic
                     ? std::string("Automatic example Pinyin: polyphonic "
                                   "readings may need checking.\r\n\r\n")
                     : std::string()) +
                e.attribution + "\r\n\r\n");
    } else
      s += L"No sourced example is available for this word.\r\n\r\n";
    return s + wide("SOURCE\r\n" + w->source);
  }
  void openCard(std::optional<Word> word = std::nullopt) {
    preview = std::move(word);
    if (!card) {
      setBlock("card", true);
      card = topWindow(L"CiBarCard", L"CíBar · Word Card", 530, 640);
      label(card, L"Created by Akash Mahedy · @akashmahedy", 20, 12, 490);
      child(card, L"EDIT", L"", 400, 20, 48, 490, 452,
            ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL | WS_VSCROLL |
                WS_TABSTOP);
      button(card, L"Copy", 401, 20, 516, 90);
      button(card, L"Dictionary", 402, 124, 516, 115);
      button(card, L"Favorite", 403, 253, 516, 110);
      button(card, L"Source", 404, 377, 516, 110);
      button(card, L"Previous", Previous, 20, 565, 110);
      button(card, L"Next", Next, 144, 565, 90);
      button(card, L"Pause", Pause, 248, 565, 110);
      button(card, L"Library…", LibraryMenu, 372, 565, 115);
    }
    layoutControls(card);
    updateCard();
    ShowWindow(card, SW_SHOW);
    SetForegroundWindow(card);
  }
  void updateCard() {
    SetDlgItemTextW(card, 400, cardText().c_str());
    auto w = cardWord();
    SetDlgItemTextW(card, 403,
                    w && store->data.favorites.contains(w->id) ? L"Unfavorite"
                                                               : L"Favorite");
    SetDlgItemTextW(card, Pause, playback.manual ? L"Resume" : L"Pause");
    EnableWindow(GetDlgItem(card, 404),
                 w && w->example && !w->example->sourceURL.empty());
  }
  void cardAction(int id) {
    auto w = cardWord();
    if (id == 401) {
      auto t = cardText();
      if (OpenClipboard(card)) {
        EmptyClipboard();
        auto mem = GlobalAlloc(GMEM_MOVEABLE, (t.size() + 1) * sizeof(wchar_t));
        if (mem) {
          auto p = GlobalLock(mem);
          memcpy(p, t.c_str(), (t.size() + 1) * sizeof(wchar_t));
          GlobalUnlock(mem);
          if (!SetClipboardData(CF_UNICODETEXT, mem))
            GlobalFree(mem);
        }
        CloseClipboard();
      }
    } else if (id == 402 && w) {
      auto url = L"https://www.mdbg.net/chinese/"
                 L"dictionary?page=worddict&wdrst=0&wdqb=" +
                 encodeURL(w->hanzi);
      ShellExecuteW(nullptr, L"open", url.c_str(), nullptr, nullptr,
                    SW_SHOWNORMAL);
    } else if (id == 403 && w) {
      auto wordID = w->id;
      if (store->data.favorites.contains(wordID))
        store->data.favorites.erase(wordID);
      else
        store->data.favorites.insert(wordID);
      persist();
      if (store->data.settings.favoritesOnly)
        applySelection();
      refresh();
      persist();
      refreshLibrary();
    } else if (id == 404 && w && w->example) {
      auto url = w->example->sourceURL;
      require(url.starts_with("https://tatoeba.org/") ||
                  url.starts_with("https://hearmandarin.com/"),
              "This source URL is not a supported HTTPS source.");
      ShellExecuteW(nullptr, L"open", wide(url).c_str(), nullptr, nullptr,
                    SW_SHOWNORMAL);
    } else
      action(id);
  }
  void openLibrary() {
    if (!library) {
      library = topWindow(L"CiBarLibrary", L"CíBar · Word library & Favorites",
                          790, 620);
      label(library, L"Search Hanzi, Pinyin or English", 20, 14, 510);
      edit(library, L"", 500, 20, 46, 480);
      check(library, L"Favorites only", 501, false, 525, 46, 230);
      auto list =
          child(library, WC_LISTVIEWW, L"", 502, 20, 94, 750, 450,
                WS_TABSTOP | LVS_REPORT | LVS_OWNERDATA | LVS_SINGLESEL);
      ListView_SetExtendedListViewStyle(list, LVS_EX_FULLROWSELECT |
                                                  LVS_EX_DOUBLEBUFFER);
      int col = 0;
      for (auto [name, width] :
           std::vector<std::pair<std::wstring, int>>{{L"Level / #", 90},
                                                     {L"Hanzi", 120},
                                                     {L"Pinyin", 180},
                                                     {L"English", 350}}) {
        LVCOLUMNW c{};
        c.mask = LVCF_TEXT | LVCF_WIDTH;
        c.pszText = name.data();
        c.cx = MulDiv(width, GetDpiForWindow(library), 96);
        ListView_InsertColumn(list, col++, &c);
      }
      button(library, L"Open word card", 503, 20, 564, 175);
      button(library, L"Jump to word", 504, 218, 564, 160);
      label(library, L"Created by Akash Mahedy · @akashmahedy", 410, 565, 360);
    }
    layoutControls(library);
    refreshLibrary();
    ShowWindow(library, SW_SHOW);
    SetForegroundWindow(library);
  }
  void refreshLibrary() {
    if (!library)
      return;
    auto q = wide("");
    q = windowText(GetDlgItem(library, 500));
    std::transform(q.begin(), q.end(), q.begin(), towlower);
    visibleWords.clear();
    for (auto &w : store->allWords()) {
      auto text = wide(w.hanzi + " " + w.pinyin + " " + w.english);
      std::transform(text.begin(), text.end(), text.begin(), towlower);
      if (text.find(q) != std::wstring::npos &&
          (!checked(library, 501) || store->data.favorites.contains(w.id)))
        visibleWords.push_back(w);
    }
    ListView_SetItemCountEx(GetDlgItem(library, 502), int(visibleWords.size()),
                            LVSICF_NOSCROLL);
    InvalidateRect(GetDlgItem(library, 502), nullptr, TRUE);
  }
  void libraryAction(int id) {
    int i = ListView_GetNextItem(GetDlgItem(library, 502), -1, LVNI_SELECTED);
    if (id == 500 || id == 501) {
      refreshLibrary();
      return;
    }
    require(i >= 0 && i < int(visibleWords.size()), "Select a word first.");
    if (id == 503)
      openCard(visibleWords[i]);
    else if (id == 504) {
      require(playback.jump(visibleWords[i].id),
              "This word is outside the current study selection. Change Study "
              "settings first.");
      preview.reset();
      refresh();
      persist();
      openCard();
    }
  }
  void layoutControls(HWND parent) {
    if (!contentSizes.contains(parent) || layingOut)
      return;
    layingOut = true;
    float scale = GetDpiForWindow(parent) / 96.f;
    RECT client;
    GetClientRect(parent, &client);
    auto size = contentSizes[parent];
    for (auto [bar, extent, page] : std::vector<std::tuple<int, int, int>>{
             {SB_HORZ, cint(size.cx * scale), int(client.right)},
             {SB_VERT, cint(size.cy * scale), int(client.bottom)}}) {
      SCROLLINFO si{sizeof(si), SIF_RANGE | SIF_PAGE};
      si.nMin = 0;
      si.nMax = extent - 1;
      si.nPage = UINT(std::max(1, page));
      SetScrollInfo(parent, bar, &si, TRUE);
    }
    int x = GetScrollPos(parent, SB_HORZ), y = GetScrollPos(parent, SB_VERT);
    for (auto &r : controls)
      if (GetParent(r.hwnd) == parent)
        SetWindowPos(r.hwnd, nullptr, cint(r.x * scale) - x,
                     cint(r.y * scale) - y, cint(r.w * scale),
                     cint(r.h * scale), SWP_NOZORDER | SWP_NOACTIVATE);
    layingOut = false;
  }
  void scroll(HWND parent, int bar, int command, int wheel = 0) {
    SCROLLINFO si{sizeof(si), SIF_ALL};
    GetScrollInfo(parent, bar, &si);
    int pos = si.nPos, line = MulDiv(24, GetDpiForWindow(parent), 96);
    if (wheel)
      pos -= wheel * line;
    else
      switch (command) {
      case SB_LINEUP:
        pos -= line;
        break;
      case SB_LINEDOWN:
        pos += line;
        break;
      case SB_PAGEUP:
        pos -= int(si.nPage);
        break;
      case SB_PAGEDOWN:
        pos += int(si.nPage);
        break;
      case SB_TOP:
        pos = si.nMin;
        break;
      case SB_BOTTOM:
        pos = si.nMax;
        break;
      case SB_THUMBTRACK:
      case SB_THUMBPOSITION:
        pos = si.nTrackPos;
        break;
      default:
        return;
      }
    si.fMask = SIF_POS;
    si.nPos = pos;
    SetScrollInfo(parent, bar, &si, TRUE);
    layoutControls(parent);
  }
  void repositionControls(HWND parent) {
    if (fonts.contains(parent)) {
      DeleteObject(fonts[parent]);
      fonts.erase(parent);
    }
    float scale = GetDpiForWindow(parent) / 96.f;
    for (auto &r : controls)
      if (GetParent(r.hwnd) == parent)
        SendMessageW(r.hwnd, WM_SETFONT,
                     reinterpret_cast<WPARAM>(fontFor(parent)), TRUE);
    layoutControls(parent);
    if (parent == library) {
      int widths[] = {90, 120, 180, 350};
      for (int i = 0; i < 4; i++)
        ListView_SetColumnWidth(GetDlgItem(parent, 502), i,
                                cint(widths[i] * scale));
    }
  }
  void destroyWindow(HWND w) {
    if (w == card) {
      card = nullptr;
      preview.reset();
      if (!quitting)
        setBlock("card", false);
    }
    if (w == settings)
      settings = nullptr;
    if (w == library) {
      library = nullptr;
      visibleWords.clear();
    }
    controls.erase(std::remove_if(controls.begin(), controls.end(),
                                  [&](auto &r) { return !IsWindow(r.hwnd); }),
                   controls.end());
    if (fonts.contains(w)) {
      DeleteObject(fonts[w]);
      fonts.erase(w);
    }
    contentSizes.erase(w);
  }
  ~App() {
    if (foregroundHook)
      UnhookWinEvent(foregroundHook);
    if (locationHook)
      UnhookWinEvent(locationHook);
    for (auto &[w, f] : fonts)
      DeleteObject(f);
    if (uiFont)
      DeleteObject(uiFont);
  }
};
void CALLBACK foregroundEvent(HWINEVENTHOOK, DWORD, HWND, LONG, LONG, DWORD,
                              DWORD) {
  if (instance && instance->pill && !instance->fullCheckQueued) {
    instance->fullCheckQueued = true;
    PostMessageW(instance->pill, ForegroundMessage, 0, 0);
  }
}
void CALLBACK locationEvent(HWINEVENTHOOK hook, DWORD event, HWND w,
                            LONG object, LONG child, DWORD thread, DWORD time) {
  if (object == OBJID_WINDOW && w == GetForegroundWindow())
    foregroundEvent(hook, event, w, object, child, thread, time);
}
LRESULT CALLBACK windowProc(HWND w, UINT msg, WPARAM wp, LPARAM lp) {
  auto a = instance;
  if (!a)
    return DefWindowProcW(w, msg, wp, lp);
  try {
    if (msg == WM_CLOSE) {
      if (w == a->pill)
        a->quitting = true;
      DestroyWindow(w);
      return 0;
    }
    if (msg == WM_NCDESTROY && w != a->pill) {
      a->destroyWindow(w);
      return DefWindowProcW(w, msg, wp, lp);
    }
    if (w == a->pill) {
      if (a->taskbarCreated && msg == a->taskbarCreated) {
        a->addTray();
        a->refresh();
        return 0;
      }
      switch (msg) {
      case WM_MOUSEACTIVATE:
        return MA_NOACTIVATE;
      case WM_ERASEBKGND:
        return 1;
      case WM_PAINT: {
        PAINTSTRUCT p;
        BeginPaint(w, &p);
        EndPaint(w, &p);
        return 0;
      }
      case WM_LBUTTONDOWN:
        GetCursorPos(&a->dragStart);
        {
          RECT r;
          GetWindowRect(w, &r);
          a->windowStart = {r.left, r.top};
        }
        a->dragging = true;
        a->moving = false;
        SetCapture(w);
        return 0;
      case WM_MOUSEMOVE:
        if (a->dragging && !a->presentation.locked) {
          POINT p;
          GetCursorPos(&p);
          int dx = p.x - a->dragStart.x, dy = p.y - a->dragStart.y;
          if (abs(dx) > 4 || abs(dy) > 4)
            a->moving = true;
          if (a->moving) {
            a->presentation.positioned = true;
            a->presentation.x = a->windowStart.x + dx;
            a->presentation.y = a->windowStart.y + dy;
            SetWindowPos(w, HWND_TOPMOST, a->presentation.x, a->presentation.y,
                         0, 0, SWP_NOSIZE | SWP_NOACTIVATE);
          }
        }
        return 0;
      case WM_LBUTTONUP:
        if (a->dragging) {
          a->dragging = false;
          ReleaseCapture();
          if (a->moving) {
            a->savePresentation();
            a->refresh();
          } else
            a->openCard();
        }
        return 0;
      case WM_CAPTURECHANGED:
        a->dragging = false;
        return 0;
      case WM_CONTEXTMENU:
        a->trayMenu();
        return 0;
      case WM_TIMER:
        if (wp == 1) {
          if (!a->playback.paused() && a->playback.left() <= .02)
            a->playback.advance();
          a->refresh();
          a->persist();
        } else if (wp == 2)
          a->renderer.countdown(a->playback.fraction(), a->playback.left(),
                                a->playback.paused(), true);
        return 0;
      case ForegroundMessage:
        a->fullCheckQueued = false;
        a->checkFullscreen();
        return 0;
      case ReopenMessage:
        a->openSettings();
        return 0;
      case TrayMessage:
        if (LOWORD(lp) == WM_RBUTTONUP || LOWORD(lp) == WM_CONTEXTMENU)
          a->trayMenu();
        else if (LOWORD(lp) == NIN_SELECT || LOWORD(lp) == NIN_KEYSELECT ||
                 LOWORD(lp) == WM_LBUTTONUP) {
          if (a->presentation.hidden)
            a->action(Hide);
          a->openCard();
        }
        return 0;
      case WM_WTSSESSION_CHANGE:
        if (wp == WTS_SESSION_LOCK || wp == WTS_SESSION_UNLOCK)
          a->setBlock("session", wp == WTS_SESSION_LOCK);
        return 0;
      case WM_POWERBROADCAST:
        if (wp == PBT_APMSUSPEND)
          a->setBlock("sleep", true);
        else if (wp == PBT_APMRESUMEAUTOMATIC || wp == PBT_APMRESUMESUSPEND)
          a->setBlock("sleep", false);
        return TRUE;
      case WM_DPICHANGED:
      case WM_DISPLAYCHANGE:
      case WM_SETTINGCHANGE:
        if (a->built)
          a->refresh();
        return 0;
      case WM_DESTROY:
        a->persist();
        a->savePresentation();
        WTSUnRegisterSessionNotification(w);
        {
          NOTIFYICONDATAW n{sizeof(n)};
          n.hWnd = w;
          n.uID = 1;
          Shell_NotifyIconW(NIM_DELETE, &n);
        }
        PostQuitMessage(0);
        return 0;
      }
    }
    if (msg == WM_SIZE) {
      a->layoutControls(w);
      return 0;
    }
    if (msg == WM_VSCROLL || msg == WM_HSCROLL) {
      a->scroll(w, msg == WM_VSCROLL ? SB_VERT : SB_HORZ, LOWORD(wp));
      return 0;
    }
    if (msg == WM_MOUSEWHEEL) {
      a->scroll(w, SB_VERT, 0, GET_WHEEL_DELTA_WPARAM(wp) / WHEEL_DELTA * 3);
      return 0;
    }
    if (msg == WM_DPICHANGED) {
      auto r = reinterpret_cast<RECT *>(lp);
      MONITORINFO mi{sizeof(mi)};
      GetMonitorInfoW(MonitorFromRect(r, MONITOR_DEFAULTTONEAREST), &mi);
      int width = std::min(int(r->right - r->left),
                           int(mi.rcWork.right - mi.rcWork.left));
      int height = std::min(int(r->bottom - r->top),
                            int(mi.rcWork.bottom - mi.rcWork.top));
      int x = std::clamp(int(r->left), int(mi.rcWork.left),
                         int(mi.rcWork.right) - width);
      int y = std::clamp(int(r->top), int(mi.rcWork.top),
                         int(mi.rcWork.bottom) - height);
      SetWindowPos(w, nullptr, x, y, width, height,
                   SWP_NOZORDER | SWP_NOACTIVATE);
      a->repositionControls(w);
      return 0;
    }
    if (w == a->settings) {
      if (msg == WM_NOTIFY && reinterpret_cast<NMHDR *>(lp)->idFrom == 90 &&
          reinterpret_cast<NMHDR *>(lp)->code == TCN_SELCHANGE) {
        a->selectedPage = TabCtrl_GetCurSel(GetDlgItem(w, 90));
        a->displayPage();
        return 0;
      }
      if (msg == WM_COMMAND) {
        int id = LOWORD(wp), code = HIWORD(wp);
        if (id == 100 && code == CBN_SELCHANGE)
          a->buildRanges();
        else if (id == 143 && code == BN_CLICKED)
          a->applyStudy();
        else if (id == 144 && code == BN_CLICKED)
          a->startup(a->checked(w, 144));
        else if ((id >= 200 && id <= 207 && code == BN_CLICKED) ||
                 ((id == 212 || id == 213) && code == CBN_SELCHANGE) ||
                 (id == 216 && code == BN_CLICKED))
          a->applyAppearance();
        else if (id == 215 && code == BN_CLICKED) {
          CHOOSECOLORW c{sizeof(c)};
          COLORREF colors[16]{};
          c.hwndOwner = w;
          c.lpCustColors = colors;
          c.Flags = CC_FULLOPEN | CC_RGBINIT;
          auto rgb = hexColor(a->store->data.settings.customColor);
          c.rgbResult =
              RGB(int(rgb.r * 255), int(rgb.g * 255), int(rgb.b * 255));
          if (ChooseColorW(&c)) {
            std::ostringstream h;
            h << std::hex << std::uppercase << std::setfill('0') << std::setw(2)
              << int(GetRValue(c.rgbResult)) << std::setw(2)
              << int(GetGValue(c.rgbResult)) << std::setw(2)
              << int(GetBValue(c.rgbResult));
            SetDlgItemTextW(w, 214, wide(h.str()).c_str());
            SendDlgItemMessageW(w, 212, CB_SETCURSEL, 5, 0);
            a->applyAppearance();
          }
        } else if (id == 217 && code == BN_CLICKED) {
          a->presentation.locked = a->checked(w, 217);
          a->savePresentation();
        } else if (id >= 300 && id <= 304 && code == BN_CLICKED)
          a->dataAction(id);
        else if (code == BN_CLICKED && (id == Reset || id == LibraryMenu))
          a->action(id);
        return 0;
      }
    }
    if (w == a->card) {
      if (msg == WM_COMMAND && HIWORD(wp) == BN_CLICKED) {
        a->cardAction(LOWORD(wp));
        return 0;
      }
    }
    if (w == a->library) {
      if (msg == WM_COMMAND) {
        int id = LOWORD(wp), code = HIWORD(wp);
        if ((id == 500 && code == EN_CHANGE) ||
            (id == 501 && code == BN_CLICKED) ||
            ((id == 503 || id == 504) && code == BN_CLICKED))
          a->libraryAction(id);
        return 0;
      }
      if (msg == WM_NOTIFY) {
        auto n = reinterpret_cast<NMHDR *>(lp);
        if (n->idFrom == 502 && n->code == LVN_GETDISPINFOW) {
          auto d = reinterpret_cast<NMLVDISPINFOW *>(lp);
          int i = d->item.iItem;
          if (i >= 0 && i < int(a->visibleWords.size())) {
            auto &v = a->visibleWords[i];
            a->libraryCell = d->item.iSubItem == 0
                                 ? wide("H" + std::to_string(v.level) + " · " +
                                        std::to_string(v.serial))
                             : d->item.iSubItem == 1 ? wide(v.hanzi)
                             : d->item.iSubItem == 2 ? wide(v.pinyin)
                                                     : wide(v.english);
            if (d->item.mask & LVIF_TEXT)
              wcsncpy_s(d->item.pszText, size_t(d->item.cchTextMax),
                        a->libraryCell.c_str(), _TRUNCATE);
          }
          return 0;
        }
        if (n->idFrom == 502 &&
            (n->code == NM_DBLCLK || n->code == NM_RETURN)) {
          a->libraryAction(503);
          return 0;
        }
      }
    }
  } catch (const std::exception &e) {
    a->error(e);
  }
  return DefWindowProcW(w, msg, wp, lp);
}
int WINAPI wWinMain(HINSTANCE module, HINSTANCE, LPWSTR, int) {
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  HANDLE singleton = CreateMutexW(nullptr, FALSE, L"Local\\CiBarWindows");
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    if (auto w = FindWindowW(L"CiBarPill", nullptr))
      PostMessageW(w, ReopenMessage, 0, 0);
    if (singleton)
      CloseHandle(singleton);
    CoUninitialize();
    return 0;
  }
  int result = 0;
  bool automated = wcsstr(GetCommandLineW(), L"--smoke-test") != nullptr;
  try {
    wchar_t path[32768];
    require(GetModuleFileNameW(nullptr, path, 32768) > 0,
            "Cannot locate app files.");
    fs::path exe(path), data;
    PWSTR local = nullptr;
    hr(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local));
    data = fs::path(local) / L"CiBar";
    CoTaskMemFree(local);
    using VersionFunction = LONG(WINAPI *)(OSVERSIONINFOW *);
    auto versionFunction = reinterpret_cast<VersionFunction>(
        GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion"));
    SYSTEM_INFO nativeSystem{};
    GetNativeSystemInfo(&nativeSystem);
    require(nativeSystem.wProcessorArchitecture == PROCESSOR_ARCHITECTURE_AMD64,
            "This preview requires an Intel/AMD x64 PC. Windows ARM64 is not "
            "supported.");
    OSVERSIONINFOW vi{sizeof(vi)};
    require(versionFunction && versionFunction(&vi) == 0 &&
                vi.dwBuildNumber >= 22000,
            "This preview requires Windows 11 or newer.");
    int argc = 0;
    auto args = CommandLineToArgvW(GetCommandLineW(), &argc);
    bool smoke = false, showSettings = false;
    for (int i = 1; i < argc; i++) {
      if (std::wstring(args[i]) == L"--data-dir" && i + 1 < argc)
        data = args[++i];
      else if (std::wstring(args[i]) == L"--smoke-test")
        smoke = true;
      else if (std::wstring(args[i]) == L"--settings")
        showSettings = true;
    }
    LocalFree(args);
    App app(module, exe.parent_path() / L"Resources", data, exe);
    instance = &app;
    app.automated = smoke;
    app.init();
    if (smoke) {
      app.openSettings();
      app.openLibrary();
      app.openCard();
      atomicText(data / L"smoke-result.json",
                 json{{"graphics", "DirectComposition"},
                      {"windowsCreated", true},
                      {"wordCount", app.store->bundled.size()},
                      {"guiVerifiedOnWindows11", false}}
                     .dump(2));
      SetTimer(app.pill, 3, 1500, nullptr);
    } else if (showSettings)
      app.openSettings();
    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
      if (smoke && msg.message == WM_TIMER && msg.wParam == 3) {
        app.quitting = true;
        DestroyWindow(app.pill);
        continue;
      }
      bool dialog = false;
      for (auto w : {app.settings, app.card, app.library})
        if (w && IsDialogMessageW(w, &msg)) {
          dialog = true;
          break;
        }
      if (!dialog) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
      }
    }
    result = app.failed ? 1 : 0;
    instance = nullptr;
  } catch (const std::exception &e) {
    if (instance)
      instance = nullptr;
    if (automated)
      OutputDebugStringW(wide(e.what()).c_str());
    else
      MessageBoxW(nullptr, wide(e.what()).c_str(), L"CíBar could not start",
                  MB_OK | MB_ICONERROR);
    result = 1;
  }
  if (singleton)
    CloseHandle(singleton);
  CoUninitialize();
  return result;
}
