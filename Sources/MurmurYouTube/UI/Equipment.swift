import SwiftUI

// The physical vocabulary of the app: panels, wells, keys, lamps, silkscreen, meters.
// Every value here comes from `DS`. If a component needs a number that isn't a token, the
// token is missing — add it there rather than inlining it.

// MARK: - Surfaces

/// A brushed-metal panel. The grain is drawn, not an image: it stays sharp at any scale,
/// follows the silver/black face automatically, and costs nothing to ship.
struct BrushedPanel: View {
    var radius: CGFloat = DS.Radius.panel

    var body: some View {
        ZStack {
            DS.Color.panel
            Grain()
        }
        .clipShape(.rect(cornerRadius: radius))
        .overlay(
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(DS.Color.panelHighlight, lineWidth: DS.Border.bevel)
                .blendMode(.plusLighter)
                .opacity(0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(DS.Color.seam, lineWidth: DS.Border.seam)
                .opacity(0.35)
        )
    }

    /// Fine horizontal striations, the direction a rolled aluminum sheet is brushed.
    private struct Grain: View {
        var body: some View {
            Canvas { context, size in
                var y: CGFloat = 0
                var alternate = false
                while y < size.height {
                    let shade = alternate ? DS.Material.grainDark : DS.Material.grainLight
                    let color = alternate ? Color.black : Color.white
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: DS.Material.grainPitch / 2)),
                        with: .color(color.opacity(shade))
                    )
                    y += DS.Material.grainPitch
                    alternate.toggle()
                }
            }
            .rotationEffect(DS.Material.grainAngle)
            .allowsHitTesting(false)
        }
    }
}

/// A recessed well cut into the panel. Content sits *in* it, so the inner edge is dark at
/// the top and light at the bottom — the inverse of a raised cap.
struct Well<Content: View>: View {
    var radius: CGFloat = DS.Radius.panel
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(DS.Color.well, in: .rect(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(DS.Color.seam, lineWidth: DS.Border.hairline)
                    .opacity(0.55)
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DS.Color.panelHighlight)
                    .frame(height: DS.Border.bevel)
                    .opacity(0.35)
                    .padding(.horizontal, DS.Border.bevel)
            }
    }
}

/// The dark readout window — the tape window of a deck. Darker than a `Well`, and always
/// dark regardless of face, because a lit readout needs something to be lit against.
struct DeckWindow<Content: View>: View {
    var radius: CGFloat = DS.Radius.panel
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(DS.Color.deck, in: .rect(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(DS.Color.seam, lineWidth: DS.Border.hairline)
            )
    }
}

// MARK: - Labels

/// A silkscreened panel label: small, uppercase, tightly tracked.
///
/// The uppercasing happens here rather than at the call site so a label can never be
/// half-styled — the look depends on all three of size, tracking and case.
struct Silkscreen: View {
    let text: String
    var large = false
    var color: Color = DS.Color.silkscreen

    var body: some View {
        Text(text.uppercased())
            .font(large ? DS.Font.silkscreenLarge : DS.Font.silkscreen)
            .tracking(DS.Font.silkscreenTracking)
            .foregroundStyle(color)
    }
}

// MARK: - Hardware detail

/// A panel screw. Purely decorative, and deliberately so — real equipment has fasteners,
/// and their absence is one of the things that makes software look like software.
struct Screw: View {
    var body: some View {
        Circle()
            .fill(DS.Color.panelShade)
            .overlay(
                Circle().strokeBorder(DS.Color.seam.opacity(0.6), lineWidth: DS.Border.hairline)
            )
            .overlay(
                Rectangle()
                    .fill(DS.Color.seam.opacity(0.7))
                    .frame(width: DS.Material.screwSize * 0.55, height: DS.Border.hairline)
                    .rotationEffect(.degrees(28))
            )
            .overlay(alignment: .top) {
                Circle()
                    .fill(DS.Color.panelHighlight)
                    .frame(height: DS.Border.bevel)
                    .opacity(0.6)
            }
            .frame(width: DS.Material.screwSize, height: DS.Material.screwSize)
    }
}

/// A run of ventilation slots.
struct Vents: View {
    var count = 6

    var body: some View {
        HStack(spacing: DS.Material.ventSlotGap) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: DS.Material.ventRadius)
                    .fill(DS.Color.seam)
                    .frame(width: DS.Material.ventSlotWidth, height: DS.Material.ventSlotHeight)
                    .opacity(0.5)
            }
        }
    }
}

/// An indicator lamp behind a lens. Lit lamps get a specular dot, not a bloom — the brief
/// rules out glow, and real lamps read as lit because of the highlight on the lens.
struct Lamp: View {
    let color: Color
    var isLit: Bool
    var size: CGFloat = DS.Material.lampSize

    var body: some View {
        Circle()
            .fill(color.opacity(isLit ? 1 : DS.Material.lampUnlitOpacity))
            .overlay(
                Circle().strokeBorder(DS.Color.seam.opacity(0.7), lineWidth: DS.Border.hairline)
            )
            .overlay(alignment: .topLeading) {
                if isLit {
                    Circle()
                        .fill(.white)
                        .opacity(DS.Material.lampSpecular)
                        .frame(width: size * 0.3, height: size * 0.3)
                        .offset(x: size * 0.2, y: size * 0.18)
                }
            }
            .frame(width: size, height: size)
            .animation(DS.Motion.lamp, value: isLit)
    }
}

// MARK: - Controls

