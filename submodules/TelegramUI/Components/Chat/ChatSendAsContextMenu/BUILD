load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ChatSendAsContextMenu",
    module_name = "ChatSendAsContextMenu",
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
        "//submodules/AsyncDisplayKit",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramPresentationData",
        "//submodules/TelegramCore",
        "//submodules/AppBundle",
        "//submodules/ContextUI",
        "//submodules/TelegramStringFormatting",
        "//submodules/AvatarNode",
        "//submodules/AccountContext",
        "//submodules/UndoUI",
        "//submodules/TelegramUI/Components/ContextControllerImpl",
    ],
    visibility = [
        "//visibility:public",
    ],
)
