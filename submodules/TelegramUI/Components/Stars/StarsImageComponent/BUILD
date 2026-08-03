load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "StarsImageComponent",
    module_name = "StarsImageComponent",
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
        "//submodules/ComponentFlow",
        "//submodules/Components/ViewControllerComponent",
        "//submodules/TelegramPresentationData",
        "//submodules/PhotoResources",
        "//submodules/AvatarNode",
        "//submodules/AccountContext",
        "//submodules/InvisibleInkDustNode",
        "//submodules/AnimatedStickerNode",
        "//submodules/TelegramAnimatedStickerNode",
    ],
    visibility = [
        "//visibility:public",
    ],
)
