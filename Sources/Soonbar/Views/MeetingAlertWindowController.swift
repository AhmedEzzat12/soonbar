import AppKit
import SoonbarCore
import SwiftUI

/// Borderless panel that can take keyboard focus, so Return joins and Esc dismisses.
private final class AlertPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The full-screen "your meeting is starting" alert: one panel per display, above full-screen apps
/// and on every Space.
@MainActor
final class MeetingAlertWindowController {
    private var panels: [NSPanel] = []
    private var autoDismissTask: Task<Void, Never>?

    func show(_ events: [CalendarEvent], model: AppModel) {
        dismiss()
        guard !events.isEmpty else { return }
        let seconds = model.prefs.meetingAlertAutoDismissSeconds
        let closesAt = seconds > 0 ? Date().addingTimeInterval(TimeInterval(seconds)) : nil
        for screen in NSScreen.screens {
            let panel = AlertPanel(
                contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
            )
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(
                rootView: MeetingAlertView(events: events, shownAt: Date(), closesAt: closesAt, dismiss: { [weak self] in self?.dismiss() })
                    .environment(model)
            )
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        NSApp.activate()
        (panels.first { $0.screen == NSScreen.main } ?? panels.first)?.makeKey()
        NSSound(named: "Glass")?.play()
        guard seconds > 0 else { return }
        // Closes as if dismissed: later alert times and snoozes for the meeting still come.
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }
}

struct MeetingAlertView: View {
    let events: [CalendarEvent]
    let shownAt: Date
    /// When the alert closes by itself, if set to (Settings → Alerts).
    var closesAt: Date?
    let dismiss: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(0.4)
            VStack(spacing: 32) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 56, weight: .medium))
                ForEach(events) { event in
                    card(for: event, isPrimary: event.id == events.first?.id)
                }
                HStack(spacing: 12) {
                    if !snoozeChoices.isEmpty {
                        Text("Remind me in").opacity(0.75)
                        ForEach(snoozeChoices, id: \.self) { minutes in
                            Button("\(minutes) min") {
                                model.snoozeMeetingAlert(events, minutes: minutes)
                                dismiss()
                            }
                        }
                        Divider().frame(height: 18).overlay(.white.opacity(0.3))
                    }
                    Button("Dismiss") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                .controlSize(.large)
                if let closesAt {
                    TimelineView(.periodic(from: shownAt, by: 1)) { context in
                        Text("Closes in \(RelativeTime.countdown(until: closesAt, now: context.date))")
                            .font(.callout)
                            .monospacedDigit()
                            .opacity(0.6)
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 680)
            .padding(40)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    private func card(for event: CalendarEvent, isPrimary: Bool) -> some View {
        let link = MeetingLinkDetector.detect(url: event.url, location: event.location, notes: event.notes)
        return VStack(spacing: 12) {
            Text(status(of: event))
                .font(.title3.weight(.semibold))
                .opacity(0.75)
            HStack(alignment: .center, spacing: 14) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(model.calendarInfo(event.calendarID)?.color ?? .gray))
                    .frame(width: 6, height: 44)
                Text(event.title)
                    .font(.system(size: 40, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            Text(details(of: event))
                .font(.title3)
                .opacity(0.75)
            if let link {
                Button {
                    model.join(link)
                    model.finishMeetingAlerts(event)
                    dismiss()
                } label: {
                    Label("Join \(link.provider.displayName)", systemImage: "video.fill")
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(isPrimary ? .defaultAction : nil)
                .padding(.top, 8)
            }
        }
    }

    /// Snooze lengths that still end before every meeting in the alert does.
    private var snoozeChoices: [Int] {
        [1, 2, 5].filter { minutes in
            events.allSatisfy { MeetingAlertPlanner.snoozeDate(for: $0, now: shownAt, minutes: minutes) != nil }
        }
    }

    private func status(of event: CalendarEvent) -> String {
        let seconds = event.start.timeIntervalSince(shownAt)
        if seconds >= 60 {
            return "Starts \(RelativeTime.untilStart(event.start, now: shownAt, calendar: model.calendar, locale: .current))"
        }
        return seconds > -60 ? "Starting now" : "Started \(RelativeTime.duration(minutes: Int(-seconds / 60))) ago"
    }

    private func details(of event: CalendarEvent) -> String {
        let time = AgendaFormatting.timeRange(for: event, on: event.start, calendar: model.calendar, locale: .current)
        let calendar = model.calendarInfo(event.calendarID)?.title
        let account = model.account(forCalendarID: event.calendarID)?.title
        return [time, calendar, account].compactMap { $0 }.joined(separator: " · ")
    }
}
