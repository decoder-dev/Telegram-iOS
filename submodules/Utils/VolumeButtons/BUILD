load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "VolumeButtons",
    module_name = "VolumeButtons",
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
        "//submodules/LegacyComponents",
        "//submodules/AccountContext",
    ],
    visibility = [
        "//visibility:public",
    ],
)
