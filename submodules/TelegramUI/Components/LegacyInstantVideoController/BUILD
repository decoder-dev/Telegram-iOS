load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "LegacyInstantVideoController",
    module_name = "LegacyInstantVideoController",
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
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/TelegramCore",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramPresentationData",
        "//submodules/MediaResources",
        "//submodules/LegacyComponents",
        "//submodules/AccountContext",
        "//submodules/LegacyUI",
        "//submodules/ImageCompression",
        "//submodules/LocalMediaResources",
        "//submodules/AppBundle",
        "//submodules/LegacyMediaPickerUI",
        "//submodules/ChatPresentationInterfaceState",
        "//submodules/TelegramUI/Components/ChatSendButtonRadialStatusNode",
    ],
    visibility = [
        "//visibility:public",
    ],
)
