import SoonbarCore
import SwiftUI

/// A number and a unit for a custom duration, stored as seconds and kept within `range`.
struct DurationField: View {
    @Binding var seconds: Int
    /// In seconds.
    let range: ClosedRange<Int>
    var units: [DurationUnit] = DurationUnit.allCases
    var suffix: String?
    @State private var value = 1
    @State private var unit = DurationUnit.minutes

    var body: some View {
        HStack(spacing: 6) {
            TextField("", value: $value, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .labelsHidden()
            Stepper("", value: $value, in: 1...9_999).labelsHidden()
            if units.count > 1 {
                Picker("", selection: $unit) {
                    ForEach(units, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            } else if let only = units.first {
                Text(only.rawValue)
            }
            if let suffix { Text(suffix) }
        }
        .onAppear { load() }
        .onChange(of: value) { commit() }
        .onChange(of: unit) { commit() }
    }

    private func load() {
        (value, unit) = CustomDuration.split(seconds, allowed: units)
    }

    /// Out-of-range numbers snap to the nearest allowed one, and the field shows what was kept.
    private func commit() {
        let kept = CustomDuration.seconds(value, unit, within: range)
        seconds = kept
        guard kept != value * unit.seconds else { return }
        if kept % unit.seconds == 0 { value = kept / unit.seconds } else { (value, unit) = CustomDuration.split(kept, allowed: units) }
    }
}

/// A picker with preset values plus "Custom…", which reveals a `DurationField`. `value` is stored in `storedUnit`.
struct PresetOrCustomPicker: View {
    let title: String
    @Binding var value: Int
    let presets: [(label: String, value: Int)]
    var storedUnit: DurationUnit = .seconds
    /// In `storedUnit`.
    let customRange: ClosedRange<Int>
    var units: [DurationUnit] = DurationUnit.allCases
    var customSuffix: String?
    /// Where the custom field starts when the current value is outside `customRange` (like "Never" = 0).
    var customStart: Int?
    /// How the picked custom time reads in the closed picker, like "After 45 seconds".
    var customLabel: (String) -> String = { "Custom: \($0)" }
    /// Set once the user picks; until then a value that isn't a preset counts as custom.
    @State private var choseCustom: Bool?
    private static let customTag = Int.min

    var body: some View {
        let isCustom = choseCustom ?? !presets.contains { $0.value == value }
        Picker(title, selection: Binding(
            get: { isCustom ? Self.customTag : value },
            set: { tag in
                if tag == Self.customTag {
                    choseCustom = true
                    if !customRange.contains(value) { value = customStart ?? customRange.lowerBound }
                } else {
                    choseCustom = false
                    value = tag
                }
            }
        )) {
            ForEach(presets, id: \.value) { Text($0.label).tag($0.value) }
            Divider()
            Text(isCustom ? customLabel(CustomDuration.label(value * storedUnit.seconds)) : "Custom…").tag(Self.customTag)
        }
        if isCustom {
            LabeledContent("Custom") {
                DurationField(
                    seconds: Binding(get: { value * storedUnit.seconds }, set: { value = $0 / storedUnit.seconds }),
                    range: (customRange.lowerBound * storedUnit.seconds)...(customRange.upperBound * storedUnit.seconds),
                    units: units, suffix: customSuffix
                )
            }
        }
    }
}
