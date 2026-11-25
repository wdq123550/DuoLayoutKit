//
//  DuoLayoutKitTests.swift
//  DuoLayoutKitTests
//
//  验证各屏幕形态下的缩放基准、侧边栏居中偏移、可用水平区域以及形态辅助属性。
//

import XCTest
@testable import DuoLayoutKit

final class DuoLayoutKitTests: XCTestCase {
    /// 验证按 FurFriends 风格配置（390 / 669 / 951）时，各形态计算出的基准宽和设计稿宽是否准确
    func testScaleMetricsWithDefaultStyleConfig() {
        let config = DuoLayoutConfig(
            portraitDesignWidth: 390,
            innerPortraitBaseWidth: nil,
            innerPortraitDesignWidth: 669,
            innerLandscapeDesignWidth: 951
        )
        let phoneBase = DuoLayoutManager.computeBaseWidth(
            for: .phone(CGSize(width: 393, height: 759)),
            windowWidth: 393,
            mainScreenWidth: 393,
            config: config
        )
        XCTAssertEqual(phoneBase, 393)
        XCTAssertEqual(DuoLayoutManager.computeDesignWidth(for: .phone(CGSize(width: 393, height: 759)), config: config), 390)

        let outerForm = DuoDisplayForm.outer(CGSize(width: 382, height: 789))
        let outerBase = DuoLayoutManager.computeBaseWidth(
            for: outerForm,
            windowWidth: 466,
            mainScreenWidth: 466,
            config: config
        )
        XCTAssertEqual(outerBase, 382)
        XCTAssertEqual(DuoLayoutManager.computeDesignWidth(for: outerForm, config: config), 390)

        let innerPortraitForm = DuoDisplayForm.innerPortrait(CGSize(width: 669, height: 910))
        let innerPortraitBase = DuoLayoutManager.computeBaseWidth(
            for: innerPortraitForm,
            windowWidth: 669,
            mainScreenWidth: 466,
            config: config
        )
        XCTAssertEqual(innerPortraitBase, 669)
        XCTAssertEqual(DuoLayoutManager.computeDesignWidth(for: innerPortraitForm, config: config), 669)

        let innerLandscapeForm = DuoDisplayForm.innerLandscape(CGSize(width: 867, height: 649))
        let innerLandscapeBase = DuoLayoutManager.computeBaseWidth(
            for: innerLandscapeForm,
            windowWidth: 951,
            mainScreenWidth: 466,
            config: config
        )
        XCTAssertEqual(innerLandscapeBase, 951)
        XCTAssertEqual(DuoLayoutManager.computeDesignWidth(for: innerLandscapeForm, config: config), 951)
    }

    /// 验证按固定内屏竖屏基准配置（360 / 466 / 951）时，内屏竖拿固定采用 466 且保持 1:1
    func testScaleMetricsWithFixedInnerPortraitBaseWidth() {
        let config = DuoLayoutConfig(
            portraitDesignWidth: 360,
            innerPortraitBaseWidth: 466,
            innerPortraitDesignWidth: 466,
            innerLandscapeDesignWidth: 951
        )
        let innerPortraitForm = DuoDisplayForm.innerPortrait(CGSize(width: 669, height: 910))
        let baseWidth = DuoLayoutManager.computeBaseWidth(
            for: innerPortraitForm,
            windowWidth: 669,
            mainScreenWidth: 466,
            config: config
        )
        let designWidth = DuoLayoutManager.computeDesignWidth(for: innerPortraitForm, config: config)
        XCTAssertEqual(baseWidth, 466)
        XCTAssertEqual(designWidth, 466)
    }

    /// 验证侧边栏在左、在右和无侧边栏时，内容中心偏移量和可用水平区域计算是否正确
    func testSideColumnRegionAndCenterOffset() {
        XCTAssertEqual(DuoLayoutManager.computeContentCenterOffsetX(for: .left(84)), 42)
        XCTAssertEqual(DuoLayoutManager.computeContentCenterOffsetX(for: .right(84)), -42)
        XCTAssertEqual(DuoLayoutManager.computeContentCenterOffsetX(for: nil), 0)

        let leftRegion = DuoLayoutManager.computeAvailableHorizontalRegion(windowWidth: 469, sideColumn: .left(84))
        XCTAssertEqual(leftRegion.startX, 84)
        XCTAssertEqual(leftRegion.width, 385)

        let rightRegion = DuoLayoutManager.computeAvailableHorizontalRegion(windowWidth: 469, sideColumn: .right(84))
        XCTAssertEqual(rightRegion.startX, 0)
        XCTAssertEqual(rightRegion.width, 385)

        let fullRegion = DuoLayoutManager.computeAvailableHorizontalRegion(windowWidth: 669, sideColumn: nil)
        XCTAssertEqual(fullRegion.startX, 0)
        XCTAssertEqual(fullRegion.width, 669)
    }

