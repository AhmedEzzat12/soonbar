import AppKit
import SoonbarCore
import SwiftUI

/// Borderless, so it opts back in to key status; as a non-activating panel it takes it only when clicked,
/// without activating the app.
private final class BriefPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The meeting brief: a small card in the top-right corner, just under the menu bar, on every Space.
/// It never steals focus and closes itself at the given date.
@MainActor
final class MeetingBriefPanelController {
    static let width: CGFloat = 340
    private static let cornerRadius: CGFloat = 14
    private static let margin: CGFloat = 10

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(_ event: CalendarEvent, model: AppModel, until dismissDate: Date?) {
        dismiss()
        let hosting = NSHostingView(rootView: MeetingBriefView(
            event: event, brief: MeetingBriefBuilder.build(for: event), dismiss: { [weak self] in self?.dismiss() }
        ).environment(model))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]

        // NSVisualEffectView with a mask image is how AppKit draws rounded, behind-window material.
        let background = NSVisualEffectView(frame: hosting.frame)
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask
        background.addSubview(hosting)

        let panel = BriefPanel(
            contentRect: hosting.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = background
        if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - Self.margin, y: frame.maxY - size.height - Self.margin))
        }
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        self.panel = panel

        guard let dismissDate else { return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, dismissDate.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private static let roundedMask: NSImage = {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }()
}

struct MeetingBriefView: View {
    let event: CalendarEvent
    let brief: MeetingBrief
    let dismiss: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(model.calendarInfo(event.calendarID)?.color ?? .gray))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 10) {
                header
                if let location = brief.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.callout)
                        .lineLimit(2)
                }
                if !brief.attendees.isEmpty { attendees }
                if !brief.links.isEmpty { links }
                if let notes = brief.notes {
                    Text(EventDetailView.linkified(notes))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                }
                if let link = brief.meetingLink {
                    Button {
                        model.join(link)
                        dismiss()
                    } label: {
                        Label("Join \(link.provider.displayName)", systemImage: "video.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .padding(14)
        .frame(width: MeetingBriefPanelController.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(2)
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text(subtitle(now: context.date))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
            .accessibilityLabel("Close")
        }
    }

    private var attendees: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(brief.attendees.enumerated()), id: \.offset) { _, attendee in
                HStack(spacing: 6) {
                    Image(systemName: Self.symbol(for: attendee.status))
                        .foregroundStyle(Self.color(for: attendee.status))
                        .help(Self.label(for: attendee.status))
                        .accessibilityLabel(Self.label(for: attendee.status))
                    Text(MeetingBriefBuilder.displayName(attendee))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if attendee.isOrganizer {
                        Text("Organizer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if brief.moreAttendees > 0 {
                Text("and \(brief.moreAttendees) more")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private var links: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(brief.links, id: \.self) { link in
                Link(destination: link.url) {
                    Label(link.title, systemImage: "link")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .help(link.url.absoluteString)
            }
        }
        .font(.callout)
    }

    private func subtitle(now: Date) -> String {
        let time = AgendaFormatting.timeRange(for: event, on: event.start, calendar: model.calendar, locale: .current)
        let status = MeetingBriefBuilder.status(start: event.start, now: now, calendar: model.calendar, locale: .current)
        return "\(time) · \(status)"
    }

    private static func symbol(for status: Attendee.Status) -> String {
        switch status {
        case .accepted: "checkmark.circle.fill"
        case .declined: "xmark.circle.fill"
        case .tentative: "questionmark.circle.fill"
        case .pending: "clock"
        case .unknown: "circle.dashed"
        }
    }

    private static func color(for status: Attendee.Status) -> Color {
        switch status {
        case .accepted: .green
        case .declined: .red
        case .tentative: .orange
        case .pending, .unknown: .secondary
        }
    }

    private static func label(for status: Attendee.Status) -> String {
        switch status {
        case .accepted: "Accepted"
        case .declined: "Declined"
        case .tentative: "Maybe"
        case .pending: "Hasn't responded"
        case .unknown: "Response unknown"
        }
    }
}
