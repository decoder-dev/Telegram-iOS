load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SliderContextItem",
    module_name = "SliderContextItem",
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
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/ContextUI:ContextUI",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/AnimatedCountLabelNode:AnimatedCountLabelNode",
    ],
    visibility = [
        "//visibility:public",
    ],
)
