// web/push.js içindeki window.mfPush yardımcılarına köprü.
import 'dart:js_interop';

@JS('mfPush.state')
external JSString _state();

@JS('mfPush.subscribe')
external JSPromise<JSString> _subscribe(JSString vapidKey);

@JS('mfPush.current')
external JSPromise<JSString> _current();

@JS('mfPush.unsubscribe')
external JSPromise<JSString> _unsubscribe();

@JS('mfPush.isIos')
external JSBoolean _isIos();

String pushState() {
  try {
    return _state().toDart;
  } catch (_) {
    return 'unsupported';
  }
}

Future<String> pushSubscribe(String vapidKey) async =>
    (await _subscribe(vapidKey.toJS).toDart).toDart;

Future<String> pushCurrent() async {
  try {
    return (await _current().toDart).toDart;
  } catch (_) {
    return '';
  }
}

Future<String> pushUnsubscribe() async {
  try {
    return (await _unsubscribe().toDart).toDart;
  } catch (_) {
    return '';
  }
}

bool pushIsIos() {
  try {
    return _isIos().toDart;
  } catch (_) {
    return false;
  }
}
