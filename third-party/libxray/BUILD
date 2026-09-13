load("@build_bazel_rules_apple//apple:apple.bzl", "apple_static_xcframework_import")

# LibXray.xcframework is fetched by CI (checksum-pinned XTLS/libxray release)
# into this directory before Bazel runs; see .github/workflows/build.yml.
# The framework itself is gitignored; only this BUILD file is tracked.
apple_static_xcframework_import(
    name = "LibXray",
    xcframework_imports = glob(
        ["LibXray.xcframework/**"],
        allow_empty = False,
    ),
    visibility = ["//visibility:public"],
)
