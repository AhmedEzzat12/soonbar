import SoonbarCore
import SwiftUI

/// What was typed in New, kept when leaving without adding (Esc, the back button, clicking away), so pressing New
/// again picks up where it left off. Dropped after an hour, when "tomorrow" may no longer mean what it did.
struct QuickAddMemory {
    var text: String
    var draft: QuickAddDraft
    var overridden: Set<QuickAddView.Field>
    var savedAt = Date()

    var isFresh: Bool { Date().timeIntervalSince(savedAt) < 3600 }
}

/// One line of text parsed live into an editable form. Fields the user edits by hand
/// stop being overwritten by further typing.
struct QuickAddView: View {
    @Environment(AppModel.self) private var model
    @Environment(PreferencesStore.self) private var prefs
    @State private var text = ""
    @State private var draft = QuickAddParser(calendar: .current, now: Date()).parse("", calendars: [])
    @State private var overridden: Set<Field> = []
    @State private var errorMessage: String?
    @State private var isSaving = false
    /// Set when the draft is added or discarded, so leaving doesn't keep it.
    @State private var finished = false
    @State private var restoredNote: String?
    @FocusState private var inputFocused: Bool

    enum Field: Hashable {
        case kind, title, calendar, allDay, start, end, dueTime
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            TextField("Lunch with Sara tomorrow 1pm 1h #work", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
            HStack {
                Text("Start with ! for a reminder · #name picks a calendar")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if prefs.addFromTextEnabled {
                    Spacer()
                    Button("From Text…") { openAddFromText() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            if prefs.addFromTextEnabled && text.count > 80 {
                Button("This looks like more than one item: find events in it") { openAddFromText() }
                    .buttonStyle(.link)
                    .font(.caption)
            }

            form

            if let token = draft.unmatchedCalendarToken {
                Text("No calendar matches #\(token), using the default.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if model.writableCalendars(for: draft.kind).isEmpty {
                Text(draft.kind == .event ? "No writable calendars." : "No writable reminder lists.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Discard", role: .destructive) { discard() }
                    .disabled(!hasContent)
                    .help("Throw away what you typed")
                Spacer()
                Button("Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(12)
        .onAppear(perform: restore)
        .onDisappear(perform: keep)
        .onExitCommand { goBack() }
        .onChange(of: text) { reparse() }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(hasContent ? "Back to the agenda (Esc). What you typed is kept." : "Back to the agenda (Esc)")
            Text(draft.kind == .event ? "New Event" : "New Reminder").font(.headline)
            Spacer()
            if hasContent, let restoredNote {
                Text(restoredNote).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var form: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                label("Type")
                Picker("", selection: kindBinding) {
                    Text("Event").tag(QuickAddKind.event)
                    Text("Reminder").tag(QuickAddKind.reminder)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            GridRow {
                label("Title")
                TextField("Title", text: binding(\.title, .title))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }
            GridRow {
                label(draft.kind == .event ? "Calendar" : "List")
                calendarPicker
            }
            if draft.kind == .event {
                GridRow {
                    label("All day")
                    Toggle("", isOn: binding(\.isAllDay, .allDay)).labelsHidden()
                }
                GridRow {
                    label("Starts")
                    DatePicker("", selection: startBinding,
                               displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                        .labelsHidden()
                }
                if !draft.isAllDay {
                    GridRow {
                        label("Ends")
                        DatePicker("", selection: endBinding, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                }
            } else {
                GridRow {
                    label("Due")
                    DatePicker("", selection: binding(\.start, .start),
                               displayedComponents: draft.hasDueTime ? [.date, .hourAndMinute] : [.date])
                        .labelsHidden()
                }
                GridRow {
                    label("Time")
                    Toggle("", isOn: binding(\.hasDueTime, .dueTime)).labelsHidden()
                }
            }
        }
        .font(.callout)
    }

    private var calendarPicker: some View {
        Picker("", selection: calendarBinding) {
            ForEach(model.accounts) { account in
                let calendars = model.writableCalendars(for: draft.kind).filter { $0.accountID == account.id }
                if !calendars.isEmpty {
                    Section("\(account.title) [\(prefs.badge(for: account))]") {
                        ForEach(calendars) { calendar in
                            Text(calendar.title).tag(Optional(calendar.id))
                        }
                    }
                }
            }
        }
        .labelsHidden()
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    // MARK: - Bindings

    private func binding<Value>(_ keyPath: WritableKeyPath<QuickAddDraft, Value>, _ field: Field) -> Binding<Value> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { draft[keyPath: keyPath] = $0; overridden.insert(field) }
        )
    }

    private var kindBinding: Binding<QuickAddKind> {
        Binding(
            get: { draft.kind },
            set: { kind in
                // Event calendars and reminder lists are different things; drop a hand-picked one.
                draft.kind = kind
                draft.calendarID = nil
                overridden.insert(.kind)
                overridden.remove(.calendar)
                reparse()
            }
        )
    }

    /// Moving the start keeps the event's length, like Calendar.app.
    private var startBinding: Binding<Date> {
        Binding(
            get: { draft.start },
            set: { newStart in
                let length = draft.end.timeIntervalSince(draft.start)
                draft.start = newStart
                draft.end = newStart.addingTimeInterval(length)
                overridden.insert(.start)
            }
        )
    }

    /// No `in: start...` range on the picker: while typing moved the start, it clamped the old end to the old start
    /// and wrote that back as a hand-picked end. The end is kept after the start here instead.
    private var endBinding: Binding<Date> {
        Binding(
            get: { draft.end },
            set: { newEnd in
                draft.end = max(newEnd, draft.start)
                overridden.insert(.end)
            }
        )
    }

    private var calendarBinding: Binding<String?> {
        Binding(
            get: { resolvedCalendarID },
            set: { draft.calendarID = $0; overridden.insert(.calendar) }
        )
    }

    // MARK: - Parsing and saving

    /// The chosen calendar if it can hold this kind of item, else the default.
    private var resolvedCalendarID: String? {
        if let chosen = draft.calendarID, model.writableCalendars(for: draft.kind).contains(where: { $0.id == chosen }) {
            return chosen
        }
        return model.defaultCalendarID(for: draft.kind)
    }

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty || overridden.contains(.title)
    }

    private var canSave: Bool {
        !isSaving && !draft.title.trimmingCharacters(in: .whitespaces).isEmpty && resolvedCalendarID != nil
    }

    private func reparse() {
        let parser = QuickAddParser(calendar: model.calendar, now: Date())
        let parsed = parser.parse(text, calendars: model.calendars, forcedKind: overridden.contains(.kind) ? draft.kind : nil)
        var next = draft
        if !overridden.contains(.kind) { next.kind = parsed.kind }
        if !overridden.contains(.title) { next.title = parsed.title }
        if !overridden.contains(.calendar) { next.calendarID = parsed.calendarID }
        next.unmatchedCalendarToken = parsed.unmatchedCalendarToken
        if !overridden.contains(.allDay) { next.isAllDay = parsed.isAllDay }
        if !overridden.contains(.start) { next.start = parsed.start }
        if !overridden.contains(.end) {
            let parsedLength = parsed.end.timeIntervalSince(parsed.start)
            next.end = overridden.contains(.start) ? next.start.addingTimeInterval(parsedLength) : parsed.end
        }
        if !overridden.contains(.dueTime) { next.hasDueTime = parsed.hasDueTime }
        next.hasExplicitDate = parsed.hasExplicitDate
        next.dayIsImplied = parsed.dayIsImplied
        // With a day picked in the month grid, "Dentist 3pm" goes on that day.
        if let day = model.selectedDay, !overridden.contains(.start) {
            next = next.placed(onDay: day, calendar: model.calendar)
        }
        draft = next
    }

    // MARK: - Leaving

    private func goBack() {
        model.popoverMode = .agenda
    }

    private func restore() {
        if let memory = model.quickAddMemory, memory.isFresh {
            text = memory.text
            draft = memory.draft
            overridden = memory.overridden
            restoredNote = "Draft"
        }
        model.quickAddMemory = nil
        reparse()
        inputFocused = true
    }

    /// Leaving without adding keeps what was typed for next time.
    private func keep() {
        guard !finished, hasContent else { return }
        model.quickAddMemory = QuickAddMemory(text: text, draft: draft, overridden: overridden)
    }

    private func discard() {
        finished = true
        model.quickAddMemory = nil
        model.popoverMode = .agenda
    }

    /// Long text pasted here is carried over, so it doesn't have to be pasted again.
    private func openAddFromText() {
        model.importText = text.count > 80 ? text : ""
        if text.count > 80 { finished = true }
        model.popoverMode = .addFromText
    }

    private func save() {
        guard canSave, let calendarID = resolvedCalendarID else { return }
        isSaving = true
        do {
            finished = true
            try model.save(draft, calendarID: calendarID)
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
            finished = false
        }
    }
}
