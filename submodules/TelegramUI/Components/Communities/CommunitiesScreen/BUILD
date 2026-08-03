load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "CommunitiesScreen",
    module_name = "CommunitiesScreen",
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
        "//submodules/ComponentFlow",
        "//submodules/Components/ViewControllerComponent",
        "//submodules/Display",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/Components/MultilineTextComponent",
        "//submodules/TelegramUI/Components/AvatarComponent",
        "//submodules/Components/BundleIconComponent",
        "//submodules/TelegramUI/Components/ListActionItemComponent",
        "//submodules/TelegramUI/Components/ListSectionComponent",
        "//submodules/TelegramUI/Components/Stories/PeerListItemComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)
