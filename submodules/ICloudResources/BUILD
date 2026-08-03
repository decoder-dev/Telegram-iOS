load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ICloudResources",
    module_name = "ICloudResources",
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
        "//submodules/TelegramCore",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/Display",
        "//submodules/Pdf",
    ],
    visibility = [
        "//visibility:public",
    ],
)
