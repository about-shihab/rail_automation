const {test} = require('node:test');
const assert = require('node:assert/strict');
const {normalizePhone, announcementMessage, dispatchAnnouncement} = require('../announcement');

function fixture(devices, results) {
  const store = new Map([
    ['users/01813570430', {is_admin: true}],
    ...Object.entries(devices).map(([id, data]) => ['push_devices/' + id, data]),
  ]);
  const calls = [];
  function ref(path) {
    return {
      path,
      get: async () => snapshot(path),
      set: async data => store.set(path, {...store.get(path), ...data}),
      collection: name => collection(path + '/' + name),
    };
  }
  function snapshot(path) {
    const value = structuredClone(store.get(path));
    return {id: path.split('/').at(-1), ref: ref(path), exists: value !== undefined, data: () => value};
  }
  function collection(path, where, limit = 400, after) {
    return {
      doc: id => ref(path + '/' + id),
      where: (field, _, value) => collection(path, [field, value], limit, after),
      orderBy: () => collection(path, where, limit, after),
      limit: value => collection(path, where, value, after),
      startAfter: value => collection(path, where, limit, value.id),
      get: async () => {
        const docs = [...store.keys()].filter(key => key.startsWith(path + '/') &&
          !key.slice(path.length + 1).includes('/')).sort().map(snapshot)
          .filter(doc => (!where || doc.data()[where[0]] === where[1]) && (!after || doc.id > after))
          .slice(0, limit);
        return {docs, empty: !docs.length};
      },
    };
  }
  const db = {
    collection,
    getAll: async (...refs) => refs.map(item => snapshot(item.path)),
    batch: () => {
      const writes = [];
      return {set: (item, data) => writes.push([item.path, data]), commit: async () => {
        writes.forEach(([path, data]) => store.set(path, data));
      }};
    },
    runTransaction: async callback => callback({
      get: async item => snapshot(item.path),
      delete: item => store.delete(item.path),
    }),
  };
  const messaging = {sendEachForMulticast: async message => {
    calls.push(message);
    return {responses: results ? await results(message, store) : message.tokens.map(() => ({success: true}))};
  }};
  return {store, calls, send: data => dispatchAnnouncement({
    id: 'announcement1',
    data: {delivery: 'push', kind: 'admin_announcement', title: 'Notice', body: 'Message', target: 'all', sentBy: '01813570430', ...data},
    db, messaging,
    fieldValue: {serverTimestamp: () => new Date()},
    fieldPath: {documentId: () => '__name__'},
  })};
}

test('exact phone normalization prevents suffix matching and malformed targeting', () => {
  assert.equal(normalizePhone('+8801813570430'), '01813570430');
  assert.equal(normalizePhone('01813-570430'), '01813570430');
  assert.equal(normalizePhone('570430'), '');
  assert.equal(normalizePhone(''), '');
});

test('message contains OS notification, high priority, channel, stable tag, and safe size', () => {
  const message = announcementMessage('doc123', {title: 'Notice', body: 'Important update'});
  assert.equal(message.notification.title, 'Notice');
  assert.equal(message.android.priority, 'high');
  assert.equal(message.android.notification.channelId, 'br_broadcast_alerts');
  assert.equal(message.android.notification.tag, announcementMessage('doc123', {title: 'Changed', body: 'Body'}).android.notification.tag);
  assert.deepEqual(message.data, {kind: 'admin_announcement', notification_id: 'doc123'});
  assert.throws(() => announcementMessage('doc123', {title: 'T', body: 'ক'.repeat(1000)}), /limits/);
});

test('all-user announcements include anonymous devices; targeted messages only include exact phone', async () => {
  const data = {a: {platform: 'android', token: 'a', phone: '01813570430'}, b: {platform: 'android', token: 'b', phone: null}, c: {platform: 'android', token: 'c', phone: '01700000000'}};
  const all = fixture(data);
  await all.send({});
  assert.deepEqual(all.calls[0].tokens, ['a', 'b', 'c']);
  const targeted = fixture(data);
  await targeted.send({target: '+8801813570430'});
  assert.deepEqual(targeted.calls[0].tokens, ['a']);
});

test('legacy Firestore alerts and non-admin creators never produce pushes', async () => {
  const f = fixture({a: {platform: 'android', token: 'a'}});
  await f.send({delivery: 'firestore'});
  assert.equal(f.calls.length, 0);
  await f.send({sentBy: '01700000000'});
  assert.equal(f.calls.length, 0);
  assert.equal(f.store.get('notifications/announcement1').pushStatus, 'failed');
});

test('retry only sends failed tokens, while duplicate events do not resend successes', async () => {
  let attempt = 0;
  const f = fixture({a: {platform: 'android', token: 'a'}, b: {platform: 'android', token: 'b'}}, message => {
    attempt++;
    return message.tokens.map(token => attempt === 1 && token === 'b'
      ? {success: false, error: {code: 'messaging/internal-error'}} : {success: true});
  });
  await assert.rejects(f.send({}), /Transient/);
  await f.send({});
  assert.deepEqual(f.calls[1].tokens, ['b']);
  await f.send({});
  assert.equal(f.calls.length, 2);
});

test('expired tokens are removed, while concurrently refreshed registrations survive', async () => {
  const f = fixture({a: {platform: 'android', token: 'old-a'}, b: {platform: 'android', token: 'old-b'}}, (message, store) => {
    store.set('push_devices/b', {platform: 'android', token: 'new-b'});
    return message.tokens.map(() => ({success: false, error: {code: 'messaging/registration-token-not-registered'}}));
  });
  await f.send({});
  assert.equal(f.store.has('push_devices/a'), false);
  assert.equal(f.store.get('push_devices/b').token, 'new-b');
});

test('fanout paginates safely below the FCM multicast limit', async () => {
  const devices = Object.fromEntries(Array.from({length: 401}, (_, i) => [String(i).padStart(4, '0'), {platform: 'android', token: 'token' + i}]));
  const f = fixture(devices);
  await f.send({});
  assert.deepEqual(f.calls.map(call => call.tokens.length), [400, 1]);
});

test('no registered recipients is reported rather than claiming a delivery', async () => {
  const f = fixture({});
  await f.send({});
  assert.equal(f.store.get('notifications/announcement1').pushStatus, 'no_devices');
});
