//
//  DuoLayoutManager.swift
//  DuoLayoutKit
//
//  统一管理 App 当前的屏幕形态、缩放基准、安全区、侧边栏位置和底部横排 Tab 栏高度。
//  SwiftUI 页面直接读取本单例的 @Observable 属性自动重画；UIKit 页面监听 `Notification.Name.duoLayoutDidChange` 通知重排。
//  不给整个类加 @MainActor：缩放方法可能在非主线程的同步代码里被调用，只保证所有写入与 UIKit 控制器操作在主线程执行。
//

import UIKit
import Observation
import DeviceKit

@Observable
public final class DuoLayoutManager {
    public static let shared = DuoLayoutManager()
    private init() {}
    //MARK: - 存储属性
    /// 记录当前生效的设计稿基准配置，默认使用竖屏 390、内屏竖拿 669、内屏横拿 951
    public private(set) var config: DuoLayoutConfig = DuoLayoutConfig()
    /// 记录当前用来缩放的屏幕基准宽度；根控制器第一次刷新之前，先用整块主屏幕的宽度
    public private(set) var baseWidth: CGFloat = UIScreen.main.bounds.size.width
    /// 记录当前使用的设计稿基准宽度，随当前形态与配置同步切换
    public private(set) var designWidth: CGFloat = 390
    /// 记录 App 当前所处的屏幕形态；根控制器第一次刷新之前，先按普通 iPhone、整块主屏幕记
    public private(set) var form: DuoDisplayForm = .phone(UIScreen.main.bounds.size)
    /// 记录窗口最新的安全区域（上、下、左、右），供需要随开合或旋转自动刷新的界面直接读取
    public private(set) var safeAreaInsets: UIEdgeInsets = .zero
    /// 记录当前活跃页面内容真正要避开的区域（已合入侧边栏与底部横排 Tab 栏占用，并清掉横转竖残留的侧边栏宽度）
    public private(set) var contentInsets: UIEdgeInsets = .zero
    /// 记录系统 Tab 栏横排在屏幕底部时从 Tab 栏顶边到窗口底边实际占用的总高度（含底部安全区）；侧边竖排、隐藏或无 Tab 栏时为 0
    public private(set) var bottomTabBarOccupiedHeight: CGFloat = 0
    /// 记录当前设备是不是 iPhone Duo，外界只能读；模拟器上按它模拟的机型判断
    public let isDuo: Bool = Device.current.realDevice == .iPhoneDuo
    /// 弱引用窗口根控制器，用于读取窗口尺寸、窗口级安全区和注册系统侧边栏位置变化监听，不参与界面刷新
    @ObservationIgnored private weak var rootViewController: UIViewController?
    /// 弱引用当前已注册侧边栏位置监听的系统 Tab 栏控制器，控制器替换时用于解绑旧监听，不参与界面刷新
    @ObservationIgnored private weak var observedTabBarController: UITabBarController?
    /// 保存根控制器上注册的竖排侧边栏特征变化监听句柄，切换根控制器时用于注销旧监听，不参与界面刷新
    @ObservationIgnored private var rootTraitRegistration: (any UITraitChangeRegistration)?
    /// 保存系统 Tab 栏控制器上注册的竖排侧边栏特征变化监听句柄，Tab 容器替换时用于注销旧监听，不参与界面刷新
    @ObservationIgnored private var tabBarTraitRegistration: (any UITraitChangeRegistration)?
    /// 挂在当前活跃页面最底层的透明监听视图，用于第一时间捕获子页面安全区延迟更新与侧边栏位置变化，不参与界面刷新
    @ObservationIgnored private var safeAreaObserverView: DuoSafeAreaObserverView?
    /// 标记是否已经安排了下一轮主线程的刷新，避免同一轮布局里重复计算，不参与界面刷新
    @ObservationIgnored private var isRefreshScheduled = false
    /// 标记本次刷新排队期间是否又收到新的布局事件，跑完本轮后再补算一次，避免分屏换边或横转竖停在过渡值上，不参与界面刷新
    @ObservationIgnored private var needsAnotherRefresh = false
}

