//
//  TabBarController.swift
//  Sileo
//
//  Created by CoolStar on 4/20/20.
//  Copyright © 2022 Sileo Team. All rights reserved.
//

import Foundation
import LNPopupController

class TabBarController: UITabBarController, UITabBarControllerDelegate {
    static var singleton: TabBarController?
    private var downloadsController: UINavigationController?
    private(set) public var popupIsPresented = false
    private let floatingTabBar = UIView()
    private let selectedTabBackgroundView = UIView()
    private var floatingTabItemViews = [UIView]()
    private var floatingTabIconViews = [UIImageView]()
    private var floatingTabTitleLabels = [UILabel]()
    private var floatingTabBarPressGesture: UILongPressGestureRecognizer?
    private var didSetupFloatingTabBar = false
    private var popupLock = DispatchSemaphore(value: 1)
    private var shouldSelectIndex = -1
    private var fuckedUpSources = false
//    private let ipadModeMinWidth = CGFloat(752) //debug
    private let ipadModeMinWidth = CGFloat(768)

    private var popupQueueLock = DispatchSemaphore(value: 1)
    private static let popupQueueContext = 50
    private static let popupQueueKey = DispatchSpecificKey<Int>()
    private static let popupQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "Sileo.PopupQueue", qos: .userInitiated)
        queue.setSpecific(key: popupQueueKey, value: popupQueueContext)
        return queue
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self
        TabBarController.singleton = self

        downloadsController = UINavigationController(rootViewController: DownloadManager.shared.viewController)
        downloadsController?.isNavigationBarHidden = true
        downloadsController?.popupItem.title = ""
        downloadsController?.popupItem.subtitle = ""

        weak var weakSelf = self
        NotificationCenter.default.addObserver(weakSelf as Any,
                                               selector: #selector(updateSileoColors),
                                               name: SileoThemeManager.sileoChangedThemeNotification,
                                               object: nil)
        setupFloatingTabBar()
        updateSileoColors()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.updatePopup()
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        shouldSelectIndex = tabBarController.selectedIndex
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        updateFloatingTabSelection(tabBarController.selectedIndex, animated: true)
        if shouldSelectIndex == tabBarController.selectedIndex {
            if let splitViewController = viewController as? UISplitViewController {
                if let navController = splitViewController.viewControllers[0] as? UINavigationController {
                    navController.popToRootViewController(animated: true)
                }
            }
        }
        if tabBarController.selectedIndex == 4 && shouldSelectIndex == 4 {
            if let navController = tabBarController.viewControllers?[4] as? SileoNavigationController,
               let packageList = navController.viewControllers[0] as? PackageListViewController {
                packageList.searchController.searchBar.becomeFirstResponder()
            }
        }
        if tabBarController.selectedIndex == 3 && shouldSelectIndex == 3 {
            if let navController = tabBarController.viewControllers?[3] as? SileoNavigationController,
               let packageList = navController.viewControllers[0] as? PackageListViewController,
               let collectionView = packageList.collectionView {
                let yVal = -1 * collectionView.adjustedContentInset.top
                collectionView.setContentOffset(CGPoint(x: 0, y: yVal), animated: true)
            }
        }
        if tabBarController.selectedIndex ==  2 && !fuckedUpSources {
            if let sourcesSVC = tabBarController.viewControllers?[2] as? UISplitViewController,
               let sourcesNaVC = sourcesSVC.viewControllers[0] as? SileoNavigationController {
                if sourcesNaVC.presentedViewController == nil {
                    sourcesNaVC.popToRootViewController(animated: false)
                }
            }
            fuckedUpSources = true
        }
        if viewController as? SileoNavigationController != nil { return }
        if viewController as? SourcesSplitViewController != nil { return }
        fatalError("View Controller mismatch")
    }

    func presentPopup() {
        presentPopup(completion: nil)
    }

    func presentPopup(animated:Bool = true, completion: (() -> Void)?) {
        NSLog("SileoLog: TabBarController.presentPopup \(popupIsPresented), \(downloadsController), \(completion)")

        guard let downloadsController = downloadsController, !popupIsPresented else {
            if let completion = completion {
                completion()
            }
            return
        }

        popupLock.wait()
        defer {
            popupLock.signal()
        }

        popupIsPresented = true
        self.popupContentView.popupCloseButtonAutomaticallyUnobstructsTopBars = false
        self.popupBar.toolbar.tag = WHITE_BLUR_TAG
        self.popupBar.barStyle = .prominent

        self.updateSileoColors()

        self.popupBar.toolbar.setBackgroundImage(nil, forToolbarPosition: .any, barMetrics: .default)
        self.popupBar.tabBarHeight = self.tabBar.frame.height
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.popupBar.isInlineWithTabBar = true
            self.popupBar.tabBarHeight += 1
        }
        self.popupBar.progressViewStyle = .bottom
        self.popupInteractionStyle = .drag

        TabBarController.popupQueue.async {
            self.popupQueueLock.wait()
            DispatchQueue.main.async {
                self.presentPopupBar(withContentViewController: downloadsController, animated: animated) {
                    completion?()
                    self.popupQueueLock.signal()
                }
            }
        }

        self.updateSileoColors()
    }

    func dismissPopup() {
        dismissPopup(completion: nil)
    }

    func dismissPopup(animated:Bool = true, completion: (() -> Void)?) {
        NSLog("SileoLog: TabBarController.dismissPopup \(popupIsPresented) \(completion)")

        guard popupIsPresented else {
            if let completion = completion {
                completion()
            }
            return
        }

        popupLock.wait()
        defer {
            popupLock.signal()
        }

        popupIsPresented = false

        TabBarController.popupQueue.async {
            self.popupQueueLock.wait()
            DispatchQueue.main.async {
                self.dismissPopupBar(animated: animated) {
                    completion?()
                    self.popupQueueLock.signal()
                }
            }
        }
    }

    func presentPopupController() {
        self.presentPopupController(completion: nil)
    }

    func presentPopupController(completion: (() -> Void)?) {
        NSLog("SileoLog: TabBarController.presentPopupController \(completion)")

        guard popupIsPresented else {
            if let completion = completion {
                completion()
            }
            return
        }

        popupLock.wait()
        defer {
            popupLock.signal()
        }

        self.openPopup(animated: true, completion: completion)
    }

    func dismissPopupController() {
        self.dismissPopupController(completion: nil)
    }

    func dismissPopupController(completion: (() -> Void)?) {
        NSLog("SileoLog: TabBarController.dismissPopupController \(completion)")

        guard popupIsPresented else {
            completion?()
            return
        }

        popupLock.wait()
        defer {
            popupLock.signal()
        }

        self.closePopup(animated: true, completion: completion)
    }

    func updatePopup() {
        updatePopup(completion: nil)
    }

    func updatePopup(animated:Bool = true, completion: (() -> Void)? = nil, bypass: Bool = false) {
        func hideRegardless() {
            if UIDevice.current.userInterfaceIdiom == .pad && self.view.frame.width >= ipadModeMinWidth {
                downloadsController?.popupItem.title = String(localizationKey: "Queued_Package_Status")
                downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), 0)
                self.dismissPopupController()
                self.presentPopup(animated: animated, completion: completion)
            } else {
                self.dismissPopup(animated: animated, completion: completion)
            }
        }
