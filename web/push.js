// Flutter'dan çağrılan Web Push yardımcıları (window.mfPush).
(function () {
  function urlB64ToUint8Array(base64) {
    const padding = '='.repeat((4 - (base64.length % 4)) % 4);
    const raw = atob((base64 + padding).replace(/-/g, '+').replace(/_/g, '/'));
    return Uint8Array.from([...raw].map((c) => c.charCodeAt(0)));
  }

  function isIos() {
    return /iphone|ipad|ipod/i.test(navigator.userAgent) ||
      (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  }

  function isStandalone() {
    return window.matchMedia('(display-mode: standalone)').matches ||
      window.navigator.standalone === true;
  }

  async function registration() {
    return navigator.serviceWorker.register('/push-sw.js?v=1', { scope: '/push/' });
  }

  // 'unsupported' | 'ios-install' | 'denied' | 'granted' | 'default'
  function state() {
    const supported = 'serviceWorker' in navigator && 'PushManager' in window &&
      'Notification' in window;
    if (!supported) return isIos() && !isStandalone() ? 'ios-install' : 'unsupported';
    return Notification.permission;
  }

  // Abone olur; {endpoint, p256dh, auth} JSON metni döner ya da hata fırlatır.
  async function subscribe(vapidKey) {
    const permission = await Notification.requestPermission();
    if (permission !== 'granted') throw new Error('permission-' + permission);
    const reg = await registration();
    await navigator.serviceWorker.ready;
    let sub = await reg.pushManager.getSubscription();
    if (!sub) {
      sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlB64ToUint8Array(vapidKey),
      });
    }
    const json = sub.toJSON();
    return JSON.stringify({ endpoint: json.endpoint, p256dh: json.keys.p256dh, auth: json.keys.auth });
  }

  // Mevcut aboneliğin endpoint'i (yoksa boş).
  async function current() {
    if (!('serviceWorker' in navigator)) return '';
    const reg = await navigator.serviceWorker.getRegistration('/push/');
    const sub = reg ? await reg.pushManager.getSubscription() : null;
    return sub ? sub.endpoint : '';
  }

  // Aboneliği iptal eder; iptal edilen endpoint'i döner.
  async function unsubscribe() {
    if (!('serviceWorker' in navigator)) return '';
    const reg = await navigator.serviceWorker.getRegistration('/push/');
    const sub = reg ? await reg.pushManager.getSubscription() : null;
    if (!sub) return '';
    const endpoint = sub.endpoint;
    await sub.unsubscribe();
    return endpoint;
  }

  window.mfPush = { state, subscribe, current, unsubscribe, isIos };
})();
