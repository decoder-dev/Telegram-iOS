load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "TelegramVLESS",
    module_name = "TelegramVLESS",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SwiftSignalKit:SwiftSignalKit",
        "//third-party/libxray:LibXray",
    ],
    visibility = [
        "//visibility:public",
    ],
)
