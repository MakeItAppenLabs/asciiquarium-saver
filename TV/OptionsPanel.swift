import SwiftUI
import AquariumKit

/// The Options panel shown over the live tank. Every change applies and saves at once; there is no OK
/// or Cancel. Back pops a sub-screen, or closes the panel from the top.
struct OptionsPanel: View {
    @State private var settings: AquariumSettings
    @State private var path: [Screen] = []
    private let onChange: (AquariumSettings) -> Void
    private let onClose: () -> Void

    init(
        settings: AquariumSettings,
        onChange: @escaping (AquariumSettings) -> Void,
        onClose: @escaping () -> Void
    ) {
        _settings = State(initialValue: settings)
        self.onChange = onChange
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // tvOS draws these pickers as a row of choices without their title, so the section
                // header names each one.
                Section("Fish amount") {
                    Picker("Fish amount", selection: fishStep) {
                        ForEach(FishStep.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                Section("Creature set") {
                    Picker("Creature set", selection: $settings.creatureSet) {
                        Text("Full").tag(CreatureSet.full)
                        Text("Classic").tag(CreatureSet.classic)
                    }
                }
                Section("Text size") {
                    Picker("Text size", selection: $settings.textSize) {
                        Text("Small").tag(TextSize.small)
                        Text("Medium").tag(TextSize.medium)
                        Text("Large").tag(TextSize.large)
                    }
                }
                Section {
                    NavigationLink(value: Screen.specials) {
                        LabeledContent(
                            "Special creatures",
                            value: "\(settings.enabledSpecials.count) of \(SpecialKind.allCases.count)")
                    }
                    NavigationLink(value: Screen.background) {
                        LabeledContent("Background", value: backgroundSummary)
                    }
                    NavigationLink("Credits", value: Screen.credits)
                }
            }
            .navigationTitle("Options")
            .navigationDestination(for: Screen.self) { screen in
                switch screen {
                case .specials: SpecialsList(enabled: $settings.enabledSpecials)
                case .background: BackgroundChooser(background: $settings.background)
                case .credits: CreditsView()
                }
            }
            // Back closes the panel only from the top; in a sub-screen it goes back one screen.
            .onExitCommand(perform: path.isEmpty ? onClose : nil)
        }
        .onChange(of: settings) { _, new in onChange(new) }
    }

    private enum Screen: Hashable { case specials, background, credits }

    private var fishStep: Binding<FishStep> {
        Binding(
            get: { FishStep.nearest(toFishAmount: settings.fishAmount) },
            set: { settings.fishAmount = $0.fishAmount }
        )
    }

    private var backgroundSummary: String {
        if case .gradient = settings.background { "Gradient" } else { "Solid" }
    }
}

// MARK: Special creatures

private struct SpecialsList: View {
    @Binding var enabled: Set<SpecialKind>

    var body: some View {
        List(SpecialKind.allCases, id: \.self) { kind in
            Toggle(Self.title(for: kind), isOn: Binding(
                get: { enabled.contains(kind) },
                set: { on in if on { enabled.insert(kind) } else { enabled.remove(kind) } }
            ))
        }
        .navigationTitle("Special creatures")
    }

    /// The same names as the Mac's Options sheet.
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
}

// MARK: Background

private struct BackgroundChooser: View {
    @Binding var background: Background

    private enum Mode: Hashable { case solid, gradient }

    var body: some View {
        List {
            Section("Style") {
                Picker("Style", selection: mode) {
                    Text("Solid").tag(Mode.solid)
                    Text("Gradient").tag(Mode.gradient)
                }
            }
            switch background {
            case .solid(let color):
                SwatchRow(title: "Color", selected: color) { background = .solid($0) }
            case .gradient(let top, let bottom):
                SwatchRow(title: "Top", selected: top) { background = .gradient(top: $0, bottom: bottom) }
                SwatchRow(title: "Bottom", selected: bottom) { background = .gradient(top: top, bottom: $0) }
            }
        }
        .navigationTitle("Background")
    }

    /// Solid to Gradient starts from the default gradient; Gradient to Solid keeps the top color.
    private var mode: Binding<Mode> {
        Binding(
            get: { if case .gradient = background { .gradient } else { .solid } },
            set: { new in
                switch (background, new) {
                case (.solid, .gradient): background = AquariumSettings.defaultGradient
                case (.gradient(let top, _), .solid): background = .solid(top)
                default: break
                }
            }
        )
    }
}

private struct SwatchRow: View {
    let title: String
    let selected: RGB
    let choose: (RGB) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
            HStack(spacing: 18) {
                ForEach(Swatches.all, id: \.name) { swatch in
                    Button { choose(swatch.rgb) } label: {
                        Circle()
                            .fill(Color(red: swatch.rgb.r, green: swatch.rgb.g, blue: swatch.rgb.b))
                            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 2))
                            .overlay {
                                if swatch.rgb == selected {
                                    Image(systemName: "checkmark").font(.headline).foregroundStyle(.white)
                                }
                            }
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.card)
                    .accessibilityLabel(swatch.name)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: Credits

private struct CreditsView: View {
    var body: some View {
        // Each paragraph takes focus in turn, which is how the remote scrolls through text on tvOS.
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(Credits.paragraphs, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focusable()
                }
            }
            .padding()
        }
        .navigationTitle("Credits")
    }
}
