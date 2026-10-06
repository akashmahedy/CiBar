// Promotional media rendered from the app's real AppKit views.
// This tool uses an isolated store; it never starts the installed app.
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
_ = NSApplication.shared
NSApp.appearance = NSAppearance(named: .aqua)
let temp = FileManager.default.temporaryDirectory.appendingPathComponent("CiBar-demo-" + UUID().uuidString)
let store = try Store(directory: temp)
let controller = AppController(store: store)
let words = ["安排", "按"].map { name in store.bundledWords.first { $0.hanzi == name }! }
var settings = Settings()
settings.width = 390
settings.contrast = "Balanced"
controller.playback.configure(words, settings: settings, snapshot: nil)
let card = WordCardController(app: controller)
let cardWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 640), styleMask: .borderless, backing: .buffered, defer: false)
cardWindow.appearance = NSAppearance(named: .aqua)
cardWindow.contentViewController = card
card.refresh()
card.view.layoutSubtreeIfNeeded()

func capture(_ view: NSView) -> NSImage {
    view.layoutSubtreeIfNeeded()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = view.bounds.size
    view.cacheDisplay(in: view.bounds, to: rep)
    let image = NSImage(size: view.bounds.size); image.addRepresentation(rep)
    return image
}
let pill = PillView(frame: NSRect(x: 0, y: 0, width: 390, height: 22))
pill.appearance = NSAppearance(named: .aqua)
let cardImage = capture(card.view)
let ink = PillView.color(hex: "17373C")
let teal = PillView.color(hex: "427F80")
let muted = PillView.color(hex: "526C70")

