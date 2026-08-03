load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "TokenListTextField",
    module_name = "TokenListTextField",
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
        "//submodules/ComponentFlow",
        "//submodules/AsyncDisplayKit",
        "//submodules/TelegramPresentationData",
        "//submodules/TelegramCore",
        "//submodules/AvatarNode",
        "//submodules/AccountContext",
        "//submodules/Components/ComponentDisplayAdapters",
    ],
    visibility = [
        "//visibility:public",
    ],
)
