import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
FFMPEG = ROOT / "submodules/ffmpeg/Sources/FFMpeg/ffmpeg-8.1.2"


class FFmpegCodeQLScope(unittest.TestCase):
    def test_workflow_uses_the_scope_file(self):
        workflow = (ROOT / ".github/workflows/codeql.yml").read_text(encoding="utf-8")
        self.assertIn("config-file: ./.github/codeql/codeql-config.yml", workflow)

    def test_ignored_paths_are_not_built_into_the_app(self):
        config = (ROOT / ".github/codeql/codeql-config.yml").read_text(encoding="utf-8")
        build = (ROOT / "submodules/ffmpeg/Sources/FFMpeg/build-ffmpeg-bazel.sh").read_text(encoding="utf-8")
        self.assertIn("--disable-everything", build)
        ignored_paths = "\n".join(line for line in config.splitlines() if line.startswith("  - "))
        for ignored in ("libavfilter", "libswscale", "libavdevice", "libavformat/yop.c", "libavcodec/exr.c", "libavcodec/mips", "libavcodec/loongarch", "asfcrypt.c", "rtmpcrypt.c", "omadec.c"):
            self.assertIn(ignored, ignored_paths)
        # Only the decoders the app enables stay in scope.
        for kept in ("h264pred_template.c", "exif.c"):
            self.assertNotIn(kept, ignored_paths)
        self.assertIn("id: cpp/suspicious-add-sizeof", config)

    def test_loop_counters_cover_their_bounds(self):
        exif = (FFMPEG / "libavcodec/exif.c").read_text(encoding="utf-8")
        self.assertIn("for (uint32_t i = 0; i < ifd->count; i++) {", exif)
        imgutils = (FFMPEG / "libavutil/imgutils.c").read_text(encoding="utf-8")
        self.assertIn("(ptrdiff_t)linesizes[0] * h", imgutils)
        self.assertIn("av_malloc((size_t)len*len*sizeof(*s->exp))", (FFMPEG / "libavutil/tx_template.c").read_text(encoding="utf-8"))
        self.assertIn("pos + (int64_t)i * ts->raw_packet_size", (FFMPEG / "libavformat/mpegts.c").read_text(encoding="utf-8"))
        ps = (FFMPEG / "libavcodec/vvc/ps.c").read_text(encoding="utf-8")
        self.assertIn("for (int sample = 0; sample < max; sample++) {", ps)
        dca = (FFMPEG / "libavcodec/dcaenc.c").read_text(encoding="utf-8")
        start = dca.index("static uint32_t set_best_abits_code(")
        self.assertIn("    int i;\n    uint32_t t;", dca[start:start + 300])


if __name__ == "__main__":
    unittest.main()
