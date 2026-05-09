import SwiftUI

// =======================================================
// MARK: - Film Tuning Panel
// Live slider overlay for the FUJI CCD pipeline. Bound to a
// `FujiTuning` instance — slider drags update the binding;
// the parent view re-processes its captured image on change.
// Designed as a debug / authoring tool: dial in a look, then
// copy the displayed numbers into `FujiTuning.indoor` /
// `.outdoor` defaults in `FilmFilterEngine.swift`.
// =======================================================

struct FilmTuningPanel: View {
    @Binding var tuning: FilmFilterEngine.FujiTuning
    let defaultTuning: FilmFilterEngine.FujiTuning
    let onDismiss: () -> Void

    private let amber = Color(red: 0.95, green: 0.68, blue: 0.25)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.08))

            ScrollView {
                VStack(spacing: 18) {
                    sliderRow(
                        "LUT",
                        binding: $tuning.lutIntensity,
                        defaultValue: defaultTuning.lutIntensity,
                        range: 0...1,
                        hint: "LUT 调色强度（0=旁路）"
                    )

                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.vertical, 4)

                    sliderRow(
                        "FLASH",
                        binding: $tuning.flashStrength,
                        defaultValue: defaultTuning.flashStrength,
                        range: 0...1,
                        hint: "中央闪光斑强度"
                    )
                    sliderRow(
                        "GRAIN",
                        binding: $tuning.grainStrength,
                        defaultValue: defaultTuning.grainStrength,
                        range: 0...0.10,
                        hint: "颗粒/噪点"
                    )
                    sliderRow(
                        "VIGNETTE",
                        binding: $tuning.vignetteIntensity,
                        defaultValue: defaultTuning.vignetteIntensity,
                        range: 0...0.40,
                        hint: "四角变暗"
                    )
                    sliderRow(
                        "SATURATION",
                        binding: $tuning.saturation,
                        defaultValue: defaultTuning.saturation,
                        range: 0.5...1.5,
                        hint: "颜色浓度"
                    )
                    sliderRow(
                        "CONTRAST",
                        binding: $tuning.contrast,
                        defaultValue: defaultTuning.contrast,
                        range: 0.7...1.5,
                        hint: "明暗反差"
                    )
                    sliderRow(
                        "SOFT FOCUS",
                        binding: $tuning.softFocusRadius,
                        defaultValue: defaultTuning.softFocusRadius,
                        range: 0...3,
                        hint: "镜头软焦半径"
                    )

                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.vertical, 4)

                    sliderRow(
                        "WB TEMP",
                        binding: $tuning.wbTemperature,
                        defaultValue: defaultTuning.wbTemperature,
                        range: -1...1,
                        hint: "冷 ← → 暖"
                    )
                    sliderRow(
                        "WB TINT",
                        binding: $tuning.wbTint,
                        defaultValue: defaultTuning.wbTint,
                        range: -1...1,
                        hint: "品红 ← → 绿"
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            footer
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .preferredColorScheme(.dark)
    }

    // ---------------------------------------------------

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("CCD 调参")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white)
                Text("拖动看效果 · 满意后抄进代码")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            Button {
                tuning = defaultTuning
            } label: {
                Text("RESET")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }

            Button {
                onDismiss()
            } label: {
                Text("DONE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(amber)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func sliderRow(
        _ label: String,
        binding: Binding<Double>,
        defaultValue: Double,
        range: ClosedRange<Double>,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 92, alignment: .leading)

                Text(hint)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.35))

                Spacer()

                if abs(binding.wrappedValue - defaultValue) > 0.0005 {
                    Button {
                        binding.wrappedValue = defaultValue
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }

                Text(String(format: "%.3f", binding.wrappedValue))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(amber)
                    .frame(width: 58, alignment: .trailing)
                    .monospacedDigit()
            }

            Slider(value: binding, in: range)
                .accentColor(amber)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CURRENT VALUES")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text(currentValuesSnippet)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.65))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04))
    }

    private var currentValuesSnippet: String {
        """
        lutIntensity: \(String(format: "%.3f", tuning.lutIntensity)),
        flashStrength: \(String(format: "%.3f", tuning.flashStrength)),
        grainStrength: \(String(format: "%.3f", tuning.grainStrength)),
        vignetteIntensity: \(String(format: "%.3f", tuning.vignetteIntensity)),
        saturation: \(String(format: "%.3f", tuning.saturation)),
        contrast: \(String(format: "%.3f", tuning.contrast)),
        softFocusRadius: \(String(format: "%.3f", tuning.softFocusRadius)),
        wbTemperature: \(String(format: "%.3f", tuning.wbTemperature)),
        wbTint: \(String(format: "%.3f", tuning.wbTint))
        """
    }
}