    /// 验证六种屏幕形态枚举的辅助判断属性是否符合预期
    func testDisplayFormFlags() {
        let size = CGSize(width: 385, height: 649)
        XCTAssertFalse(DuoDisplayForm.phone(size).hasSideBar)
        XCTAssertFalse(DuoDisplayForm.innerPortrait(size).hasSideBar)
        XCTAssertTrue(DuoDisplayForm.outer(size).hasSideBar)
        XCTAssertTrue(DuoDisplayForm.innerLandscape(size).hasSideBar)
        XCTAssertTrue(DuoDisplayForm.innerSplitLeft(size).hasSideBar)
        XCTAssertTrue(DuoDisplayForm.innerSplitRight(size).hasSideBar)

        XCTAssertTrue(DuoDisplayForm.innerSplitLeft(size).isSplit)
        XCTAssertTrue(DuoDisplayForm.innerSplitRight(size).isSplit)
        XCTAssertFalse(DuoDisplayForm.outer(size).isSplit)

        XCTAssertFalse(DuoDisplayForm.phone(size).isInnerScreen)
        XCTAssertFalse(DuoDisplayForm.outer(size).isInnerScreen)
        XCTAssertTrue(DuoDisplayForm.innerPortrait(size).isInnerScreen)
        XCTAssertTrue(DuoDisplayForm.innerLandscape(size).isInnerScreen)
        XCTAssertTrue(DuoDisplayForm.innerSplitLeft(size).isInnerScreen)
        XCTAssertTrue(DuoDisplayForm.innerSplitRight(size).isInnerScreen)
    }

    /// 验证外屏、内屏横屏、内屏竖屏的过渡安全区过滤逻辑，确保中途未稳定的脏安全区会被跳过
    func testTransitionSafeAreaStabilityChecks() {
        // 竖转横过渡帧：窗口已横，但安全区还停在竖屏的 top=82, left=0, right=0
        let stalePortraitInsets = UIEdgeInsets(top: 82, left: 0, bottom: 34, right: 0)
        XCTAssertFalse(DuoLayoutManager.hasSingleSideBarInset(stalePortraitInsets))
        // 横屏/外屏稳定态：右侧状态栏 84 已就位
        let stableLandscapeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84)
        XCTAssertTrue(DuoLayoutManager.hasSingleSideBarInset(stableLandscapeInsets))
        // 换边过渡帧：左右同时有侧边栏
        let dualSideBarInsets = UIEdgeInsets(top: 0, left: 84, bottom: 34, right: 84)
        XCTAssertFalse(DuoLayoutManager.hasSingleSideBarInset(dualSideBarInsets))

        // 横转竖过渡帧：残留右侧 84，或顶部状态栏安全区还是 0
        XCTAssertFalse(DuoLayoutManager.isStableInnerPortraitInsets(stableLandscapeInsets, isStatusBarHidden: false))
        XCTAssertFalse(DuoLayoutManager.isStableInnerPortraitInsets(UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0), isStatusBarHidden: false))
        // 竖屏稳定态：左右为 0 且顶部 82 已就位
        XCTAssertTrue(DuoLayoutManager.isStableInnerPortraitInsets(stalePortraitInsets, isStatusBarHidden: false))
        // 状态栏主动隐藏时，顶部为 0 也可通过
        XCTAssertTrue(DuoLayoutManager.isStableInnerPortraitInsets(UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0), isStatusBarHidden: true))
    }

    /// 验证横转竖、竖转横时等待系统 Tab 栏搬家就位的判断逻辑
    func testTabBarSettleCheck() {
        let portrait = DuoDisplayForm.innerPortrait(CGSize(width: 669, height: 835))
        let landscape = DuoDisplayForm.innerLandscape(CGSize(width: 867, height: 635))
        // 横转竖：有可见 Tab 栏，但底部 Tab 高还是 0 -> 需要等下一帧
        XCTAssertTrue(DuoLayoutManager.needsWaitTabBarSettle(for: portrait, hasVisibleTabBar: true, isSystemVerticalBarEnabled: false, bottomTabBarHeight: 0))
        // 横转竖：底部 Tab 栏已经落位到 83 -> 稳定放行
        XCTAssertFalse(DuoLayoutManager.needsWaitTabBarSettle(for: portrait, hasVisibleTabBar: true, isSystemVerticalBarEnabled: false, bottomTabBarHeight: 83))
        // 竖转横：有可见 Tab 栏且系统启用了竖排栏，但底部 Tab 高还残留 83 -> 需要等下一帧
        XCTAssertTrue(DuoLayoutManager.needsWaitTabBarSettle(for: landscape, hasVisibleTabBar: true, isSystemVerticalBarEnabled: true, bottomTabBarHeight: 83))
        // 竖转横：Tab 栏已经竖到右侧（底部高 0） -> 稳定放行
        XCTAssertFalse(DuoLayoutManager.needsWaitTabBarSettle(for: landscape, hasVisibleTabBar: true, isSystemVerticalBarEnabled: true, bottomTabBarHeight: 0))
        // 没有可见 Tab 栏（如二级页） -> 不等待
        XCTAssertFalse(DuoLayoutManager.needsWaitTabBarSettle(for: portrait, hasVisibleTabBar: false, isSystemVerticalBarEnabled: false, bottomTabBarHeight: 0))
    }
}
