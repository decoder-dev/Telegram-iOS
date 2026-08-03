load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "DirectionalPanGesture",
    module_name = "DirectionalPanGesture",
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
    visibility = [
        "//visibility:public",
    ],
)
