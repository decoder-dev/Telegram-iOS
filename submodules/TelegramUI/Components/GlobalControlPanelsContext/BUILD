load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "GlobalControlPanelsContext",
    module_name = "GlobalControlPanelsContext",
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
        "//submodules/TelegramCore",
        "//submodules/AccountContext",
        "//submodules/TelegramUIPreferences",
        "//submodules/TelegramCallsUI",
        "//submodules/Display",
        "//submodules/UndoUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)