/// A transport key: rectangular, chunky, with real travel. Pressed means *pressed* — the cap
/// sinks and its shadow collapses — rather than merely tinted.
struct TransportKey: View {
    let title: String
    var systemImage: String?
    var isEngaged = false
    var engagedColor: Color = DS.Color.record
    var isEnabled = true
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.tight) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .bold))
                }
                Silkscreen(text: title, color: labelColor)
            }
            .frame(minWidth: DS.Material.keyMinWidth)
            .frame(height: DS.Material.keyHeight)
            .padding(.horizontal, DS.Space.base)
            .background(cap)
            .offset(y: isPressed ? DS.Material.keyTravel : 0)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onLongPressGesture(minimumDuration: 0) {} onPressingChanged: { pressing in
            withAnimation(pressing ? DS.Motion.press : DS.Motion.release) { isPressed = pressing }
        }
    }

    private var labelColor: Color {
        isEngaged ? engagedColor : DS.Color.ink
    }

    private var cap: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.control)
                .fill(DS.Color.cap)
            // Top bevel catches the light; bottom bevel is in shade. Swapped when pressed.
            RoundedRectangle(cornerRadius: DS.Radius.control)
                .strokeBorder(isPressed ? DS.Color.panelShade : DS.Color.panelHighlight,
                              lineWidth: DS.Border.bevel)
            RoundedRectangle(cornerRadius: DS.Radius.control)
                .strokeBorder(DS.Color.seam.opacity(0.5), lineWidth: DS.Border.hairline)
        }
        .shadow(
            color: (isPressed ? DS.Shadow.pressed : DS.Shadow.raised).color,
            radius: (isPressed ? DS.Shadow.pressed : DS.Shadow.raised).radius,
            x: (isPressed ? DS.Shadow.pressed : DS.Shadow.raised).x,
            y: (isPressed ? DS.Shadow.pressed : DS.Shadow.raised).y
        )
    }
}

// MARK: - Instrumentation

/// A VU meter with a real needle.
///
/// The needle is damped rather than driven directly from the signal: a physical VU movement
/// takes ~300ms to reach a step and overshoots slightly before settling, and that lag is the
/// instrument's character. Tracking the level exactly would produce a twitching line that
/// reads as a progress bar with a stick on it.
struct VUMeter: View {
    /// Current input level, 0...1.
    let level: Float
    var isActive: Bool

    /// The needle's physical state lives in a plain reference type, deliberately *not* in
    /// `@State`. The movement has to advance once per drawn frame, and SwiftUI state mutated
    /// inside a `Canvas` draw closure is a mutation during view update — which SwiftUI logs
    /// as undefined behavior and which, at 120fps, floods the process. A reference the view
    /// merely holds is invisible to the state graph, so stepping it is safe.
    @State private var movement = NeedleMovement()

    private final class NeedleMovement {
        var position: Double = 0
        var velocity: Double = 0
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, at: timeline.date)
            }
        }
        .background(DS.Color.meterFace)
        .overlay(
            Rectangle()
                .fill(DS.Color.meterLamp)
                .opacity(isActive ? 0.14 : 0)
                .animation(DS.Motion.lamp, value: isActive)
        )
        .clipShape(.rect(cornerRadius: DS.Radius.chip))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.chip)
                .strokeBorder(DS.Color.seam, lineWidth: DS.Border.hairline)
        )
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, at date: Date) {
        advanceNeedle()

        let pivot = CGPoint(x: size.width / 2, y: size.height * 1.05)
        let radius = min(size.width * 0.46, size.height * 0.92)
        let sweep = DS.Material.needleSweep.radians

        // Scale arc, with the red zone past 0 VU.
        for tick in stride(from: 0.0, through: 1.0, by: 0.1) {
            let angle = -sweep / 2 + sweep * tick
            let isOver = tick >= DS.Material.meterZeroPoint
            let inner = radius * (tick.truncatingRemainder(dividingBy: 0.2) < 0.01 ? 0.78 : 0.86)
            var path = Path()
            path.move(to: point(from: pivot, angle: angle, distance: inner))
            path.addLine(to: point(from: pivot, angle: angle, distance: radius))
            context.stroke(
                path,
                with: .color(isOver ? DS.Color.meterRed : DS.Color.meterNeedle),
                lineWidth: DS.Border.hairline
            )
        }

        // Needle.
        let angle = -sweep / 2 + sweep * movement.position
        var needlePath = Path()
        needlePath.move(to: pivot)
        needlePath.addLine(to: point(from: pivot, angle: angle, distance: radius * 0.98))
        context.stroke(
            needlePath,
            with: .color(DS.Color.meterNeedle),
            lineWidth: DS.Material.needleWidth
        )
    }

    /// Critically-damped-ish spring toward the target, tuned to VU ballistics.
    private func advanceNeedle() {
        let target = Double(min(max(level, 0), 1))
        let rising = target > movement.position
        let time = rising ? DS.Motion.needleAttack : DS.Motion.needleRelease
        // Frame-rate independent enough at 60–120Hz, and a meter is forgiving of the rest.
        let stiffness = 1 / time
        let delta = target - movement.position
        movement.velocity += delta * stiffness * 0.16
        movement.velocity *= 0.72
        movement.position += movement.velocity
        movement.position = min(max(movement.position, 0), 1 + DS.Motion.needleOvershoot)
    }

    private func point(from origin: CGPoint, angle: Double, distance: CGFloat) -> CGPoint {
        CGPoint(
            x: origin.x + sin(angle) * distance,
            y: origin.y - cos(angle) * distance
        )
    }
}

/// A monospaced readout on a dark window — the tape counter.
struct Readout: View {
    let text: String
    var large = false

    var body: some View {
        Text(text)
            .font(large ? DS.Font.counterLarge : DS.Font.counter)
            .foregroundStyle(DS.Color.inkOnDeck)
    }
}
