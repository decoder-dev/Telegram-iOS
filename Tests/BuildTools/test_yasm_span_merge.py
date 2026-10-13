import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


class YasmSpanMerge(unittest.TestCase):
    def test_merge_copies_before_releasing_original_and_keeps_it_on_oom(self):
        source = (ROOT / 'third-party/yasm/yasm-1.3.0/tools/re2c/code.c').read_text(encoding='utf-8')
        merge = source.split('nSpans = merge(span, s, to);', 1)[1].split('\n\t\t    break;', 1)[0]

        allocation = merge.index('Span *merged = nSpans ? malloc(sizeof(Span)*nSpans) : NULL;')
        copy = merge.index('memcpy(merged, span, nSpans*sizeof(Span));')
        release = merge.index('free(s->go.span);')
        update = merge.index('s->go.span = merged;')
        self.assertLess(allocation, copy)
        self.assertLess(copy, release)
        self.assertLess(release, update)
        self.assertLess(merge.index('if(nSpans)'), copy)
        self.assertIn('if(nSpans == 0 || merged)', merge)
        self.assertNotIn('memcpy(s->go.span, span', merge)


if __name__ == '__main__':
    unittest.main()