//MARK: - 计算属性
public extension DuoLayoutManager {
    /// 计算当前尺寸缩放比例（屏幕基准宽度除以设计稿基准宽度），供业务工程的 `.adapt`、`.adjust`、`fixSize` 和字体方法统一换算
    var sizeScale: CGFloat {
        guard designWidth > 0 else { return 1 }
        return baseWidth / designWidth
    }
    /// 取出当前安全区以内真正能放内容的区域尺寸；内部读取 `form`，形态变化时 SwiftUI 视图会自动刷新
    var usableSize: CGSize {
        form.safeSize
    }
    /// 计算当前 iPhone Duo 侧边竖排栏所在的一侧与宽度；普通 iPhone、内屏竖拿或当前页面没有侧边栏时返回 nil。
    /// 内部读取 `form`，形态变化时 SwiftUI 视图会自动刷新
    var sideColumn: DuoSideColumn? {
        let safeWidth: CGFloat
        // 内屏左半边分屏时侧边栏只算在页面安全区里；其他形态侧边栏算在窗口安全区里
        let isOnPageLeft: Bool
        switch form {
        case .outer(let size), .innerLandscape(let size), .innerSplitRight(let size):
            safeWidth = size.width
            isOnPageLeft = false
        case .innerSplitLeft(let size):
            safeWidth = size.width
            isOnPageLeft = true
        case .phone, .innerPortrait:
            return nil
        }
        guard let window = currentWindow else { return nil }
        let width = window.bounds.width - safeWidth
        guard width > 0 else { return nil }
        let isLeft = isOnPageLeft || window.safeAreaInsets.left > window.safeAreaInsets.right
        return isLeft ? .left(width) : .right(width)
    }
    /// 计算扣掉侧边竖排栏后，内容区中心相对整窗中心的水平偏移量，供顶部横幅、全屏加载框、弹窗等一键居中
    var contentCenterOffsetX: CGFloat {
        Self.computeContentCenterOffsetX(for: sideColumn)
    }
    /// 计算窗口扣掉侧边竖排栏后的水平起始坐标与可用宽度，供 Toast、悬浮按钮吸边等直接定位
    var availableHorizontalRegion: (startX: CGFloat, width: CGFloat) {
        let windowWidth = currentWindow?.bounds.width ?? UIScreen.main.bounds.size.width
        return Self.computeAvailableHorizontalRegion(windowWidth: windowWidth, sideColumn: sideColumn)
    }
}

//MARK: - 内部计算属性
private extension DuoLayoutManager {
    /// 取出当前正在显示本 App 的窗口，优先读已绑定根控制器所在的窗口
    var currentWindow: UIWindow? {
        if let rootWindow = rootViewController?.viewIfLoaded?.window {
            return rootWindow
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
        }
        return scenes.first?.windows.first
    }
    /// 从根控制器子树里自动查找当前有效的导航控制器，供读取顶层页面安全区与导航栏显隐状态
    var resolvedNavigationController: UINavigationController? {
        guard let rootViewController else { return nil }
        return findController(ofType: UINavigationController.self, in: rootViewController)
    }
    /// 取出当前位于界面顶层的系统 Tab 栏控制器；推进二级页后顶层不再是 Tab 页时返回 nil
    var activeTabBarController: UITabBarController? {
        if let topController = resolvedNavigationController?.topViewController {
            return findController(ofType: UITabBarController.self, in: topController)
        }
        guard let rootViewController else { return nil }
        return findController(ofType: UITabBarController.self, in: rootViewController)
    }
    /// 取出当前最内层的活跃页面视图（在一级 Tab 页时取当前选中子页，在二级页时取栈顶页），只取已加载且在窗口里的视图
    var activePageView: UIView? {
        if let selectedView = activeTabBarController?.selectedViewController?.viewIfLoaded,
           selectedView.window != nil {
            return selectedView
        }
        if let topView = resolvedNavigationController?.topViewController?.viewIfLoaded,
           topView.window != nil {
            return topView
        }
        return nil
    }
    /// 判断当前分屏页面是否已经排版完成且既无可见 Tab 栏也无可见系统导航栏（这种页面在左分屏不会产生左侧栏安全区）
    var isCurrentSplitPageWithoutSideBar: Bool {
        guard let activePageView, activePageView.bounds.width > 0 else { return false }
        let hasVisibleTabBar = activeTabBarController?.tabBar.isHidden == false
        let hasVisibleNavBar = resolvedNavigationController?.isNavigationBarHidden == false
        return hasVisibleTabBar == false && hasVisibleNavBar == false
    }
    /// 判断 iOS 27.1+ 系统偏好是否把竖排侧边栏放在右侧，在读不到侧边栏宽度时用来区分左右分屏
    var isSystemVerticalBarOnTrailing: Bool {
        if #available(iOS 27.1, *) {
            let traitCollection = activeTabBarController?.traitCollection
                ?? resolvedNavigationController?.traitCollection
                ?? rootViewController?.traitCollection
            return traitCollection?.verticalBarEdge == .trailing
        }
        return false
    }
}

