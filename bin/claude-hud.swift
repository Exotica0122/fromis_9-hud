import AppKit

// fromis_9 theme: a light pink surface with dark plum ink. A dark panel could not be
// read as pink without pushing the text below AA, so the polarity is flipped instead.
let baseTop = NSColor(srgbRed: 1.000, green: 0.878, blue: 0.933, alpha: 0.97)   // #FFE0EE
let baseBottom = NSColor(srgbRed: 1.000, green: 0.749, blue: 0.855, alpha: 0.97) // #FFBFDA
let edge = NSColor(srgbRed: 0.898, green: 0.561, blue: 0.714, alpha: 1)         // #E58FB6
let ink = NSColor(srgbRed: 0.239, green: 0.055, blue: 0.141, alpha: 1)          // #3D0E24
let inkBody = NSColor(srgbRed: 0.353, green: 0.137, blue: 0.251, alpha: 1)      // #5A2340
let inkMeta = NSColor(srgbRed: 0.420, green: 0.165, blue: 0.278, alpha: 1)      // #6B2A47
let inkFaint = NSColor(srgbRed: 0.541, green: 0.314, blue: 0.439, alpha: 1)     // #8A5070
let logoTint = NSColor(srgbRed: 0.690, green: 0.165, blue: 0.384, alpha: 1)     // #B02A62

/// Portraits and their config, in order: $CLAUDE_HUD_PORTRAITS, ~/.claude/portraits,
/// then a portraits/ directory beside the checkout. None present is a supported state.
let portraitDirs: [URL] = {
    let fm = FileManager.default
    var dirs: [URL] = []
    if let env = ProcessInfo.processInfo.environment["CLAUDE_HUD_PORTRAITS"], !env.isEmpty {
        dirs.append(URL(fileURLWithPath: (env as NSString).expandingTildeInPath))
    }
    dirs.append(fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/portraits"))
    let binary = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    dirs.append(binary.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("portraits"))
    return dirs
}()

func portraitFile(_ name: String) -> URL? {
    let fm = FileManager.default
    for dir in portraitDirs {
        let url = dir.appendingPathComponent(name)
        if fm.fileExists(atPath: url.path) { return url }
    }
    return nil
}

struct Member {
    let slug: String
    let name: String
    let hue: NSColor
}

func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

let defaultMembers: [Member] = [
    Member(slug: "hayoung", name: "Hayoung", hue: rgb(143, 52, 0)),
    Member(slug: "jiwon", name: "Jiwon", hue: rgb(7, 73, 111)),
    Member(slug: "chaeyoung", name: "Chaeyoung", hue: rgb(107, 72, 0)),
    Member(slug: "nagyung", name: "Nagyung", hue: rgb(145, 0, 47)),
    Member(slug: "jiheon", name: "Jiheon", hue: rgb(35, 52, 140)),
]

/// "<slug> <display name> <rail hex>" lines in roster.conf; the name may contain spaces.
func loadRoster() -> [Member] {
    guard let url = portraitFile("roster.conf"),
          let text = try? String(contentsOf: url, encoding: .utf8) else { return defaultMembers }
    var out: [Member] = []
    for raw in text.split(separator: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { continue }
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count >= 3, let hue = parseHex(parts[parts.count - 1]) else { continue }
        out.append(Member(slug: parts[0],
                          name: parts[1..<(parts.count - 1)].joined(separator: " "),
                          hue: hue))
    }
    return out.isEmpty ? defaultMembers : out
}

let members: [Member] = loadRoster()

/// Local calendar day, so the rotation happens at your midnight, not UTC's.
func daySeed() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd"
    return f.string(from: Date())
}

func member(for key: String) -> Member {
    guard !key.isEmpty else { return members[0] }
    var hash: UInt64 = 5381
    for byte in key.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
    return members[Int(hash % UInt64(members.count))]
}

