import SwiftUI
import AppKit

// MARK: - Horizontal Split (Left sidebar | Right content)

class HSplitController<Left: View, Right: View>: NSSplitViewController {
    let leftView: Left
    let rightView: Right
    let leftMin: CGFloat
    let leftMax: CGFloat
    private var savedLeftWidth: CGFloat?
    private var isWindowResizing = false

    init(left: Left, right: Right, leftMin: CGFloat, leftMax: CGFloat) {
        self.leftView = left
        self.rightView = right
        self.leftMin = leftMin
        self.leftMax = leftMax
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let leftHost = NSHostingController(rootView: leftView)
        leftHost.view.widthAnchor.constraint(greaterThanOrEqualToConstant: leftMin).isActive = true
        leftHost.view.widthAnchor.constraint(lessThanOrEqualToConstant: leftMax).isActive = true
        let leftItem = NSSplitViewItem(viewController: leftHost)
        leftItem.canCollapse = false
        addSplitViewItem(leftItem)

        let rightHost = NSHostingController(rootView: rightView)
        rightHost.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
        let rightItem = NSSplitViewItem(viewController: rightHost)
        addSplitViewItem(rightItem)

        splitView.autosaveName = "MainHSplit"

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillStartResize),
            name: NSWindow.willStartLiveResizeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidResize),
            name: NSWindow.didResizeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidEndResize),
            name: NSWindow.didEndLiveResizeNotification, object: nil)
    }

    @objc private func windowWillStartResize(_ note: Notification) {
        guard (note.object as? NSWindow) == view.window else { return }
        isWindowResizing = true
        if splitView.subviews.count >= 2 {
            savedLeftWidth = splitView.subviews[0].frame.width
        }
    }

    @objc private func windowDidResize(_ note: Notification) {
        guard isWindowResizing,
              (note.object as? NSWindow) == view.window,
              let saved = savedLeftWidth,
              splitView.subviews.count >= 2 else { return }
        splitView.setPosition(saved, ofDividerAt: 0)
    }

    @objc private func windowDidEndResize(_ note: Notification) {
        guard (note.object as? NSWindow) == view.window else { return }
        isWindowResizing = false
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

struct PersistentHSplitView<Left: View, Right: View>: NSViewControllerRepresentable {
    let autosaveName: String
    let left: Left
    let right: Right
    let leftMinWidth: CGFloat
    let leftMaxWidth: CGFloat

    init(
        autosaveName: String,
        leftMinWidth: CGFloat = 150,
        leftMaxWidth: CGFloat = 220,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) {
        self.autosaveName = autosaveName
        self.leftMinWidth = leftMinWidth
        self.leftMaxWidth = leftMaxWidth
        self.left = left()
        self.right = right()
    }

    func makeNSViewController(context: Context) -> NSViewController {
        return HSplitController(left: left, right: right, leftMin: leftMinWidth, leftMax: leftMaxWidth)
    }

    func updateNSViewController(_ controller: NSViewController, context: Context) {
        guard let sc = controller as? HSplitController<Left, Right> else { return }
        if let leftHost = sc.splitViewItems[0].viewController as? NSHostingController<Left> {
            leftHost.rootView = left
        }
        if let rightHost = sc.splitViewItems[1].viewController as? NSHostingController<Right> {
            rightHost.rootView = right
        }
    }
}

// MARK: - Vertical Split (Top editor / Bottom output)

class VSplitController<Top: View, Bottom: View>: NSSplitViewController {
    let topView: Top
    let bottomView: Bottom
    let topMin: CGFloat
    let bottomMin: CGFloat
    private var savedTopHeight: CGFloat?
    private var isWindowResizing = false

    init(top: Top, bottom: Bottom, topMin: CGFloat, bottomMin: CGFloat) {
        self.topView = top
        self.bottomView = bottom
        self.topMin = topMin
        self.bottomMin = bottomMin
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = false
        splitView.dividerStyle = .thin

        let topHost = NSHostingController(rootView: topView)
        topHost.view.heightAnchor.constraint(greaterThanOrEqualToConstant: topMin).isActive = true
        let topItem = NSSplitViewItem(viewController: topHost)
        topItem.canCollapse = false
        addSplitViewItem(topItem)

        let bottomHost = NSHostingController(rootView: bottomView)
        bottomHost.view.heightAnchor.constraint(greaterThanOrEqualToConstant: bottomMin).isActive = true
        let bottomItem = NSSplitViewItem(viewController: bottomHost)
        bottomItem.canCollapse = false
        addSplitViewItem(bottomItem)

        splitView.autosaveName = "MainVSplit"

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillStartResize),
            name: NSWindow.willStartLiveResizeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidResize),
            name: NSWindow.didResizeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidEndResize),
            name: NSWindow.didEndLiveResizeNotification, object: nil)
    }

    @objc private func windowWillStartResize(_ note: Notification) {
        guard (note.object as? NSWindow) == view.window else { return }
        isWindowResizing = true
        if splitView.subviews.count >= 2 {
            savedTopHeight = splitView.subviews[0].frame.height
        }
    }

    @objc private func windowDidResize(_ note: Notification) {
        guard isWindowResizing,
              (note.object as? NSWindow) == view.window,
              let saved = savedTopHeight,
              splitView.subviews.count >= 2 else { return }
        let total = splitView.bounds.height
        let divider = splitView.dividerThickness
        let maxTop = total - divider - bottomMin
        let restored = min(saved, maxTop)
        splitView.setPosition(restored, ofDividerAt: 0)
    }

    @objc private func windowDidEndResize(_ note: Notification) {
        guard (note.object as? NSWindow) == view.window else { return }
        isWindowResizing = false
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

struct PersistentVSplitView<Top: View, Bottom: View>: NSViewControllerRepresentable {
    let autosaveName: String
    let top: Top
    let bottom: Bottom
    let topMinHeight: CGFloat
    let bottomMinHeight: CGFloat

    init(
        autosaveName: String,
        topMinHeight: CGFloat = 150,
        bottomMinHeight: CGFloat = 80,
        @ViewBuilder top: () -> Top,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.autosaveName = autosaveName
        self.topMinHeight = topMinHeight
        self.bottomMinHeight = bottomMinHeight
        self.top = top()
        self.bottom = bottom()
    }

    func makeNSViewController(context: Context) -> NSViewController {
        return VSplitController(top: top, bottom: bottom, topMin: topMinHeight, bottomMin: bottomMinHeight)
    }

    func updateNSViewController(_ controller: NSViewController, context: Context) {
        guard let sc = controller as? VSplitController<Top, Bottom> else { return }
        if let topHost = sc.splitViewItems[0].viewController as? NSHostingController<Top> {
            topHost.rootView = top
        }
        if let bottomHost = sc.splitViewItems[1].viewController as? NSHostingController<Bottom> {
            bottomHost.rootView = bottom
        }
    }
}
