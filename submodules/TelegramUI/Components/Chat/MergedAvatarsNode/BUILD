load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "MergedAvatarsNode",
    module_name = "MergedAvatarsNode",
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
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/Display",
        "//submodules/TelegramPresentationData",
        "//submodules/AvatarNode",
        "//submodules/AccountContext",
    ],
    visibility = [
        "//visibility:public",
    ],
)