struct Options {
    var title = "Claude"
    var badge = ""
    var repoName = ""
    var branch = ""
    var body = ""
    var seconds = 5.0
    var accent: NSColor?
    var member = ""
    var avatar = ""
    var avatarFocus: CGFloat?
    var avatarZoom: CGFloat?
    var sound = "Glass"
    var volume: Float = 1.0
    var screen = "main"
    var avatarSize: CGFloat = 84
    var avatarCorner: CGFloat = 12
    var logo = ""
    var logoHeight: CGFloat = 30
    var logoAlpha: CGFloat = 0.58
    var onClick = ""
    var preview = ""
    var previewBackdrop = "8A8A8A"
    var serve = false
    var previewStack = 0
    var previewExpanded = false
    var solo = false
}

func parseHex(_ s: String) -> NSColor? {
    let hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
    guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
    return rgb(Int((v >> 16) & 0xff), Int((v >> 8) & 0xff), Int(v & 0xff))
}

func parseArgs(_ argv: [String]) -> Options {
    var o = Options()
    var args = argv
    while let flag = args.first {
        args.removeFirst()
        let value = args.first
        func take() -> String { let v = value ?? ""; args = Array(args.dropFirst()); return v }
        switch flag {
        case "--title": o.title = take()
        case "--badge": o.badge = take()
        case "--repo": o.repoName = take()
        case "--branch": o.branch = take()
        case "--body": o.body = take()
        case "--seconds": o.seconds = Double(take()) ?? o.seconds
        case "--accent": o.accent = parseHex(take())
        case "--member": o.member = take()
        case "--avatar": o.avatar = take()
        case "--avatar-focus": o.avatarFocus = Double(take()).map { CGFloat($0) }
        case "--avatar-zoom": o.avatarZoom = Double(take()).map { CGFloat($0) }
        case "--avatar-size": o.avatarSize = CGFloat(Double(take()) ?? 84)
        case "--avatar-corner": o.avatarCorner = CGFloat(Double(take()) ?? 12)
        case "--logo": o.logo = take()
        case "--logo-height": o.logoHeight = CGFloat(Double(take()) ?? 30)
        case "--logo-alpha": o.logoAlpha = CGFloat(Double(take()) ?? 0.58)
        case "--sound": o.sound = take()
        case "--volume": o.volume = Float(take()) ?? o.volume
        case "--screen": o.screen = take()
        case "--on-click": o.onClick = take()
        case "--preview": o.preview = take()
        case "--preview-backdrop": o.previewBackdrop = take()
        case "--serve": o.serve = true
        case "--preview-stack": o.previewStack = Int(take()) ?? 0
        case "--preview-expanded": o.previewExpanded = true
        case "--solo": o.solo = true
        default: break
        }
    }
    return o
}

/// Accepts a path, a file in ~/.claude/sounds, or a macOS system sound name.
func resolveSound(_ name: String) -> URL? {
    if name.isEmpty || name == "none" { return nil }
    let fm = FileManager.default
    let direct = (name as NSString).expandingTildeInPath
    if fm.fileExists(atPath: direct) { return URL(fileURLWithPath: direct) }
    let home = fm.homeDirectoryForCurrentUser
    let dirs = [home.appendingPathComponent(".claude/sounds"),
                home.appendingPathComponent("Library/Sounds"),
                URL(fileURLWithPath: "/System/Library/Sounds")]
    for dir in dirs {
        for ext in ["aiff", "aif", "wav", "mp3", "m4a", "caf"] {
            let url = dir.appendingPathComponent("\(name).\(ext)")
            if fm.fileExists(atPath: url.path) { return url }
        }
    }
    return nil
}

/// Per-image crop tuning: "<slug> <focus> <zoom>" lines in crops.conf.
func cropConfig(for slug: String) -> (focus: CGFloat, zoom: CGFloat)? {
    guard let url = portraitFile("crops.conf"),
          let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    for raw in text.split(separator: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { continue }
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count >= 3, String(parts[0]) == slug,
              let f = Double(parts[1]), let z = Double(parts[2]) else { continue }
        return (CGFloat(f), CGFloat(z))
    }
    return nil
}