//MARK: - 对外方法
public extension DuoLayoutManager {
    /// 注入项目专属的设计稿基准宽度配置；建议在 App 启动创建窗口之前调用一次
    func setup(config: DuoLayoutConfig) {
        self.config = config
        let windowWidth = currentWindow?.bounds.width ?? UIScreen.main.bounds.size.width
        baseWidth = Self.computeBaseWidth(
            for: form,
            windowWidth: windowWidth,
            mainScreenWidth: UIScreen.main.bounds.size.width,
            config: config
        )
        designWidth = Self.computeDesignWidth(for: form, config: config)
        scheduleRefresh()
    }

    /// 按当前屏幕形态的缩放比例换算设计稿尺寸，供宿主工程桥接自己的 `.adapt`、`.adjust` 或 `fixSize`
    func scaled(_ value: CGFloat, rounded: Bool = false) -> CGFloat {
        let result = value * sizeScale
        return rounded ? result.rounded() : result
    }

    /// 绑定窗口根控制器，在其上注册系统竖排侧边栏位置变化监听，并安排一次形态刷新
    @MainActor
    func bindRootViewController(_ viewController: UIViewController) {
        guard rootViewController !== viewController else { return }
        if let previousRoot = rootViewController, let registration = rootTraitRegistration {
            previousRoot.unregisterForTraitChanges(registration)
        }
        rootTraitRegistration = nil
        rootViewController = viewController
        if #available(iOS 27.1, *) {
            rootTraitRegistration = viewController.registerForTraitChanges(
                UITraitCollection.systemTraitsAffectingVerticalBarEdge
            ) { (_: UIViewController, _) in
                self.scheduleRefreshWithFollowUp()
            }
        }
        scheduleRefresh()
    }

    /// 在窗口尺寸转场结束、安全区变化或布局变化时调用本方法。
    /// 本方法把同一轮布局里的多次触发合并到下一轮主线程里统一算一次；如果排队期间又来了新的布局，跑完本轮后再补算一次
    func scheduleRefresh() {
        if isRefreshScheduled {
            needsAnotherRefresh = true
            return
        }
        isRefreshScheduled = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.isRefreshScheduled = false
                let runAgain = self.needsAnotherRefresh
                self.needsAnotherRefresh = false
                self.refresh()
                if runAgain {
                    self.scheduleRefresh()
                }
            }
        }
    }
}

//MARK: - 内部纯计算方法
extension DuoLayoutManager {
    /// 按形态与配置计算用来缩放的屏幕基准宽度
    static func computeBaseWidth(
        for form: DuoDisplayForm,
        windowWidth: CGFloat,
        mainScreenWidth: CGFloat,
        config: DuoLayoutConfig
    ) -> CGFloat {
        switch form {
        case .phone:
            return mainScreenWidth
        case .outer(let size), .innerSplitLeft(let size), .innerSplitRight(let size):
            return size.width
        case .innerPortrait:
            return config.innerPortraitBaseWidth ?? windowWidth
        case .innerLandscape:
            return windowWidth
        }
    }

    /// 按形态与配置计算对应的设计稿基准宽度
    static func computeDesignWidth(for form: DuoDisplayForm, config: DuoLayoutConfig) -> CGFloat {
        switch form {
        case .innerPortrait:
            return config.innerPortraitDesignWidth
        case .innerLandscape:
            return config.innerLandscapeDesignWidth
        case .phone, .outer, .innerSplitLeft, .innerSplitRight:
            return config.portraitDesignWidth
        }
    }

