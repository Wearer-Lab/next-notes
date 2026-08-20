import SwiftUI

/// The design system for Murmur YouTube.
///
/// Direction: 1980s portable field recorders and cassette decks — Sony TC-D5, Marantz PMD,
/// Nakamichi, Braun. Equipment, not theme. Every value a view needs lives here; components
/// never declare their own colors, sizes, radii or durations.
///
/// Two faces, the way decks actually shipped: **silver face** (brushed aluminum, the TC-D5)
/// in light appearance, **black face** (matte, the PMD) in dark. Same tokens, same names,
/// different material — so a view is written once and both faces work.
///
/// The rules that keep this from drifting into pastiche:
/// - One accent: the record lamp red. Nothing else in the app is red.
/// - Amber and green appear only on level instrumentation, never as UI color.
/// - Radii stay small. Equipment has hard edges and visible seams.
/// - Depth comes from bevels and inset shadows, never from glow or blur.
enum DS {

    // MARK: - Color

    /// Surfaces, from the outer body inward. `Face` resolves each to the silver or black
    /// variant based on the current appearance.
    enum Color {
        /// The outer body of the unit. Darkest surface; frames everything.
        static let chassis = face(light: 0x2A2825, dark: 0x121110)

        /// The main working surface — brushed aluminum on silver, matte plastic on black.
        static let panel = face(light: 0xB8B4AD, dark: 0x2E2C29)

        /// Top bevel highlight on a raised element.
        static let panelHighlight = face(light: 0xC9C5BE, dark: 0x3C3936)

        /// Bottom bevel shade on a raised element.
        static let panelShade = face(light: 0x9E9A93, dark: 0x211F1D)

        /// Recessed wells — where lists, meters and readouts sit, set into the panel.
        static let well = face(light: 0x6E6A64, dark: 0x1A1917)

        /// The dark window of a tape deck. Backdrop for readouts and the transcript list.
        static let deck = face(light: 0x38352F, dark: 0x151412)

        /// Button caps and other molded plastic. Braun cream on silver, warm grey on black.
        static let cap = face(light: 0xE8E3D8, dark: 0x35322E)

        /// The hard line where two panels meet. Always the darkest value available.
        static let seam = face(light: 0x6B6862, dark: 0x000000)

        // Text
        /// Primary readable text.
        static let ink = face(light: 0x1C1A17, dark: 0xE4DED0)
        /// Supporting text — timings, counts, secondary rows.
        static let inkSecondary = face(light: 0x514D47, dark: 0x9A948A)
        /// Silkscreened labels printed onto the panel. Slightly lower contrast than `ink`,
        /// the way real screenprint sits into brushed metal.
        static let silkscreen = face(light: 0x3A3630, dark: 0xB0AA9E)
        /// Text on a dark readout well, regardless of face.
        static let inkOnDeck = swatch(0xD8D2C4)

        // Accent — the only red in the app
        /// The record lamp. Lacquered, not fluorescent.
        static let record = swatch(0xC8342A)
        /// The lamp when unlit — a dark lens, not an absence.
        static let recordIdle = face(light: 0x7A4A45, dark: 0x4A2724)

        // Selection and focus. Deliberately not red: on real equipment red means one thing,
        // and it needs to stay readable at a glance as "this is recording". Selection is
        // carried by a lit panel plus a warm edge instead of by hue.
        /// A selected row — the panel lifts rather than tints.
        static let selection = face(light: 0xCDC8C0, dark: 0x3A3733)
        /// Edge on a selected or focused element.
        static let selectionEdge = face(light: 0x8A857D, dark: 0x585349)
        /// Keyboard focus ring. Same family, higher contrast so it reads without color.
        static let focusRing = face(light: 0x6B665E, dark: 0x726C61)
        /// Row under the pointer, before selection.
        static let hover = face(light: 0xC2BDB6, dark: 0x343130)

