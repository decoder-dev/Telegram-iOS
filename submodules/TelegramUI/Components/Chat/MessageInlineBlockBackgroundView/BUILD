load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "MessageInlineBlockBackgroundView",
    module_name = "MessageInlineBlockBackgroundView",
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
        "//submodules/Display",
        "//submodules/Components/HierarchyTrackingLayer",
        "//submodules/TelegramCore",
        "//submodules/TelegramUI/Components/AnimationCache",
        "//submodules/TelegramUI/Components/MultiAnimationRenderer",
        "//submodules/TelegramUI/Components/EmojiTextAttachmentView",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/AccountContext",
    ],
    visibility = [
        "//visibility:public",
    ],
)