func resolveAvatar(_ explicit: String, slug: String) -> NSImage? {
    if explicit == "none" { return nil }
    let fm = FileManager.default
    if !explicit.isEmpty {
        let path = (explicit as NSString).expandingTildeInPath
        if fm.fileExists(atPath: path) { return NSImage(contentsOfFile: path) }
    }
    for ext in ["webp", "png", "jpg", "jpeg", "heic"] {
        if let url = portraitFile("\(slug).\(ext)") { return NSImage(contentsOf: url) }
    }
    return nil
}

/// Recolour a flat black mark so it reads on the panel.
func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let out = NSImage(size: image.size)
    out.lockFocus()
    let rect = NSRect(origin: .zero, size: image.size)
    image.draw(in: rect)
    color.set()
    rect.fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

/// intrinsicContentSize under-measures these faces by a few points, which makes the cell
/// draw an ellipsis inside a frame that is wide enough. Pin to the measured glyph width;
/// the priority decides who yields first when the row genuinely overflows.
func pinWidth(_ field: NSTextField, priority: Float) {
    guard let font = field.font else { return }
    // boundingRect goes through CoreText, so glyphs served by a fallback face
    // (⏸, ✳) are measured at their real width; NSString.size under-reports them.
    let attributed = NSAttributedString(string: field.stringValue, attributes: [.font: font])
    let unbounded = NSSize(width: CGFloat.greatestFiniteMagnitude,
                           height: CGFloat.greatestFiniteMagnitude)
    let measured = attributed.boundingRect(with: unbounded,
                                           options: [.usesLineFragmentOrigin, .usesFontLeading])
    let c = field.widthAnchor.constraint(equalToConstant: ceil(measured.width) + 3)
    c.priority = NSLayoutConstraint.Priority(priority)
    c.isActive = true
}

func label(_ text: String, font: NSFont, color: NSColor, lines: Int) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = font
    l.textColor = color
    l.lineBreakMode = .byTruncatingTail
    l.maximumNumberOfLines = lines
    l.usesSingleLineMode = lines == 1
    l.cell?.wraps = lines != 1
    l.cell?.truncatesLastVisibleLine = true
    l.translatesAutoresizingMaskIntoConstraints = false
    l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return l
}

final class GradientView: NSView {
    let gradient = CAGradientLayer()
    override func layout() {
        super.layout()
        gradient.frame = bounds
    }
}

/// One notification. Clicking runs its command; hovering the stack pauses its clock.
final class Card: NSView {
    let onClick: String
    var deadline: Date
    var height: CGFloat
    var dismissed = false

    init(frame: NSRect, onClick: String, seconds: Double, height: CGFloat) {
        self.onClick = onClick
        self.deadline = Date().addingTimeInterval(seconds)
        self.height = height
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        guard !onClick.isEmpty else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", onClick]
        try? task.run()
        (window?.delegate as? StackController)?.dismiss(self)
    }
}

let cardWidth: CGFloat = 528
let cardPadding: CGFloat = 16
let cardCorner: CGFloat = 17

