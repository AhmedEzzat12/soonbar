import AppKit
import SoonbarCore
import Observation
import SwiftUI

/// Owns the menu bar item and the popover. Re-renders the title whenever the model changes.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let model: AppModel
    private let prefs: PreferencesStore
    private var renderedDay = 0
    /// AppKit leaves only ~5.5 pt between a status item's icon and its title, which looks cramped.
    /// A thin space + hair space before the title brings it to ~8.5 pt (measured), in both title styles.
    private static let iconTitleGap = "\u{2009}\u{200A}"

    init(model: AppModel, prefs: PreferencesStore) {
        self.model = model
        self.prefs = prefs
        super.init()

        let hosting = NSHostingController(rootView: PopoverView().environment(model).environment(prefs))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        observeModel()
    }

    func show(mode: PopoverMode) {
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            model.beginPopoverSession()
            model.scheduleRefresh(delay: 0)
        }
        model.popoverMode = mode
        NSApp.activate()
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() {
        popover.performClose(nil)
    }

    @objc private func togglePopover() {
        if popover.isShown { close() } else { show(mode: .agenda) }
    }

    func popoverDidClose(_ notification: Notification) {
        model.popoverMode = .agenda
    }

    /// withObservationTracking fires once per change, so re-arm after every render.
    private func observeModel() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeModel() }
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let day = model.calendar.component(.day, from: model.now)
        if day != renderedDay {
            button.image = CalendarIconRenderer.image(day: day)
            renderedDay = day
        }
        popover.behavior = model.isPinned ? .applicationDefined : .transient

        guard let title = model.menuBarTitle else {
            button.title = ""
            button.imagePosition = .imageOnly
            return
        }
        button.imagePosition = .imageLeading
        let dotColor = prefs.showColorDot ? model.calendarInfo(title.event.calendarID)?.color : nil
        guard dotColor != nil || title.isUrgent else {
            button.title = Self.iconTitleGap + title.text
            return
        }
        let font = NSFont.menuBarFont(ofSize: 0)
        let text = NSMutableAttributedString(string: Self.iconTitleGap, attributes: [.font: font])
        if let dotColor {
            text.append(NSAttributedString(string: "● ", attributes: [.font: font, .foregroundColor: NSColor(dotColor)]))
        }
        // Red text on the translucent menu bar is hard to read, so urgency is a red icon and the text stays neutral.
        if title.isUrgent, let timer = Self.urgentIcon(font: font) {
            text.append(NSAttributedString(attachment: timer))
            text.append(NSAttributedString(string: " ", attributes: [.font: font]))
        }
        text.append(NSAttributedString(string: title.text, attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
        button.attributedTitle = text
    }

    /// A red timer sized to the menu bar font.
    private static func urgentIcon(font: NSFont) -> NSTextAttachment? {
        let config = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .semibold)
            .applying(.init(paletteColors: [.systemRed]))
        guard let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Ending soon")?
            .withSymbolConfiguration(config) else { return nil }
        image.isTemplate = false
        let attachment = NSTextAttachment()
        attachment.image = image
        // Centered on the capital letters, the usual way to line an inline icon up with text.
        let y = ((font.capHeight - image.size.height) / 2).rounded()
        attachment.bounds = CGRect(x: 0, y: y, width: image.size.width, height: image.size.height)
        return attachment
    }
}
