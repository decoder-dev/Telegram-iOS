import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
FFMPEG = ROOT / 'submodules/ffmpeg/Sources/FFMpeg/ffmpeg-8.1.2/libavcodec'


class FfmpegUnsignedBounds(unittest.TestCase):
    def test_jpeg2000_tile_part_length_is_clamped_before_subtraction(self):
        source = (FFMPEG / 'jpeg2000_parser.c').read_text(encoding='utf-8')
        self.assertIn('tile_part_size > 9 ? tile_part_size - 9 : 0', source)
        self.assertNotIn('(state64 & 0xFFFFFFFF) - 9 > 0', source)

    def test_rav1e_pass_input_uses_a_checked_remaining_length(self):
        source = (FFMPEG / 'librav1e.c').read_text(encoding='utf-8')
        function = source.split('static int set_stats(AVCodecContext *avctx)', 1)[1].split('\nstatic av_cold int librav1e_encode_close', 1)[0]
        self.assertIn('ctx->pass_size > 0', function)
        self.assertIn('ctx->pass_pos < (size_t)ctx->pass_size', function)
        self.assertIn('(size_t)ctx->pass_size - ctx->pass_pos', function)
        self.assertIn('ctx->pass_data + ctx->pass_pos, remaining', function)
        self.assertIn('(size_t)ret > remaining', function)
        self.assertNotIn('ctx->pass_size - ctx->pass_pos > 0', function)

    def test_bmp_palette_checks_compare_bounds_without_unsigned_difference(self):
        source = (FFMPEG / 'bmp.c').read_text(encoding='utf-8')
        self.assertEqual(source.count('hsize > ihsize + 14U'), 2)
        self.assertNotIn('hsize - ihsize - 14 > 0', source)


if __name__ == '__main__':
    unittest.main()
