const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('lib/services/web_session_service.dart', 'utf8');
const script = source.match(/iosCheckoutLocationScript = r'''([\s\S]*?)'''/)[1];

function browser(native) {
  const timers = new Map();
  let id = 0;
  const context = {navigator: {geolocation: {getCurrentPosition: native}},
    setTimeout(fn, ms) { timers.set(++id, {fn, ms}); return id; },
    clearTimeout(id) { timers.delete(id); }};
  vm.runInNewContext(script, context);
  return {geo: context.navigator.geolocation, timers, context};
}

test('hung location rejects so Railway can continue payment without location', async () => {
  let lateSuccess;
  const {geo, timers} = browser((success, failure, options) => {
    lateSuccess = success;
    assert.equal(options.timeout, 5000);
  });
  let submitted = 0;
  // Mirrors Railway's location Promise -> catch(null) -> submit flow.
  const payment = new Promise((resolve, reject) => geo.getCurrentPosition(resolve, reject,
    {enableHighAccuracy: true})).catch(() => null).then(location => {
      assert.equal(location, null);
      submitted++;
    });
  assert.equal(submitted, 0);
  const timer = [...timers.values()][0];
  assert.equal(timer.ms, 5000);
  timer.fn();
  await payment;
  lateSuccess({coords: {latitude: 1}});
  assert.equal(submitted, 1);
});

test('successful location and native errors settle once and clear timeout', () => {
  for (const success of [true, false]) {
    let nativeSuccess, nativeFailure;
    const {geo, timers} = browser((ok, fail) => { nativeSuccess = ok; nativeFailure = fail; });
    const values = [];
    geo.getCurrentPosition(v => values.push(v), e => values.push(e), {timeout: 1200});
    assert.equal([...timers.values()][0].ms, 1200);
    (success ? nativeSuccess : nativeFailure)('result');
    nativeFailure('late error');
    assert.deepEqual(values, ['result']);
    assert.equal(timers.size, 0);
  }
});

test('repeated installation does not wrap again', () => {
  const {geo, context} = browser(() => {});
  const first = geo.getCurrentPosition;
  vm.runInNewContext(script, context);
  assert.equal(geo.getCurrentPosition, first);
});
