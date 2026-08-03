load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

filegroup(
    name = "OverlayStatusControllerResources",
    srcs = glob([
        "Resources/**/*",
    ], exclude = ["Resources/**/.*"]),
    visibility = ["//visibility:public"],
)

swift_library(
    name = "OverlayStatusController",
    module_name = "OverlayStatusController",
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
        "//submodules/Display:Display",
        "//submodules/OverlayStatusController/Impl:OverlayStatusControllerImpl"
    ],
    visibility = [
        "//visibility:public",
    ],
)
