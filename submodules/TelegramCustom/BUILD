load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:resources.bzl", "apple_resource_bundle")

# 核心工具库
swift_library(
    name = "TelegramCustomCore",
    srcs = glob(["Sources/Core/**/*.swift"]),
    module_name = "TelegramCustomCore",
    data = glob(["Resources/Localizations/**/*.strings"]),
    visibility = ["//visibility:public"],
)

# 开屏页模块
swift_library(
    name = "SplashScreenModule",
    srcs = glob(["Sources/Features/SplashScreen/**/*.swift"]),
    module_name = "SplashScreen",
    deps = [":TelegramCustomCore"],
    data = glob(["Resources/Localizations/**/*.strings"]),
    visibility = ["//visibility:public"],
)

# 登录页模块
swift_library(
    name = "LoginScreenModule",
    srcs = glob(["Sources/Features/LoginScreen/**/*.swift"]),
    module_name = "LoginScreen",
    deps = [":TelegramCustomCore"],
    data = glob(["Resources/Localizations/**/*.strings"]),
    visibility = ["//visibility:public"],
)

# 多语言资源
apple_resource_bundle(
    name = "LocalizationResources",
    resources = glob(["Resources/Localizations/**/*.strings"]),
    visibility = ["//visibility:public"],
)

# 统一导出（未来可扩展更多模块）
swift_library(
    name = "TelegramCustom",
    module_name = "TelegramCustom",
    srcs = ["Sources/TelegramCustom.swift"],
    deps = [
        ":TelegramCustomCore",
        ":SplashScreenModule",
        ":LoginScreenModule",
    ],
    visibility = ["//visibility:public"],
)