    /// 按侧边栏位置计算内容区中心相对整窗中心的水平偏移量
    static func computeContentCenterOffsetX(for sideColumn: DuoSideColumn?) -> CGFloat {
        switch sideColumn {
        case .left(let width):
            return width / 2
        case .right(let width):
            return -width / 2
        case nil:
            return 0
        }
    }

    /// 按窗口宽度和侧边栏位置计算内容区的水平起始坐标与可用宽度
    static func computeAvailableHorizontalRegion(
        windowWidth: CGFloat,
        sideColumn: DuoSideColumn?
    ) -> (startX: CGFloat, width: CGFloat) {
        switch sideColumn {
        case .left(let width):
            return (width, max(windowWidth - width, 0))
        case .right(let width):
            return (0, max(windowWidth - width, 0))
        case nil:
            return (0, max(windowWidth, 0))
        }
    }
}

//MARK: - 内部刷新方法
private extension DuoLayoutManager {
    /// 安排本次刷新并在跑完后再多补一轮主线程检查，用于吃掉系统把 Tab 栏在侧边和底部之间搬家时的延迟更新
    func scheduleRefreshWithFollowUp() {
        if isRefreshScheduled {
            needsAnotherRefresh = true
            return
        }
        needsAnotherRefresh = true
        scheduleRefresh()
    }

