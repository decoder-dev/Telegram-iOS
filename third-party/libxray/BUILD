load("@build_bazel_rules_apple//apple:apple.bzl", "apple_static_xcframework_import")

# LibXray.xcframework is fetched by CI (checksum-pinned XTLS/libxray release)
# into this directory before Bazel runs; see .github/workflows/build.yml.
# The framework itself is gitignored; only this BUILD file is tracked.
#
# sdk_dylibs: the Go runtime inside the archive uses the res_9_* resolver
# entry points, which live in libresolv.dylib on Apple platforms.
apple_static_xcframework_import(
    name = "LibXray",
    xcframework_imports = glob(
        ["LibXray.xcframework/**"],
        allow_empty = False,
    ),
    sdk_dylibs = [
        "libresolv.dylib",
    ],
    visibility = ["//visibility:public"],
)
