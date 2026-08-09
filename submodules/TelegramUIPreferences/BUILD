load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

swift_library(
    name = "TelegramUIPreferences",
    module_name = "TelegramUIPreferences",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/Postbox:Postbox",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/CryptoUtils:CryptoUtils",
    ],
    # Security is linked via `import Security` (swift_library has no sdk_frameworks).
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "TelegramUIPreferencesTestsLib",
    testonly = True,
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    deps = [
        ":TelegramUIPreferences",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/Postbox:Postbox",
    ],
)

# The default runner picks an invalid device and the test process exits 15, so the
# device/OS pair is pinned, matching //submodules/TextFormat:TextFormatTestRunner.
ios_test_runner(
    name = "TelegramUIPreferencesTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "MessageSavingStoreTests",
    minimum_os_version = "13.0",
    runner = ":TelegramUIPreferencesTestRunner",
    deps = [
        ":TelegramUIPreferencesTestsLib",
    ],
    visibility = [
        "//visibility:public",
    ],
)
