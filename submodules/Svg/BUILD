load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "Svg",
    module_name = "Svg",
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
        "//submodules/Svg/LegacyImpl",
    ],
    visibility = [
        "//visibility:public",
    ],
)