/// Builds one notification card and reports the height its content needs.
func buildCard(_ opts: Options, flat: Bool) -> Card {
    let sessionKey = opts.badge.split(separator: ":").first.map(String.init) ?? opts.repoName
    let identity = opts.badge.isEmpty ? opts.repoName : opts.badge
    let chosen: Member
    switch opts.member.lowercased() {
    case "": chosen = member(for: identity + "@" + daySeed())
    case "random": chosen = members.randomElement()!
    case "hash": chosen = member(for: sessionKey)
    default: chosen = members.first { $0.slug == opts.member.lowercased() } ?? member(for: identity)
    }
    let signal = opts.accent ?? chosen.hue
    let avatar = resolveAvatar(opts.avatar, slug: chosen.slug)
    let crop = cropConfig(for: chosen.slug)
    let avatarFocus = opts.avatarFocus ?? crop?.focus ?? 0.30
    let avatarZoom = opts.avatarZoom ?? crop?.zoom ?? 1.7

    let avatarSize = opts.avatarSize
    let railWidth: CGFloat = 3.5
    let leadWidth = avatar == nil ? railWidth : avatarSize

    let logoImage: NSImage? = {
        if opts.logo == "none" { return nil }
        let fm = FileManager.default
        if !opts.logo.isEmpty {
            let path = (opts.logo as NSString).expandingTildeInPath
            return fm.fileExists(atPath: path) ? NSImage(contentsOfFile: path) : nil
        }
        for name in ["logo.svg", "logo.pdf", "logo.png"] {
            if let url = portraitFile(name) { return NSImage(contentsOf: url) }
        }
        return nil
    }()
    let logoRatio: CGFloat = {
        guard let image = logoImage, image.size.height > 0 else { return 1 }
        return image.size.width / image.size.height
    }()
    let logoWidth = logoImage == nil ? 0 : opts.logoHeight * logoRatio
    let logoReserve = logoImage == nil ? 0 : logoWidth + 14
    let textWidth = cardWidth - cardPadding * 2 - leadWidth - 14 - logoReserve

    let card = Card(frame: .zero, onClick: opts.onClick, seconds: opts.seconds, height: 0)
    card.translatesAutoresizingMaskIntoConstraints = false
    card.wantsLayer = true

    // No NSVisualEffectView: the scrim over it sits at alpha 0.97, so the vibrancy
    // material contributed about 3% of the visible pixel while the window server
    // rendered it across the whole window rect — the faint light box behind the card.
    let container = NSView()
    container.wantsLayer = true
    if flat {
        container.layer?.backgroundColor = (parseHex(opts.previewBackdrop) ?? .gray).cgColor
    }
    container.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(container)

    let scrim = GradientView()
    scrim.wantsLayer = true
    scrim.gradient.colors = [baseTop.cgColor, baseBottom.cgColor]
    scrim.gradient.startPoint = CGPoint(x: 0.5, y: 0)
    scrim.gradient.endPoint = CGPoint(x: 0.5, y: 1)
    scrim.layer?.addSublayer(scrim.gradient)
    scrim.layer?.cornerRadius = cardCorner
    scrim.layer?.cornerCurve = .continuous
    scrim.layer?.masksToBounds = true
    scrim.layer?.borderWidth = 1
    scrim.layer?.borderColor = edge.cgColor
    scrim.translatesAutoresizingMaskIntoConstraints = false

    let lead = NSView()
    lead.wantsLayer = true
    lead.translatesAutoresizingMaskIntoConstraints = false
    if let image = avatar {
        var proposed = CGRect(origin: .zero, size: image.size)
        lead.layer?.contents = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
        lead.layer?.contentsGravity = .resizeAspectFill
        lead.layer?.cornerRadius = opts.avatarCorner
        lead.layer?.cornerCurve = .continuous
        lead.layer?.masksToBounds = true
        lead.layer?.borderWidth = 2.5
        lead.layer?.borderColor = signal.cgColor
        let size = image.size
        if size.width > 0, size.height > 0 {
            let side = min(size.width, size.height) / max(1, avatarZoom)
            let rw = side / size.width
            let rh = side / size.height
            // contentsRect measures y from the bottom; avatarFocus is a fraction from the top.
            let y = max(0, min(1 - rh, (1 - avatarFocus) - rh / 2))
            lead.layer?.contentsRect = CGRect(x: (1 - rw) / 2, y: y, width: rw, height: rh)
        }
    } else {
        lead.layer?.backgroundColor = signal.cgColor
        lead.layer?.cornerRadius = railWidth / 2
    }

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 4
    stack.translatesAutoresizingMaskIntoConstraints = false

    let titleLabel = label(opts.title, font: .systemFont(ofSize: 15, weight: .semibold), color: ink, lines: 1)
    pinWidth(titleLabel, priority: 700)
    stack.addArrangedSubview(titleLabel)

    // Laid out by hand: NSStackView compresses a label even when the row has slack.
    let metaRow = NSView()
    metaRow.translatesAutoresizingMaskIntoConstraints = false
    let mono = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .medium)
    var metaItems: [NSTextField] = []
    if !opts.badge.isEmpty {
        let b = label(opts.badge, font: mono, color: signal, lines: 1)
        b.setContentCompressionResistancePriority(.required, for: .horizontal)
        pinWidth(b, priority: 1000)
        metaItems.append(b)
    }
    if !opts.repoName.isEmpty {
        let r = label(opts.repoName, font: .systemFont(ofSize: 11.5), color: inkMeta, lines: 1)
        r.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250), for: .horizontal)
        pinWidth(r, priority: 250)
        metaItems.append(r)
    }
    if !opts.branch.isEmpty {
        let br = label(opts.branch, font: .systemFont(ofSize: 11.5), color: inkFaint, lines: 1)
        br.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(300), for: .horizontal)
        pinWidth(br, priority: 300)
        metaItems.append(br)
    }
    if !metaItems.isEmpty {
        var previous: NSView?
        for item in metaItems {
            metaRow.addSubview(item)
            item.topAnchor.constraint(equalTo: metaRow.topAnchor).isActive = true
            item.bottomAnchor.constraint(equalTo: metaRow.bottomAnchor).isActive = true
            if let prev = previous {
                item.leadingAnchor.constraint(equalTo: prev.trailingAnchor, constant: 10).isActive = true
            } else {
                item.leadingAnchor.constraint(equalTo: metaRow.leadingAnchor).isActive = true
            }
            previous = item
        }
        let tail = previous!.trailingAnchor.constraint(lessThanOrEqualTo: metaRow.trailingAnchor)
        tail.priority = NSLayoutConstraint.Priority(999)
        tail.isActive = true
        stack.addArrangedSubview(metaRow)
        metaRow.widthAnchor.constraint(equalToConstant: textWidth).isActive = true
    }

    if !opts.body.isEmpty {
        let b = label(opts.body, font: .systemFont(ofSize: 12.5), color: inkBody, lines: 2)
        b.preferredMaxLayoutWidth = textWidth
        // Pin the laid-out width to the measured width, or the cell truncates instead of wrapping.
        b.widthAnchor.constraint(equalToConstant: textWidth).isActive = true
        stack.setCustomSpacing(9, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(b)
    }

    container.addSubview(scrim)
    container.addSubview(lead)
    container.addSubview(stack)

    if let raw = logoImage {
        let view = NSImageView()
        view.image = tinted(raw, logoTint)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.alphaValue = opts.logoAlpha
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -cardPadding),
            view.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            view.heightAnchor.constraint(equalToConstant: opts.logoHeight),
            view.widthAnchor.constraint(equalToConstant: logoWidth),
        ])
    }

    let widthConstraint = card.widthAnchor.constraint(equalToConstant: cardWidth)
    var constraints: [NSLayoutConstraint] = [
        widthConstraint,
        container.leadingAnchor.constraint(equalTo: card.leadingAnchor),
        container.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        container.topAnchor.constraint(equalTo: card.topAnchor),
        container.bottomAnchor.constraint(equalTo: card.bottomAnchor),

        scrim.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        scrim.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        scrim.topAnchor.constraint(equalTo: container.topAnchor),
        scrim.bottomAnchor.constraint(equalTo: container.bottomAnchor),

        lead.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: cardPadding),
        lead.widthAnchor.constraint(equalToConstant: leadWidth),

        stack.leadingAnchor.constraint(equalTo: lead.trailingAnchor, constant: 14),
        stack.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                        constant: -(cardPadding + logoReserve)),
        stack.topAnchor.constraint(equalTo: container.topAnchor, constant: cardPadding - 1),
        stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -(cardPadding - 1)),
    ]
    if avatar == nil {
        constraints += [
            lead.topAnchor.constraint(equalTo: container.topAnchor, constant: cardPadding),
            lead.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -cardPadding),
        ]
    } else {
        constraints += [
            lead.heightAnchor.constraint(equalToConstant: avatarSize),
            lead.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: avatarSize + cardPadding * 2),
        ]
    }
    NSLayoutConstraint.activate(constraints)

    card.layoutSubtreeIfNeeded()
    let measured = max(card.fittingSize.height, 66)
    card.height = measured
    // The card was sized by Auto Layout; the stack positions it by frame. Leaving it
    // constraint-driven means the frames layout() assigns are discarded on the next
    // layout pass, so release the root here — its internal constraints still hold.
    widthConstraint.isActive = false
    card.translatesAutoresizingMaskIntoConstraints = true
    card.frame = NSRect(x: 0, y: 0, width: cardWidth, height: measured)
    card.layoutSubtreeIfNeeded()
    return card
}

