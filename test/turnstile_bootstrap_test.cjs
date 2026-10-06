const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

// Exercise the actual embedded script against the public Turnstile interface.
const dart = fs.readFileSync('lib/services/turnstile_session.dart', 'utf8');
const script = dart.split('static final bootstrap')[1]
  .match(/'''([\s\S]*?)'''/)[1]
  .replace(/\$\{jsonEncode\('[^']+'\)\}/g, "'test-site-key'");
const messages = [];
let options;
let renders = 0, executions = 0, resets = 0, loads = 0;
const context = vm.createContext({
  window: { flutter_inappwebview: {
    callHandler: (name, message) => messages.push(message),
  } },
  document: {
    createElement: () => ({ remove() {} }),
    head: { appendChild: element => { loads++; element.onload(); } },
  },
  turnstile: {
    render: (selector, config) => {
      renders++; options = config;
      assert.equal(config.execution, 'execute');
      assert.equal(config.retry, 'never');
      assert.equal(config['refresh-expired'], 'manual');
      assert.equal(config['refresh-timeout'], 'manual');
      return 7;
    },
    execute: id => { assert.equal(id, 7); executions++; },
    reset: id => { assert.equal(id, 7); resets++; },
  },
});

vm.runInContext(script, context);
vm.runInContext(script, context);
assert.equal(loads, 1);
assert.equal(renders, 1);
assert.equal(executions, 0, 'Preloading must not mint a token');
assert.equal(messages.at(-1).status, 'READY');

context.window.__railBegin(1);
options.callback('first-token');
assert.equal(messages.at(-1).requestId, 1);
assert.equal(messages.at(-1).token, 'first-token');
context.window.__railBegin(2);
options['before-interactive-callback']();
assert.equal(messages.at(-1).requestId, 2);
assert.equal(messages.at(-1).status, 'INTERACTIVE');
context.window.__railCancel();
options.callback('cancelled-token');
assert.equal(messages.at(-1).requestId, null, 'Late result must have no booking owner');
context.window.__railBegin(3);
options.callback('third-token');
assert.equal(messages.at(-1).requestId, 3);
assert.equal(renders, 1);
assert.equal(loads, 1);
assert.equal(executions, 3);
assert.equal(resets, 2);
console.log('Turnstile script: idle preload, explicit execution, reset and cancellation passed.');
