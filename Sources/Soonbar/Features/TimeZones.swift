import SoonbarCore
import SwiftUI

// Second time zone: event times there in the agenda, and its current time in the Today header.
// Off until a zone is picked (PreferencesStore.secondTimeZoneID).

/// Calendar tab.
struct SecondTimeZoneSettingsSection: View {
    @Environment(PreferencesStore.self) private var prefs

    var body: some View {
        Section {
            LabeledContent("Second time zone") {
                Menu(prefs.secondTimeZone.map(Self.label) ?? "None") {
                    Button("None") { prefs.secondTimeZoneID = nil }
                    Divider()
                    ForEach(Self.regions, id: \.name) { region in
                        Menu(region.name) {
                            ForEach(region.zones, id: \.self) { id in
                                Button(TimeZone(identifier: id).map(Self.label) ?? id) { prefs.secondTimeZoneID = id }
                            }
                        }
                    }
                }
                .fixedSize()
            }
        } header: {
            Text("Time zones")
        } footer: {
            SectionFooter("Meetings also show their time there, and the Today header shows the time there now. "
                          + "Free times can be written in this zone too (Share availability, below).")
        }
    }

    /// "New York (GMT-4)".
    static func label(_ zone: TimeZone) -> String {
        let offset = zone.localizedName(for: .shortGeneric, locale: .current).flatMap { $0.hasPrefix("GMT") ? $0 : nil }
            ?? zone.abbreviation() ?? ""
        return "\(SecondTimeZone.cityName(zone)) (\(offset))"
    }

    /// Every known zone grouped by its region prefix ("America", "Europe", …), cities alphabetical.
    static let regions: [(name: String, zones: [String])] = {
        let grouped = Dictionary(grouping: TimeZone.knownTimeZoneIdentifiers.filter { $0.contains("/") }) {
            String($0.split(separator: "/")[0])
        }
        return grouped.keys.sorted().map { key in
            (key, grouped[key, default: []].sorted { SecondTimeZone.cityName(TimeZone(identifier: $0)!) < SecondTimeZone.cityName(TimeZone(identifier: $1)!) })
        }
    }()
}

/// The time in the second zone, shown on the Today header.
struct SecondZoneClock: View {
    @Environment(AppModel.self) private var model
    @Environment(PreferencesStore.self) private var prefs

    var body: some View {
        if let zone = prefs.secondTimeZone, zone.secondsFromGMT(for: model.now) != model.calendar.timeZone.secondsFromGMT(for: model.now) {
            Label(SecondTimeZone.clock(now: model.now, zone: zone, calendar: model.calendar, locale: .current), systemImage: "globe")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        }
    }
}
