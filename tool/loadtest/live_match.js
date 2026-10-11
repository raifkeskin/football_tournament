// Lig Masası maç günü testi (k6): canlı maçı izleyen kalabalık.
//
// Her sanal kullanıcı = maç detayını açık tutan bir kişi: uygulamadaki gibi
// matches (id=...) ve match_events (match_id=...) kanallarına abone olur;
// maç güncellenince sinyal gelir ve uygulama gibi maçı + olayları yeniden
// okur. Skoru yazan taraf live_match.sh içindeki psql döngüsüdür (demo maçta
// skoru aynı değerle günceller: bildirim tetiklenmez, veri değişmez).
//
// Ölçülen: güncellemenin aboneye ulaşma süresi (veritabanı saatinden), sinyal
// sonrası yeniden okuma süresi, kanal katılımı ve hatalar.
//
// Çalıştırma: tool/loadtest/live_match.sh smoke | full
import http from 'k6/http';
import ws from 'k6/ws';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

const URL = __ENV.SUPABASE_URL;
const KEY = __ENV.SUPABASE_ANON_KEY;
const MODE = __ENV.MODE || 'smoke';
const MATCH = __ENV.MATCH_ID;
const DEMO_EMAIL = __ENV.DEMO_EMAIL || '5000000000@masterclass.com';
const DEMO_PASSWORD = __ENV.DEMO_PASSWORD || 'demo2026';

const wsJoinOk = Rate('ws_join_ok');
const wsErrors = Counter('ws_errors');
const deliveryMs = Trend('delivery_ms', true);
const delivered = Counter('updates_delivered');
const refetchMs = Trend('refetch_ms', true);
const restErrors = Rate('rest_errors');

// smoke 5 izleyici ~2 dk; full 50 → 100 → 150 (~10 dk).
const STAGES = MODE === 'full'
  ? [
      { duration: '1m', target: 50 },
      { duration: '2m', target: 50 },
      { duration: '1m', target: 100 },
      { duration: '2m', target: 100 },
      { duration: '1m', target: 150 },
      { duration: '3m', target: 150 },
      { duration: '30s', target: 0 },
    ]
  : [
      { duration: '20s', target: 5 },
      { duration: '1m30s', target: 5 },
      { duration: '10s', target: 0 },
    ];

export const options = {
  setupTimeout: '60s',
  scenarios: {
    fans: { executor: 'ramping-vus', exec: 'fan', stages: STAGES, gracefulRampDown: '30s' },
  },
  thresholds: {
    rest_errors: [{ threshold: 'rate<0.10', abortOnFail: true, delayAbortEval: '1m' }],
    ws_join_ok: [{ threshold: 'rate>0.90', abortOnFail: true, delayAbortEval: '1m' }],
  },
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

function headers(token) {
  return { apikey: KEY, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
}

function get(token, path, name) {
  const res = http.get(`${URL}/rest/v1/${path}`, { headers: headers(token), tags: { name } });
  restErrors.add(res.status >= 400 || res.status === 0);
  return res;
}

export function setup() {
  if (!MATCH) throw new Error('MATCH_ID gerekli');
  const res = http.post(
    `${URL}/auth/v1/token?grant_type=password`,
    JSON.stringify({ email: DEMO_EMAIL, password: DEMO_PASSWORD }),
    { headers: { apikey: KEY, 'Content-Type': 'application/json' } },
  );
  if (res.status !== 200) throw new Error(`demo girişi başarısız: ${res.status}`);
  return { token: res.json('access_token') };
}

function join(socket, ref, table, column, token) {
  socket.send(JSON.stringify({
    topic: `realtime:sig:${table}:${column}=${MATCH}:${__VU}-${__ITER}`,
    event: 'phx_join',
    ref: String(ref),
    join_ref: String(ref),
    payload: {
      config: {
        broadcast: { ack: false, self: false },
        presence: { key: '' },
        postgres_changes: ['INSERT', 'UPDATE', 'DELETE'].map((event) => ({
          event, schema: 'public', table, filter: `${column}=eq.${MATCH}`,
        })),
      },
      access_token: token,
    },
  }));
}

export function fan(data) {
  const t = data.token;
  const wsUrl = `${URL.replace('https://', 'wss://')}/realtime/v1/websocket?apikey=${KEY}&vsn=1.0.0`;
  // Ekran açılışı: maç + olaylar.
  get(t, `matches?select=*&id=eq.${MATCH}`, 'match');
  get(t, `match_events?select=*&match_id=eq.${MATCH}&order=minute.asc`, 'match_events');
  let ref = 0;
  const res = ws.connect(wsUrl, {}, (socket) => {
    socket.on('open', () => {
      join(socket, ++ref, 'matches', 'id', t);
      join(socket, ++ref, 'match_events', 'match_id', t);
      socket.setInterval(() => {
        socket.send(JSON.stringify({ topic: 'phoenix', event: 'heartbeat', payload: {}, ref: String(++ref) }));
      }, 25000);
      // Maçı 2-4 dk izler, sonra çıkar (yerine yeni izleyici gelir).
      socket.setTimeout(() => socket.close(), 120000 + Math.random() * 120000);
    });
    socket.on('message', (msg) => {
      let m;
      try { m = JSON.parse(msg); } catch (_) { return; }
      if (m.event === 'phx_reply' && m.payload && m.payload.response && m.payload.response.postgres_changes) {
        wsJoinOk.add(m.payload.status === 'ok');
        return;
      }
      if (m.event === 'phx_reply' && m.payload && m.payload.status === 'error') {
        wsJoinOk.add(false);
        return;
      }
      if (m.event === 'system' && m.payload && m.payload.status === 'error') {
        wsErrors.add(1);
        return;
      }
      if (m.event === 'postgres_changes') {
        const rec = (m.payload && m.payload.data && m.payload.data.record) || {};
        if (rec.updated_at) deliveryMs.add(Date.now() - Date.parse(rec.updated_at));
        delivered.add(1);
        // Uygulama sinyalde maçı ve olayları yeniden okur.
        const s = Date.now();
        get(t, `matches?select=*&id=eq.${MATCH}`, 'match_refetch');
        get(t, `match_events?select=*&match_id=eq.${MATCH}&order=minute.asc`, 'events_refetch');
        refetchMs.add(Date.now() - s);
      }
    });
    socket.on('error', () => wsErrors.add(1));
  });
  check(res, { 'ws 101': (r) => r && r.status === 101 });
  if (!res || res.status !== 101) {
    wsJoinOk.add(false);
    wsErrors.add(1);
    sleep(5);
  }
}
