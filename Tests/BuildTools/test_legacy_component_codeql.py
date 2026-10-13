import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


class LegacyComponentCodeQLFixes(unittest.TestCase):
    def test_lmdb_size_multiplication_is_widened_before_multiplying(self):
        source = (ROOT / "submodules/LegacyComponents/Sources/mdb.c").read_text(encoding="utf-8")
        self.assertIn(
            "data->mv_size = (size_t)NUMKEYS(mx->mc_pg[mx->mc_top]) *",
            source,
        )

    def test_lmdb_page_merge_uses_wide_loop_index(self):
        source = (ROOT / "submodules/LegacyComponents/Sources/mdb.c").read_text(encoding="utf-8")
        start = source.index("mdb_page_merge(MDB_cursor *csrc, MDB_cursor *cdst)\n{")
        end = source.index("/** Copy the contents of a cursor.", start)
        merge = source[start:end]
        self.assertRegex(merge, r"unsigned int\s+i;")
        self.assertIn("i < NUMKEYS(csrc->mc_pg[csrc->mc_top])", merge)

    def test_nanosvg_does_not_test_nonnull_input_pointers(self):
        source = (ROOT / "submodules/Svg/LegacyImpl/Sources/nanosvg.h").read_text(encoding="utf-8")
        self.assertNotIn("if (name && value)", source)
        self.assertIn("attr[nattr++] = name;\n\t\tattr[nattr++] = value;", source)


if __name__ == "__main__":
    unittest.main()
