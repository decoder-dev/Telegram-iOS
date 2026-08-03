load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ChatScheduleTimeScreen",
    module_name = "ChatScheduleTimeScreen",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
        # Xcode 27: keep new diagnostic groups as warnings (SE-0443 last-wins)
        "-Wwarning", "ImplicitStrongCapture",
        "-Wwarning", "DeprecatedDeclaration",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/TelegramCore",
        "//submodules/AccountContext",
        "//submodules/TelegramPresentationData",
        "//submodules/TelegramStringFormatting",
        "//submodules/SolidRoundedButtonNode",
        "//submodules/PresentationDataUtils",
        "//submodules/UIKitRuntimeUtils",
        "//submodules/ComponentFlow",
        "//submodules/TelegramUI/Components/ToastComponent",
        "//submodules/Markdown",
        "//submodules/TelegramUI/Components/LottieComponent",
        "//submodules/Components/MultilineTextComponent",
        "//submodules/Components/ComponentDisplayAdapters",
    ],
    visibility = [
        "//visibility:public",
    ],
)
