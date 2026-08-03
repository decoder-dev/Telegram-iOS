load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "InstantVideoRadialStatusNode",
    module_name = "InstantVideoRadialStatusNode",
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
        "//submodules/Display",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/MediaPlayer:UniversalMediaPlayer",
        "//submodules/LegacyComponents",
        "//submodules/UIKitRuntimeUtils",
    ],
    visibility = [
        "//visibility:public",
    ],
)
