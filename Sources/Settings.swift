import AppKit
import ServiceManagement

final class SettingsController: NSWindowController {
    unowned let app: AppController
    let tabs = NSTabView()
    let studyView = NSView(), appearanceView = NSView(), dataView = NSView()
    let packPopup = NSPopUpButton(frame:.zero,pullsDown:false)
    let modePopup = NSPopUpButton(frame:.zero,pullsDown:false)
    let delay = NSTextField(string:"45")
    let favoritesOnly = NSButton(checkboxWithTitle:"Play favorites only (within the selected ranges)",target:nil,action:nil)
    var packIDs:[String] = []
    var levels:[Int] = []
    var levelChecks:[Int:NSButton] = [:]
    var rangeFields:[Int:(NSTextField,NSTextField)] = [:]
    var appearanceChecks:[Int:NSButton] = [:]
    let booleanKeys:[WritableKeyPath<Settings,Bool>] = [\.showLevel,\.showSerial,\.showHanzi,\.showPinyin,\.showMeaning,\.showFill,\.highlight,\.adaptiveWidth]
    let fontSlider = NSSlider(value:13,minValue:9,maxValue:18,target:nil,action:nil)
    let widthSlider = NSSlider(value:260,minValue:80,maxValue:600,target:nil,action:nil)
    let fontValue = NSTextField(string:"13"), widthValue = NSTextField(string:"260")
    let preset = NSPopUpButton(frame:.zero,pullsDown:false), contrast = NSPopUpButton(frame:.zero,pullsDown:false)
    let colorWell = NSColorWell()
    let preview = PillView(frame:NSRect(x:0,y:0,width:260,height:22))
    let login = NSButton(checkboxWithTitle:"Launch CíBar at login",target:nil,action:nil)
    let dataLabel = label("",size:13,color:.secondaryLabelColor)
    let selectionLabel = label("",size:12,color:.secondaryLabelColor)
    init(app:AppController) {
        self.app = app
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:720,height:700),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title = "CíBar · Settings"; window.center()
        super.init(window:window)
        tabs.tabViewType = .topTabsBezelBorder
        for (name,view) in [("Study",studyView),("Appearance",appearanceView),("Data & Backup",dataView)] {
            let item = NSTabViewItem(identifier:name); item.label=name; item.view=view; tabs.addTabViewItem(item)
        }
        let title = horizontal([label("CíBar",size:25,weight:.semibold),vertical([label("A little Chinese, throughout your day.",size:13,color:.secondaryLabelColor),label("Created by Akash Mahedy · @akashmahedy",size:11,color:.secondaryLabelColor)],spacing:3)])
        let stack = vertical([title,tabs],spacing:18)
        insetStack(stack,in:window.contentView!,inset:24)
        fit(tabs,width:672,height:596)
        packPopup.target = self; packPopup.action = #selector(packChanged)
        buildAppearance(); buildData(); reload()
    }
    required init?(coder:NSCoder) { fatalError() }
    func reload() {
        packIDs = ["hsk2025"] + Array(Set(app.store.data.customWords.map(\.pack))).sorted()
        packPopup.removeAllItems()
        for id in packIDs {
            let title:String
            if id=="hsk2025" { title="HSK 3.0 · 2025 syllabus · Levels 1–6" }
            else if id=="legacy-hsk4" { title="Previous corrected HSK4 · migration copy" }
            else { title=app.store.data.customWords.first(where:{$0.pack==id})?.source.replacingOccurrences(of:"User import: ",with:"") ?? "Custom list" }
            packPopup.addItem(withTitle:title)
        }
        packPopup.selectItem(at:packIDs.firstIndex(of:app.store.data.settings.pack) ?? 0)
        rebuildStudy(); reloadAppearance()
        let counts = (1...6).map { l in "H\(l): \(app.store.bundledWords.filter{$0.level==l}.count)" }.joined(separator:"  ·  ")
        dataLabel.stringValue = "Offline HSK words: \(app.store.bundledWords.count)\n\(counts)\n\nCustom / preserved words: \(app.store.data.customWords.count)\nFavorites: \(app.store.data.favorites.count)\n\nSettings are saved on this Mac. Export a backup to move everything to another Mac. No account or cloud service is required."
    }
    @objc func packChanged() { rebuildStudy() }
    func rebuildStudy() {
        for v in studyView.subviews { v.removeFromSuperview() }
        levelChecks = [:]; rangeFields = [:]
        let id = packIDs[packPopup.indexOfSelectedItem]
        levels = id=="hsk2025" ? Array(1...6) : [0]
        let s=app.store.data.settings
        let header=label("Choose levels and a serial range for each",size:17,weight:.semibold)
        fit(packPopup,width:560)
        let table=vertical([],spacing:10)
        let columnLabels=horizontal([label("Level",size:11,color:.secondaryLabelColor),label("Start",size:11,color:.secondaryLabelColor),label("End",size:11,color:.secondaryLabelColor)])
        fit(columnLabels.views[0],width:220); fit(columnLabels.views[1],width:94)
        table.addArrangedSubview(columnLabels)
        for l in levels {
            let count=app.store.allWords.filter{$0.pack==id && $0.level==l}.count
            let c=NSButton(checkboxWithTitle:l==0 ? "Custom list · \(count) words" : "HSK \(l) · \(count) words",target:nil,action:nil)
            c.state = id==s.pack && s.levels.contains(l) ? .on : .off
            if id != s.pack { c.state = .on }
            fit(c,width:220)
            let a=NSTextField(string:""),b=NSTextField(string:"")
            a.placeholderString="1"; b.placeholderString=String(count)
            fit(a,width:94);fit(b,width:94)
            if id==s.pack, let r=s.ranges[String(l)] { a.stringValue=String(r.start);b.stringValue=String(r.end) }
            levelChecks[l]=c;rangeFields[l]=(a,b)
            table.addArrangedSubview(horizontal([c,a,b,label("inclusive",size:11,color:.tertiaryLabelColor)]))
        }
        modePopup.removeAllItems();modePopup.addItems(withTitles:["Sequential","Random · no repeats within a cycle"]);modePopup.selectItem(at:s.random ? 1:0);fit(modePopup,width:260)
        delay.stringValue=String(Int(s.interval));fit(delay,width:86)
        favoritesOnly.state=s.favoritesOnly ? .on:.off
        let playbackRow=horizontal([label("Playback"),modePopup])
        let delayRow=horizontal([label("Time per word"),delay,label("seconds · 1–86400",size:12,color:.secondaryLabelColor)])
        selectionLabel.stringValue="Current selection: \(app.playback.words.count) words. Settings below apply when you click Apply."
        let stack=vertical([header,packPopup,table,label("Blank range = all words in that level. Serial numbers stay level-local.",size:11,color:.secondaryLabelColor),playbackRow,delayRow,favoritesOnly,button("Apply study settings",target:self,action:#selector(applyStudy)),selectionLabel,login],spacing:15)
        login.target=self;login.action=#selector(loginChanged);login.state=SMAppService.mainApp.status == .enabled ? .on:.off
        insetStack(stack,in:studyView,inset:24)
    }
    @objc func applyStudy() {
        do {
            var s=app.store.data.settings;s.pack=packIDs[packPopup.indexOfSelectedItem]
            s.levels=levels.filter{levelChecks[$0]!.state == .on};s.ranges=[:]
            for l in s.levels {
                let (a,b)=rangeFields[l]!,maxSerial=app.store.allWords.filter{$0.pack==s.pack && $0.level==l}.map(\.serial).max() ?? 1
                let start=a.stringValue.trimmingCharacters(in:.whitespaces),end=b.stringValue.trimmingCharacters(in:.whitespaces)
                if !start.isEmpty || !end.isEmpty {
                    guard let first=Int(start.isEmpty ? "1":start), let last=Int(end.isEmpty ? String(maxSerial):end), first>=1,last>=first,last<=maxSerial else { throw AppError.message("Invalid range for \(l==0 ? "custom list":"HSK \(l)"). Use 1–\(maxSerial).") }
                    s.ranges[String(l)]=WordRange(start:first,end:last)
                }
            }
            guard let seconds=Double(delay.stringValue) else { throw AppError.message("Enter a number of seconds.") }
            s.interval=seconds;s.random=modePopup.indexOfSelectedItem==1;s.favoritesOnly=favoritesOnly.state == .on
            try app.apply(s);selectionLabel.stringValue="Applied · \(app.playback.words.count) words · \(Int(seconds)) seconds per word"
        }catch{app.alert(error.localizedDescription)}
    }
    func buildAppearance() {
        let names=["Level label","Serial number","Hanzi","Pinyin","English meaning","Smooth countdown fill","Highlight background","Adaptive width (short words stay short)"]
        var checks:[NSView]=[]
        for (i,name) in names.enumerated() {
            let b=NSButton(checkboxWithTitle:name,target:self,action:#selector(appearanceChanged(_:)));b.tag=i
            appearanceChecks[i]=b;checks.append(b)
        }
        let grid=horizontal([vertical(Array(checks[0...3]),spacing:10),vertical(Array(checks[4...7]),spacing:10)],spacing:40)
        for (slider,field,tag) in [(fontSlider,fontValue,10),(widthSlider,widthValue,11)] {
            slider.target=self;slider.action=#selector(sliderChanged(_:));slider.tag=tag;slider.isContinuous=false
            field.target=self;field.action=#selector(sizeEdited(_:));field.tag=tag
            fit(slider,width:350);fit(field,width:64)
        }
        preset.addItems(withTitles:["Ocean","Sage","Plum","Amber","Graphite","Custom"]);contrast.addItems(withTitles:["Soft","Balanced","Strong"])
        preset.target=self;preset.action=#selector(appearanceChanged(_:));preset.tag=20
        contrast.target=self;contrast.action=#selector(appearanceChanged(_:));contrast.tag=21
        colorWell.target=self;colorWell.action=#selector(colorChanged);fit(colorWell,width:44,height:28)
        let fontRow=horizontal([label("Font size"),fontSlider,fontValue,label("pt",size:12,color:.secondaryLabelColor)])
        let widthRow=horizontal([label("Width cap"),widthSlider,widthValue,label("pt",size:12,color:.secondaryLabelColor)])
        fit(fontRow.views[0],width:72);fit(widthRow.views[0],width:72)
        let colorRow=horizontal([label("Preset"),preset,label("Contrast"),contrast,label("Custom"),colorWell])
        let previewContainer=NSView();fit(previewContainer,width:600,height:36);previewContainer.addSubview(preview)
        preview.frame.origin=NSPoint(x:0,y:7)
        let help=label("Appearance changes apply immediately. All text fields can be switched off; CíBar then shows its name. The card always keeps the full vocabulary. Width is capped by available screen space.",size:12,color:.secondaryLabelColor);fit(help,width:600)
        let stack=vertical([label("Make the menu bar your own",size:17,weight:.semibold),grid,fontRow,widthRow,colorRow,label("LIVE PREVIEW",size:11,weight:.semibold,color:.secondaryLabelColor),previewContainer,help,button("Reset appearance",target:self,action:#selector(resetAppearance))],spacing:20)
        insetStack(stack,in:appearanceView,inset:24)
    }
    func reloadAppearance() {
        let s=app.store.data.settings
        for (i,b) in appearanceChecks { b.state=s[keyPath:booleanKeys[i]] ? .on:.off }
        fontSlider.doubleValue=s.fontSize;widthSlider.doubleValue=s.width;fontValue.stringValue=String(Int(s.fontSize));widthValue.stringValue=String(Int(s.width))
        preset.selectItem(withTitle:s.preset);contrast.selectItem(withTitle:s.contrast);colorWell.color=PillView.color(hex:s.customColor)
        refreshPreview()
    }
    func refreshPreview() {
        let word=app.playback.current ?? app.store.bundledWords[0]
        _=preview.configure(word:word,settings:app.store.data.settings,availableWidth:600)
        preview.countdown(fraction:0.65,duration:0,paused:true,reducedMotion:false)
    }
    @objc func appearanceChanged(_ sender:NSControl) {
        var s=app.store.data.settings
        if sender.tag < booleanKeys.count { s[keyPath:booleanKeys[sender.tag]]=(sender as! NSButton).state == .on }
        if sender.tag==20 { s.preset=preset.titleOfSelectedItem! }
        if sender.tag==21 { s.contrast=contrast.titleOfSelectedItem! }
        applyAppearance(s)
    }
    @objc func sliderChanged(_ sender:NSSlider) {
        var s=app.store.data.settings
        if sender.tag==10 { s.fontSize=sender.doubleValue.rounded() } else { s.width=sender.doubleValue.rounded() }
        applyAppearance(s)
    }
    @objc func sizeEdited(_ sender:NSTextField) {
        var s=app.store.data.settings
        if let value=Double(sender.stringValue) { if sender.tag==10 { s.fontSize=value }else{s.width=value};applyAppearance(s) }
        else{app.alert("Enter a numeric size.");reloadAppearance()}
    }
    @objc func colorChanged() {
        guard let c=colorWell.color.usingColorSpace(.sRGB) else{return}
        var s=app.store.data.settings;s.customColor=String(format:"%02X%02X%02X",Int(c.redComponent*255),Int(c.greenComponent*255),Int(c.blueComponent*255));s.preset="Custom";applyAppearance(s)
    }
    func applyAppearance(_ settings:Settings) {
        do {
            var s=settings;try s.validate();app.store.data.settings=s;app.refreshDisplay();app.save();reloadAppearance()
        } catch {app.alert(error.localizedDescription);reloadAppearance()}
    }
    @objc func resetAppearance() {
        var s=app.store.data.settings;let d=Settings()
        for key in booleanKeys{s[keyPath:key]=d[keyPath:key]}
        s.fontSize=d.fontSize;s.width=d.width;s.preset=d.preset;s.contrast=d.contrast;s.customColor=d.customColor
        applyAppearance(s)
    }
    @objc func loginChanged() {
        do {
            if login.state == .on {try SMAppService.mainApp.register()}else{try SMAppService.mainApp.unregister()}
            if SMAppService.mainApp.status == .requiresApproval {
                app.alert("macOS requires you to approve CíBar in System Settings → General → Login Items & Extensions.")
                SMAppService.openSystemSettingsLoginItems()
            }
        }catch{app.alert("Launch at login could not be changed: \(error.localizedDescription)")}
        login.state=SMAppService.mainApp.status == .enabled ? .on:.off
    }
    func buildData() {
        fit(dataLabel,width:595)
        let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1.0.1"
        let stack=vertical([label("Your words, portable",size:17,weight:.semibold),dataLabel,horizontal([button("Import CSV / TSV…",target:self,action:#selector(importWords)),button("Open word library",target:app,action:#selector(AppController.openLibrary))]),horizontal([button("Export backup…",target:self,action:#selector(exportBackup)),button("Restore backup…",target:self,action:#selector(restoreBackup))]),horizontal([button("Open data folder",target:self,action:#selector(openFolder)),button("Sources & licenses",target:self,action:#selector(openLicenses)),button("Data review",target:self,action:#selector(openReview))]),label("Import columns: serial, hanzi, pinyin, english. Optional example_hanzi, example_pinyin, example_english. CSV supports quoted commas; TSV uses tabs. Custom serials must be unique positive numbers.",size:12,color:.secondaryLabelColor),label("CíBar \(version) · Native macOS app · No subscription\nExamples are sourced when available. Automatic sentence Pinyin is labelled. Vocabulary is a study aid; meanings depend on context.",size:11,color:.secondaryLabelColor)],spacing:22)
        insetStack(stack,in:dataView,inset:24)
    }
    @objc func importWords(){app.importList()}
    @objc func exportBackup(){app.exportBackup()}
    @objc func restoreBackup(){app.restoreBackup()}
    @objc func openFolder(){NSWorkspace.shared.open(app.store.directory)}
    @objc func openLicenses(){NSWorkspace.shared.open(Bundle.main.resourceURL!.appendingPathComponent("ATTRIBUTIONS.txt"))}
    @objc func openReview(){NSWorkspace.shared.open(Bundle.main.resourceURL!.appendingPathComponent("DATA-REVIEW.json"))}
}
