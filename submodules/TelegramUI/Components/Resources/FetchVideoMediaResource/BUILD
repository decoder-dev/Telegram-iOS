load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "FetchVideoMediaResource",
    module_name = "FetchVideoMediaResource",
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
        "//submodules/Postbox",
        "//submodules/SSignalKit/SSignalKit",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/LegacyComponents",
        "//submodules/FFMpegBinding",
        "//submodules/LocalMediaResources",
        "//submodules/LegacyMediaPickerUI",
        "//submodules/TelegramUI/Components/MediaEditor",
    ],
    visibility = [
        "//visibility:public",
    ],
)
