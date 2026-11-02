load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

swift_library(
    name = "ItemListUI",
    module_name = "ItemListUI",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/LottieSettings:LottieSettings",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/MergeLists:MergeLists",
        "//submodules/TextFormat:TextFormat",
        "//submodules/Markdown:Markdown",
        "//submodules/ProgressNavigationButtonNode:ProgressNavigationButtonNode",
        "//submodules/SwitchNode:SwitchNode",
        "//submodules/AnimatedStickerNode:AnimatedStickerNode",
        "//submodules/TelegramAnimatedStickerNode:TelegramAnimatedStickerNode",
        "//submodules/CheckNode:CheckNode",
        "//submodules/SegmentedControlNode:SegmentedControlNode",
        "//submodules/AccountContext:AccountContext",
        "//submodules/AnimationUI:AnimationUI",
        "//submodules/ShimmerEffect:ShimmerEffect",
        "//submodules/ManagedAnimationNode:ManagedAnimationNode",
        "//submodules/AvatarNode",
        "//submodules/TelegramCore",
        "//submodules/ComponentFlow",
        "//submodules/TelegramUI/Components/TabSelectorComponent",
        "//submodules/Components/ComponentDisplayAdapters",
        "//submodules/TelegramUI/Components/TextNodeWithEntities",
        "//submodules/TelegramUI/Components/ListItemComponentAdaptor",
        "//submodules/TelegramUI/Components/GlassBackgroundComponent",
        "//submodules/TelegramUI/Components/GlassControls",
        "//submodules/TelegramUI/Components/HorizontalTabsComponent",
        "//submodules/TelegramUI/Components/SideColumnLayout",
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "SettingsRowLayoutTestsLib",
    testonly = True,
    srcs = [
        "Tests/SettingsRowLayoutTests.swift",
        "Tests/ButtonAccessibilityTests.swift",
    ],
    deps = [
        ":ItemListUI",
        "//submodules/ComponentFlow",
        "//submodules/TelegramUI/Components/ButtonComponent",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//Telegram:PresentationStrings",
    ],
)

ios_test_runner(
    name = "SettingsRowLayoutTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "SettingsRowLayoutTests",
    minimum_os_version = "15.0",
    runner = ":SettingsRowLayoutTestRunner",
    data = ["//Telegram:GeneratedPresentationStrings/Resources/PresentationStrings.data"],
    deps = [":SettingsRowLayoutTestsLib"],
    visibility = ["//visibility:public"],
)