/// Top-anchored container: laying out from the top is the natural direction here.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Owns the one panel every notification is drawn into. Collapsed, only the newest
/// card is readable and the rest peek beneath it; hovering expands the stack and
/// holds every clock until the pointer leaves.
final class StackController: NSObject, NSWindowDelegate {
    let panel: NSPanel
    let root = FlippedView()
    var cards: [Card] = []
    var peeks: [NSView] = []
    var expanded = false
    var ticker: Timer?
    var idleSince = Date()
    let solo: Bool
    var headless = false
    var screenMode = "main"

    static let gap: CGFloat = 10
    static let peekStep: CGFloat = 7
    static let maxPeeks = 2

    init(solo: Bool) {
        self.solo = solo
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: cardWidth, height: 100),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        super.init()
        panel.appearance = NSAppearance(named: .aqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false          // the panel is transparent between cards
        panel.level = .statusBar
        panel.ignoresMouseEvents = false // clicking a card is the whole point
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = root
        root.wantsLayer = true

        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func mainDisplayScreen() -> NSScreen {
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first ?? NSScreen.main!
    }

    func pointerScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? mainDisplayScreen()
    }

    func add(_ opts: Options) {
        screenMode = opts.screen
        let card = buildCard(opts, flat: false)
        card.deadline = Date().addingTimeInterval(opts.seconds)
        // No shadow at all. Stacked cards overlap their shadows into a grey field that
        // reads as a box behind the panel; the 1px border holds each card's shape.
        cards.insert(card, at: 0)
        root.addSubview(card)
        idleSince = Date()

        if let url = resolveSound(opts.sound), let s = NSSound(contentsOf: url, byReference: false) {
            s.volume = max(0, min(1, opts.volume))
            chimes.append(s)
            s.play()
        }
        layout(animated: false)
        if !headless, !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                panel.animator().alphaValue = 1
            }
        }
    }

    func dismiss(_ card: Card) {
        guard !card.dismissed else { return }
        card.dismissed = true
        cards.removeAll { $0 === card }
        card.removeFromSuperview()
        idleSince = Date()
        if cards.isEmpty { hide() } else { layout(animated: true) }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
            if self?.solo == true { NSApp.terminate(nil) }
        })
    }

    func tick() {
        pollHover()
        if !expanded {
            let now = Date()
            for card in cards where card.deadline <= now { dismiss(card) }
        } else {
            // Hovering holds every clock: push each deadline along with the pointer.
            for card in cards { card.deadline = max(card.deadline, Date().addingTimeInterval(0.3)) }
        }
        if !solo, cards.isEmpty, Date().timeIntervalSince(idleSince) > 45 { NSApp.terminate(nil) }
    }

    func layout(animated: Bool) {
        guard let front = cards.first else { return }

        let duration = 0.38
        // A long tail: fast out of the gate, then a slow settle, like Sonner's.
        let curve = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)

        var height: CGFloat
        var targets: [(card: Card, frame: NSRect, alpha: CGFloat)] = []
        if expanded {
            var y: CGFloat = 0
            for card in cards {
                targets.append((card, NSRect(x: 0, y: y, width: cardWidth, height: card.height), 1))
                y += card.height + Self.gap
            }
            height = max(0, y - Self.gap)
        } else {
            // Everything tucks back behind the front card and fades, rather than
            // disappearing the instant the pointer leaves.
            for (index, card) in cards.enumerated() {
                targets.append((card, NSRect(x: 0, y: 0, width: cardWidth, height: card.height),
                                index == 0 ? 1 : 0))
            }
            height = front.height + CGFloat(min(cards.count - 1, Self.maxPeeks)) * Self.peekStep
        }

        // Everything animating must be visible for the duration, whatever it ends as.
        cards.forEach { $0.isHidden = false }

        let wantPeeks = !expanded && cards.count > 1
        // Rebuild rather than top up: the count changes as cards arrive and expire, and
        // an "only if empty" guard froze it at whatever the second card created.
        if wantPeeks && peeks.count != min(cards.count - 1, Self.maxPeeks) {
            peeks.forEach { $0.removeFromSuperview() }
            peeks = []
            for i in 0..<min(cards.count - 1, Self.maxPeeks) {
                let peek = NSView()
                peek.wantsLayer = true
                peek.layer?.backgroundColor = baseBottom.cgColor
                peek.layer?.cornerRadius = cardCorner
                peek.layer?.cornerCurve = .continuous
                peek.layer?.borderWidth = 1
                peek.layer?.borderColor = edge.withAlphaComponent(0.7).cgColor
                let inset = CGFloat(i + 1) * 13
                peek.frame = NSRect(x: inset, y: front.height + CGFloat(i) * Self.peekStep - cardCorner,
                                    width: cardWidth - inset * 2, height: cardCorner + Self.peekStep)
                peek.alphaValue = 0
                root.addSubview(peek, positioned: .below, relativeTo: nil)
                peeks.append(peek)
            }
        }

        let screen = screenMode == "mouse" ? pointerScreen() : mainDisplayScreen()
        let visible = screen.visibleFrame
        let topY = visible.maxY - 24
        let frame = NSRect(x: visible.midX - cardWidth / 2, y: topY - height,
                           width: cardWidth, height: height)

        if ProcessInfo.processInfo.environment["HUD_DEBUG"] != nil {
            var out = "layout expanded=\(expanded) cards=\(cards.count) panel=\(frame)\n"
            for t in targets { out += "  target=\(t.frame) alpha=\(t.alpha)\n" }
            FileHandle.standardError.write(out.data(using: .utf8)!)
        }

        let settle = { [weak self] in
            guard let self else { return }
            if !self.expanded {
                for (index, card) in self.cards.enumerated() { card.isHidden = index != 0 }
            }
            if self.expanded {
                self.peeks.forEach { $0.removeFromSuperview() }
                self.peeks = []
            }
        }

        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                ctx.timingFunction = curve
                self.panel.animator().setFrame(frame, display: true)
                for t in targets {
                    t.card.animator().frame = t.frame
                    t.card.animator().alphaValue = t.alpha
                }
                for peek in self.peeks { peek.animator().alphaValue = self.expanded ? 0 : 1 }
            }, completionHandler: settle)
        } else {
            panel.setFrame(frame, display: true)
            for t in targets { t.card.frame = t.frame; t.card.alphaValue = t.alpha }
            for peek in peeks { peek.alphaValue = expanded ? 0 : 1 }
            settle()
        }
    }

    /// NSTrackingArea needs the window in the event path; a non-activating borderless
    /// panel owned by an accessory app is not, so the pointer is polled instead.
    func pollHover() {
        guard panel.isVisible, !cards.isEmpty else { return }
        let inside = NSMouseInRect(NSEvent.mouseLocation, panel.frame, false)
        if inside, !expanded, cards.count > 1 {
            expanded = true
            layout(animated: true)
        } else if !inside, expanded {
            expanded = false
            for card in cards { card.deadline = Date().addingTimeInterval(3) }
            layout(animated: true)
        }
    }
}

