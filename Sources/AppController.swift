import AppKit
import ServiceManagement
import UniformTypeIdentifiers

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store: Store
    let playback = Playback()
    var item: NSStatusItem!
    let pill = PillView(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
    var cardWindow: NSPanel!
    var card: WordCardController!
    var settingsWindow: SettingsController?
    var libraryWindow: LibraryController?
    var timer: Timer?
    var reducedMotionTimer: Timer?
    var observers: [NSObjectProtocol] = []
    var lastError: String?
    var currentKey = ""
    init(store: Store) { self.store = store; super.init() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: 260)
        item.behavior = [.terminationOnRemoval]
        item.autosaveName = "CiBarVocabulary"
        let b = item.button!; b.title = ""; b.addSubview(pill)
        pill.click = { [weak self] in self?.toggleCard() }
        pill.quickMenu = { [weak self] in self?.quickMenu() }
        card = WordCardController(app: self)
        cardWindow = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 640), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        cardWindow.title = "CíBar · Word Card"; cardWindow.contentViewController = card
        cardWindow.delegate = self; cardWindow.isReleasedWhenClosed = false
        cardWindow.level = .floating
        playback.onChange = { [weak self] in self?.changed() }
        migrateSwiftBar()
        configureSelection()
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.playback.setBlocker("sleep", active: true) })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.playback.setBlocker("sleep", active: false) })
        observers.append(workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.playback.setBlocker("session", active: true) })
        observers.append(workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.playback.setBlocker("session", active: false) })
        observers.append(workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshDisplay() })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshDisplay() })
        if let warning = store.loadWarning { alert(warning) }
        if CommandLine.arguments.contains("--show-settings") { openSettings() }
        writeDiagnostics()
    }
    func migrateSwiftBar() {
        guard !store.data.migratedSwiftBar else { return }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/SwiftBar-HSK/.data")
        let file = dir.appendingPathComponent("countdown-state.json")
        if let raw = try? Data(contentsOf: file), let state = try? JSONSerialization.jsonObject(with: raw) as? [String: Any], let serial = state["serial"] as? Int {
            let interval = state["interval"] as? Double ?? 45
            store.data.settings.interval = max(1, min(86400, interval))
            let selected = Playback.select(store.allWords, settings: store.data.settings, favorites: [])
            let deadline = state["deadline"] as? Double ?? 0
            let remaining = deadline > Date().timeIntervalSince1970 ? min(interval, deadline-Date().timeIntervalSince1970) : interval
            store.data.sessions[store.data.settings.selectionKey] = Snapshot(order: selected.map(\.id), index: selected.firstIndex(where: { $0.serial == serial }) ?? 0, remaining: remaining, manuallyPaused: false)
            if let legacy = try? String(contentsOf: dir.appendingPathComponent("hsk4.tsv"), encoding: .utf8), let words = try? Store.importWords(text: legacy, delimiter: "\t", pack: "legacy-hsk4") {
                store.data.customWords.append(contentsOf: words.map { var w = $0; w.source = "Previous corrected MandarinBean HSK4 · preserved migration copy"; w.note = "Legacy list retained unchanged; use the HSK 2025 pack for syllabus-specific meanings."; return w })
            }
        }
        store.data.migratedSwiftBar = true
        save()
    }
    func configureSelection() {
        currentKey = store.data.settings.selectionKey
        playback.configure(Playback.select(store.allWords, settings: store.data.settings, favorites: store.data.favorites), settings: store.data.settings, snapshot: store.data.sessions[currentKey])
    }
    func changed() {
        refreshDisplay(); persistSession()
        if cardWindow?.isVisible == true { card.refresh() }
        libraryWindow?.refresh()
    }
    func refreshDisplay() {
        guard item != nil else { return }
        timer?.invalidate(); reducedMotionTimer?.invalidate()
        let screenWidth = item.button?.window?.screen?.frame.width ?? NSScreen.main?.frame.width ?? 1440
        let available = min(600, max(80, screenWidth / 3))
        let w = pill.configure(word: playback.current, settings: store.data.settings, availableWidth: available)
        item.length = w
        pill.frame.origin = CGPoint(x: 0, y: max(0, ((item.button?.bounds.height ?? 24)-22)/2))
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        pill.countdown(fraction: playback.fraction, duration: playback.timeLeft, paused: playback.paused, reducedMotion: reduce)
        item.button?.toolTip = pill.toolTip
        if !playback.paused && playback.current != nil {
            timer = Timer(timeInterval: max(0.01, playback.timeLeft), repeats: false) { [weak self] _ in self?.playback.advance() }
            timer?.tolerance = 0.05; RunLoop.main.add(timer!, forMode: .common)
            if reduce && store.data.settings.showFill {
                reducedMotionTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    self.pill.countdown(fraction: self.playback.fraction, duration: self.playback.timeLeft, paused: self.playback.paused, reducedMotion: true)
                }
                reducedMotionTimer?.tolerance = 0.1; RunLoop.main.add(reducedMotionTimer!, forMode: .common)
            }
        }
    }
    func persistSession() {
        guard !currentKey.isEmpty else { return }
        store.data.sessions[currentKey] = playback.snapshot(); save()
    }
    func save() {
        do { try store.save(); lastError = nil }
        catch { if lastError != error.localizedDescription { lastError = error.localizedDescription; alert("Could not save CíBar settings: \(error.localizedDescription)") } }
    }
    func apply(_ new: Settings) throws {
        var s = new; try s.validate()
        let selected = Playback.select(store.allWords, settings: s, favorites: store.data.favorites)
        guard !selected.isEmpty else { throw AppError.message("No words match these levels, ranges or favorites. Change the selection and try again.") }
        persistSession()
        let old = store.data.settings; store.data.settings = s
        if s.selectionKey != old.selectionKey { configureSelection() }
        else if s.interval != old.interval { playback.changeInterval(s.interval) }
        else { refreshDisplay(); save() }
    }
    func toggleFavorite(_ word: Word) {
        if store.data.favorites.contains(word.id) { store.data.favorites.remove(word.id) } else { store.data.favorites.insert(word.id) }
        if store.data.settings.favoritesOnly { persistSession(); configureSelection() }
        save(); card.refresh(); libraryWindow?.refresh()
    }
    @objc func toggleCard() { if cardWindow.isVisible { closeCard() } else { showCard() } }
    func closeCard() { if cardWindow.isVisible { cardWindow.close() } }
    func showCard(preview: Word? = nil) {
        card.preview = preview; card.refresh()
        if !cardWindow.isVisible {
            playback.setBlocker("card", active: true)
            NSApp.activate(ignoringOtherApps: true)
            let screen = item.button?.window?.screen ?? NSScreen.main!
            let anchor = item.button?.window.map { $0.convertToScreen(item.button!.convert(item.button!.bounds, to: nil)) } ?? NSRect(x: screen.visibleFrame.maxX-260,y: screen.visibleFrame.maxY,width:260,height:22)
            let x = min(max(screen.visibleFrame.minX, anchor.midX - 240), screen.visibleFrame.maxX - 480)
            let y = max(screen.visibleFrame.minY, screen.visibleFrame.maxY - cardWindow.frame.height - 8)
            cardWindow.setFrameOrigin(NSPoint(x: x, y: y))
        }
        cardWindow.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === cardWindow { card.preview = nil; playback.setBlocker("card", active: false) }
    }
    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === cardWindow { closeCard() }
    }
    @objc func next() { card.preview = nil; playback.advance() }
    @objc func previous() { card.preview = nil; playback.advance(-1) }
    @objc func pause() { playback.togglePause() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func compact() {
        var s = store.data.settings; s.showMeaning = false; s.width = 160
        try? apply(s); settingsWindow?.reloadAppearance()
    }
    @objc func openSettings() {
        closeCard()
        if settingsWindow == nil { settingsWindow = SettingsController(app: self) }
        settingsWindow!.reload(); settingsWindow!.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true); settingsWindow!.window?.makeKeyAndOrderFront(nil)
    }
    @objc func openLibrary() {
        closeCard()
        if libraryWindow == nil { libraryWindow = LibraryController(app: self) }
        libraryWindow!.refresh(); libraryWindow!.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true); libraryWindow!.window?.makeKeyAndOrderFront(nil)
    }
    func quickMenu() {
        let menu = NSMenu()
        for (title, action) in [("Open word card", #selector(toggleCard)), ("Previous word", #selector(previous)), ("Next word", #selector(next)), (playback.manuallyPaused ? "Resume" : "Pause", #selector(pause)), ("Compact display", #selector(compact)), ("Word library & favorites…", #selector(openLibrary)), ("Settings…", #selector(openSettings)), ("Quit CíBar", #selector(quit))] {
            let m = menu.addItem(withTitle: title, action: action, keyEquivalent: ""); m.target = self
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: pill)
    }
    func alert(_ message: String) {
        let a = NSAlert(); a.messageText = "CíBar"; a.informativeText = message; a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true); a.runModal()
    }
    func importList() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText]; p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let pack = "custom-" + UUID().uuidString
            let words = try Store.importWords(text: text, delimiter: url.pathExtension.lowercased() == "csv" ? "," : "\t", pack: pack)
            store.data.customWords.append(contentsOf: words.map { var w = $0; w.source = "User import: \(url.lastPathComponent)"; return w })
            var s = store.data.settings; s.pack = pack; s.levels = [0]; s.ranges = [:]; s.favoritesOnly = false
            try apply(s); settingsWindow?.reload(); libraryWindow?.refresh()
            alert("Imported \(words.count) words. Your HSK lists and their progress are preserved.")
        } catch { alert(error.localizedDescription) }
    }
    func licenses() -> String { (try? String(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("ATTRIBUTIONS.txt"), encoding: .utf8)) ?? "" }
    func exportBackup(to destination: URL? = nil) {
        persistSession()
        var url = destination
        if url == nil {
            let p = NSSavePanel(); p.nameFieldStringValue = "CiBar-Backup.json"; p.allowedContentTypes = [.json]
            guard p.runModal() == .OK else { return }; url = p.url
        }
        guard let url = url else { return }
        do {
            let backup = Backup(data: store.data, words: store.bundledWords, licenses: licenses())
            try Store.writeBackup(backup, to: url)
            if destination == nil { alert("Backup saved. It includes vocabulary, settings, favorites and progress.") }
        } catch { alert(error.localizedDescription) }
    }
    func restore(_ url: URL) throws {
        let backup = try JSONDecoder().decode(Backup.self, from: Data(contentsOf: url))
        guard backup.format == "CiBarBackup", backup.version == 1, backup.data.schemaVersion == 1 else { throw AppError.message("This is not a supported CíBar backup.") }
        var settings = backup.data.settings; try settings.validate()
        try Store.validateWords(backup.words + backup.data.customWords)
        guard !Playback.select(backup.words + backup.data.customWords, settings: settings, favorites: backup.data.favorites).isEmpty else { throw AppError.message("The backup's selection has no words.") }
        persistSession()
        let recovery = store.directory.appendingPathComponent("before-restore-\(Int(Date().timeIntervalSince1970)).json")
        try Store.writeBackup(Backup(data: store.data, words: store.bundledWords, licenses: licenses()), to: recovery)
        // Preserve bundled vocabulary from the restored snapshot, even on a newer app.
        let encoder = JSONEncoder()
        try encoder.encode(backup.words).write(to: store.directory.appendingPathComponent("restored-words.json"), options: .atomic)
        store.bundledWords = backup.words; store.data = backup.data; store.data.settings = settings
        configureSelection(); settingsWindow?.reload(); libraryWindow?.refresh()
    }
    func restoreBackup() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.json]
        guard p.runModal() == .OK, let url = p.url else { return }
        do { try restore(url); alert("Backup restored. Your previous state was backed up in the CíBar data folder.") }
        catch { alert("Restore failed: \(error.localizedDescription)") }
    }
    func writeDiagnostics() {
        guard CommandLine.arguments.contains("--diagnostics") else { return }
        let dict: [String: Any] = ["wordCount":store.allWords.count, "selectedCount":playback.words.count, "current":playback.current?.hanzi ?? "", "serial":playback.current?.serial ?? 0, "interval":playback.interval, "fill":store.data.settings.showFill, "pid":ProcessInfo.processInfo.processIdentifier]
        if let d = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) { try? d.write(to: store.directory.appendingPathComponent("diagnostics.json"), options: .atomic) }
    }
    func applicationWillTerminate(_ notification: Notification) { persistSession() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }
}
