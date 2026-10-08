const { test } = require('node:test');
const assert = require('node:assert/strict');
const Readability = require('../../submodules/TelegramUI/Resources/Readability/Readability.js');

function normalize(href) {
  let removed = false, result = href;
  const link = {
    getAttribute: () => href,
    setAttribute: (_, value) => { result = value; },
    childNodes: [{ nodeType: 3 }], textContent: 'link text',
    parentNode: { replaceChild: () => { removed = true; } },
  };
  const reader = Object.create(Readability.prototype);
  reader._doc = { baseURI: 'https://example.com/article', documentURI: 'https://example.com/article', createTextNode: text => ({ text }) };
  reader._getAllNodesWithTag = (_, tags) => tags[0] === 'a' ? [link] : [];
  reader._fixRelativeUris({});
  return { removed, result };
}

test('reader removes executable URLs with case and control-character obfuscation', () => {
  for (const href of ['javascript:alert(1)', 'JaVaScRiPt:alert(1)', '  javascript:alert(1)', 'java\tscript:alert(1)', 'java\nscript:alert(1)', '\rjavascript:alert(1)']) {
    assert.equal(normalize(href).removed, true, JSON.stringify(href));
  }
});

test('reader preserves navigation links and resolves relative URLs', () => {
  assert.deepEqual(normalize('../page'), { removed: false, result: 'https://example.com/page' });
  assert.deepEqual(normalize('#section'), { removed: false, result: '#section' });
  assert.equal(normalize('https://example.com/javascript:guide').removed, false);
});
