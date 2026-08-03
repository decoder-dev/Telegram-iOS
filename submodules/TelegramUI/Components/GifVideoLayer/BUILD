load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "GifVideoLayer",
    module_name = "GifVideoLayer",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
        # Xcode 27: keep new diagnostic groups as warnings (SE-0443 last-wins)
        "-Wwarning", "ImplicitStrongCapture",
        "-Wwarning", "DeprecatedDeclaration",
        "-Wwarning", "NoUseUnstructuredThrowingTask",
    ],
    deps = [
        "//submodules/Display",
        "//submodules/TelegramUI/Components/BatchVideoRendering",
        "//submodules/AccountContext",
        "//submodules/TelegramCore",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/PhotoResources",
    ],
    visibility = [
        "//visibility:public",
    ],
)
