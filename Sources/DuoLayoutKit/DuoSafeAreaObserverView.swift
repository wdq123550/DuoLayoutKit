//
//  DuoSafeAreaObserverView.swift
//  DuoLayoutKit
//
//  贴在当前活跃页面最底层的透明监听视图，用来第一时间捕获子页面安全区延迟更新和系统竖排侧边栏位置变化。
//

import UIKit

/// 贴在当前活跃页面最底层的透明监听视图，不拦截点击也不参与无障碍焦点
final class DuoSafeAreaObserverView: UIView {
    /// 初始化透明监听视图，关闭交互并在 iOS 27.1+ 上注册系统竖排侧边栏位置变化监听
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if #available(iOS 27.1, *) {
            registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) { (self: DuoSafeAreaObserverView, _) in
                self.onVerticalBarEdgeDidChange?()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    //MARK: - 存储属性
    /// 宿主页面安全区发生变化时，调用本闭包通知屏幕形态管理器安排刷新
    var onSafeAreaDidChange: (() -> Void)?
    /// 系统竖排侧边栏所在边沿发生变化时，调用本闭包通知屏幕形态管理器安排刷新与补查
    var onVerticalBarEdgeDidChange: (() -> Void)?

    //MARK: - 生命周期
    /// 宿主页面安全区更新后系统调用本方法，立即通知屏幕形态管理器重新核对形态与安全区
    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        onSafeAreaDidChange?()
    }
}
