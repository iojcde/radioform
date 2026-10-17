import SwiftUI
import AppKit

struct TenBandEQ: View {
    @ObservedObject private var presetManager = PresetManager.shared

    private var displayOrder: [Int] {
        [PresetManager.preampFocusIndex] + Array(0..<presetManager.currentBandCount)
    }

    /// Format frequency value for band labels
    private func formatFrequency(_ hz: Float) -> String {
        if hz < 1000 {
            return "\(Int(hz))"
        } else if hz < 10000 {
            return String(format: "%.1fK", hz / 1000)
        } else {
            return "\(Int(hz / 1000))K"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Grid of vertical sliders with background grid lines
            ScrollView(.horizontal, showsIndicators: presetManager.currentBandCount > 10) {
                ZStack(alignment: .top) {
                    // Horizontal grid lines
                    GeometryReader { geometry in
                        let sliderHeight: CGFloat = 100
                        let topPadding: CGFloat = 0

                        // Draw grid lines every 3 dB (-12 to +12 = 9 lines)
                        ForEach(0..<9, id: \.self) { index in
                            let dbValue = 12 - (Float(index) * 3)
                            let yPosition = topPadding + (sliderHeight * CGFloat(index) / 8.0)
                            let isCenterLine = (dbValue == 0)

                            Rectangle()
                                .fill(Color(NSColor.separatorColor).opacity(isCenterLine ? 0.3 : 0.15))
                                .frame(height: 1)
                                .offset(y: yPosition)
                        }
                    }
                    .frame(height: 100)

                    // Sliders on top of grid
                    HStack(spacing: 0) {
                        ForEach(displayOrder, id: \.self) { index in
                            VStack(spacing: 4) {
                                VerticalSlider(
                                    value: index != PresetManager.preampFocusIndex
                                        ? Binding(
                                            get: { presetManager.currentBands[index] },
                                            set: { newValue in
                                                presetManager.updateBand(index: index, gainDb: newValue)
                                            }
                                        )
                                        : Binding(
                                            get: { presetManager.currentPreampDb },
                                            set: { newValue in
                                                presetManager.updatePreamp(gainDb: newValue)
                                            }
                                        ),
                                    range: -12...12,
                                    isFocused: presetManager.focusedBandIndex == index,
                                    onDoubleTap: {
                                        presetManager.toggleFocusedBand(index)
                                    }
                                )
                                .frame(width: 20, height: 100)
                                .opacity(index != PresetManager.preampFocusIndex && !presetManager.currentBandEnabled[index] ? 0.65 : 1)
                                .help(index != PresetManager.preampFocusIndex && !presetManager.currentBandEnabled[index] ? "Filter disabled. Adjust to enable." : "Double-click for filter settings.")

                                Text(String(format: "%+.1f", index == PresetManager.preampFocusIndex
                                    ? presetManager.currentPreampDb : presetManager.currentBands[index]))
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .frame(width: 24)
                                    .accessibilityLabel("Gain in decibels")
                                    .help("Gain (dB)")

                                // Frequency label
                                Text(index == PresetManager.preampFocusIndex ? "Pre" : formatFrequency(presetManager.currentFrequencies[index]))
                                .font(.system(size: 9))
                                .foregroundColor(index == PresetManager.preampFocusIndex ? .accentColor.opacity(0.7) : .secondary)
                                .frame(minWidth: 22)
                            }
                            .frame(maxWidth: .infinity)

                            if index == PresetManager.preampFocusIndex {
                                // Subtle separator after preamp knob
                                Rectangle()
                                    .fill(Color(NSColor.separatorColor).opacity(0.3))
                                    .frame(width: 1, height: 80)
                                    .padding(.horizontal, 4)
                            }
                        }
                    }
                }
                .frame(width: max(280, CGFloat(presetManager.currentBandCount + 1) * 28))
                .padding(.vertical, 12)
            }
            .frame(height: 160)
            .background(
                // Scroll wheel receiver for Q factor — active when a filter is focused
                Group {
                    if let focusedIndex = presetManager.focusedBandIndex, (0..<presetManager.currentBandCount).contains(focusedIndex) {
                        ScrollWheelReceiver { delta in
                            let currentQ = presetManager.currentQFactors[focusedIndex]
                            let newQ = currentQ + Float(delta) * 0.1
                            presetManager.updateBandQ(index: focusedIndex, qFactor: newQ)
                        }
                    }
                }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                presetManager.setFocusedBand(nil)
            }
            .padding(.horizontal, 8)

            HStack {
                Button { presetManager.addBand() } label: {
                    Label("Add Filter", systemImage: "plus")
                }
                .disabled(presetManager.currentBandCount >= EQPreset.maximumBands)
                Spacer()
                if let index = presetManager.focusedBandIndex,
                   (0..<presetManager.currentBandCount).contains(index) {
                    Button { presetManager.removeBand(at: index) } label: {
                        Label("Remove Filter", systemImage: "minus")
                    }
                    .disabled(presetManager.currentBandCount <= 1)
                }
            }
            .font(.caption)
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
        }
    }
}

