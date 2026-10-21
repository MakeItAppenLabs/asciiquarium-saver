import AppKit
import AquariumKit

/// The Options sheet: edits the `AquariumSettings` the saver uses. Built in code, no nib.
///
/// Opening it reads the stored settings. OK writes them back and calls `onSave`, then ends the sheet;
/// Cancel ends it and leaves the store alone.
final class ConfigSheet: NSWindowController {
    /// The README's Credits section on GitHub, which the "Credits" button opens. Nil would keep the
    /// button disabled.
    static let creditsURL: URL? = URL(string: "https://github.com/AaronMashburn/asciiquarium-saver#credits")

    private static let contentWidth: CGFloat = 500

    // Controls are internal so the Preview app's test driver can set them and click the buttons.
    let fishSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    let creatureSetControl = NSSegmentedControl(
        labels: ["Full", "Classic"], trackingMode: .selectOne, target: nil, action: nil)
    private(set) var specialChecks: [SpecialKind: NSButton] = [:]
    let backgroundPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let solidWell = NSColorWell(style: .default)
    let topWell = NSColorWell(style: .default)
    let bottomWell = NSColorWell(style: .default)
    let textSizeControl = NSSegmentedControl(
        labels: ["Small", "Medium", "Large"], trackingMode: .selectOne, target: nil, action: nil)
    let creditsButton = NSButton(title: "Credits", target: nil, action: nil)
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let okButton = NSButton(title: "OK", target: nil, action: nil)

    private let topLabel = ConfigSheet.label("Top")
    private let bottomLabel = ConfigSheet.label("Bottom")

    private let store: SettingsStore
    private let onSave: (AquariumSettings) -> Void
    private let initial: AquariumSettings
    private let savedShowsAlpha = NSColorPanel.shared.showsAlpha

