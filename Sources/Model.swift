import Foundation

struct Example: Codable, Equatable {
    var hanzi: String
    var pinyin: String
    var english: String
    var attribution: String
    var sourceURL: String
    var pinyinAutomatic: Bool
}
struct Word: Codable, Equatable {
    var id: String
    var pack: String
    var level: Int
    var serial: Int
    var hanzi: String
    var pinyin: String
    var english: String
    var source: String
    var note: String
    var example: Example?
    var reference: String { level > 0 ? "H\(level) · \(serial)" : "\(serial)" }
}
struct WordRange: Codable, Equatable {
    var start: Int
    var end: Int
}
struct Settings: Codable, Equatable {
    var pack = "hsk2025"
    var levels = [4]
    var ranges: [String: WordRange] = [:]
    var interval = 45.0
    var random = false
    var favoritesOnly = false
    var showLevel = true
    var showSerial = true
    var showHanzi = true
    var showPinyin = true
    var showMeaning = true
    var showFill = true
    var highlight = true
    var adaptiveWidth = true
    var fontSize = 13.0
    var width = 260.0
    var preset = "Ocean"
    var contrast = "Soft"
    var customColor = "5A919C"
    var selectionKey: String {
        let r = levels.sorted().map { "\($0):\(ranges[String($0)]?.start ?? 1)-\(ranges[String($0)]?.end ?? 99999)" }.joined(separator: ",")
        return "\(pack)|\(r)|\(random)|\(favoritesOnly)"
    }
    func title(for word: Word) -> String {
        var pieces: [String] = []
        if showLevel && word.level > 0 { pieces.append("H\(word.level)") }
        if showSerial { pieces.append(String(word.serial)) }
        if showHanzi { pieces.append(word.hanzi) }
        if showPinyin { pieces.append(word.pinyin) }
        if showMeaning { pieces.append(word.english) }
        return pieces.isEmpty ? "CíBar" : pieces.joined(separator: " · ")
    }
    mutating func validate() throws {
        guard interval.isFinite, (1...86400).contains(interval), fontSize.isFinite, (9...18).contains(fontSize), width.isFinite, (80...600).contains(width) else { throw AppError.message("Delay must be 1–86400 seconds, font 9–18 pt, width 80–600 pt.") }
        guard !levels.isEmpty, levels.allSatisfy({ (0...6).contains($0) }) else { throw AppError.message("Select at least one level.") }
        levels = Array(Set(levels)).sorted()
        for r in ranges.values { guard r.start >= 1, r.end >= r.start else { throw AppError.message("Ranges must start at 1 or above, with End ≥ Start.") } }
        guard ["Ocean", "Sage", "Plum", "Amber", "Graphite", "Custom"].contains(preset), ["Soft", "Balanced", "Strong"].contains(contrast) else { throw AppError.message("Unknown appearance preset.") }
        guard customColor.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else { throw AppError.message("Custom color must be a six-digit hex color.") }
    }
}
enum AppError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}
struct Snapshot: Codable {
    var order: [String]
    var index: Int
    var remaining: Double
    var manuallyPaused: Bool
}
struct SavedData: Codable {
    var schemaVersion = 1
    var settings = Settings()
    var favorites: Set<String> = []
    var customWords: [Word] = []
    var sessions: [String: Snapshot] = [:]
    var migratedSwiftBar = false
}
struct Backup: Codable {
    var format = "CiBarBackup"
    var version = 1
    var createdAt = Date()
    var data: SavedData
    var words: [Word]
    var licenses: String
}
final class Playback {
    private(set) var words: [Word] = []
    private(set) var index = 0
    private(set) var remaining = 45.0
    private(set) var manuallyPaused = false
    private var blockers: Set<String> = []
    private var startedAt: Double?
    private(set) var interval = 45.0
    private(set) var random = false
    var onChange: (() -> Void)?
    var current: Word? { words.indices.contains(index) ? words[index] : nil }
    var paused: Bool { manuallyPaused || !blockers.isEmpty }
    var timeLeft: Double { max(0, remaining - (startedAt.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0)) }
    var fraction: Double { min(1, timeLeft / interval) }
    static func select(_ words: [Word], settings: Settings, favorites: Set<String>) -> [Word] {
        words.filter { word in
            guard word.pack == settings.pack, settings.levels.contains(word.level), !settings.favoritesOnly || favorites.contains(word.id) else { return false }
            if let r = settings.ranges[String(word.level)] { return (r.start...r.end).contains(word.serial) }
            return true
        }.sorted { $0.level == $1.level ? $0.serial < $1.serial : $0.level < $1.level }
    }
    func configure(_ selected: [Word], settings: Settings, snapshot: Snapshot?) {
        interval = settings.interval; random = settings.random
        words = selected; index = 0; remaining = interval; manuallyPaused = false
        if let snap = snapshot, !words.isEmpty {
            let lookup = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
            if random && Set(snap.order) == Set(lookup.keys) && snap.order.count == lookup.count { words = snap.order.compactMap { lookup[$0] } }
            let oldID = snap.order.indices.contains(snap.index) ? snap.order[snap.index] : nil
            if let id = oldID, let i = words.firstIndex(where: { $0.id == id }) { index = i; remaining = min(interval, max(0.01, snap.remaining)) }
            manuallyPaused = snap.manuallyPaused
        } else if random { words.shuffle() }
        startedAt = paused || words.isEmpty ? nil : ProcessInfo.processInfo.systemUptime
        onChange?()
    }
    func snapshot() -> Snapshot { Snapshot(order: words.map(\.id), index: index, remaining: timeLeft, manuallyPaused: manuallyPaused) }
    func setBlocker(_ key: String, active: Bool) {
        remaining = timeLeft; startedAt = nil
        if active { blockers.insert(key) } else { blockers.remove(key) }
        if !paused && !words.isEmpty { startedAt = ProcessInfo.processInfo.systemUptime }
        onChange?()
    }
    func togglePause() {
        remaining = timeLeft; startedAt = nil; manuallyPaused.toggle()
        if !paused && !words.isEmpty { startedAt = ProcessInfo.processInfo.systemUptime }
        onChange?()
    }
    func advance(_ direction: Int = 1) {
        guard !words.isEmpty else { return }
        if direction > 0 && index == words.count - 1 && random {
            let old = current?.id; words.shuffle()
            if words.count > 1 && words[0].id == old { words.swapAt(0, 1) }
        }
        index = (index + direction + words.count) % words.count
        remaining = interval; startedAt = paused ? nil : ProcessInfo.processInfo.systemUptime
        onChange?()
    }
    func jump(id: String) {
        guard let i = words.firstIndex(where: { $0.id == id }) else { return }
        index = i; remaining = interval; startedAt = paused ? nil : ProcessInfo.processInfo.systemUptime; onChange?()
    }
    func changeInterval(_ seconds: Double) {
        let f = fraction
        interval = seconds; remaining = max(0.01, seconds * f)
        startedAt = paused ? nil : ProcessInfo.processInfo.systemUptime
        onChange?()
    }
}
final class Store {
    let directory: URL
    let url: URL
    var data: SavedData
    var bundledWords: [Word]
    var loadWarning: String?
    var allWords: [Word] { bundledWords + data.customWords }
    init(directory: URL? = nil) throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = directory ?? support.appendingPathComponent("CiBar", isDirectory: true)
        url = self.directory.appendingPathComponent("state.json")
        let resource = Bundle.main.resourceURL!.appendingPathComponent("words.json")
        bundledWords = try JSONDecoder().decode([Word].self, from: Data(contentsOf: resource))
        data = SavedData()
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                data = try JSONDecoder().decode(SavedData.self, from: Data(contentsOf: url))
                guard data.schemaVersion == 1 else { throw AppError.message("Unsupported settings version.") }
                try data.settings.validate(); try Self.validateWords(data.customWords, allowEmpty: true)
            } catch {
                let recovery = self.directory.appendingPathComponent("state-recovery-\(Int(Date().timeIntervalSince1970)).json")
                try FileManager.default.copyItem(at: url, to: recovery)
                loadWarning = "Saved settings could not be loaded. The original file was preserved at \(recovery.path)."
                data = SavedData()
            }
        }
        let restored = self.directory.appendingPathComponent("restored-words.json")
        if FileManager.default.fileExists(atPath: restored.path) {
            let words = try JSONDecoder().decode([Word].self, from: Data(contentsOf: restored))
            try Self.validateWords(words)
            bundledWords = words
        }
    }
    func save() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(data).write(to: url, options: .atomic)
    }
    static func validateWords(_ words: [Word], allowEmpty: Bool = false) throws {
        guard allowEmpty || !words.isEmpty else { throw AppError.message("The word list is empty.") }
        var ids = Set<String>(), serials = Set<String>()
        for w in words {
            guard !w.id.isEmpty, !w.pack.isEmpty, (0...6).contains(w.level), w.serial > 0,
                  !w.hanzi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !w.pinyin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !w.english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  ids.insert(w.id).inserted, serials.insert("\(w.pack):\(w.level):\(w.serial)").inserted else {
                throw AppError.message("Invalid or duplicate entry: \(w.reference) \(w.hanzi). Nothing was imported.")
            }
        }
    }
    static func writeBackup(_ backup: Backup, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(backup).write(to: url, options: .atomic)
    }
    static func parseDelimited(_ text: String, delimiter: Character) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], cell = "", quoted = false
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { cell.append("\""); i += 1 }
                else if quoted || cell.isEmpty { quoted.toggle() }
                else { cell.append(ch) }
            } else if ch == delimiter && !quoted { row.append(cell); cell = "" }
            else if ch == "\n" && !quoted { row.append(cell); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }; row = []; cell = "" }
            else { cell.append(ch) }
            i += 1
        }
        guard !quoted else { throw AppError.message("An imported CSV quote is not closed.") }
        row.append(cell); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }
    static func importWords(text: String, delimiter: Character, pack: String) throws -> [Word] {
        var rows = try parseDelimited(text, delimiter: delimiter)
        guard let header = rows.first else { throw AppError.message("File is empty.") }
        let keys = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "\u{FEFF}", with: "") }
        for name in ["serial", "hanzi", "pinyin", "english"] { guard keys.contains(name) else { throw AppError.message("Required columns: serial, hanzi, pinyin, english. Optional: example_hanzi, example_pinyin, example_english.") } }
        guard Set(keys).count == keys.count else { throw AppError.message("Duplicate column names.") }
        rows.removeFirst()
        var words: [Word] = []
        for (offset, row) in rows.enumerated() {
            guard row.count == keys.count else { throw AppError.message("Row \(offset + 2) has the wrong number of columns.") }
            let f = Dictionary(uniqueKeysWithValues: zip(keys, row))
            guard let serial = Int(f["serial"] ?? "") else { throw AppError.message("Invalid serial on row \(offset + 2).") }
            var example: Example?
            if let h = f["example_hanzi"], !h.isEmpty {
                guard let p = f["example_pinyin"], !p.isEmpty, let e = f["example_english"], !e.isEmpty else { throw AppError.message("Example on row \(offset + 2) needs all three example columns.") }
                example = Example(hanzi: h, pinyin: p, english: e, attribution: "User import", sourceURL: "", pinyinAutomatic: false)
            }
            words.append(Word(id: "\(pack):\(serial)", pack: pack, level: 0, serial: serial, hanzi: f["hanzi"]!, pinyin: f["pinyin"]!, english: f["english"]!, source: "User import", note: "", example: example))
        }
        try validateWords(words); return words
    }
}
