import SoonbarCore
import SwiftUI

// Add from text: paste an email, chat or schedule; preview the events and reminders it mentions; add the ones ticked.
// Off by default (PreferencesStore.addFromTextEnabled). Nothing is saved before "Add".

extension AppModel {
    /// Saves the ticked items; returns how many were added.
    func addImported(_ items: [TextImportItem], eventCalendarID: String?, reminderListID: String?) throws -> Int {
        var added = 0
        for item in items {
            let title = item.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            switch item.kind {
            case .event:
                guard let eventCalendarID else { continue }
                try service.saveEvent(title: title, start: item.start, end: item.end, isAllDay: item.isAllDay,
                                      calendarID: eventCalendarID, location: item.location)
            case .reminder:
                guard let reminderListID else { continue }
                try service.saveReminder(title: title, due: item.start, hasTime: item.hasDueTime, listID: reminderListID)
            }
            added += 1
        }
        if let eventCalendarID, items.contains(where: { $0.kind == .event }) { prefs.lastEventCalendarID = eventCalendarID }
        if let reminderListID, items.contains(where: { $0.kind == .reminder }) { prefs.lastReminderListID = reminderListID }
        scheduleRefresh(delay: 0)
        return added
    }
}

struct AddFromTextView: View {
    @Environment(AppModel.self) private var model
    @Environment(PreferencesStore.self) private var prefs
    @State private var text = ""
    @State private var rows: [Row]?
    @State private var usedAppleIntelligence = false
    @State private var note: String?
    @State private var isReading = false
    @State private var readTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var eventCalendarID: String?
    @State private var reminderListID: String?
    @FocusState private var editorFocused: Bool

    struct Row: Identifiable {
        var item: TextImportItem
        var isSelected: Bool
        var id: Int { item.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Add from Text").font(.headline)
                Spacer()
                if rows != nil {
                    Label(usedAppleIntelligence ? "Apple Intelligence" : "Date detection",
                          systemImage: usedAppleIntelligence ? "sparkles" : "calendar.badge.clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let rows {
                results(rows)
            } else {
                input
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            footer
        }
        .padding(12)
        .onAppear {
            if text.isEmpty { text = model.importText }
            model.importText = ""
            editorFocused = true
        }
        .onDisappear { readTask?.cancel() }
    }

    // MARK: - Input

    private var input: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.callout)
                    .focused($editorFocused)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor).opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                if text.isEmpty {
                    Text("Paste an email, a chat or a schedule…")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 170)
            HStack {
                Button("Paste") {
                    if let clip = NSPasteboard.general.string(forType: .string) { text = clip }
                }
                .disabled(NSPasteboard.general.string(forType: .string) == nil)
                Spacer()
                if isReading {
                    ProgressView().controlSize(.small)
                    Text("Reading…").font(.caption).foregroundStyle(.secondary)
                }
                if text.count > TextImportEngine.maximumCharacters {
                    Text("Only the first part is read").font(.caption).foregroundStyle(.orange)
                }
            }
            .controlSize(.small)
            Text(prefs.addFromTextUsesAI && AppleIntelligenceStatus.current.isAvailable
                 ? "Read on this Mac with Apple Intelligence. Nothing is added until you check and tick it."
                 : "Finds sentences with a date. Nothing is added until you check and tick it.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Results

    private func results(_ rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if rows.isEmpty {
                Text("No events or reminders found in this text.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows.indices, id: \.self) { index in
                            ImportRowView(row: binding(index))
                            if index < rows.count - 1 { Divider() }
                        }
                    }
                }
                .frame(maxHeight: 300)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let note {
                Text(note).font(.caption).foregroundStyle(.orange)
            } else if !rows.isEmpty {
                Text(usedAppleIntelligence ? "Found by Apple Intelligence. Check each item before adding."
                                           : "Found by date detection. Check each item before adding.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if rows.contains(where: { $0.isSelected && $0.item.kind == .event }) {
                LabeledContent("Calendar") { picker(for: .event, selection: $eventCalendarID) }.font(.callout)
            }
            if rows.contains(where: { $0.isSelected && $0.item.kind == .reminder }) {
                LabeledContent("List") { picker(for: .reminder, selection: $reminderListID) }.font(.callout)
            }
        }
    }

