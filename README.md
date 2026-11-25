# DuoLayoutKit 接入指南

`DuoLayoutKit` 是专门给 iPhone Duo 适配做的唯一屏幕形态感知与缩放底座，同时兼容 **SwiftUI** 和 **UIKit** 工程。

它把 iPhone Duo 上所有系统怪脾气都收进包里，包括：开合与旋转等转场结束再算、分屏左右换边窗口宽高不变、左分屏 84pt 安全区藏在里层页面、无导航栏二级页左分屏防卡死、内屏横屏转竖屏 Tab 栏搬回底部慢半拍。宿主工程不需要再到处写补丁，统一读取 `DuoLayoutManager.shared` 就行。

## 环境要求

- iOS 17.0 及以上（iPhone Duo 系统特征监听在 iOS 27.1 及以上自动开启）
- 依赖 `DeviceKit` `5.10.0` 及以上（包内已经声明依赖）

---

## 一、SwiftUI 项目怎么接（3 步）

### 第 1 步：启动时配置设计稿宽度

在 `SceneDelegate` 创建窗口之前调用一次 `setup(config:)`，填入本项目的各形态设计稿宽度：

```swift
import DuoLayoutKit

DuoLayoutManager.shared.setup(
    config: DuoLayoutConfig(
        portraitDesignWidth: 390,      // 直板机、Duo 外屏、左右分屏的设计稿宽
        innerPortraitBaseWidth: nil,   // 传 nil 直接用窗口实际宽（669）；需要固定宽度（如 466）就填具体数字
        innerPortraitDesignWidth: 669, // 内屏竖拿设计稿宽
        innerLandscapeDesignWidth: 951 // 内屏横拿设计稿宽
    )
)
```

### 第 2 步：把窗口根控制器换成 `DuoHostingController`

```swift
let rootController = DuoHostingController(rootView: MainView())
window.rootViewController = rootController
window.makeKeyAndVisible()
DuoLayoutManager.shared.bindRootViewController(rootController)
```

如果你的工程有自己的根控制器子类（比如要自定义状态栏样式），直接继承 `DuoHostingController` 即可，不用自己重写 `viewWillTransition`、`viewSafeAreaInsetsDidChange` 和 `viewDidLayoutSubviews`。

### 第 3 步：桥接项目自己的缩放扩展，页面直接读属性

把项目里原本的 `.adapt`（或 `.adjust`）改成乘以 `DuoLayoutManager.shared.sizeScale`：

```swift
extension CGFloat {
    var adapt: CGFloat {
        DuoLayoutManager.shared.scaled(self, rounded: true)
    }
}
```

业务 SwiftUI 页面**不需要写任何通知或监听代码**。因为 `DuoLayoutManager` 是 `@Observable`，页面只要在 `body` 里用了 `.adapt` 或读了 `DuoLayoutManager.shared` 的属性，开合、旋转、分屏换边时会自动重画。

---

## 二、UIKit 项目怎么接（3 步）

### 第 1 步：启动时配置设计稿宽度

```swift
import DuoLayoutKit

DuoLayoutManager.shared.setup(
    config: DuoLayoutConfig(
        portraitDesignWidth: 360,
        innerPortraitBaseWidth: 466,
        innerPortraitDesignWidth: 466,
        innerLandscapeDesignWidth: 951
    )
)
```

### 第 2 步：根导航控制器继承 `DuoNavigationController`

```swift
class BaseNavigationController: DuoNavigationController {
    // 原有导航栏配置代码照旧保留
}
```

如果你的工程不方便改继承链，也可以在现有根控制器里手动做两件事：
1. 成为窗口根控制器时调 `DuoLayoutManager.shared.bindRootViewController(self)`。
2. 在 `viewWillTransition(to:with:)`（等 `coordinator.animate(alongsideTransition: nil)` 结束闭包里）、`viewSafeAreaInsetsDidChange()`、`viewDidLayoutSubviews()` 三处调用 `DuoLayoutManager.shared.scheduleRefresh()`。

### 第 3 步：桥接缩放方法，页面监听通知并在 `viewWillAppear` 补查

把项目里原来的 `fixSize` 改成读 `DuoLayoutManager.shared.scaled(...)`：

