load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ManagedDiceAnimationNode",
    module_name = "ManagedDiceAnimationNode",
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
        "//submodules/TelegramCore",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/AccountContext",
        "//submodules/StickerResources",
        "//submodules/ManagedAnimationNode",
    ],
    visibility = [
        "//visibility:public",
    ],
)