func frame(time: Double, portrait: Bool, gif: Bool = false) -> NSBitmapImageRep {
    let width = portrait ? 1080 : 1280, height = portrait ? 1920 : 720
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let W = CGFloat(width), H = CGFloat(height)
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x, y: H-y-h, width: w, height: h) }
    func box(_ r: NSRect, color: NSColor, radius: CGFloat = 22) { color.setFill(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill() }
    func text(_ s: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor = ink, weight: NSFont.Weight = .regular, width: CGFloat? = nil) {
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byWordWrapping
        (s as NSString).draw(in: rect(x, y, width ?? W-x-64, size*3.3), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: p])
    }
    box(rect(0,0,W,H),color:PillView.color(hex:"F5F3EC"),radius:0)
    box(rect(W-340,-120,520,520),color:PillView.color(hex:"DFEAE3"),radius:260)
    let t = gif ? time*2 : time
    let showingCard = t >= 12 && t < 21
    let outro = t >= 21
    text("CíBar",x:64,y:portrait ? 90:45,size:portrait ? 88:52,weight:.bold)
    text("A little Chinese, throughout your day.",x:64,y:portrait ? 207:116,size:portrait ? 35:25,color:muted)
    let caption = outro ? "Free. Offline. Open source." : showingCard ? "Click for meaning + a sourced example." : t < 3 ? "Chinese vocabulary in your Mac menu bar." : "Hanzi + Pinyin + English. A gentle timer."
    text(caption,x:64,y:portrait ? 295:172,size:portrait ? 36:25,weight:.semibold)
    let index = t < 21 ? 0 : 1
    // The reading card is the first word; it holds the timer while open.
    let activeWord = showingCard ? words[0] : words[index]
    _ = pill.configure(word: activeWord, settings: settings, availableWidth: 390)
    let fraction = showingCard ? 0.55 : t < 3 ? 1 : t < 12 ? max(0,1-(t-3)/9) : max(0,1-(t-21)/4)
    pill.countdown(fraction:fraction,duration:0,paused:true,reducedMotion:false)
    let nativePill = capture(pill)
    let scale: CGFloat = portrait ? 2.35 : 1.8
    let pw = pill.bounds.width*scale
    let barY: CGFloat = portrait ? 420:247
    box(rect(64,barY-18,W-128,22*scale+36),color:.white,radius:16)
    nativePill.draw(in:rect(showingCard && !portrait ? 80 : (W-pw)/2,barY,pw,22*scale))
    if showingCard {
        let cw: CGFloat = portrait ? 816:326, ch = cw*640/480
        let cx = portrait ? (W-cw)/2 : W-cw-64
        let cy: CGFloat = portrait ? 556:337
        // Landscape card gets the entire available space beneath the header.
        let actualY = portrait ? cy : 205
        box(rect(cx-2,actualY-2,cw+4,ch+4),color:PillView.color(hex:"CADBD7"),radius:16)
        box(rect(cx,actualY,cw,ch),color:.white,radius:14)
        cardImage.draw(in:rect(cx,actualY,cw,ch))
        if !portrait {
            text("Read at your own pace.",x:64,y:370,size:35,weight:.semibold,width:650)
            text("Opening the card pauses the timer.\nClose it to continue.",x:64,y:440,size:25,color:muted,width:600)
        }
        // Editorial click indicator, not a recorded pointer.
        if t < 13 {
            teal.withAlphaComponent(0.6).setStroke()
            let ring=NSBezierPath(ovalIn:rect(W/2-18,barY-7,36,36));ring.lineWidth=3;ring.stroke()
        }
    } else if outro {
        text("Mac stable · Windows 11 preview",x:64,y:portrait ? 625:380,size:portrait ? 40:30,weight:.semibold)
        text("Download CíBar",x:64,y:portrait ? 830:465,size:portrait ? 64:40,color:teal,weight:.bold)
        text("akashmahedy.github.io/CiBar/",x:64,y:portrait ? 930:525,size:portrait ? 37:28)
    } else {
        text("Keep learning while you work.",x:64,y:portrait ? 700:390,size:portrait ? 58:38,weight:.semibold,width:W-128)
        text("Choose HSK levels, word order, delay\nand appearance. No account needed.",x:64,y:portrait ? 865:490,size:portrait ? 37:26,color:muted)
    }
    text("Created by Akash Mahedy · @akashmahedy",x:64,y:H-(portrait ? 145:60),size:portrait ? 27:18,color:muted)
    text("Native UI demo · timing shortened",x:64,y:H-(portrait ? 95:34),size:portrait ? 23:14,color:muted)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func video(portrait: Bool, name: String) throws {
    let url=output.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) }
    let writer=try AVAssetWriter(outputURL:url,fileType:.mp4)
    let width=portrait ? 1080:1280, height=portrait ? 1920:720
    let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:portrait ? 4500000:2500000,AVVideoExpectedSourceFrameRateKey:30]])
    input.expectsMediaDataInRealTime=false
    let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height,kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true])
    writer.add(input);writer.startWriting();writer.startSession(atSourceTime:.zero)
    for n in 0..<750 {
        try autoreleasepool {
            while !input.isReadyForMoreMediaData { if writer.status == .failed { throw writer.error! }; Thread.sleep(forTimeInterval:0.005) }
            let rep=frame(time:Double(n)/30,portrait:portrait)
            var pixel: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&pixel)
            let buffer=pixel!; CVPixelBufferLockBaseAddress(buffer,[])
            let ctx=CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue)!
            ctx.draw(rep.cgImage!,in:CGRect(x:0,y:0,width:width,height:height))
            CVPixelBufferUnlockBaseAddress(buffer,[])
            guard adaptor.append(buffer,withPresentationTime:CMTime(value:Int64(n),timescale:30)) else { throw writer.error ?? AppError.message("Cannot append video frame") }
            if n % 150 == 0 { print("\(name): \(n/30)s");fflush(stdout) }
        }
    }
    input.markAsFinished();let done=DispatchSemaphore(value:0);writer.finishWriting{done.signal()};done.wait()
    guard writer.status == .completed else { throw writer.error ?? AppError.message("Video writer failed") }
}
try video(portrait:true,name:"CiBar-demo-vertical.mp4")
try video(portrait:false,name:"CiBar-demo-landscape.mp4")
let gifURL=output.appendingPathComponent("CiBar-demo.gif")
let destination=CGImageDestinationCreateWithURL(gifURL as CFURL,UTType.gif.identifier as CFString,125,nil)!
CGImageDestinationSetProperties(destination,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
for n in 0..<125 {
    autoreleasepool {
        let rep=frame(time:Double(n)/10,portrait:false,gif:true)
        let small=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:960,pixelsHigh:540,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:small)
        NSImage(cgImage:rep.cgImage!,size:NSSize(width:1280,height:720)).draw(in:NSRect(x:0,y:0,width:960,height:540))
        NSGraphicsContext.restoreGraphicsState()
        CGImageDestinationAddImage(destination,small.cgImage!,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.1]] as CFDictionary)
    }
}
guard CGImageDestinationFinalize(destination) else { throw AppError.message("GIF export failed") }
for t in [4.0,13.5,23.0] { try frame(time:t,portrait:true).representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("preview-\(Int(t)).png")) }
print("Exported two 25-second videos, a 12.5-second GIF and preview frames.")
