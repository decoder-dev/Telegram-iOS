load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "TemporaryCachedPeerDataManager",
    module_name = "TemporaryCachedPeerDataManager",
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
        "//submodules/TelegramStringFormatting:TelegramStringFormatting",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/Postbox:Postbox",
    ],
    visibility = [
        "//visibility:public",
    ],
)
