load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "TimezoneSelectionScreen",
    module_name = "TimezoneSelectionScreen",
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
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/AccountContext",
        "//submodules/SearchUI",
        "//submodules/MergeLists",
        "//submodules/ItemListUI",
        "//submodules/PresentationDataUtils",
        "//submodules/SearchBarNode",
        "//submodules/TelegramUIPreferences",
        "//submodules/ComponentFlow",
        "//submodules/Components/BalancedTextComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)
