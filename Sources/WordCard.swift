import AppKit

final class WordCardController: NSViewController {
    unowned let app: AppController
    var preview: Word?
    var displayed: Word? { preview ?? app.playback.current }
    let reference = label("HSK 4", size: 11, weight: .semibold, color: .secondaryLabelColor)
    let hanzi = label("词", size: 32, weight: .semibold)
    let pinyin = label("cí", size: 19, color: .secondaryLabelColor)
    let meaning = label("word", size: 17)
    let note = label("", size: 11, color: .secondaryLabelColor)
    let exampleHanzi = label("", size: 18)
    let examplePinyin = label("", size: 13, color: .secondaryLabelColor)
    let exampleEnglish = label("", size: 14)
    let exampleNote = label("", size: 10, color: .secondaryLabelColor)
    let source = label("", size: 10, color: .secondaryLabelColor)
    var favoriteButton: NSButton!
    var pauseButton: NSButton!
    let jumpLevel = NSPopUpButton(frame: .zero, pullsDown: false)
    let jumpSerial = NSTextField(string: "")
    init(app: AppController) { self.app = app; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        view = NSView(frame: NSRect(x:0,y:0,width:480,height:640))
        favoriteButton = button("☆ Favorite", target: self, action: #selector(favorite))
        pauseButton = button("Pause", target: app, action: #selector(AppController.pause))
        let header = horizontal([reference, NSView(), favoriteButton])
        let top = vertical([header, hanzi, pinyin, meaning], spacing: 8)
        let example = vertical([label("EXAMPLE",size:11,weight:.semibold,color:.secondaryLabelColor), exampleHanzi, examplePinyin, exampleEnglish, exampleNote], spacing: 8)
        let sep = NSBox(); sep.boxType = .separator
        let sources = horizontal([button("Copy word",target:self,action:#selector(copyWord)),button("Dictionary ↗",target:self,action:#selector(dictionary)),button("Example source ↗",target:self,action:#selector(exampleSource))])
        let body = vertical([top, note, sep, example, sources, source], spacing: 14)
        for v in [meaning,note,exampleHanzi,examplePinyin,exampleEnglish,exampleNote,source] { fit(v,width:424) }
        fit(header,width:424)
        let document = FlippedView(); insetStack(body,in:document,inset:16)
        body.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant:-16).isActive = true
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.documentView = document; fit(scroll,width:456,height:484)
        document.translatesAutoresizingMaskIntoConstraints = false
        document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor).isActive = true
        let nav = horizontal([button("← Previous",target:app,action:#selector(AppController.previous)),pauseButton,button("Next →",target:app,action:#selector(AppController.next))])
        jumpLevel.addItems(withTitles:(1...6).map{"HSK \($0)"} + ["Custom"]); fit(jumpLevel,width:92)
        jumpSerial.placeholderString = "Serial"; fit(jumpSerial,width:78)
        let jump = horizontal([jumpLevel,jumpSerial,button("Jump",target:self,action:#selector(jump)),NSView(),button("Library",target:app,action:#selector(AppController.openLibrary)),button("Settings",target:app,action:#selector(AppController.openSettings))])
        fit(jump,width:456)
        let stack = vertical([scroll,nav,jump,label("Reading card pauses the timer. Close to continue.",size:10,color:.secondaryLabelColor)],spacing:12)
        insetStack(stack,in:view,inset:12)
    }
    func refresh() {
        _ = view
        guard let w = displayed else {
            reference.stringValue = "No words match your selection"
            hanzi.stringValue = "CíBar"; pinyin.stringValue = ""; meaning.stringValue = "Open Settings to choose a list or change your ranges."
            note.stringValue = ""; exampleHanzi.stringValue = ""; examplePinyin.stringValue = ""; exampleEnglish.stringValue = ""; exampleNote.stringValue = ""; source.stringValue = ""
            favoriteButton.isEnabled = false; return
        }
        favoriteButton.isEnabled = true
        reference.stringValue = (preview == nil ? "" : "PREVIEW · ") + w.reference + " · " + (app.store.data.settings.random ? "Random" : "Sequential")
        hanzi.stringValue = w.hanzi; pinyin.stringValue = w.pinyin; meaning.stringValue = w.english
        note.stringValue = w.note.hasPrefix("Prior reviewed") ? "" : w.note
        note.isHidden = note.stringValue.isEmpty
        favoriteButton.title = app.store.data.favorites.contains(w.id) ? "★ Favorited" : "☆ Favorite"
        pauseButton.title = app.playback.manuallyPaused ? "Resume" : "Pause"
        source.stringValue = "Word data: \(w.source)"
        if let e = w.example {
            exampleHanzi.stringValue = e.hanzi; examplePinyin.stringValue = e.pinyin; exampleEnglish.stringValue = e.english
            exampleNote.stringValue = (e.pinyinAutomatic ? "Sentence Pinyin is automatic; polyphonic readings may need checking. Examples may illustrate a different sense.\n" : "") + e.attribution
        } else {
            exampleHanzi.stringValue = "No sourced example in this offline pack."
            examplePinyin.stringValue = ""; exampleEnglish.stringValue = "You can add an example using a custom CSV/TSV list."
            exampleNote.stringValue = "Examples are shown only when available; they are not generated during playback."
        }
        jumpLevel.selectItem(at:w.level > 0 ? w.level-1 : 6)
        jumpSerial.stringValue = String(w.serial)
    }
    @objc func favorite() { if let w = displayed { app.toggleFavorite(w) } }
    @objc func copyWord() {
        guard let w = displayed else { return }
        let text = "\(w.reference) · \(w.hanzi) · \(w.pinyin) · \(w.english)" + (w.example.map{"\n\($0.hanzi)\n\($0.pinyin)\n\($0.english)"} ?? "")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType:.string)
    }
    @objc func dictionary() {
        guard let w = displayed else { return }
        var c = URLComponents(string:"https://www.mdbg.net/chinese/dictionary")!
        c.queryItems = [URLQueryItem(name:"page",value:"worddict"),URLQueryItem(name:"wdqb",value:w.hanzi)]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }
    @objc func exampleSource() {
        if let s = displayed?.example?.sourceURL, let url = URL(string:s), ["https","http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        else { app.alert("This example was written for CíBar, or supplied in your custom import. Attribution appears below the example.") }
    }
    @objc func jump() {
        let level = jumpLevel.indexOfSelectedItem == 6 ? 0 : jumpLevel.indexOfSelectedItem+1
        guard let serial = Int(jumpSerial.stringValue), let w = app.playback.words.first(where:{$0.level==level && $0.serial==serial}) else { app.alert("This word is outside the current levels/ranges. Change your Study selection first."); return }
        preview = nil; app.playback.jump(id:w.id)
    }
}

final class LibraryController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    unowned let app: AppController
    let search = NSSearchField()
    let onlyFavorites = NSButton(checkboxWithTitle:"Favorites only",target:nil,action:nil)
    let table = NSTableView()
    let countLabel = label("",size:12,color:.secondaryLabelColor)
    var filtered:[Word] = []
    init(app: AppController) {
        self.app = app
        let w = NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:580),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        w.title = "CíBar · Word Library"; w.minSize = NSSize(width:660,height:420); w.center()
        super.init(window:w)
        search.placeholderString = "Search Hanzi, Pinyin, meaning or serial"; search.delegate = self; fit(search,width:450)
        onlyFavorites.target = self; onlyFavorites.action = #selector(filterChanged)
        table.addTableColumn(NSTableColumn(identifier:NSUserInterfaceItemIdentifier("word")))
        table.addTableColumn(NSTableColumn(identifier:NSUserInterfaceItemIdentifier("meaning")))
        table.tableColumns[0].title = "Word / Pinyin"; table.tableColumns[0].width = 310
        table.tableColumns[1].title = "English"; table.tableColumns[1].width = 370
        table.dataSource = self; table.delegate = self; table.rowHeight = 44; table.usesAlternatingRowBackgroundColors = true
        table.target = self; table.doubleAction = #selector(readSelected)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        let head = horizontal([search,onlyFavorites])
        let actions = horizontal([button("Read selected",target:self,action:#selector(readSelected)),button("☆ Toggle favorite",target:self,action:#selector(favoriteSelected)),NSView(),countLabel])
        let stack = vertical([head,scroll,actions,label("Double-click to read. Playback stays on your Study selection.",size:11,color:.secondaryLabelColor)])
        insetStack(stack,in:w.contentView!,inset:20)
        scroll.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
        stack.bottomAnchor.constraint(equalTo:w.contentView!.bottomAnchor,constant:-20).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:220).isActive = true
    }
    required init?(coder:NSCoder) { fatalError() }
    @objc func filterChanged() { refresh() }
    func controlTextDidChange(_ obj:Notification) { refresh() }
    func refresh() {
        let selected = table.selectedRow >= 0 && table.selectedRow < filtered.count ? filtered[table.selectedRow].id : nil
        let q = search.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        filtered = app.store.allWords.filter { w in
            (!onlyFavorites.state.boolValue || app.store.data.favorites.contains(w.id)) && (q.isEmpty || "\(w.reference) \(w.hanzi) \(w.pinyin) \(w.english)".range(of:q,options:[.caseInsensitive,.diacriticInsensitive]) != nil)
        }
        table.reloadData(); countLabel.stringValue = "\(filtered.count) words · \(app.store.data.favorites.count) favorites"
        if let id = selected, let i = filtered.firstIndex(where:{$0.id==id}) { table.selectRowIndexes(IndexSet(integer:i),byExtendingSelection:false) }
    }
    func numberOfRows(in tableView:NSTableView)->Int { filtered.count }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
        let w = filtered[row]; let col = tableColumn!.identifier.rawValue
        let prefix = app.store.data.favorites.contains(w.id) ? "★ " : ""
        let text = col=="word" ? "\(prefix)\(w.reference)  \(w.hanzi)\n\(w.pinyin)" : w.english
        let field = label(text,size:13); field.lineBreakMode = .byTruncatingTail; field.maximumNumberOfLines = 2
        let cell = NSTableCellView(); cell.addSubview(field); field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([field.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:8),field.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-8),field.centerYAnchor.constraint(equalTo:cell.centerYAnchor)])
        return cell
    }
    @objc func readSelected() { let i = table.selectedRow; if filtered.indices.contains(i) { app.showCard(preview:filtered[i]) } }
    @objc func favoriteSelected() { let i=table.selectedRow; if filtered.indices.contains(i) { app.toggleFavorite(filtered[i]) } }
}
extension NSControl.StateValue { var boolValue:Bool { self == .on } }
