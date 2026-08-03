load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "MediaPlaybackHeaderPanelComponent",
    module_name = "MediaPlaybackHeaderPanelComponent",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
        # Xcode 27: keep new diagnostic groups as warnings (SE-0443 last-wins)
        "-Wwarning", "ImplicitStrongCapture",
        "-Wwarning", "DeprecatedDeclaration",
        "-Wwarning", "NoUseUnstructuredThrowingTask",
    ],
    deps = [
        "//submodules/Display",
        "//submodules/AsyncDisplayKit",
        "//submodules/TelegramPresentationData",
        "//submodules/AccountContext",
        "//submodules/TelegramCore",
        "//submodules/Components/ComponentDisplayAdapters",
        "//submodules/TelegramUIPreferences",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/MediaPlayer:UniversalMediaPlayer",
        "//submodules/TelegramStringFormatting",
        "//submodules/ManagedAnimationNode",
        "//submodules/ContextUI",
        "//submodules/TelegramNotices",
        "//submodules/TooltipUI",
        "//submodules/TelegramUI/Components/SliderContextItem",
        "//submodules/TelegramUI/Components/GlobalControlPanelsContext",
        "//submodules/UndoUI",
        "//submodules/OverlayStatusController",
        "//submodules/PresentationDataUtils",
    ],
    visibility = [
        "//visibility:public",
    ],
)
