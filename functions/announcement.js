const {createHash} = require('node:crypto');

function normalizePhone(raw) {
  let phone = String(raw ?? '').replace(/\D/g, '');
  if (phone.startsWith('880') && phone.length === 13) phone = phone.slice(2);
  return /^01[3-9]\d{8}$/.test(phone) ? phone : '';
}

function announcementMessage(id, data) {
  const title = typeof data.title === 'string' ? data.title.trim() : '';
  const body = typeof data.body === 'string' ? data.body.trim() : '';
  if (!title || !body || !id || id.includes('/')) throw new Error('Invalid announcement');
  if (Buffer.byteLength(title, 'utf8') > 256 || Buffer.byteLength(body, 'utf8') > 2500) {
    throw new Error('Announcement exceeds push message limits');
  }
  const tag = createHash('sha256').update(id).digest('hex');
  // A notification payload is essential: Android displays it without relying
  // on the app's Firestore listener or a running Flutter engine.
  return {
    notification: {title, body},
    data: {kind: 'admin_announcement', notification_id: id},
    android: {
      priority: 'high',
      ttl: 24 * 60 * 60 * 1000,
      notification: {
        channelId: 'br_broadcast_alerts',
        icon: 'ic_stat_rail',
        color: '#009B78',
        sound: 'default',
        tag,
      },
    },
  };
}

const invalidTokens = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

// One invocation at a time (configured in index.js) plus durable per-token
// receipts prevents re-sending successful recipients on an ordinary retry.
// The OS tag is stable even if a crash occurs between send and receipt commit.
async function dispatchAnnouncement({id, data, db, messaging, fieldValue, fieldPath}) {
  if (data.delivery !== 'push' || data.kind !== 'admin_announcement') return {skipped: true};
  const notificationRef = db.collection('notifications').doc(id);
  let message;
  let target;
  try {
    message = announcementMessage(id, data);
    target = data.target === 'all' ? 'all' : normalizePhone(data.targetPhone ?? data.target);
    if (!target) throw new Error('Invalid recipient');
    const sender = normalizePhone(data.sentBy);
    if (!sender) throw new Error('Invalid administrator');
    const administrator = await db.collection('users').doc(sender).get();
    const user = administrator.data();
    if (!user || user.is_blocked === true ||
        !(user.is_admin === true || String(user.role).toLowerCase() === 'admin')) {
      throw new Error('Administrator access required');
    }
  } catch (error) {
    // Permanent validation errors should not retry for days.
    // Infrastructure errors must retry instead of being reported as validation.
    if (!['Invalid announcement', 'Announcement exceeds push message limits',
      'Invalid recipient', 'Invalid administrator', 'Administrator access required'].includes(error.message)) {
      throw error;
    }
    await notificationRef.set({pushStatus: 'failed', pushError: error.message}, {merge: true});
    return {failed: true};
  }

  let query = db.collection('push_devices');
  if (target !== 'all') query = query.where('phone', '==', target);
  query = query.orderBy(fieldPath.documentId()).limit(400);
  let cursor;
  let transientFailure = false;
  const seenTokens = new Set();
  for (;;) {
    const page = await (cursor ? query.startAfter(cursor) : query).get();
    if (page.empty) break;
    cursor = page.docs.at(-1);
    const candidates = page.docs.filter(device => {
      const value = device.data();
      if (value.platform !== 'android' || typeof value.token !== 'string' || !value.token) return false;
      if (seenTokens.has(value.token)) return false;
      seenTokens.add(value.token);
      return true;
    });
    if (!candidates.length) continue;
    const refs = candidates.map(device => db.collection('push_delivery_receipts').doc(id)
      .collection('tokens').doc(createHash('sha256').update(device.data().token).digest('hex')));
    const receipts = await db.getAll(...refs);
    const pending = candidates.map((device, index) => ({device, ref: refs[index]}))
      .filter((_, index) => !receipts[index].exists);
    if (!pending.length) continue;
    const response = await messaging.sendEachForMulticast({
      ...message,
      tokens: pending.map(item => item.device.data().token),
    });
    const batch = db.batch();
    const expired = [];
    response.responses.forEach((result, index) => {
      const item = pending[index];
      if (result.success || invalidTokens.has(result.error?.code)) {
        batch.set(item.ref, {
          status: result.success ? 'sent' : 'expired',
          createdAt: fieldValue.serverTimestamp(),
          expireAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
        });
        if (!result.success) expired.push(item.device);
      } else {
        transientFailure = true;
      }
    });
    await batch.commit();
    for (const device of expired) {
      // Token refresh can occur while a push is in flight; don't delete the
      // replacement registration just because its old token expired.
      await db.runTransaction(async transaction => {
        const current = await transaction.get(device.ref);
        if (current.data()?.token === device.data().token) transaction.delete(device.ref);
      });
    }
  }
  if (transientFailure) throw new Error('Transient FCM delivery failure');
  await notificationRef.set({
    pushStatus: seenTokens.size ? 'sent' : 'no_devices',
    pushRecipientCount: seenTokens.size,
    pushSentAt: fieldValue.serverTimestamp(),
  }, {merge: true});
  return {sent: true, recipientCount: seenTokens.size};
}

module.exports = {normalizePhone, announcementMessage, dispatchAnnouncement};
