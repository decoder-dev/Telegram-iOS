load("@rules_cc//cc:objc_library.bzl", "objc_library")

# The voice changer's effect graph and the playback equalizer, plain C (ported from Ghostgram).
# Realtime-safe processing: every buffer is allocated by ...Create, ...Process... never allocates or locks.
objc_library(
    name = "ForkVoiceDSP",
    enable_modules = True,
    module_name = "ForkVoiceDSP",
    srcs = glob([
        "Sources/**/*.c",
    ]),
    hdrs = glob([
        "PublicHeaders/**/*.h",
    ]),
    includes = [
        "PublicHeaders",
        "PublicHeaders/ForkVoiceDSP",
    ],
    copts = [
        "-std=c11",
        "-O2",
        "-Werror",
    ],
    visibility = [
        "//visibility:public",
    ],
)
