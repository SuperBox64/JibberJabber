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

class ProportionalSplitDelegate: NSObject, NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        let dividerThickness = splitView.dividerThickness
        let newHeight = splitView.bounds.height
        let oldHeight = oldSize.height

        guard oldHeight > 0, splitView.subviews.count == 2 else {
            splitView.adjustSubviews()
            return
        }

        let topView = splitView.subviews[0]
        let bottomView = splitView.subviews[1]
        let oldTopHeight = topView.frame.height
        let usableOld = oldHeight - dividerThickness
        let usableNew = newHeight - dividerThickness

        guard usableOld > 0 else {
            splitView.adjustSubviews()
            return
        }

        let ratio = oldTopHeight / usableOld
        let newTopHeight = round(ratio * usableNew)
        let newBottomHeight = usableNew - newTopHeight
        let width = splitView.bounds.width

        topView.frame = NSRect(x: 0, y: newBottomHeight + dividerThickness, width: width, height: newTopHeight)
        bottomView.frame = NSRect(x: 0, y: 0, width: width, height: newBottomHeight)
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

    func makeCoordinator() -> ProportionalSplitDelegate {
        ProportionalSplitDelegate()
    }

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = NSSplitViewController()
        controller.splitView.isVertical = false
        controller.splitView.dividerStyle = .thin
        controller.splitView.delegate = context.coordinator

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

    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        if let topHost = controller.splitViewItems[0].viewController as? NSHostingController<Top> {
            topHost.rootView = top
        }
        if let bottomHost = controller.splitViewItems[1].viewController as? NSHostingController<Bottom> {
            bottomHost.rootView = bottom
        }
    }
}