struct VerticalSlider: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var value: Float
    let range: ClosedRange<Float>
    let isFocused: Bool
    let onDoubleTap: () -> Void

    private let normalKnobSize: CGFloat = 16
    private let focusedKnobSize: CGFloat = 22

    // While dragging, if the user moves the cursor horizontally beyond this threshold, the dB levels will be adjusted more precisely
    private let preciseThresholdX: Float = 50
    // Exit precise mode below this threshold (hysteresis prevents flickering near boundary)
    private let preciseExitThresholdX: Float = 35
    // Multiplier that allows for fine-grained dB adjustments
    private let preciseFactor: Float = 0.05

    // Remember the drag Y value so we can maintain the slider position when shifting to precise mode
    @State private var prevDragY: CGFloat? = nil

    // Used for the knob border to reflect the current dragging mode
    @State private var isDragging: Bool = false
    @State private var isPreciseDrag: Bool = false

    private var knobSize: CGFloat {
        isFocused ? focusedKnobSize : normalKnobSize
    }

    private var knobDisplayText: String {
        if value >= 0 {
            return String(format: "+%.1f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Track background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.35 : 0.18))
                    .frame(width: 4)

                // Center line (0 dB)
                let centerY = geometry.size.height / 2
                Rectangle()
                    .fill(Color(NSColor.tertiaryLabelColor))
                    .frame(width: 20, height: 1)
                    .position(x: geometry.size.width / 2, y: centerY)

                // Filled portion (from center to knob)
                let normalizedValue = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                let knobY = geometry.size.height * (1 - CGFloat(normalizedValue))

                if value != 0 {
                    let fillHeight = abs(knobY - centerY)
                    let fillY = min(knobY, centerY)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: 4, height: fillHeight)
                        .position(x: geometry.size.width / 2, y: fillY + fillHeight / 2)
                }

                // Knob
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    colorScheme == .dark ? Color(white: 0.80) : Color(NSColor.controlBackgroundColor),
                                    colorScheme == .dark ? Color(white: 0.58) : Color(NSColor.controlBackgroundColor).opacity(0.9)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    (isFocused
                                        ? isDragging
                                            ? Color.white
                                            : Color.accentColor
                                        : Color.primary.opacity(colorScheme == .dark ? 0.65 : 0.3)),
                                    style: StrokeStyle(
                                        lineWidth: isFocused ? 1.5 : 1,

                                        // Dotted border indicates precise dragging mode
                                        dash: isDragging && isPreciseDrag ? [2, 2] : []
                                    )
                                )
                        )

                    // dB text inside focused knob
                    if isFocused {
                        Text(knobDisplayText)
                            .font(.system(size: 7, weight: .medium, design: .rounded))
                            .foregroundColor(colorScheme == .dark ? .black : .primary.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            // Reduce horizontal text movement when dragging
                            .monospacedDigit()
                    }
                }
                .frame(width: knobSize, height: knobSize)
                .shadow(color: .black.opacity(0.15), radius: 1.5, x: 0, y: 0.5)
                .position(
                    x: geometry.size.width / 2,
                    y: knobY
                )
                .onTapGesture(count: 2) {
                    onDoubleTap()
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { gesture in
                            let rangeSpan = range.upperBound - range.lowerBound
                            let knobCenterX = Float(knobSize / 2)
                            let mouseDistanceX = abs(Float(gesture.location.x) - knobCenterX)

                            isDragging = true
                            if mouseDistanceX > preciseThresholdX {
                                isPreciseDrag = true
                            } else if mouseDistanceX < preciseExitThresholdX {
                                isPreciseDrag = false
                            }
                            let multiplier: Float = isPreciseDrag ? preciseFactor : 1

                            let deltaY = Float(gesture.translation.height - (prevDragY ?? gesture.translation.height))
                            let progress = -deltaY / Float(geometry.size.height)
                            let valueIncrement = progress * rangeSpan * multiplier
                            value = min(max(range.lowerBound, value + valueIncrement), range.upperBound)

                            prevDragY = gesture.translation.height
                        }
                        .onEnded { _ in
                            isDragging = false
                            isPreciseDrag = false
                            prevDragY = nil
                        }
                )
            }
        }
    }
}

// MARK: - Scroll Wheel Receiver (macOS)

struct ScrollWheelReceiver: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        ScrollWheelNSView(onScroll: onScroll)
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }

    class ScrollWheelNSView: NSView {
        var onScroll: (CGFloat) -> Void

        init(onScroll: @escaping (CGFloat) -> Void) {
            self.onScroll = onScroll
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func scrollWheel(with event: NSEvent) {
            onScroll(event.deltaY)
        }
    }
}
