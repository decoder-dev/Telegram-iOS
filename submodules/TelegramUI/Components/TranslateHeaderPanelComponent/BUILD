load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "TranslateHeaderPanelComponent",
    module_name = "TranslateHeaderPanelComponent",
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
        "//submodules/TelegramPresentationData",
        "//submodules/AccountContext",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/LocalizedPeerData",
        "//submodules/TelegramStringFormatting",
        "//submodules/TextFormat",
        "//submodules/Markdown",
        "//submodules/MoreButtonNode",
        "//submodules/ContextUI",
        "//submodules/TranslateUI",
        "//submodules/TelegramUIPreferences",
        "//submodules/TelegramNotices",
        "//submodules/PremiumUI",
        "//submodules/TelegramUI/Components/TranslationLanguagesContextMenuContent",
    ],
    visibility = [
        "//visibility:public",
    ],
)
