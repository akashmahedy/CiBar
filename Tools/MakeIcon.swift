import AppKit
import Foundation
let output = URL(fileURLWithPath: CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
    let scale=CGFloat(size)/1024
    let ctx=NSGraphicsContext.current!.cgContext;ctx.scaleBy(x:scale,y:scale)
    let rect=NSRect(x:70,y:70,width:884,height:884)
    let path=NSBezierPath(roundedRect:rect,xRadius:196,yRadius:196)
    NSGradient(starting:NSColor(srgbRed:0.12,green:0.27,blue:0.32,alpha:1),ending:NSColor(srgbRed:0.27,green:0.51,blue:0.52,alpha:1))!.draw(in:path,angle:65)
    let attr:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:550,weight:.medium),.foregroundColor:NSColor(srgbRed:0.92,green:0.97,blue:0.94,alpha:1)]
    let text="词" as NSString;let t=text.size(withAttributes:attr);text.draw(at:NSPoint(x:(1024-t.width)/2,y:230),withAttributes:attr)
    let base=NSBezierPath(roundedRect:NSRect(x:244,y:212,width:536,height:36),xRadius:18,yRadius:18)
    NSColor.white.withAlphaComponent(0.16).setFill();base.fill()
    let fill=NSBezierPath(roundedRect:NSRect(x:244,y:212,width:345,height:36),xRadius:18,yRadius:18)
    NSColor(srgbRed:0.71,green:0.86,blue:0.78,alpha:1).setFill();fill.fill()
    NSGraphicsContext.restoreGraphicsState()
    let data=rep.representation(using:.png,properties:[:])!
    if size<=512 {try data.write(to:output.appendingPathComponent("icon_\(size)x\(size).png"))}
    if size>=32 {try data.write(to:output.appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png"))}
}