    /// 同步内部监听对象：把侧边栏位置监听挂到当前系统 Tab 栏控制器上，并把透明安全区监听视图贴到当前活跃页面最底层
    @MainActor
    func syncInternalObservers() {
        let currentTabController = activeTabBarController
        if observedTabBarController !== currentTabController {
            if let previousTab = observedTabBarController, let registration = tabBarTraitRegistration {
                previousTab.unregisterForTraitChanges(registration)
            }
            tabBarTraitRegistration = nil
            observedTabBarController = currentTabController
            if let currentTabController, #available(iOS 27.1, *) {
                tabBarTraitRegistration = currentTabController.registerForTraitChanges(
                    UITraitCollection.systemTraitsAffectingVerticalBarEdge
                ) { (_: UITabBarController, _) in
                    self.scheduleRefreshWithFollowUp()
                }
            }
        }
        guard let targetView = activePageView else { return }
        let observer = makeSafeAreaObserverViewIfNeeded()
        guard observer.superview !== targetView else { return }
        observer.frame = targetView.bounds
        targetView.insertSubview(observer, at: 0)
    }

    /// 创建并返回内部复用的透明安全区监听视图，已创建则直接返回原实例
    @MainActor
    func makeSafeAreaObserverViewIfNeeded() -> DuoSafeAreaObserverView {
        if let safeAreaObserverView {
            return safeAreaObserverView
        }
        let observer = DuoSafeAreaObserverView()
        observer.onSafeAreaDidChange = {
            self.scheduleRefresh()
        }
        observer.onVerticalBarEdgeDidChange = {
            self.scheduleRefreshWithFollowUp()
        }
        safeAreaObserverView = observer
        return observer
    }

    /// 重新计算当前屏幕形态、安全区与底部 Tab 栏高度；有实际变化时更新对外状态并在 Duo 上发出 UIKit 通知
    @MainActor
    func refresh() {
        syncInternalObservers()
        guard let window = currentWindow, window.bounds.width > 0 else { return }
        guard let newForm = calculateForm(in: window) else { return }
        let newWindowInsets = window.safeAreaInsets
        let newBottomTabBarHeight = measureBottomHorizontalTabBarHeight(in: window)
        let newContentInsets = calculateContentInsets(
            in: window,
            form: newForm,
            bottomTabBarHeight: newBottomTabBarHeight
        )
        let isFormChanged = newForm != form
        let isWindowInsetsChanged = newWindowInsets != safeAreaInsets
        let isContentInsetsChanged = newContentInsets != contentInsets
        let isBottomTabBarHeightChanged = abs(newBottomTabBarHeight - bottomTabBarOccupiedHeight) > 0.5
        guard isFormChanged || isWindowInsetsChanged || isContentInsetsChanged || isBottomTabBarHeightChanged else {
            return
        }
        if isFormChanged {
            form = newForm
            baseWidth = Self.computeBaseWidth(
                for: newForm,
                windowWidth: window.bounds.width,
                mainScreenWidth: UIScreen.main.bounds.size.width,
                config: config
            )
            designWidth = Self.computeDesignWidth(for: newForm, config: config)
        }
        if isWindowInsetsChanged {
            safeAreaInsets = newWindowInsets
        }
        if isContentInsetsChanged {
            contentInsets = newContentInsets
        }
        if isBottomTabBarHeightChanged {
            bottomTabBarOccupiedHeight = newBottomTabBarHeight
        }
        guard isDuo else { return }
        #if DEBUG
        if config.isDebugLoggingEnabled {
            let formatInsets: (UIEdgeInsets) -> String = { "上 \($0.top) 下 \($0.bottom) 左 \($0.left) 右 \($0.right)" }
            print(
                "[DuoLayout] 形态=\(newForm) 基准宽=\(baseWidth) 设计稿宽=\(designWidth) 缩放=\(sizeScale) 窗口=\(window.bounds.size) 窗口安全区=(\(formatInsets(newWindowInsets))) 内容安全区=(\(formatInsets(newContentInsets))) 底部Tab高=\(newBottomTabBarHeight)"
            )
        }
        #endif
        if isFormChanged {
            NotificationCenter.default.post(
                name: .duoLayoutDidChange,
                object: self,
                userInfo: [DuoLayoutNotificationKey.form: newForm]
            )
        }
    }

    /// 按窗口所在的屏幕、窗口尺寸和安全区，算出 App 当前所处的屏幕形态。
    /// 分屏期间页面安全区还没稳定（或换边瞬间左右同时出现侧边栏）时返回 nil，等下一次布局再算
    func calculateForm(in window: UIWindow) -> DuoDisplayForm? {
        let windowInsets = window.safeAreaInsets
        let height = max(window.bounds.height - windowInsets.top - windowInsets.bottom, 0)
        let sizeByWindow = CGSize(
            width: max(window.bounds.width - windowInsets.left - windowInsets.right, 0),
            height: height
        )
        guard isDuo else { return .phone(sizeByWindow) }
        // iPhone Duo 上 UIScreen.main 固定是外屏；窗口所在的屏幕和它一样大，说明 App 正显示在外屏上
        guard let screen = window.windowScene?.screen, screen.bounds.size != UIScreen.main.bounds.size else {
            return .outer(sizeByWindow)
        }
        // 窗口和内屏一样宽，说明 App 占满了内屏，没有分屏
        guard window.bounds.width < screen.bounds.width else {
            return window.bounds.width > window.bounds.height ? .innerLandscape(sizeByWindow) : .innerPortrait(sizeByWindow)
        }
        // 内屏上窗口比屏幕窄，说明在和别的 App 左右分屏：
        // 右分屏时右侧 84pt 状态栏算在窗口安全区里；左分屏时左侧 84pt Tab 栏/导航栏只算在导航栈内部页面上。
        // 藏掉导航栏且没有 Tab 栏的二级页在左分屏时页面安全区左边可能是 0，需要结合系统竖排栏方向落成无侧栏左分屏，避免卡在旧形态上
        let pageInsets: UIEdgeInsets
        if let resolvedPageInsets = resolveSplitPageSafeAreaInsets() {
            pageInsets = resolvedPageInsets
        } else if windowInsets.right > 1 {
            pageInsets = windowInsets
        } else if isCurrentSplitPageWithoutSideBar {
            return isSystemVerticalBarOnTrailing ? .innerSplitRight(sizeByWindow) : .innerSplitLeft(sizeByWindow)
        } else {
            return nil
        }
        let leftColumn = max(windowInsets.left, pageInsets.left)
        let rightColumn = max(windowInsets.right, pageInsets.right)
        // 换边瞬间左右可能同时读到侧边栏宽度，这时分不清在哪一边，先跳过等下一次布局
        if leftColumn > 1, rightColumn > 1 { return nil }
        let splitSize = CGSize(width: max(window.bounds.width - max(leftColumn, rightColumn), 0), height: height)
        if rightColumn > leftColumn {
            return .innerSplitRight(splitSize)
        }
        if leftColumn > rightColumn {
            return .innerSplitLeft(splitSize)
        }
        return isSystemVerticalBarOnTrailing ? .innerSplitRight(splitSize) : .innerSplitLeft(splitSize)
    }

    /// 读取导航栈顶层页面（含其内部 TabView 对应的 UITabBarController）的安全区，供左右分屏判断左侧栏宽度
    func resolveSplitPageSafeAreaInsets() -> UIEdgeInsets? {
        guard let topController = resolvedNavigationController?.topViewController,
              let topView = topController.viewIfLoaded,
              topView.window != nil else {
            return nil
        }
        var resolved = topView.safeAreaInsets
        // SwiftUI 的 TabView 底层是 UITabBarController，左分屏时左侧栏安全区可能挂在当前选中的 Tab 子页面上，这里合并取最大值
        if let tabController = findController(ofType: UITabBarController.self, in: topController),
           let selectedView = tabController.selectedViewController?.viewIfLoaded,
           selectedView.window != nil {
            let tabInsets = selectedView.safeAreaInsets
            resolved = UIEdgeInsets(
                top: max(resolved.top, tabInsets.top),
                left: max(resolved.left, tabInsets.left),
                bottom: max(resolved.bottom, tabInsets.bottom),
                right: max(resolved.right, tabInsets.right)
            )
        }
        guard resolved != .zero else { return nil }
        return resolved
    }

    /// 量出系统 Tab 栏横排在屏幕底部时实际占用的总高度（从 Tab 栏顶边到窗口底边）；Tab 栏竖排在侧边、隐藏或当前页无 Tab 栏时返回 0
    func measureBottomHorizontalTabBarHeight(in window: UIWindow) -> CGFloat {
        guard let tabController = activeTabBarController else { return 0 }
        let tabBar = tabController.tabBar
        guard tabBar.isHidden == false, tabBar.window != nil, window.bounds.height > 0 else { return 0 }
        let tabBarRect = tabBar.convert(tabBar.bounds, to: window)
        // 横排在底部的 Tab 栏一定是宽大于高且位于窗口下半部分，排除竖排在左右两侧时的位置
        guard tabBarRect.width > tabBarRect.height, tabBarRect.minY > window.bounds.height * 0.5 else { return 0 }
        let occupied = window.bounds.height - tabBarRect.minY
        guard occupied > 0, occupied < window.bounds.height * 0.3 else { return 0 }
        return occupied
    }

    /// 计算当前活跃页面内容真正要避开的区域。
    /// 无侧边栏形态下清掉横转竖瞬间可能残留的左右侧边栏宽度，并结合底部横排 Tab 栏真实顶边位置防止底部留白漏算
    func calculateContentInsets(
        in window: UIWindow,
        form: DuoDisplayForm,
        bottomTabBarHeight: CGFloat
    ) -> UIEdgeInsets {
        let windowInsets = window.safeAreaInsets
        let pageInsets = activePageView?.safeAreaInsets ?? resolveSplitPageSafeAreaInsets() ?? windowInsets
        let top = max(windowInsets.top, pageInsets.top)
        let baseBottom = max(windowInsets.bottom, pageInsets.bottom)
        switch form {
        case .phone, .innerPortrait:
            return UIEdgeInsets(
                top: top,
                left: 0,
                bottom: max(baseBottom, bottomTabBarHeight),
                right: 0
            )
        case .innerSplitLeft:
            return UIEdgeInsets(
                top: top,
                left: max(windowInsets.left, pageInsets.left),
                bottom: baseBottom,
                right: 0
            )
        case .outer, .innerLandscape, .innerSplitRight:
            return UIEdgeInsets(
                top: top,
                left: 0,
                bottom: baseBottom,
                right: max(windowInsets.right, pageInsets.right)
            )
        }
    }

    /// 沿子控制器树递归查找指定类型的控制器实例
    func findController<T: UIViewController>(ofType type: T.Type, in controller: UIViewController) -> T? {
        if let matched = controller as? T {
            return matched
        }
        for child in controller.children {
            if let found = findController(ofType: type, in: child) {
                return found
            }
        }
        return nil
    }
}