```swift
func fixSize(_ size: CGFloat, _ isRound: Bool = false) -> CGFloat {
    DuoLayoutManager.shared.scaled(size, rounded: isRound)
}
```

需要随开合就地重排的 UIKit 页面，监听一条通知并在页面重新出现时核对一次：

```swift
final class SampleViewController: UIViewController {
    private var laidOutForm: DuoDisplayForm?
    private var laidOutSizeScale: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onDisplayLayoutChanged),
            name: .duoLayoutDidChange,
            object: nil
        )
        applyLayout()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        relayoutIfNeeded()
    }

    @objc private func onDisplayLayoutChanged() {
        relayoutIfNeeded()
    }

    private func relayoutIfNeeded() {
        let manager = DuoLayoutManager.shared
        guard manager.isDuo, isViewLoaded else { return }
        guard manager.form != laidOutForm || manager.sizeScale != laidOutSizeScale else { return }
        applyLayout()
    }

    private func applyLayout() {
        laidOutForm = DuoLayoutManager.shared.form
        laidOutSizeScale = DuoLayoutManager.shared.sizeScale
        // 按最新缩放比例和形态重新设置字号与约束
    }
}
```

---

## 三、常用属性速查表

所有属性都从 `DuoLayoutManager.shared` 只读获取：

| 属性 | 含义 | 常见用法 |
|---|---|---|
| `isDuo` | 当前设备是不是 iPhone Duo | 区分普通直板机和 Duo 逻辑 |
| `form` | 当前 6 种形态之一（`phone` / `outer` / `innerPortrait` / `innerLandscape` / `innerSplitLeft` / `innerSplitRight`） | 区分横屏版、内屏竖拿版、分屏版布局；自带 `hasSideBar`、`isSplit`、`isInnerPortrait`、`isInnerLandscape`、`isInnerScreen` |
| `sizeScale` | 当前缩放比例（`baseWidth / designWidth`） | 统一驱动 `.adapt` / `.adjust` / `fixSize` 和字体 |
| `usableSize` | 扣掉侧边栏和上下安全区后的内容可用尺寸 | 计算卡片最大宽度、内容区宽 |
| `sideColumn` | 侧边竖排栏在哪一边、有多宽（`.left(width)` / `.right(width)` / `nil`） | 判断贴左边还是贴右边避开侧边栏 |
| `contentCenterOffsetX` | 扣掉侧边栏后，内容中心相对整窗中心的水平偏移 | 顶部提现横幅、全屏 Loading、弹窗一键居中，不再手写 `switch sideColumn` |
| `availableHorizontalRegion` | 扣掉侧边栏后的水平起点 `startX` 和可用宽 `width` | Toast 换行限宽与居中、金币浮窗吸边定位 |
| `safeAreaInsets` | 窗口最新的上下左右安全区 | SwiftUI 页面需要顶底安全区并随开合自动刷新时读它 |
| `contentInsets` | 当前活跃页面真正要避开的区域 | 已自动清掉横转竖残留的 84pt，并合入底部横排 Tab 栏高度 |
| `bottomTabBarOccupiedHeight` | 系统 Tab 栏横排在底部时，从 Tab 栏顶边到窗口底边实际占用的总高度 | 底部悬浮进度栏、悬浮按钮、引导层定位；Tab 栏竖排到侧边或进二级页时自动为 `0` |

---

## 四、实用提醒

1. **不要把缩放结果写进 `static let`**：写成计算属性 `static var`。`static let` 在首次读取时就固定死了，早于首次形态刷新就会一直用错的比例。
2. **背景铺满，内容让开侧边栏**：背景图和底色直接贴满窗口，交互控件避开 `sideColumn` 或用 `contentInsets` / `usableSize`。
3. **居中浮层直接用 `contentCenterOffsetX`**：顶部横幅、全屏加载框、居中弹窗只需要把水平中心偏移设为 `DuoLayoutManager.shared.contentCenterOffsetX`，左分屏、右分屏、外屏、内屏横屏、内屏竖屏一次全对上。
4. **验收日志**：DEBUG 模式下（且配置开启 `isDebugLoggingEnabled`），在 Xcode 控制台筛选 `[DuoLayout]`，就能看到每次切换打印出来的形态、基准宽、设计稿宽、缩放比例、窗口安全区、内容安全区和底部 Tab 栏高度。
