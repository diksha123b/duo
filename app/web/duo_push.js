// Small bridge between the Flutter app and the browser's push APIs.
window.duoPush = {
  supported() {
    return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  },
  permission() {
    return 'Notification' in window ? Notification.permission : 'denied';
  },
  async registration() {
    return navigator.serviceWorker.register('push-sw.js');
  },
  /** Asks permission (must follow a tap) and returns the subscription as JSON, or '' if refused. */
  async subscribe(publicKey) {
    const permission = await Notification.requestPermission();
    if (permission !== 'granted') return '';
    const reg = await this.registration();
    await navigator.serviceWorker.ready;
    const key = Uint8Array.from(
      atob(publicKey.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (publicKey.length % 4)) % 4)),
      (c) => c.charCodeAt(0),
    );
    const sub = (await reg.pushManager.getSubscription()) ||
      (await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key }));
    return JSON.stringify(sub);
  },
  /** The current subscription's endpoint, or '' if none. */
  async current() {
    if (!this.supported()) return '';
    const reg = await navigator.serviceWorker.getRegistration('push-sw.js');
    const sub = reg && (await reg.pushManager.getSubscription());
    return sub ? sub.endpoint : '';
  },
  /** Unsubscribes this browser; returns the old endpoint, or ''. */
  async unsubscribe() {
    if (!this.supported()) return '';
    const reg = await navigator.serviceWorker.getRegistration('push-sw.js');
    const sub = reg && (await reg.pushManager.getSubscription());
    if (!sub) return '';
    const endpoint = sub.endpoint;
    await sub.unsubscribe();
    return endpoint;
  },
};
