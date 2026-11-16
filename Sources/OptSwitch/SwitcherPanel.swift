import AppKit

/// Interactive card view representing one open window in the SwitcherPanel HUD.
final class WindowCardView: NSView {
    let index: Int
    var onClick: ((Int) -> Void)?

    var isSelected: Bool = false {
        didSet {
            updateSelectionAppearance()
        }
    }

    init(frame frameRect: NSRect, item: WindowItem, index: Int, isSelected: Bool) {
        self.index = index
        self.isSelected = isSelected
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        setupSubviews(with: item)
        updateSelectionAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSubviews(with item: WindowItem) {
        let padding: CGFloat = 10
        let cardWidth = bounds.width
        let cardHeight = bounds.height

        // Preview container (either capped window thumbnail or large app icon)
        let previewHeight: CGFloat = 110
        let previewFrame = NSRect(
            x: padding,
            y: cardHeight - padding - previewHeight,
            width: cardWidth - (padding * 2),
            height: previewHeight
        )

        let previewContainer = NSView(frame: previewFrame)
        previewContainer.wantsLayer = true
        previewContainer.layer?.cornerRadius = 8
        previewContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        addSubview(previewContainer)

        if let thumbnail = item.thumbnail {
            let thumbView = NSImageView(frame: previewContainer.bounds.insetBy(dx: 4, dy: 4))
            thumbView.image = thumbnail
            thumbView.imageScaling = .scaleProportionallyUpOrDown
            previewContainer.addSubview(thumbView)

            // Small badge app icon in the bottom-right of the preview
            if let appIcon = item.appIcon {
                let badgeSize: CGFloat = 28
                let badgeView = NSImageView(frame: NSRect(
                    x: previewContainer.bounds.width - badgeSize - 6,
                    y: 6,
                    width: badgeSize,
                    height: badgeSize
                ))
                badgeView.image = appIcon
                badgeView.imageScaling = .scaleProportionallyUpOrDown
                previewContainer.addSubview(badgeView)
            }
        } else if let appIcon = item.appIcon {
            let iconSize: CGFloat = 64
            let iconView = NSImageView(frame: NSRect(
                x: (previewContainer.bounds.width - iconSize) / 2,
                y: (previewContainer.bounds.height - iconSize) / 2,
                width: iconSize,
                height: iconSize
            ))
            iconView.image = appIcon
            iconView.imageScaling = .scaleProportionallyUpOrDown
            previewContainer.addSubview(iconView)
        }

        // Window Title label
        let titleLabel = NSTextField(labelWithString: item.windowTitle)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.frame = NSRect(x: padding, y: 28, width: cardWidth - (padding * 2), height: 18)
        addSubview(titleLabel)

        // App Name label
        let appLabel = NSTextField(labelWithString: item.appName)
        appLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        appLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        appLabel.alignment = .center
        appLabel.lineBreakMode = .byTruncatingTail
        appLabel.maximumNumberOfLines = 1
        appLabel.frame = NSRect(x: padding, y: 10, width: cardWidth - (padding * 2), height: 16)
        addSubview(appLabel)
    }

    private func updateSelectionAppearance() {
        if isSelected {
            layer?.borderWidth = 3.0
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        } else {
            layer?.borderWidth = 1.0
            layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(index)
    }
}

/// Floating Dark-Mode HUD Overlay Panel for Option+Tab window switching.
final class SwitcherPanel: NSPanel {
    private let visualEffectView = NSVisualEffectView()
    private var cardViews: [WindowCardView] = []
    private(set) var items: [WindowItem] = []
    private(set) var selectedIndex: Int = 0

    /// Invoked when the user clicks a window card directly with the mouse.
    var onMouseSelectWindow: ((WindowItem) -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.appearance = NSAppearance(named: .darkAqua)

        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 18
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 1.0
        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        self.contentView = visualEffectView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Displays the switcher panel with the provided window list (fetched ONCE per session).
    func present(with windows: [WindowItem], initialIndex: Int) {
        self.items = windows
        guard !windows.isEmpty else {
            hideHUD()
            return
        }

        self.selectedIndex = max(0, min(initialIndex, windows.count - 1))
        rebuildGrid()
        centerOnActiveScreen()
        orderFrontRegardless()
    }

    /// Updates the highlighted selection index without re-fetching any windows or screenshots.
    func updateSelection(to newIndex: Int) {
        guard !items.isEmpty else { return }
        let count = items.count
        let wrappedIndex = ((newIndex % count) + count) % count
        selectedIndex = wrappedIndex

        for (idx, card) in cardViews.enumerated() {
            card.isSelected = (idx == selectedIndex)
        }
    }

    /// Returns the currently highlighted WindowItem, if any.
    func currentlySelectedWindow() -> WindowItem? {
        guard !items.isEmpty, selectedIndex >= 0, selectedIndex < items.count else {
            return nil
        }
        return items[selectedIndex]
    }

    /// Hides the HUD and releases cached card views & thumbnails immediately.
    func hideHUD() {
        orderOut(nil)
        cardViews.forEach { $0.removeFromSuperview() }
        cardViews.removeAll()
        items.removeAll()
        selectedIndex = 0
    }

    private func rebuildGrid() {
        cardViews.forEach { $0.removeFromSuperview() }
        cardViews.removeAll()

        let screenFrame = activeScreenFrame()
        let maxColumns = min(max(1, Int((screenFrame.width * 0.88) / 196)), 6)
        let totalItems = items.count
        let columns = min(totalItems, maxColumns)
        let rows = Int(ceil(Double(totalItems) / Double(columns)))

        let cardWidth: CGFloat = 180
        let cardHeight: CGFloat = 172
        let spacing: CGFloat = 14
        let outerPadding: CGFloat = 20

        let panelWidth = (CGFloat(columns) * cardWidth) + (CGFloat(max(0, columns - 1)) * spacing) + (outerPadding * 2)
        let panelHeight = (CGFloat(rows) * cardHeight) + (CGFloat(max(0, rows - 1)) * spacing) + (outerPadding * 2)

        setContentSize(NSSize(width: panelWidth, height: panelHeight))
        visualEffectView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        for (index, item) in items.enumerated() {
            let row = index / columns
            let col = index % columns

            let x = outerPadding + CGFloat(col) * (cardWidth + spacing)
            // Flip Y so row 0 is at the top of the panel
            let y = panelHeight - outerPadding - cardHeight - (CGFloat(row) * (cardHeight + spacing))

            let cardFrame = NSRect(x: x, y: y, width: cardWidth, height: cardHeight)
            let card = WindowCardView(frame: cardFrame, item: item, index: index, isSelected: index == selectedIndex)
            card.onClick = { [weak self] clickedIdx in
                guard let self = self else { return }
                self.updateSelection(to: clickedIdx)
                if let chosen = self.currentlySelectedWindow() {
                    self.onMouseSelectWindow?(chosen)
                }
            }
            visualEffectView.addSubview(card)
            cardViews.append(card)
        }
    }

    private func activeScreenFrame() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        if let screenWithMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screenWithMouse.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func centerOnActiveScreen() {
        let screenRect = activeScreenFrame()
        let panelSize = frame.size
        let originX = screenRect.origin.x + (screenRect.width - panelSize.width) / 2.0
        let originY = screenRect.origin.y + (screenRect.height - panelSize.height) / 2.0
        setFrameOrigin(NSPoint(x: originX.rounded(), y: originY.rounded()))
    }
}
