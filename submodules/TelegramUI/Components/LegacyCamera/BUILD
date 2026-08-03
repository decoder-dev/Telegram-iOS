load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "LegacyCamera",
    module_name = "LegacyCamera",
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
        "//submodules/SSignalKit/SSignalKit",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/LegacyComponents",
        "//submodules/Display",
        "//submodules/TelegramCore",
        "//submodules/AccountContext",
        "//submodules/ShareController",
        "//submodules/LegacyUI",
        "//submodules/LegacyMediaPickerUI",

    ],
    visibility = [
        "//visibility:public",
    ],
)
