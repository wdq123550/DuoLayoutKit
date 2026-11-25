//
//  DuoLayoutTypes.swift
//  DuoLayoutKit
//
//  定义屏幕形态、侧边栏位置、设计稿基准配置以及给 UIKit 使用的通知常量。
//

import UIKit

//MARK: - 枚举定义
/// 描述 App 当前所处的屏幕形态。
/// 关联值是页面能放内容的区域尺寸：宽度是窗口宽度扣掉左右被状态栏、竖排 Tab 栏占掉的那一列，高度是窗口高度扣掉上下安全区
public enum DuoDisplayForm {
    /// 表示 App 运行在普通 iPhone 上（不是 iPhone Duo）
    case phone(CGSize)
    /// 表示 iPhone Duo 合上，App 显示在外屏
    case outer(CGSize)
    /// 表示 iPhone Duo 展开竖拿，App 占满内屏
    case innerPortrait(CGSize)
    /// 表示 iPhone Duo 展开横拿，App 占满内屏
    case innerLandscape(CGSize)
    /// 表示 iPhone Duo 展开横拿并与别的 App 左右分屏，本 App 在左半边
    case innerSplitLeft(CGSize)
    /// 表示 iPhone Duo 展开横拿并与别的 App 左右分屏，本 App 在右半边
    case innerSplitRight(CGSize)
}

/// 描述 iPhone Duo 上系统把状态栏、导航栏按钮或 Tab 栏竖排成的那一列，关联值是这一列的宽度
public enum DuoSideColumn {
    /// 表示竖排栏位于页面左侧（内屏左半边分屏）
    case left(CGFloat)
    /// 表示竖排栏位于页面右侧（外屏、内屏横拿占满、内屏右半边分屏）
    case right(CGFloat)
}

/// 存放 `Notification.Name.duoLayoutDidChange` 通知 `userInfo` 使用的键名
public enum DuoLayoutNotificationKey {
    /// 对应 `userInfo` 中变化后的屏幕形态，值类型为 `DuoDisplayForm`
    public static let form = "duoDisplayForm"
}

//MARK: - 计算属性
public extension DuoDisplayForm {
    /// 取出这个形态下页面能放内容的区域尺寸
    var safeSize: CGSize {
        switch self {
        case .phone(let size), .outer(let size), .innerPortrait(let size),
             .innerLandscape(let size), .innerSplitLeft(let size), .innerSplitRight(let size):
            return size
        }
    }
    /// 判断当前屏幕形态有没有侧边竖排栏（iPhone Duo 外屏、内屏横拿、左右分屏有侧边栏；普通 iPhone 和 Duo 内屏竖拿没有）
    var hasSideBar: Bool {
        switch self {
        case .outer, .innerLandscape, .innerSplitLeft, .innerSplitRight:
            return true
        case .phone, .innerPortrait:
            return false
        }
    }
    /// 判断当前屏幕形态是不是 iPhone Duo 内屏竖拿，供页面区分内屏竖拿布局
    var isInnerPortrait: Bool {
        if case .innerPortrait = self {
            return true
        }
        return false
    }
    /// 判断当前屏幕形态是不是 iPhone Duo 内屏横拿，供页面区分横屏版和竖屏版布局
    var isInnerLandscape: Bool {
        if case .innerLandscape = self {
            return true
        }
        return false
    }
    /// 判断当前屏幕形态是不是 iPhone Duo 左右分屏（左分屏或右分屏都返回 true）
    var isSplit: Bool {
        switch self {
        case .innerSplitLeft, .innerSplitRight:
            return true
        case .phone, .outer, .innerPortrait, .innerLandscape:
            return false
        }
    }
    /// 判断当前屏幕形态是不是位于 iPhone Duo 内屏（包含内屏竖拿、内屏横拿和左右分屏）
    var isInnerScreen: Bool {
        switch self {
        case .innerPortrait, .innerLandscape, .innerSplitLeft, .innerSplitRight:
            return true
        case .phone, .outer:
            return false
        }
    }
}

//MARK: - 计算属性
public extension DuoSideColumn {
    /// 取出侧边竖排栏的宽度
    var width: CGFloat {
        switch self {
        case .left(let width), .right(let width):
            return width
        }
    }
    /// 判断侧边竖排栏是不是位于页面左侧
    var isLeft: Bool {
        if case .left = self {
            return true
        }
        return false
    }
    /// 判断侧边竖排栏是不是位于页面右侧
    var isRight: Bool {
        if case .right = self {
            return true
        }
        return false
    }
}

//MARK: - 配置模型
/// 定义各屏幕形态的设计稿基准宽度和调试日志开关，在 App 启动时通过 `DuoLayoutManager.shared.setup(config:)` 注入
public struct DuoLayoutConfig {
    /// 创建一套屏幕形态缩放配置，未传的参数采用常见默认值（竖屏 390、内屏竖拿 669、内屏横拿 951）
    public init(
        portraitDesignWidth: CGFloat = 390,
        innerPortraitBaseWidth: CGFloat? = nil,
        innerPortraitDesignWidth: CGFloat = 669,
        innerLandscapeDesignWidth: CGFloat = 951,
        isDebugLoggingEnabled: Bool = true
    ) {
        self.portraitDesignWidth = portraitDesignWidth
        self.innerPortraitBaseWidth = innerPortraitBaseWidth
        self.innerPortraitDesignWidth = innerPortraitDesignWidth
        self.innerLandscapeDesignWidth = innerLandscapeDesignWidth
        self.isDebugLoggingEnabled = isDebugLoggingEnabled
    }
    //MARK: - 存储属性
    /// 记录普通直板机、iPhone Duo 外屏和左右分屏共用的竖屏设计稿宽度
    public let portraitDesignWidth: CGFloat
    /// 记录 iPhone Duo 内屏竖拿时固定使用的屏幕基准宽度；为 nil 时直接使用窗口实际宽度（如 669）
    public let innerPortraitBaseWidth: CGFloat?
    /// 记录 iPhone Duo 内屏竖拿对应的设计稿宽度；与内屏竖拿基准宽度相等时缩放比例为 1:1
    public let innerPortraitDesignWidth: CGFloat
    /// 记录 iPhone Duo 内屏横拿对应的设计稿宽度；与含侧边栏的整屏宽度 951 对应 1:1
    public let innerLandscapeDesignWidth: CGFloat
    /// 控制是否在 DEBUG 构建下向控制台输出 `[DuoLayout]` 状态日志
    public let isDebugLoggingEnabled: Bool
}

//MARK: - 通知名
public extension Notification.Name {
    /// 当 iPhone Duo 的屏幕形态发生变化（开合、内屏旋转、进出分屏、分屏左右换边）时发出，供 UIKit 页面刷新布局。
    /// 发出时 `DuoLayoutManager.shared` 里的形态与缩放比例已经更新为最新值，普通直板机不会发送本通知
    static let duoLayoutDidChange = Notification.Name("DuoLayoutKit.duoLayoutDidChange")
}

//MARK: - Equatable
extension DuoDisplayForm: Equatable {}

//MARK: - Equatable
extension DuoSideColumn: Equatable {}

//MARK: - Equatable
extension DuoLayoutConfig: Equatable {}
