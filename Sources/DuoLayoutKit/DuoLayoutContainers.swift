//
//  DuoLayoutContainers.swift
//  DuoLayoutKit
//
//  提供给 SwiftUI 项目和 UIKit 项目开箱即用的窗口根控制器基类，
//  自动把窗口转场、安全区变化和布局变化事件转发给 `DuoLayoutManager.shared`。
//

import SwiftUI
import UIKit

/// 给 SwiftUI 项目使用的窗口根控制器基类。
/// 在 `SceneDelegate` 里把它设为 `window.rootViewController` 后，会自动绑定到 `DuoLayoutManager.shared` 并转发窗口形态事件
open class DuoHostingController<Content: View>: UIHostingController<Content> {
    /// 判断本控制器是不是所在窗口的根页面；只有根页面负责驱动全局屏幕形态刷新
    private var isWindowRoot: Bool {
        view.window?.rootViewController === self
    }

    /// 视图出现后如果是窗口根页面，自动向 `DuoLayoutManager.shared` 注册绑定
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard isWindowRoot else { return }
        DuoLayoutManager.shared.bindRootViewController(self)
    }

    /// 窗口尺寸变化时（iPhone Duo 开合、内屏旋转、进出分屏），等系统转场动画结束后再安排刷新屏幕形态
    open override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self, self.isWindowRoot else { return }
            DuoLayoutManager.shared.bindRootViewController(self)
            DuoLayoutManager.shared.scheduleRefresh()
        }
    }

    /// 根视图安全区变化时（外屏冷启动安全区稳定、分屏左右换边）安排刷新屏幕形态
    open override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        guard isWindowRoot else { return }
        DuoLayoutManager.shared.bindRootViewController(self)
        DuoLayoutManager.shared.scheduleRefresh()
    }

    /// 根视图完成一次布局后安排刷新屏幕形态，避免漏掉页面切换带来的安全区变化
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard isWindowRoot else { return }
        DuoLayoutManager.shared.bindRootViewController(self)
        DuoLayoutManager.shared.scheduleRefresh()
    }
}

/// 给 UIKit 项目使用的根导航控制器基类。
/// 宿主工程的根导航控制器继承本类后，会自动绑定到 `DuoLayoutManager.shared` 并在开合、旋转、分屏换边时驱动全局刷新
open class DuoNavigationController: UINavigationController {
    /// 判断本导航控制器是不是所在窗口的根页面；弹出来的二级导航控制器不会驱动全局刷新
    private var isWindowRoot: Bool {
        view.window?.rootViewController === self
    }

    /// 视图出现后如果是窗口根页面，自动向 `DuoLayoutManager.shared` 注册绑定
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard isWindowRoot else { return }
        DuoLayoutManager.shared.bindRootViewController(self)
    }

    /// 窗口尺寸变化时（iPhone Duo 开合、内屏旋转、进出分屏），等系统转场动画结束后再安排刷新屏幕形态
    open override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self, self.isWindowRoot else { return }
            DuoLayoutManager.shared.bindRootViewController(self)
            DuoLayoutManager.shared.scheduleRefresh()
        }
    }

    /// 根视图安全区变化时（外屏冷启动安全区稳定、分屏左右换边）安排刷新屏幕形态
    open override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        guard isWindowRoot else { return }
        DuoLayoutManager.shared.bindRootViewController(self)
        DuoLayoutManager.shared.scheduleRefresh()
    }

    /// 根视图完成一次布局后安排刷新屏幕形态，推入或退出页面后同步更新活跃页监听与安全区
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard isWindowRoot else { return }
        DuoLayoutManager.shared.bindRootViewController(self)
        DuoLayoutManager.shared.scheduleRefresh()
    }
}
