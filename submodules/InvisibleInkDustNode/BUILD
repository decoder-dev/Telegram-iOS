load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "InvisibleInkDustNode",
    module_name = "InvisibleInkDustNode",
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
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AppBundle:AppBundle",
        "//submodules/LegacyComponents:LegacyComponents",
    ],
    visibility = [
        "//visibility:public",
    ],
)
