const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue, FieldPath} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {dispatchAnnouncement} = require('./announcement');

initializeApp();

exports.deliverAdminAnnouncement = onDocumentCreated({
  document: 'notifications/{notificationId}',
  region: 'asia-south1',
  retry: true,
  maxInstances: 1,
  concurrency: 1,
  timeoutSeconds: 300,
}, async event => {
  if (!event.data) return;
  await dispatchAnnouncement({
    id: event.params.notificationId,
    data: event.data.data(),
    db: getFirestore(),
    messaging: getMessaging(),
    fieldValue: FieldValue,
    fieldPath: FieldPath,
  });
});