        // Instrumentation only. Never use these for UI chrome.
        /// Classic cream VU face.
        static let meterFace = swatch(0xD8CFB4)
        /// The amber lamp behind a VU face.
        static let meterLamp = swatch(0xE8B860)
        /// Needle and scale printing.
        static let meterNeedle = swatch(0x1C1A17)
        /// Nominal level.
        static let meterGreen = swatch(0x6F9E45)
        /// Approaching peak.
        static let meterAmber = swatch(0xD39A2E)
        /// Over.
        static let meterRed = swatch(0xC0392B)

        // MARK: Face resolution

        private static func swatch(_ hex: UInt32) -> SwiftUI.Color { SwiftUI.Color(hex: hex) }

        /// Resolves to the silver-face or black-face value for the current appearance.
        private static func face(light: UInt32, dark: UInt32) -> SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
        }
    }

    // MARK: - Material

    /// The physical detail that makes a panel read as a machined object rather than a filled
    /// rectangle: metal grain, fasteners, ventilation, lamps, segmented readouts.
    ///
    /// These are what "lean into it" means here — density of real hardware detail, not
    /// decoration laid on top. Every one of them exists on a TC-D5 or a PMD.
    enum Material {
        // Brushed aluminum grain. Anisotropic: fine horizontal striations across the panel.
        /// Opacity of the lighter striations.
        static let grainLight: Double = 0.055
        /// Opacity of the darker striations.
        static let grainDark: Double = 0.07
        /// Distance between striations.
        static let grainPitch: CGFloat = 2
        /// Grain runs horizontally across a face, as on a rolled sheet.
        static let grainAngle: Angle = .degrees(0)

        // Fasteners
        /// Diameter of a panel screw head.
        static let screwSize: CGFloat = 9
        /// Inset of a screw from the panel corner.
        static let screwInset: CGFloat = 10

        // Ventilation
        /// A single vent slot.
        static let ventSlotWidth: CGFloat = 3
        static let ventSlotHeight: CGFloat = 22
        static let ventSlotGap: CGFloat = 4
        static let ventRadius: CGFloat = 1.5

        // Indicator lamps — small, hard-edged, lit from behind a lens.
        static let lampSize: CGFloat = 7
        /// A lit lamp's lens highlight — a specular dot, not a bloom.
        static let lampSpecular: Double = 0.45
        /// How far an unlit lamp sits below the lit value.
        static let lampUnlitOpacity: Double = 0.22

        // Segmented readout — the tape counter and timings.
        /// Stroke width of a seven-segment bar.
        static let segmentThickness: CGFloat = 3
        /// Gap between segments within a digit.
        static let segmentGap: CGFloat = 1
        /// Unlit segments stay faintly visible, as on a real LCD.
        static let segmentGhostOpacity: Double = 0.12

        // Transport keys — rectangular, wide, with real travel.
        static let keyHeight: CGFloat = 34
        static let keyMinWidth: CGFloat = 52
        /// How far a key sinks when pressed.
        static let keyTravel: CGFloat = 1.5

        // VU meter
        /// Total sweep of the needle, centered on vertical.
        static let needleSweep: Angle = .degrees(96)
        static let needleWidth: CGFloat = 1.5
        /// Where 0 VU sits along the scale, 0...1 — the red zone begins here.
        static let meterZeroPoint: Double = 0.72
    }

    // MARK: - Type

    /// A neutral grotesque, the way equipment was labeled. Helvetica Neue is the honest
    /// choice on macOS — the system font is too humanist for a silkscreen look. Falls back
    /// to the system face if it's ever unavailable.
    enum Font {
        private static let grotesque = "Helvetica Neue"

        /// Panel labels: small, uppercase, tightly tracked. Pair with `.silkscreenTracking`
        /// and uppercase the string — the font alone doesn't make the look.
        static let silkscreen = named(size: 9, weight: .medium)
        /// A slightly larger silkscreen label, for section headers on the panel.
        static let silkscreenLarge = named(size: 11, weight: .medium)

        static let caption = named(size: 10, weight: .regular)
        static let label = named(size: 11, weight: .regular)
        static let body = named(size: 13, weight: .regular)
        static let bodyEmphasis = named(size: 13, weight: .medium)
        static let title = named(size: 17, weight: .semibold)

        /// Readouts and timings. Monospaced so digits don't shift as they tick.
        static let counter = SwiftUI.Font.system(size: 13, design: .monospaced).monospacedDigit()
        /// The big transport counter.
        static let counterLarge = SwiftUI.Font.system(size: 26, weight: .medium, design: .monospaced)
            .monospacedDigit()

        /// Letter spacing for silkscreen labels, in points.
        static let silkscreenTracking: CGFloat = 1.1

        private static func named(size: CGFloat, weight: SwiftUI.Font.Weight) -> SwiftUI.Font {
            .custom(grotesque, size: size).weight(weight)
        }
    }

    // MARK: - Spacing

    /// A 4pt grid. Panels are laid out on it; nothing sits between steps.
    enum Space {
        static let hair: CGFloat = 2
        static let tight: CGFloat = 4
        static let snug: CGFloat = 8
        static let base: CGFloat = 12
        static let roomy: CGFloat = 16
        static let wide: CGFloat = 24
        static let panel: CGFloat = 32
    }

    // MARK: - Radius

    /// Small by design. Equipment has hard edges; anything soft reads as software.
    enum Radius {
        /// Seams and dividers — square.
        static let none: CGFloat = 0
        /// Indicator chips, small lamps.
        static let chip: CGFloat = 2
        /// Button caps and controls.
        static let control: CGFloat = 3
        /// Recessed wells and grouped panels.
        static let panel: CGFloat = 5
        /// The window itself.
        static let window: CGFloat = 8
    }

    // MARK: - Border

    enum Border {
        /// A drawn hairline. Not scaled — 1pt reads as a machined edge at any density.
        static let hairline: CGFloat = 1
        /// The seam between two panels, drawn in `Color.seam`.
        static let seam: CGFloat = 1
        /// Bevel thickness on raised controls.
        static let bevel: CGFloat = 1
    }

    // MARK: - Elevation

    /// Depth is physical: a raised cap casts a short hard shadow, a well is cut into the
    /// panel. No soft ambient glows.
    enum Shadow {
        /// A button cap sitting proud of the panel.
        static let raised = Spec(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
        /// A cap while pressed — nearly flush.
        static let pressed = Spec(color: .black.opacity(0.22), radius: 1, x: 0, y: 0)
        /// A grouped panel above the chassis.
        static let panel = Spec(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
        /// The window against the desktop.
        static let window = Spec(color: .black.opacity(0.30), radius: 24, x: 0, y: 8)

        struct Spec {
            let color: SwiftUI.Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
    }

    // MARK: - Motion

    /// Mechanical, not bouncy. A key travels and stops; it doesn't spring.
    enum Motion {
        /// Key travel down. Fast enough to feel like contact.
        static let press = Animation.easeOut(duration: 0.06)
        /// Key travel up.
        static let release = Animation.easeOut(duration: 0.12)
        /// Panel and view changes.
        static let panel = Animation.easeInOut(duration: 0.18)
        /// The record lamp coming on — instant, like a filament.
        static let lamp = Animation.easeOut(duration: 0.08)

        /// VU ballistics. A real VU meter reaches 99% of a step in ~300ms and overshoots
        /// slightly; that lag *is* the instrument's character, so the needle is damped
        /// rather than tracking the signal directly.
        static let needleAttack: TimeInterval = 0.30
        static let needleRelease: TimeInterval = 0.42
        /// Peak overshoot as a fraction of the step, before settling.
        static let needleOvershoot: Double = 0.06
    }
}

// MARK: - Hex helpers

private extension SwiftUI.Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
