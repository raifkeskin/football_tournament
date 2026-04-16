const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

function normalizePhoneToRaw10(input) {
  const digits = String(input || '').replace(/\D/g, '');
  if (!digits) return '';
  let d = digits;
  if (d.startsWith('90') && d.length >= 12) d = d.slice(2);
  if (d.startsWith('0')) d = d.slice(1);
  if (d.length > 10) d = d.slice(d.length - 10);
  return d;
}

function validPassword(p) {
  const v = String(p || '').trim();
  if (v.length < 6 || v.length > 10) return false;
  const hasDigit = /\d/.test(v);
  const hasSpecial = /[^A-Za-z0-9]/.test(v);
  return hasDigit || hasSpecial;
}

exports.resetPasswordWithOtp = functions.https.onCall(async (data) => {
  const phone = normalizePhoneToRaw10(data && data.phone);
  const otp = String((data && data.otp) || '').trim();
  const newPassword = String((data && data.newPassword) || '');

  if (phone.length !== 10) {
    throw new functions.https.HttpsError('invalid-argument', 'Telefon geçersiz.');
  }
  if (!/^\d{6}$/.test(otp)) {
    throw new functions.https.HttpsError('invalid-argument', 'OTP geçersiz.');
  }
  if (!validPassword(newPassword)) {
    throw new functions.https.HttpsError('invalid-argument', 'Şifre geçersiz.');
  }

  const db = admin.firestore();
  const otpRef = db.collection('otp_requests').doc(phone);
  const otpSnap = await otpRef.get();
  const otpData = otpSnap.exists ? otpSnap.data() : null;
  if (!otpData) {
    throw new functions.https.HttpsError('not-found', 'OTP bulunamadı.');
  }

  const storedCode = String(otpData.code || '').trim();
  const expiresAt = otpData.expiresAt && otpData.expiresAt.toDate ? otpData.expiresAt.toDate() : null;
  if (!expiresAt) {
    throw new functions.https.HttpsError('failed-precondition', 'OTP geçersiz.');
  }
  if (Date.now() > expiresAt.getTime()) {
    throw new functions.https.HttpsError('deadline-exceeded', 'OTP süresi doldu.');
  }
  if (storedCode !== otp) {
    throw new functions.https.HttpsError('permission-denied', 'OTP hatalı.');
  }

  const usersSnap = await db.collection('users').where('phone', '==', phone).limit(1).get();
  if (usersSnap.empty) {
    throw new functions.https.HttpsError('not-found', 'Kullanıcı bulunamadı.');
  }
  const userDoc = usersSnap.docs[0];
  const uid = userDoc.id;

  await admin.auth().updateUser(uid, { password: newPassword });
  await otpRef.delete();

  return { ok: true };
});

