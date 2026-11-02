load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

swift_library(
    name = "SearchBarNode",
    module_name = "SearchBarNode",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/ActivityIndicator:ActivityIndicator",
        "//submodules/AppBundle:AppBundle",
        "//submodules/ComponentFlow:ComponentFlow",
        "//submodules/AvatarNode:AvatarNode",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramUI/Components/EmojiStatusComponent",
        "//submodules/TelegramUI/Components/GlassBackgroundComponent",
        "//submodules/Components/ComponentDisplayAdapters",
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "SearchBarLayoutTestsLib",
    testonly = True,
    srcs = ["Tests/SearchBarLayoutTests.swift"],
    deps = [
        ":SearchBarNode",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//Telegram:PresentationStrings",
    ],
)

ios_test_runner(
    name = "SearchBarLayoutTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "SearchBarLayoutTests",
    minimum_os_version = "15.0",
    runner = ":SearchBarLayoutTestRunner",
    data = ["//Telegram:GeneratedPresentationStrings/Resources/PresentationStrings.data"],
    deps = [":SearchBarLayoutTestsLib"],
    visibility = ["//visibility:public"],
)