    private func picker(for kind: QuickAddKind, selection: Binding<String?>) -> some View {
        Picker("", selection: selection) {
            ForEach(model.writableCalendars(for: kind)) { calendar in
                Text("\(calendar.title) · \(model.badge(forCalendarID: calendar.id))").tag(Optional(calendar.id))
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private func binding(_ index: Int) -> Binding<Row> {
        Binding(get: { rows?[index] ?? Row(item: placeholder, isSelected: false) },
                set: { if rows?.indices.contains(index) == true { rows?[index] = $0 } })
    }

    private var placeholder: TextImportItem {
        TextImportItem(id: -1, title: "", kind: .event, location: nil, isAllDay: false, start: Date(), end: Date(),
                       hasDueTime: false, hasDate: false)
    }

    // MARK: - Footer and actions

    private var footer: some View {
        HStack {
            if rows != nil {
                Button("Back") { rows = nil; note = nil; errorMessage = nil }
            }
            Spacer()
            Button("Cancel") { model.popoverMode = .agenda }
                .keyboardShortcut(.cancelAction)
            if let rows {
                let count = rows.filter(\.isSelected).count
                Button(count == 1 ? "Add 1" : "Add \(count)") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(count == 0)
            } else {
                Button("Find Events") { read() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isReading || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func read() {
        isReading = true
        errorMessage = nil
        let source = text
        let useAI = prefs.addFromTextUsesAI
        readTask = Task {
            let result = await TextImportEngine.candidates(in: source, useAppleIntelligence: useAI, now: Date())
            guard !Task.isCancelled else { return }
            let parser = QuickAddParser(calendar: model.calendar, now: Date())
            let items = TextImport.items(from: result.candidates, sourceText: source, parser: parser)
            // Items without a trusted date start unticked: the user sets the date, then ticks them.
            rows = items.map { Row(item: $0, isSelected: $0.hasDate) }
            usedAppleIntelligence = result.usedAppleIntelligence
            note = result.note
            eventCalendarID = eventCalendarID ?? model.defaultCalendarID(for: .event)
            reminderListID = reminderListID ?? model.defaultCalendarID(for: .reminder)
            isReading = false
        }
    }

    private func add() {
        guard let rows else { return }
        do {
            let added = try model.addImported(rows.filter(\.isSelected).map(\.item),
                                              eventCalendarID: eventCalendarID, reminderListID: reminderListID)
            model.showToast(added == 1 ? "Added 1 item" : "Added \(added) items")
            model.popoverMode = .agenda
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One found item: tick, type, title, and its date (asked for when the text gave none).
private struct ImportRowView: View {
    @Binding var row: AddFromTextView.Row

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $row.isSelected).labelsHidden().toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Button {
                        row.item.kind = row.item.kind == .event ? .reminder : .event
                    } label: {
                        Image(systemName: row.item.kind == .event ? "calendar" : "checklist")
                    }
                    .buttonStyle(.borderless)
                    .help(row.item.kind == .event ? "Event (click for a reminder)" : "Reminder (click for an event)")
                    TextField("Title", text: $row.item.title)
                        .textFieldStyle(.plain)
                        .font(.callout)
                }
                HStack(spacing: 6) {
                    DatePicker("", selection: startBinding, displayedComponents: components)
                        .labelsHidden()
                        .controlSize(.small)
                    if !row.item.hasDate {
                        Text("No date in the text").font(.caption2).foregroundStyle(.orange)
                    }
                }
                if let location = row.item.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 6)
        .opacity(row.isSelected ? 1 : 0.6)
    }

    private var components: DatePickerComponents {
        switch row.item.kind {
        case .event: row.item.isAllDay ? [.date] : [.date, .hourAndMinute]
        case .reminder: row.item.hasDueTime ? [.date, .hourAndMinute] : [.date]
        }
    }

    /// Moving the start keeps the event's length; setting a date the text lacked ticks the item.
    private var startBinding: Binding<Date> {
        Binding(
            get: { row.item.start },
            set: { newStart in
                let length = row.item.end.timeIntervalSince(row.item.start)
                row.item.start = newStart
                row.item.end = newStart.addingTimeInterval(length)
                if !row.item.hasDate {
                    row.item.hasDate = true
                    row.isSelected = true
                }
            }
        )
    }
}

/// General tab.
struct AddFromTextSettingsSection: View {
    @Environment(PreferencesStore.self) private var prefs
    @State private var status = AppleIntelligenceStatus.current

    var body: some View {
        @Bindable var prefs = prefs
        Section {
            Toggle("Add events from pasted text", isOn: $prefs.addFromTextEnabled)
            Toggle("Use Apple Intelligence to read the text", isOn: $prefs.addFromTextUsesAI)
                .disabled(!prefs.addFromTextEnabled || !status.isAvailable)
            if case .unavailable(let reason) = status {
                Text(reason + " Without it, sentences with a date are found instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Add from text")
        } footer: {
            SectionFooter("Quick add shows “From Text…”. Paste an email, chat or schedule to see the events and reminders "
                          + "it mentions; nothing is added until you tick them. Apple Intelligence runs on this Mac, "
                          + "and only dates that appear in the text are used.")
        }
        .onAppear { status = AppleIntelligenceStatus.current }
    }
}
