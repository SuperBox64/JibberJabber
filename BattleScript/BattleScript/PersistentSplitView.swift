import SwiftUI
import AppKit

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

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = NSSplitViewController()
        controller.splitView.isVertical = true
        controller.splitView.dividerStyle = .thin

        let leftHost = NSHostingController(rootView: left)
        let leftItem = NSSplitViewItem(viewController: leftHost)
        leftItem.canCollapse = false
        leftItem.minimumThickness = 115
        leftItem.maximumThickness = leftMaxWidth
        controller.addSplitViewItem(leftItem)

        let rightHost = NSHostingController(rootView: right)
        let rightItem = NSSplitViewItem(viewController: rightHost)
        rightItem.minimumThickness = 400
        controller.addSplitViewItem(rightItem)

        controller.splitView.autosaveName = autosaveName

        return controller
    }

    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        if let leftHost = controller.splitViewItems[0].viewController as? NSHostingController<Left> {
            leftHost.rootView = left
        }
        if let rightHost = controller.splitViewItems[1].viewController as? NSHostingController<Right> {
            rightHost.rootView = right
        }
    }
}

class FixedTopSplitViewController: NSSplitViewController {
    override func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        guard splitView.subviews.count == 2 else {
            super.splitView(splitView, resizeSubviewsWithOldSize: oldSize)
            return
        }
        let topView = splitView.subviews[0]
        let bottomView = splitView.subviews[1]
        let divider = splitView.dividerThickness
        let width = splitView.bounds.width
        let topHeight = topView.frame.height
        let bottomHeight = max(0, splitView.bounds.height - topHeight - divider)
        topView.frame = NSRect(x: 0, y: bottomHeight + divider, width: width, height: topHeight)
        bottomView.frame = NSRect(x: 0, y: 0, width: width, height: bottomHeight)
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

    func makeNSViewController(context: Context) -> FixedTopSplitViewController {
        let controller = FixedTopSplitViewController()
        controller.splitView.isVertical = false
        controller.splitView.dividerStyle = .thin

        let topHost = NSHostingController(rootView: top)
        let topItem = NSSplitViewItem(viewController: topHost)
        topItem.canCollapse = false
        topItem.minimumThickness = topMinHeight
        controller.addSplitViewItem(topItem)

        let bottomHost = NSHostingController(rootView: bottom)
        let bottomItem = NSSplitViewItem(viewController: bottomHost)
        bottomItem.canCollapse = false
        bottomItem.minimumThickness = bottomMinHeight
        controller.addSplitViewItem(bottomItem)

        controller.splitView.autosaveName = autosaveName

        return controller
    }

    func updateNSViewController(_ controller: FixedTopSplitViewController, context: Context) {
        if let topHost = controller.splitViewItems[0].viewController as? NSHostingController<Top> {
            topHost.rootView = top
        }
        if let bottomHost = controller.splitViewItems[1].viewController as? NSHostingController<Bottom> {
            bottomHost.rootView = bottom
        }
    }
}
