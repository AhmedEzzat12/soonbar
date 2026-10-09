import AppKit
import SoonbarCore
import SwiftUI

/// Borderless, so it opts back in to key status; as a non-activating panel it takes it only when clicked,
/// without activating the app.
private final class BriefPanel: NSPanel {
    /// Called with how far the fingers have moved right since a two-finger swipe began, then once when it ends.
    var onSwipe: ((CGFloat) -> Void)?
    var onSwipeEnd: (() -> Void)?
    private var swipeOffset: CGFloat?

    override var canBecomeKey: Bool { true }

    /// Nothing in the brief scrolls, so trackpad scrolling is free to mean "swipe it away", as with a notification.
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .scrollWheel, event.hasPreciseScrollingDeltas else { return super.sendEvent(event) }
        switch event.phase {
        case .began:
            swipeOffset = 0
        case .changed:
            guard let offset = swipeOffset else { return }
            // Natural scrolling reports deltas the way the content moves, which is the way the fingers move.
            let fingersRight = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            swipeOffset = offset + fingersRight
            onSwipe?(offset + fingersRight)
        case .ended, .cancelled:
            guard swipeOffset != nil else { return }
            swipeOffset = nil
            onSwipeEnd?()
        default:
            break // momentum after the fingers lift: the swipe has already been decided
        }
    }
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
    /// Where the brief sits when it isn't being swiped.
    private var restingOrigin = NSPoint.zero
    /// The swipe or drag in progress: its offset, speed (points per second) and when it last moved.
    private var slide: (offset: CGFloat, velocity: CGFloat, time: TimeInterval)?

    func show(_ event: CalendarEvent, model: AppModel, until dismissDate: Date?) {
        dismiss()
        let hosting = NSHostingView(rootView: MeetingBriefView(
            event: event, brief: MeetingBriefBuilder.build(for: event),
            dismiss: { [weak self] in self?.dismiss() },
            slide: { [weak self] in self?.slideChanged(to: $0) },
            endSlide: { [weak self] in self?.slideEnded() }
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
        panel.onSwipe = { [weak self] in self?.slideChanged(to: $0) }
        panel.onSwipeEnd = { [weak self] in self?.slideEnded() }
        if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            restingOrigin = NSPoint(x: frame.maxX - size.width - Self.margin, y: frame.maxY - size.height - Self.margin)
            panel.setFrameOrigin(restingOrigin)
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
        slide = nil
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Swipe to dismiss

    /// The brief follows a drag or two-finger swipe to the right, fading as it goes.
    private func slideChanged(to offset: CGFloat) {
        guard let panel else { return }
        let time = ProcessInfo.processInfo.systemUptime
        var velocity: CGFloat = 0
        if let last = slide, time > last.time { velocity = (offset - last.offset) / (time - last.time) }
        slide = (offset, velocity, time)
        panel.setFrameOrigin(NSPoint(x: restingOrigin.x + SwipeToDismiss.position(for: offset), y: restingOrigin.y))
        panel.alphaValue = SwipeToDismiss.opacity(offset: offset, width: Self.width)
    }

    /// Far or fast enough slides off the screen and closes; otherwise springs back.
    private func slideEnded() {
        guard let panel, let last = slide else { return }
        slide = nil
        // Holding still before letting go is a drop, not a flick.
        let velocity = ProcessInfo.processInfo.systemUptime - last.time > 0.1 ? 0 : last.velocity
        let dismissing = SwipeToDismiss.shouldDismiss(offset: last.offset, velocity: velocity, width: Self.width)
        let target = NSPoint(x: restingOrigin.x + (dismissing ? Self.width + Self.margin * 2 : 0), y: restingOrigin.y)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: dismissing ? .easeIn : .easeOut)
            panel.animator().setFrameOrigin(target)
            panel.animator().alphaValue = dismissing ? 0 : 1
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A newer brief may have replaced this one while it slid away.
                if dismissing, let self, self.panel === panel { self.dismiss() }
            }
        }
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
    /// Called with how far the pointer has moved right during a drag, then once when it's released.
    let slide: (CGFloat) -> Void
    let endSlide: () -> Void
    @Environment(AppModel.self) private var model
    /// Screen x where the drag began. The panel moves under the pointer, so the gesture's own (window-relative)
    /// translation would stay near zero; the screen position is what tracks the drag.
    @State private var dragStartX: CGFloat?

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
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    let x = NSEvent.mouseLocation.x
                    let start = dragStartX ?? x - value.translation.width
                    dragStartX = start
                    slide(x - start)
                }
                .onEnded { _ in
                    dragStartX = nil
                    endSlide()
                }
        )
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
