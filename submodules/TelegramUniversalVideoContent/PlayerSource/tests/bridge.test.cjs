const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function load(name, extras = {}) {
  const context = vm.createContext({ EventTarget, Event, Uint8Array, atob, btoa, console, ...extras });
  let source = fs.readFileSync(path.join(process.env.PLAYER_TEST_SOURCE_ROOT || path.join(__dirname, '../src/'), name + '.js'), 'utf8');
  source = source.replace(/^import .*$/gm, '').replace(/export /g, '');
  vm.runInContext(source + `\nthis.Subject = ${name === 'index' ? 'HlsPlayerInstance' : name};`, context);
  return { Subject: context.Subject, context };
}

function xhrSetup() {
  let complete;
  const window = { nextInternalId: 0, bridgeInvokeAsync: (_, __, method) => method === 'load' ? new Promise(resolve => { complete = resolve; }) : Promise.resolve({}) };
  const { Subject } = load('XMLHttpRequestStub', { window });
  return { xhr: new Subject(), complete: data => complete(data) };
}

test('empty HTTP error response completes and headers are case insensitive', async () => {
  const { xhr, complete } = xhrSetup();
  const events = [];
  for (const name of ['load', 'loadend']) xhr.addEventListener(name, () => events.push(name));
  xhr.open('GET', 'test'); xhr.send();
  complete({ status: 404, statusText: 'Not Found', responseData: '', responseHeaders: { 'Content-Type': 'text/html' } });
  await Promise.resolve();
  assert.equal(xhr.readyState, 4);
  assert.equal(xhr.response, '');
  assert.equal(xhr.getResponseHeader('Content-Type'), 'text/html');
  assert.deepEqual(events, ['load', 'loadend']);
});

test('aborted request ignores a delayed native completion', async () => {
  const { xhr, complete } = xhrSetup();
  let loads = 0;
  xhr.addEventListener('load', () => loads++);
  xhr.open('GET', 'test'); xhr.send(); xhr.abort();
  complete({ status: 200, responseData: 'YQ==' });
  await Promise.resolve();
  assert.equal(loads, 0);
  assert.equal(xhr.readyState, 0);
  assert.equal(xhr.response, '');
});

test('reopening clears request headers and invalidates the previous response', async () => {
  const { xhr, complete } = xhrSetup();
  xhr.open('GET', 'old'); xhr.setRequestHeader('Range', 'bytes=0-1'); xhr.send();
  xhr.open('GET', 'new');
  complete({ status: 200, responseData: 'YQ==' });
  await Promise.resolve();
  assert.equal(xhr.readyState, 1);
  assert.equal(Object.keys(xhr._requestHeaders).length, 0);
});

test('network error reaches DONE before error and loadend', async () => {
  const { xhr, complete } = xhrSetup();
  let state;
  xhr.addEventListener('error', () => { state = xhr.readyState; });
  xhr.open('GET', 'test'); xhr.send(); complete({ error: 1 });
  await Promise.resolve();
  assert.equal(state, 4);
});

test('text-only responses do not assign to the read-only response getter', async () => {
  const { xhr, complete } = xhrSetup();
  xhr.open('GET', 'test'); xhr.send(); complete({ status: 200, responseText: 'hello' });
  await Promise.resolve();
  assert.equal(xhr.response, 'hello');
  assert.equal(xhr.readyState, 4);
});

test('repeated player status updates retain one timer, paused playback retains none', () => {
  const timers = new Map(); let nextTimer = 0;
  const window = { webkit: { messageHandlers: { performAction: { postMessage() {} } } } };
  const { Subject } = load('index', { window, global: { btoa, atob }, URL: {}, MediaSourceStub: class {}, SourceBufferStub: class {}, XMLHttpRequestStub: class {},
    VideoElementStub: class { constructor() { this.paused = false; this.readyState = 4; this.currentTime = 0; } },
    setTimeout: fn => { const id = ++nextTimer; timers.set(id, fn); return id; }, clearTimeout: id => timers.delete(id) });
  const player = new Subject(1);
  player.hls = { levels: [], currentLevel: 0 };
  for (let i = 0; i < 100; ++i) player.refreshPlayerStatus();
  assert.equal(timers.size, 1);
  player.video.paused = true; player.refreshPlayerStatus();
  assert.equal(timers.size, 0);
});
