load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ChatMessageGiveawayBubbleContentNode",
    module_name = "ChatMessageGiveawayBubbleContentNode",
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
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/AvatarNode",
        "//submodules/AccountContext",
        "//submodules/PhoneNumberFormat",
        "//submodules/TelegramStringFormatting",
        "//submodules/Markdown",
        "//submodules/ShimmerEffect",
        "//submodules/AnimatedStickerNode",
        "//submodules/TelegramAnimatedStickerNode",
        "//submodules/TelegramUI/Components/Chat/ChatMessageDateAndStatusNode",
        "//submodules/TelegramUI/Components/Chat/ChatMessageBubbleContentNode",
        "//submodules/TelegramUI/Components/Chat/ChatMessageItemCommon",
        "//submodules/TelegramUI/Components/Chat/ChatMessageAttachedContentButtonNode",
        "//submodules/TelegramUI/Components/ChatControllerInteraction",
        "//submodules/TelegramUI/Components/TextNodeWithEntities",
        "//submodules/TextFormat",
    ],
    visibility = [
        "//visibility:public",
    ],
)