var chimes: [NSSound] = []
var controller: StackController?
// Held at global scope: a DispatchSource stops firing the moment it is deallocated.
var listener: DispatchSourceRead?

// MARK: - socket

func socketPath() -> String {
    NSTemporaryDirectory() + "claude-hud.sock"
}

func makeAddress(_ path: String) -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
        let n = min(bytes.count, raw.count - 1)
        for i in 0..<n { raw[i] = bytes[i] }
        raw[n] = 0
    }
    return addr
}

func post(_ argv: [String]) -> Bool {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    var addr = makeAddress(socketPath())
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard ok == 0 else { return false }
    guard let data = try? JSONSerialization.data(withJSONObject: argv) else { return false }
    var payload = data
    payload.append(0x0a)
    return payload.withUnsafeBytes { send(fd, $0.baseAddress, payload.count, 0) } == payload.count
}

func serve() -> Bool {
    unlink(socketPath())
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    var addr = makeAddress(socketPath())
    let bound = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard bound == 0, listen(fd, 16) == 0 else { close(fd); return false }

    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
    listener = source
    source.setEventHandler {
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }
        var buffer = [UInt8](repeating: 0, count: 65536)
        let n = read(client, &buffer, buffer.count)
        guard n > 0 else { return }
        let data = Data(buffer[0..<n])
        for line in data.split(separator: 0x0a) {
            guard let argv = try? JSONSerialization.jsonObject(with: Data(line)) as? [String] else { continue }
            controller?.add(parseArgs(argv))
        }
    }
    source.resume()
    return true
}

