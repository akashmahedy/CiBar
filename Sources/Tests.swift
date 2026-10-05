import AppKit
import QuartzCore

func check(_ test: @autoclosure () -> Bool, _ message:String) throws {
    if !test(){throw AppError.message(message)}
}
func rejects(_ body:() throws -> Void) -> Bool {do{try body();return false}catch{return true}}
func runTests() throws {
    let url=Bundle.main.resourceURL!.appendingPathComponent("words.json")
    let words=try JSONDecoder().decode([Word].self,from:Data(contentsOf:url))
    try Store.validateWords(words)
    try check(words.count==5400,"HSK word count")
    for (level,count) in [(1,300),(2,200),(3,500),(4,1000),(5,1600),(6,1800)] {
        let list=words.filter{$0.level==level}
        try check(list.map(\.serial)==Array(1...count),"Level \(level) serials")
    }
    var s=Settings();s.levels=[3,4];s.ranges=["3":WordRange(start:20,end:22),"4":WordRange(start:100,end:101)]
    let selected=Playback.select(words,settings:s,favorites:[])
    try check(selected.map(\.serial)==[20,21,22,100,101],"Multilevel inclusive ranges")
    let engine=Playback();engine.configure(selected,settings:s,snapshot:nil)
    engine.setBlocker("card",active:true)
    let remaining=engine.timeLeft
    engine.setBlocker("sleep",active:true);engine.setBlocker("card",active:false)
    try check(engine.paused && abs(engine.timeLeft-remaining)<0.01,"Overlapping pause blockers")
    engine.togglePause();engine.setBlocker("sleep",active:false)
    try check(engine.paused && engine.manuallyPaused,"Manual pause survives reading card")
    engine.changeInterval(90)
    try check(abs(engine.timeLeft-remaining*2)<0.02,"Delay change preserves progress fraction")
    for _ in 0..<selected.count {engine.advance()}
    try check(engine.current?.id==selected[0].id,"Sequential wraps")
    engine.advance(-1);try check(engine.current?.id==selected.last?.id,"Previous wraps")
    engine.jump(id:selected[2].id);try check(engine.current?.id==selected[2].id,"Jump")
    let snap=engine.snapshot();let restored=Playback();restored.configure(selected,settings:s,snapshot:snap)
    try check(restored.current?.id==engine.current?.id && restored.manuallyPaused,"Resume saved session")
    s.random=true
    let random=Playback();random.configure(selected,settings:s,snapshot:nil)
    var seen=Set<String>()
    for _ in 0..<selected.count {seen.insert(random.current!.id);random.advance()}
    try check(seen.count==selected.count,"Random without replacement")
    s.favoritesOnly=true
    let fav=Playback.select(words,settings:s,favorites:[selected[1].id,selected.last!.id])
    try check(fav.count==2,"Favorites intersection")
    var display=Settings();display.showHanzi=false;display.showPinyin=false;display.showMeaning=false;display.showLevel=false;display.showSerial=false
    try check(display.title(for:words[0])=="CíBar","All display toggles off fallback")
    let csv="serial,hanzi,pinyin,english,example_hanzi,example_pinyin,example_english\n1,好,hǎo,\"good, fine\",你好。,Nǐ hǎo.,Hello.\n"
    let imported=try Store.importWords(text:csv,delimiter:",",pack:"test")
    try check(imported[0].english=="good, fine" && imported[0].example?.english=="Hello.","CSV quotes and examples")
    try check(rejects{_ = try Store.importWords(text:"serial\thanzi\tpinyin\tenglish\n1\t你\tnǐ\tyou\n1\t好\thǎo\tgood",delimiter:"\t",pack:"test")},"Reject duplicate serials")
    try check(rejects{_ = try Store.importWords(text:"serial,hanzi,pinyin,english\n1,你,nǐ,\"broken",delimiter:",",pack:"test")},"Reject broken CSV")
    var invalid=Settings();invalid.interval=Double.nan
    try check(rejects{try invalid.validate()},"Reject nonfinite delay")
    let testDir=FileManager.default.temporaryDirectory.appendingPathComponent("CiBar-test-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:testDir)}
    let store=try Store(directory:testDir);store.data.settings=s;store.data.favorites=[selected[1].id];store.data.customWords=imported;store.data.sessions[s.selectionKey]=snap;try store.save()
    let reloaded=try Store(directory:testDir)
    try check(reloaded.data.favorites==store.data.favorites && reloaded.data.customWords==imported,"Persistent state roundtrip")
    let backup=Backup(data:store.data,words:words,licenses:"test")
    let decoded=try JSONDecoder().decode(Backup.self,from:JSONEncoder().encode(backup))
    try check(decoded.words==words && decoded.data.settings==s,"Full backup roundtrip")
    try check(rejects { try Store.writeBackup(backup,to:testDir) },"Recovery write failure must throw before restore")
    // Every supplied palette, contrast, and extreme custom color keeps readable text.
    func luminance(_ color:NSColor)->Double {
        let c=color.usingColorSpace(.sRGB)!
        func linear(_ v:CGFloat)->Double{let x=Double(v);return x<=0.04045 ? x/12.92:pow((x+0.055)/1.055,2.4)}
        return 0.2126*linear(c.redComponent)+0.7152*linear(c.greenComponent)+0.0722*linear(c.blueComponent)
    }
    func ratio(_ a:NSColor,_ b:NSColor)->Double{let x=luminance(a),y=luminance(b);return(max(x,y)+0.05)/(min(x,y)+0.05)}
    var minimum=100.0
    for dark in [true,false] {for preset in ["Ocean","Sage","Plum","Amber","Graphite","Custom"] {for contrast in ["Soft","Balanced","Strong"] {for color in ["000000","FFFFFF","FF0000","00FF00","0000FF"] {
        var p=Settings();p.preset=preset;p.contrast=contrast;p.customColor=color
        let(bg,fill,fg)=PillView.palette(settings:p,dark:dark)
        minimum=min(minimum,ratio(bg,fg),ratio(fill,fg))
        try check(ratio(bg,fg)>=4.5 && ratio(fill,fg)>=4.5,"Text contrast \(dark) \(preset) \(contrast) \(color)")
    }}}}
    print("5400 rows; playback, filtering, pause, persistence, import, backup tested. Minimum palette contrast: \(String(format:"%.2f",minimum)):1")
    let view=PillView(frame:NSRect(x:0,y:0,width:260,height:22))
    var shortSettings=Settings();shortSettings.showPinyin=false;shortSettings.showMeaning=false
    let shortWidth=view.configure(word:words[0],settings:shortSettings,availableWidth:600)
    let longWidth=view.configure(word:words[1472],settings:Settings(),availableWidth:600)
    try check(shortWidth<longWidth && longWidth<=260,"Adaptive status width")
    shortSettings.adaptiveWidth=false;shortSettings.width=180
    try check(view.configure(word:words[0],settings:shortSettings,availableWidth:600)==180,"Fixed width")
    shortSettings.showFill=true;view.settings=shortSettings
    view.countdown(fraction:0.5,duration:22.5,paused:false,reducedMotion:false)
    let animation=view.fill.animation(forKey:"countdown") as? CABasicAnimation
    try check(animation?.duration==22.5 && animation?.keyPath=="bounds.size.width","Native layer countdown")
    view.countdown(fraction:0.5,duration:22.5,paused:true,reducedMotion:false)
    try check(view.fill.animationKeys()?.isEmpty ?? true,"Paused animation stops")
    shortSettings.highlight=false
    _=view.configure(word:words[0],settings:shortSettings,availableWidth:600)
    try check(view.track.backgroundColor?.alpha==0 && !view.fill.isHidden,"Background and fill toggles are independent")
}

func renderPreviews(directory:URL) throws {
    _=NSApplication.shared
    let words=try JSONDecoder().decode([Word].self,from:Data(contentsOf:Bundle.main.resourceURL!.appendingPathComponent("words.json")))
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    for dark in [false,true] { for size in [13.0,18.0] { for fraction in [1.0,0.5,0.05] {
        let view=PillView(frame:NSRect(x:0,y:0,width:260,height:22))
        view.appearance=NSAppearance(named:dark ? .darkAqua:.aqua)
        var s=Settings();s.fontSize=size;s.contrast="Balanced"
        let w=view.configure(word:words[1363],settings:s,availableWidth:600)
        view.countdown(fraction:fraction,duration:0,paused:true,reducedMotion:false)
        view.layoutSubtreeIfNeeded()
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(w*2),pixelsHigh:44,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        bitmap.size=view.bounds.size;view.cacheDisplay(in:view.bounds,to:bitmap)
        let name="\(dark ? "dark":"light")-\(Int(size))pt-\(Int(fraction*100)).png"
        try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name))
    }}}
}
