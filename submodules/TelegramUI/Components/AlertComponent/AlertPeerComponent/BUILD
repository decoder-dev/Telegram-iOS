load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "AlertPeerComponent",
    module_name = "AlertPeerComponent",
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
        "//submodules/AccountContext",
        "//submodules/Display",
        "//submodules/ComponentFlow",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/Components/MultilineTextComponent",
        "//submodules/TelegramUI/Components/AlertComponent",
        "//submodules/TelegramUI/Components/AvatarComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)
