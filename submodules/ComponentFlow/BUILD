load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ComponentFlow",
    module_name = "ComponentFlow",
    srcs = glob([
        "Source/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
        # Xcode 27: keep new diagnostic groups as warnings (SE-0443 last-wins)
        "-Wwarning", "ImplicitStrongCapture",
        "-Wwarning", "DeprecatedDeclaration",
    ],
    deps = [
        "//submodules/Display",
        "//submodules/UIKitRuntimeUtils",
    ],
    visibility = [
        "//visibility:public",
    ],
)
