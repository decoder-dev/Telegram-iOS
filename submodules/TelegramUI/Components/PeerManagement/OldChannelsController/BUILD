load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "OldChannelsController",
    module_name = "OldChannelsController",
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
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/Display",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/PresentationDataUtils",
        "//submodules/AccountContext",
        "//submodules/ContactsPeerItem",
        "//submodules/ItemListUI",
        "//submodules/SearchUI",
        "//submodules/SearchBarNode",
        "//submodules/SolidRoundedButtonNode",
        "//submodules/PremiumUI",
        "//submodules/ChatListSearchItemHeader",
        "//submodules/MergeLists",
    ],
    visibility = [
        "//visibility:public",
    ],
)