//we should never dismiss the popup if the queue is not empty (will cause TabBar to never display anymore)
//        if bypass {
//            hideRegardless()
//            return
//        }

        let manager = DownloadManager.shared
        NSLog("SileoLog: updatePopup(\(completion),\(bypass)) : \(self.view.frame.width) : queueRunning=\(manager.queueRunning) aptRunning=\(manager.aptRunning)  aptFinished=\(manager.aptFinished) operationCount=\(manager.operationCount()) downloading=\(manager.downloadingPackages()) ready=\(manager.readyPackages()) installing=\(manager.installingPackages()) uninstalling=\(manager.uninstallingPackages()) verifyComplete=\(manager.verifyComplete())")
//        Thread.callStackSymbols.forEach{NSLog("SileoLog: updatePopup callstack=\($0)")}

        if manager.operationCount() == 0 {
            assert(manager.queueRunning == false)

            //requires async due the deadlock: dismissPopupController->(LNPopupController)->viewDidLayoutSubviews->updatePopup->dismissPopup on iphone mode on ipad
            DispatchQueue.main.async {
                hideRegardless()
            }
        }
        else if !manager.queueRunning {
            downloadsController?.popupItem.title = String(localizationKey: "Queued_Package_Status")
            downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), manager.operationCount())
            downloadsController?.popupItem.progress = 0
            self.presentPopup(completion: completion)
        }
        else if manager.aptFinished {
            downloadsController?.popupItem.title = String(localizationKey: "Done")
            downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), manager.operationCount())
            downloadsController?.popupItem.progress = 0
            self.presentPopup(completion: completion)
        }
        else if manager.aptRunning {
            if manager.installingPackages() > 0 {
                downloadsController?.popupItem.title = String(localizationKey: "Installing_Package_Status")
                downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), manager.installingPackages())
                downloadsController?.popupItem.progress = 0
                self.presentPopup(completion: completion)
            } else if manager.uninstallingPackages() > 0 {
                downloadsController?.popupItem.title = String(localizationKey: "Removal_Queued_Package_Status")
                downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), manager.uninstallingPackages())
                downloadsController?.popupItem.progress = 0
                self.presentPopup(completion: completion)
            }
        }
        else {
            if manager.downloadingPackages() > 0 {
                downloadsController?.popupItem.title = String(localizationKey: "Downloading_Package_Status")
                downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), manager.downloadingPackages())
                downloadsController?.popupItem.progress = 0
                self.presentPopup(completion: completion)
            } else if manager.verifyComplete() {
                downloadsController?.popupItem.title = String(localizationKey: "Ready_Status")
                downloadsController?.popupItem.subtitle = String(format: String(localizationKey: "Package_Queue_Count"), manager.operationCount())
                downloadsController?.popupItem.progress = 0
                self.presentPopup(completion: completion)
            }
        }
    }

    override var bottomDockingViewForPopupBar: UIView? {
        self.tabBar
    }

    override var defaultFrameForBottomDockingView: CGRect {
        NSLog("SileoLog: TabBarController.defaultFrameForBottomDockingView")
        var tabBarFrame = self.tabBar.frame
        tabBarFrame.origin.y = self.view.bounds.height - tabBarFrame.height
        if UIDevice.current.userInterfaceIdiom == .pad {
            tabBarFrame.origin.x = 0
            tabBarFrame.size.width = self.view.bounds.width
            if tabBarFrame.width >= ipadModeMinWidth {
                tabBarFrame.size.width -= 320
            }
        }
        return tabBarFrame
    }

    override var insetsForBottomDockingView: UIEdgeInsets {
        if UIDevice.current.userInterfaceIdiom == .pad {
            if self.view.bounds.width < ipadModeMinWidth {
                return .zero
            }
            return UIEdgeInsets(top: self.tabBar.frame.height, left: self.view.bounds.width - 320, bottom: 0, right: 0)
        }
        return .zero
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        updateSileoColors()
    }

    @objc func updateSileoColors() {
        if UIColor.isDarkModeEnabled {
            self.popupBar.systemBarStyle = .black
            self.popupBar.toolbar.barStyle = .black
        } else {
            self.popupBar.systemBarStyle = .default
            self.popupBar.toolbar.barStyle = .default
        }
        updateFloatingTabColors()
    }

    private func setupFloatingTabBar() {
        guard !didSetupFloatingTabBar else { return }
        didSetupFloatingTabBar = true

        tabBar.alpha = 0.01
        tabBar.isUserInteractionEnabled = false

        floatingTabBar.backgroundColor = UIColor.sileoContentBackgroundColor
        floatingTabBar.layer.masksToBounds = false
        floatingTabBar.layer.shadowColor = UIColor.black.cgColor
        floatingTabBar.layer.shadowOpacity = UIColor.isDarkModeEnabled ? 0.42 : 0.18
        floatingTabBar.layer.shadowOffset = CGSize(width: 0, height: 8)
        floatingTabBar.layer.shadowRadius = 18
        view.addSubview(floatingTabBar)

        selectedTabBackgroundView.backgroundColor = UIColor.tintColor.withAlphaComponent(0.20)
        selectedTabBackgroundView.layer.masksToBounds = true
        floatingTabBar.addSubview(selectedTabBackgroundView)

        let controllers = viewControllers ?? []
        for (index, controller) in controllers.enumerated() {
            let itemView = UIView()
            itemView.tag = index
            itemView.backgroundColor = .clear
            itemView.isUserInteractionEnabled = false

            let iconView = UIImageView()
            iconView.contentMode = .scaleAspectFit
            iconView.tintColor = .gray
            iconView.image = tabImage(for: controller.tabBarItem, index: index)?.withRenderingMode(.alwaysTemplate)

            let titleLabel = UILabel()
            titleLabel.text = tabTitle(for: controller.tabBarItem, index: index)
            titleLabel.textAlignment = .center
            titleLabel.font = UIFont.systemFont(ofSize: 11, weight: .medium)
            titleLabel.textColor = .gray

            itemView.addSubview(iconView)
            itemView.addSubview(titleLabel)
            floatingTabBar.addSubview(itemView)

            floatingTabItemViews.append(itemView)
            floatingTabIconViews.append(iconView)
            floatingTabTitleLabels.append(titleLabel)
        }

        let pressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleFloatingTabBarPress(_:)))
        pressGesture.minimumPressDuration = 0
        pressGesture.allowableMovement = .greatestFiniteMagnitude
        floatingTabBar.addGestureRecognizer(pressGesture)
        floatingTabBarPressGesture = pressGesture
        updateFloatingTabSelection(selectedIndex, animated: false)
    }

    private func tabTitle(for item: UITabBarItem, index: Int) -> String {
        if let title = item.title, !title.isEmpty {
            return title
        }
        let fallbackTitles = [
            String(localizationKey: "Featured_Page"),
            String(localizationKey: "News_Page"),
            String(localizationKey: "Sources_Page"),
            String(localizationKey: "Packages_Page"),
            String(localizationKey: "Search_Page")
        ]
        return index < fallbackTitles.count ? fallbackTitles[index] : ""
    }

    private func tabImage(for item: UITabBarItem, index: Int) -> UIImage? {
        if let selectedImage = item.selectedImage {
            return selectedImage
        }
        if let image = item.image {
            return image
        }
        guard #available(iOS 13.0, *) else { return nil }
        let fallbackSymbols = ["star.fill", "newspaper.fill", "tray.full.fill", "shippingbox.fill", "magnifyingglass"]
        return index < fallbackSymbols.count ? UIImage(systemName: fallbackSymbols[index]) : nil
    }

    private func layoutFloatingTabBar() {
        guard didSetupFloatingTabBar, !floatingTabItemViews.isEmpty else { return }

        tabBar.alpha = 0.01
        tabBar.isUserInteractionEnabled = false
        view.bringSubviewToFront(floatingTabBar)

        let screenWidth = view.bounds.width
        let screenHeight = view.bounds.height
        let safeBottom = view.safeAreaInsets.bottom
        let tabBarHeight: CGFloat = 66
        let horizontalInset: CGFloat = 34
        let bottomMargin: CGFloat = 4
        let tabBarWidth = max(0, screenWidth - horizontalInset * 2)
        let tabBarY = screenHeight - safeBottom - tabBarHeight - bottomMargin

        floatingTabBar.frame = CGRect(x: horizontalInset, y: tabBarY, width: tabBarWidth, height: tabBarHeight)
        floatingTabBar.layer.cornerRadius = tabBarHeight / 2

        let itemWidth = tabBarWidth / CGFloat(floatingTabItemViews.count)
        for index in floatingTabItemViews.indices {
            let itemView = floatingTabItemViews[index]
            itemView.frame = CGRect(x: CGFloat(index) * itemWidth, y: 0, width: itemWidth, height: tabBarHeight)
            floatingTabIconViews[index].frame = CGRect(x: (itemWidth - 23) / 2, y: 11, width: 23, height: 23)
            floatingTabTitleLabels[index].frame = CGRect(x: 0, y: 38, width: itemWidth, height: 18)
            floatingTabTitleLabels[index].text = tabTitle(for: viewControllers?[index].tabBarItem ?? UITabBarItem(), index: index)
        }

        layoutSelectedTabBackground(for: selectedIndex, animated: false, restoreScale: true)
    }

    @objc private func handleFloatingTabBarPress(_ gesture: UILongPressGestureRecognizer) {
        guard floatingTabBar.bounds.width > 0, !floatingTabItemViews.isEmpty else { return }

        let location = gesture.location(in: floatingTabBar)
        let tabBarWidth = floatingTabBar.bounds.width
        let tabBarHeight = floatingTabBar.bounds.height
        let itemWidth = tabBarWidth / CGFloat(floatingTabItemViews.count)
        let backgroundWidth = itemWidth - 10
        let scaledBackgroundWidth = backgroundWidth * 1.18
        let minCenterX = scaledBackgroundWidth / 2 + 5
        let maxCenterX = tabBarWidth - scaledBackgroundWidth / 2 - 5
        let followX = min(max(location.x, minCenterX), maxCenterX)
        let hoverIndex = indexForFloatingTabLocation(location.x)

        switch gesture.state {
        case .began:
            updateFloatingTabColors(selectedIndex: hoverIndex)
            UIView.animate(withDuration: 0.22, delay: 0, usingSpringWithDamping: 0.58, initialSpringVelocity: 0.75, options: .curveEaseOut) {
                self.selectedTabBackgroundView.center = CGPoint(x: followX, y: tabBarHeight / 2)
                self.selectedTabBackgroundView.transform = CGAffineTransform(scaleX: 1.18, y: 1.12)
            }
        case .changed:
            updateFloatingTabColors(selectedIndex: hoverIndex)
            UIView.animate(withDuration: 0.07, delay: 0, options: .curveLinear) {
                self.selectedTabBackgroundView.center = CGPoint(x: followX, y: tabBarHeight / 2)
            }
        case .ended, .cancelled, .failed:
            selectFloatingTab(at: indexForFloatingTabLocation(location.x))
        default:
            break
        }
    }

    private func indexForFloatingTabLocation(_ x: CGFloat) -> Int {
        guard !floatingTabItemViews.isEmpty else { return 0 }
        let itemWidth = floatingTabBar.bounds.width / CGFloat(floatingTabItemViews.count)
        let index = Int(floor(x / itemWidth))
        return min(max(index, 0), floatingTabItemViews.count - 1)
    }

    private func selectFloatingTab(at index: Int) {
        guard let controllers = viewControllers, index >= 0, index < controllers.count else { return }
        let viewController = controllers[index]
        let previousIndex = selectedIndex
        shouldSelectIndex = previousIndex
        if previousIndex != index {
            if tabBarController(self, shouldSelect: viewController) {
                selectedIndex = index
                tabBarController(self, didSelect: viewController)
            }
        } else {
            tabBarController(self, didSelect: viewController)
        }
        updateFloatingTabSelection(selectedIndex, animated: true)
    }

    private func updateFloatingTabSelection(_ selectedIndex: Int, animated: Bool) {
        layoutSelectedTabBackground(for: selectedIndex, animated: animated, restoreScale: true)
        updateFloatingTabColors(selectedIndex: selectedIndex)
    }

    private func updateFloatingTabColors(selectedIndex: Int? = nil) {
        guard didSetupFloatingTabBar else { return }
        let selected = selectedIndex ?? self.selectedIndex
        floatingTabBar.backgroundColor = UIColor.sileoContentBackgroundColor
        floatingTabBar.layer.shadowOpacity = UIColor.isDarkModeEnabled ? 0.42 : 0.18
        selectedTabBackgroundView.backgroundColor = UIColor.tintColor.withAlphaComponent(0.20)

        for index in floatingTabIconViews.indices {
            let color: UIColor = index == selected ? UIColor.tintColor : .gray
            floatingTabIconViews[index].tintColor = color
            floatingTabTitleLabels[index].textColor = color
        }
    }

    private func layoutSelectedTabBackground(for index: Int, animated: Bool, restoreScale: Bool) {
        guard didSetupFloatingTabBar, floatingTabBar.bounds.width > 0, !floatingTabItemViews.isEmpty else { return }

        let tabBarWidth = floatingTabBar.bounds.width
        let tabBarHeight = floatingTabBar.bounds.height
        let itemWidth = tabBarWidth / CGFloat(floatingTabItemViews.count)
        let backgroundWidth = itemWidth - 10
        let backgroundHeight = tabBarHeight - 14
        var centerX = CGFloat(index) * itemWidth + itemWidth / 2
        let centerY = tabBarHeight / 2
        let minCenterX = backgroundWidth / 2 + 5
        let maxCenterX = tabBarWidth - backgroundWidth / 2 - 5
        centerX = min(max(centerX, minCenterX), maxCenterX)

        let bounds = CGRect(x: 0, y: 0, width: backgroundWidth, height: backgroundHeight)
        selectedTabBackgroundView.layer.cornerRadius = backgroundHeight / 2

        let changes = {
            self.selectedTabBackgroundView.bounds = bounds
            self.selectedTabBackgroundView.center = CGPoint(x: centerX, y: centerY)
            if restoreScale {
                self.selectedTabBackgroundView.transform = .identity
            }
        }

        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut, animations: changes)
        } else {
            changes()
        }
    }

    override func viewDidLayoutSubviews() {
        NSLog("SileoLog: TabBarController.viewDidLayoutSubviews")
        super.viewDidLayoutSubviews()

        self.tabBar.itemPositioning = .centered
        layoutFloatingTabBar()
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.updatePopup(animated: false)
        }
    }

    public func displayError(_ string: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.displayError(string)
            }
            return
        }
        let alertController = UIAlertController(title: String(localizationKey: "Unknown", type: .error), message: string, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: String(localizationKey: "OK"), style: .default))
        self.present(alertController, animated: true, completion: nil)
    }
}