// MARK: - main

let argv = Array(CommandLine.arguments.dropFirst())
let opts = parseArgs(argv)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Renders the composed stack, peeks and all, so the multi-card layout can be
// inspected without a screenshot.
if opts.previewStack > 0, !opts.preview.isEmpty {
    let c = StackController(solo: true)
    c.headless = true
    for i in 0..<opts.previewStack {
        var o = opts
        o.preview = ""
        o.title = "✳ card \(opts.previewStack - i)"
        o.badge = "demo:\(i + 1).1"
        o.sound = "none"
        c.add(o)
    }
    c.expanded = opts.previewExpanded
    c.layout(animated: false)
    let root = c.root
    root.frame = NSRect(origin: .zero, size: c.panel.frame.size)
    root.layoutSubtreeIfNeeded()
    if let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
        root.cacheDisplay(in: root.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: (opts.preview as NSString).expandingTildeInPath))
            print("stack preview: \(Int(root.bounds.width))x\(Int(root.bounds.height)) cards=\(c.cards.count) peeks=\(c.peeks.count) expanded=\(c.expanded)")
        }
    }
    exit(0)
}

if !opts.preview.isEmpty {
    let card = buildCard(opts, flat: opts.previewBackdrop != "none")
    card.frame = NSRect(x: 0, y: 0, width: cardWidth, height: card.height)
    card.layoutSubtreeIfNeeded()
    if let rep = card.bitmapImageRepForCachingDisplay(in: card.bounds) {
        card.cacheDisplay(in: card.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: (opts.preview as NSString).expandingTildeInPath))
            print("preview written: \(opts.preview)  \(Int(cardWidth))x\(Int(card.height))")
        }
    }
    exit(0)
}

if opts.serve {
    guard serve() else { exit(0) }          // another daemon already owns the socket
    controller = StackController(solo: false)
    app.run()
    exit(0)
}

// Try the daemon; start one if absent; fall back to a standalone stack if that fails,
// so a wedged daemon never costs a notification.
if !opts.solo {
    if post(argv) { exit(0) }
    let me = URL(fileURLWithPath: CommandLine.arguments[0])
    let spawn = Process()
    spawn.executableURL = me
    spawn.arguments = ["--serve"]
    try? spawn.run()
    for _ in 0..<40 {
        usleep(25_000)
        if post(argv) { exit(0) }
    }
}

controller = StackController(solo: true)
controller?.add(opts)
app.run()