    init(store: SettingsStore, onSave: @escaping (AquariumSettings) -> Void) {
        self.store = store
        self.onSave = onSave
        self.initial = store.load()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth + 40, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        super.init(window: window)
        window.title = "Asciiquarium Options"
        window.isReleasedWhenClosed = false
        buildContent(in: window)
        apply(initial)
        // RGB has no alpha, so don't offer it in the color panel.
        NSColorPanel.shared.showsAlpha = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // MARK: Settings <-> controls

    /// Fills the controls from `settings`. A stored solid background leaves the gradient wells at the
    /// default gradient, so the first switch to Gradient starts from it.
    private func apply(_ settings: AquariumSettings) {
        fishSlider.doubleValue = AquariumSettings.sliderPosition(fishAmount: settings.fishAmount)
        creatureSetControl.selectedSegment = settings.creatureSet == .full ? 0 : 1
        for (kind, box) in specialChecks {
            box.state = settings.enabledSpecials.contains(kind) ? .on : .off
        }
        textSizeControl.selectedSegment = TextSize.allCases.firstIndex(of: settings.textSize) ?? 1

        solidWell.color = Self.nsColor(.black)
        if case .gradient(let top, let bottom) = AquariumSettings.defaultGradient {
            topWell.color = Self.nsColor(top)
            bottomWell.color = Self.nsColor(bottom)
        }
        switch settings.background {
        case .solid(let color):
            solidWell.color = Self.nsColor(color)
            backgroundPopup.selectItem(at: 0)
        case .gradient(let top, let bottom):
            topWell.color = Self.nsColor(top)
            bottomWell.color = Self.nsColor(bottom)
            backgroundPopup.selectItem(at: 1)
        }
        updateBackgroundRow()
    }

    /// The settings the controls currently describe.
    func currentSettings() -> AquariumSettings {
        var s = initial
        // Keep the stored amount unless the slider moved, so OK without touching it can't drift it.
        let storedPosition = AquariumSettings.sliderPosition(fishAmount: initial.fishAmount)
        if abs(fishSlider.doubleValue - storedPosition) > 1e-9 {
            s.fishAmount = AquariumSettings.fishAmount(sliderPosition: fishSlider.doubleValue)
        }
        s.creatureSet = creatureSetControl.selectedSegment == 1 ? .classic : .full
        s.enabledSpecials = Set(specialChecks.filter { $0.value.state == .on }.map(\.key))
        s.background = backgroundPopup.indexOfSelectedItem == 1
            ? .gradient(top: Self.rgb(topWell.color), bottom: Self.rgb(bottomWell.color))
            : .solid(Self.rgb(solidWell.color))
        let sizeIndex = textSizeControl.selectedSegment
        s.textSize = TextSize.allCases.indices.contains(sizeIndex) ? TextSize.allCases[sizeIndex] : .medium
        return s
    }

    static func nsColor(_ c: RGB) -> NSColor {
        NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    static func rgb(_ color: NSColor) -> RGB {
        let c = color.usingColorSpace(.sRGB) ?? .black
        return RGB(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }

    // MARK: Actions

    @objc private func backgroundChanged(_ sender: Any?) {
        updateBackgroundRow()
    }

    private func updateBackgroundRow() {
        let gradient = backgroundPopup.indexOfSelectedItem == 1
        solidWell.isHidden = gradient
        topLabel.isHidden = !gradient
        topWell.isHidden = !gradient
        bottomLabel.isHidden = !gradient
        bottomWell.isHidden = !gradient
    }

    @objc func okPressed(_ sender: Any?) {
        let settings = currentSettings()
        store.save(settings)
        onSave(settings)
        finish()
    }

    @objc func cancelPressed(_ sender: Any?) {
        finish()
    }

    @objc private func creditsPressed(_ sender: Any?) {
        if let url = Self.creditsURL { NSWorkspace.shared.open(url) }
    }

    /// Closes the color panel and ends the sheet. Outside a sheet (nothing to end), just hides it.
    private func finish() {
        for well in [solidWell, topWell, bottomWell] { well.deactivate() }
        NSColorPanel.shared.orderOut(nil)
        NSColorPanel.shared.showsAlpha = savedShowsAlpha
        guard let window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.orderOut(nil)
        }
    }

    // MARK: Layout

    private static func label(_ text: String, small: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        if small { field.font = .systemFont(ofSize: NSFont.smallSystemFontSize) }
        return field
    }

    private static func title(for kind: SpecialKind) -> String {
        switch kind {
        case .ship: "Ship"
        case .whale: "Whale"
        case .monster: "Sea monster"
        case .bigFish: "Big fish"
        case .shark: "Shark"
        case .fishhook: "Fishhook"
        case .swan: "Swan"
        case .ducks: "Ducks"
        case .dolphins: "Dolphins"
        case .submarine: "Submarine"
        case .swordfish: "Swordfish"
        case .jellyfish: "Jellyfish"
        }
    }

    private static var footerText: String {
        let version = Bundle(for: ConfigSheet.self).object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "1.0.0"
        return "Asciiquarium \(version) — based on asciiquarium by Kirk Baucom; "
            + "art by Joan Stark and others; Python port by Mohammad Abu Mattar. GPL-3.0-or-later."
    }

    private func buildContent(in window: NSWindow) {
        // Fish amount
        fishSlider.isContinuous = true
        fishSlider.setAccessibilityLabel("Fish amount")
        let fishRow = NSStackView(views: [Self.label("Few"), fishSlider, Self.label("Many")])
        fishRow.spacing = 8
        fishSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Creature set, text size
        creatureSetControl.segmentStyle = .rounded
        creatureSetControl.setAccessibilityLabel("Creature set")
        textSizeControl.segmentStyle = .rounded
        textSizeControl.setAccessibilityLabel("Text size")

        // Special creatures: 12 checkboxes in 3 columns, filled row by row in Perl order.
        let kinds = SpecialKind.allCases
        var rows: [[NSView]] = []
        for start in stride(from: 0, to: kinds.count, by: 3) {
            rows.append(kinds[start..<min(start + 3, kinds.count)].map { kind in
                let box = NSButton(checkboxWithTitle: Self.title(for: kind), target: nil, action: nil)
                specialChecks[kind] = box
                return box
            })
        }
        let checks = NSGridView(views: rows)
        checks.columnSpacing = 16
        checks.rowSpacing = 6

        // Background
        backgroundPopup.addItems(withTitles: ["Solid", "Gradient"])
        backgroundPopup.target = self
        backgroundPopup.action = #selector(backgroundChanged(_:))
        backgroundPopup.setAccessibilityLabel("Background")
        solidWell.setAccessibilityLabel("Background color")
        topWell.setAccessibilityLabel("Top color")
        bottomWell.setAccessibilityLabel("Bottom color")
        for well in [solidWell, topWell, bottomWell] {
            well.translatesAutoresizingMaskIntoConstraints = false
            well.widthAnchor.constraint(equalToConstant: 44).isActive = true
            well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        let backgroundRow = NSStackView(
            views: [backgroundPopup, solidWell, topLabel, topWell, bottomLabel, bottomWell])
        backgroundRow.spacing = 8
        backgroundRow.setCustomSpacing(16, after: backgroundPopup)
        backgroundRow.setCustomSpacing(16, after: topWell)

        let form = NSGridView(views: [
            [Self.label("Fish amount:"), fishRow],
            [Self.label("Creature set:"), creatureSetControl],
            [Self.label("Special creatures:"), checks],
            [Self.label("Background:"), backgroundRow],
            [Self.label("Text size:"), textSizeControl],
        ])
        form.rowSpacing = 14
        form.columnSpacing = 12
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 1).xPlacement = .leading
        form.row(at: 2).cell(at: 0).yPlacement = .top
        form.row(at: 2).yPlacement = .top
        for index in [0, 1, 3, 4] { form.row(at: index).yPlacement = .center }
        fishRow.translatesAutoresizingMaskIntoConstraints = false
        fishRow.widthAnchor.constraint(equalToConstant: 330).isActive = true

        // Footer
        let footer = Self.label(Self.footerText, small: true)
        footer.textColor = .secondaryLabelColor
        footer.lineBreakMode = .byWordWrapping
        footer.maximumNumberOfLines = 0
        footer.preferredMaxLayoutWidth = Self.contentWidth

        creditsButton.bezelStyle = .inline
        creditsButton.isBordered = false
        creditsButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        creditsButton.contentTintColor = Self.creditsURL != nil ? .linkColor : .tertiaryLabelColor
        creditsButton.target = self
        creditsButton.action = #selector(creditsPressed(_:))
        creditsButton.isEnabled = Self.creditsURL != nil

        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed(_:))
        cancelButton.keyEquivalent = "\u{1b}"
        okButton.target = self
        okButton.action = #selector(okPressed(_:))
        okButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancelButton, okButton])
        buttons.spacing = 12

        let separator = NSBox()
        separator.boxType = .separator

        let footerStack = NSStackView(views: [footer, creditsButton])
        footerStack.orientation = .vertical
        footerStack.alignment = .leading
        footerStack.spacing = 2

        let root = NSStackView(views: [form, separator, footerStack, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        for view in [separator, buttons] {
            view.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        }

        let content = NSView()
        content.addSubview(root)
        root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        window.setContentSize(content.fittingSize)
        window.defaultButtonCell = okButton.cell as? NSButtonCell
    }
}
