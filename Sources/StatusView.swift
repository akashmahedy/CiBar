import AppKit
import QuartzCore

final class PillView: NSView {
    let track = CALayer()
    let fill = CALayer()
    let textField = NSTextField(labelWithString: "CíBar")
    var click: (() -> Void)?
    var quickMenu: (() -> Void)?
    var settings = Settings()
    var word: Word?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6; layer?.masksToBounds = true
        layer?.addSublayer(track); layer?.addSublayer(fill)
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        textField.isEditable = false; textField.isSelectable = false
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.cell?.usesSingleLineMode = true
        addSubview(textField)
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityLabel("CíBar vocabulary"); setAccessibilityHelp("Open the word card. Right-click for quick controls.")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) { click?() }
    override func rightMouseDown(with event: NSEvent) { quickMenu?() }
    override func accessibilityPerformPress() -> Bool { click?(); return true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
    static func color(hex: String) -> NSColor {
        let n = Int(hex, radix: 16) ?? 0x5A919C
        return NSColor(srgbRed: CGFloat((n >> 16) & 255)/255, green: CGFloat((n >> 8) & 255)/255, blue: CGFloat(n & 255)/255, alpha: 1)
    }
    static func mix(_ a: NSColor, _ b: NSColor, weight: CGFloat) -> NSColor {
        let x = a.usingColorSpace(.sRGB)!, y = b.usingColorSpace(.sRGB)!
        return NSColor(srgbRed: x.redComponent*(1-weight)+y.redComponent*weight, green: x.greenComponent*(1-weight)+y.greenComponent*weight, blue: x.blueComponent*(1-weight)+y.blueComponent*weight, alpha: 1)
    }
    static func palette(settings: Settings, dark: Bool) -> (NSColor, NSColor, NSColor) {
        let hex = ["Ocean":"528F9D", "Sage":"699579", "Plum":"9A79AE", "Amber":"AF8947", "Graphite":"858D95"][settings.preset] ?? settings.customColor
        let bg = color(hex: dark ? "2B3035" : "EFF2F4")
        let strength: CGFloat = ["Soft":0.14, "Balanced":0.23, "Strong":0.30][settings.contrast] ?? 0.14
        let tint = mix(bg, color(hex: hex), weight: strength)
        return (bg, tint, color(hex: dark ? "F7FAFC" : "17232A"))
    }
    func updateColors() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let (bg, tint, fg) = Self.palette(settings: settings, dark: dark)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.backgroundColor = settings.highlight ? bg.cgColor : NSColor.clear.cgColor
        fill.backgroundColor = tint.cgColor; fill.isHidden = !settings.showFill
        CATransaction.commit()
        textField.textColor = settings.highlight ? fg : .labelColor
    }
    func configure(word: Word?, settings: Settings, availableWidth: CGFloat) -> CGFloat {
        self.word = word; self.settings = settings
        let title = word.map { settings.title(for: $0) } ?? "CíBar · no words"
        let font = NSFont.systemFont(ofSize: settings.fontSize, weight: .medium)
        textField.font = font; textField.stringValue = title
        let natural = ceil((title as NSString).size(withAttributes: [.font: font]).width) + 16
        let cap = max(60, min(settings.width, availableWidth))
        let w = settings.adaptiveWidth ? min(cap, max(48, natural)) : cap
        frame.size = NSSize(width: w, height: 22)
        let textHeight = textField.fittingSize.height
        textField.frame = NSRect(x: 8, y: (22-textHeight)/2, width: w-16, height: textHeight)
        toolTip = word.map { "\($0.reference) · \($0.hanzi) · \($0.pinyin) · \($0.english)" } ?? "No words match your selection. Open settings."
        setAccessibilityLabel(toolTip ?? title)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.frame = bounds
        fill.position = CGPoint(x: 0, y: bounds.midY)
        fill.bounds.size.height = bounds.height
        CATransaction.commit(); updateColors()
        return w
    }
    func countdown(fraction: Double, duration: Double, paused: Bool, reducedMotion: Bool) {
        fill.removeAllAnimations()
        let start = bounds.width * CGFloat(max(0, min(1, fraction)))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fill.bounds.size.width = paused || reducedMotion ? start : 0
        CATransaction.commit()
        guard settings.showFill, !paused, !reducedMotion, duration > 0 else { return }
        let animation = CABasicAnimation(keyPath: "bounds.size.width")
        animation.fromValue = start; animation.toValue = 0
        animation.duration = duration; animation.timingFunction = CAMediaTimingFunction(name: .linear)
        fill.add(animation, forKey: "countdown")
    }
}

func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let v = NSTextField(wrappingLabelWithString: text); v.font = .systemFont(ofSize: size, weight: weight)
    v.textColor = color; v.isSelectable = true; return v
}
func button(_ title: String, target: AnyObject, action: Selector) -> NSButton {
    let b = NSButton(title: title, target: target, action: action); b.bezelStyle = .rounded; return b
}
func vertical(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
    let s = NSStackView(views: views); s.orientation = .vertical; s.alignment = .leading; s.spacing = spacing; return s
}
func horizontal(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
    let s = NSStackView(views: views); s.orientation = .horizontal; s.alignment = .centerY; s.spacing = spacing; return s
}
func fit(_ view: NSView, width: CGFloat? = nil, height: CGFloat? = nil) {
    view.translatesAutoresizingMaskIntoConstraints = false
    if let w = width { view.widthAnchor.constraint(equalToConstant: w).isActive = true }
    if let h = height { view.heightAnchor.constraint(equalToConstant: h).isActive = true }
}
func insetStack(_ stack: NSStackView, in view: NSView, inset: CGFloat = 24) {
    view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: inset), stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -inset)])
}
final class FlippedView: NSView { override var isFlipped: Bool { true } }
