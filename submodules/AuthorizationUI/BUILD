load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

swift_library(
    name = "AuthorizationUI",
    module_name = "AuthorizationUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/LottieSettings:LottieSettings",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/Display:Display",
        "//submodules/SSignalKit/SSignalKit",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TextFormat:TextFormat",
        "//submodules/Markdown:Markdown",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/AccountContext:AccountContext",
        "//submodules/CountrySelectionUI:CountrySelectionUI",
        "//submodules/PhoneNumberFormat:PhoneNumberFormat",
        "//submodules/LegacyComponents:LegacyComponents",
        "//submodules/LegacyMediaPickerUI:LegacyMediaPickerUI",
        "//submodules/PasswordSetupUI:PasswordSetupUI",
        "//submodules/TelegramNotices:TelegramNotices",
        "//submodules/ProgressNavigationButtonNode:ProgressNavigationButtonNode",
        "//submodules/AnimatedStickerNode:AnimatedStickerNode",
        "//submodules/TelegramAnimatedStickerNode:TelegramAnimatedStickerNode",
        "//submodules/SolidRoundedButtonNode:SolidRoundedButtonNode",
        "//submodules/ImageCompression:ImageCompression",
        "//submodules/RMIntro:RMIntro",
        "//submodules/QrCode:QrCode",
        "//submodules/PhoneInputNode:PhoneInputNode",
        "//submodules/CodeInputView:CodeInputView",
        "//submodules/DebugSettingsUI:DebugSettingsUI",
        "//submodules/InvisibleInkDustNode:InvisibleInkDustNode",
        "//submodules/AuthorizationUtils:AuthorizationUtils",
        "//submodules/ManagedAnimationNode:ManagedAnimationNode",
        "//submodules/AlertUI:AlertUI",
        "//submodules/TelegramUI/Components/TextNodeWithEntities:TextNodeWithEntities",
        "//submodules/MoreButtonNode:MoreButtonNode",
        "//submodules/ContextUI:ContextUI",
        "//submodules/InAppPurchaseManager",
        "//submodules/TelegramUI/Components/Premium/PremiumCoinComponent",
        "//submodules/TelegramUI/Components/PlainButtonComponent",
        "//submodules/Utils/DeviceModel",
        "//submodules/PresentationDataUtils",
        "//submodules/TelegramUI/Components/GlassBarButtonComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "AuthorizationFormTestLib",
    testonly = True,
    srcs = [
        "Sources/AuthorizationFormNode.swift",
        "Tests/AuthorizationFormTests.swift",
    ],
    deps = [
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/AuthorizationUtils:AuthorizationUtils",
        "//submodules/Display:Display",
        "//submodules/SolidRoundedButtonNode:SolidRoundedButtonNode",
    ],
)

ios_test_runner(
    name = "AuthorizationFormTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "AuthorizationFormTests",
    bundle_id = "org.bananagram.tests.AuthorizationFormTests",
    minimum_os_version = "15.0",
    runner = ":AuthorizationFormTestRunner",
    deps = [":AuthorizationFormTestLib"],
)
