// Lig Masası yük testi (k6). Yalnızca OKUMA yapar; veriye yazmaz.
//
// Her sanal kullanıcı = uygulamayı açık tutan bir kişi:
//  - "realtime" senaryosu: bir websocket bağlantısı, uygulamadaki gibi
//    3-5 postgres_changes kanalı (matches / match_events / groups / news),
//    25 sn'de bir heartbeat.
//  - "browse" senaryosu: ana sayfa, fikstür, puan durumu, maç detayı,
//    haberler ve bildirim sayısı okumaları; aralarda 5-20 sn düşünme süresi.
// Giriş bir kez (setup) demo hesapla yapılır, belirteç tüm kullanıcılara
// paylaştırılır (aynı hesapla yüzlerce giriş Supabase giriş sınırına takılır).
//
// Çalıştırma: tool/loadtest/run.sh smoke | full
import http from 'k6/http';
import ws from 'k6/ws';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

const URL = __ENV.SUPABASE_URL;
const KEY = __ENV.SUPABASE_ANON_KEY;
const MODE = __ENV.MODE || 'smoke';
const DEMO_EMAIL = __ENV.DEMO_EMAIL || '5000000000@masterclass.com';
const DEMO_PASSWORD = __ENV.DEMO_PASSWORD || 'demo2026';

// Okunacak sezonlar: canlı turnuva + demo ligler (veri çeşitliliği için).
const SEASONS = (__ENV.SEASONS ||
  'eefb9a2a-f156-4deb-bcbf-9115acc7635f,1b20d366-5f1c-478b-8111-01301bcf2e2a,' +
  '2b324b96-4611-42d8-aea1-28db8285b491,7a0eb379-733c-4ea1-9412-47c8531cd7e8').split(',');

const wsJoinOk = Rate('ws_join_ok');
const wsJoinTime = Trend('ws_join_ms', true);
const wsErrors = Counter('ws_errors');
const wsTooMany = Counter('ws_too_many_errors');
const restErrors = Rate('rest_errors');

// Kademeler: smoke 5 kullanıcı ~2 dk; full 20 → 50 → 100 → 150 (~28 dk).
const STAGES = MODE === 'full'
  ? [
      { duration: '2m', target: 20 },
      { duration: '4m', target: 20 },
      { duration: '2m', target: 50 },
      { duration: '5m', target: 50 },
      { duration: '2m', target: 100 },
      { duration: '5m', target: 100 },
      { duration: '2m', target: 150 },
      { duration: '5m', target: 150 },
      { duration: '1m', target: 0 },
    ]
  : [
      { duration: '30s', target: 5 },
      { duration: '1m', target: 5 },
      { duration: '15s', target: 0 },
    ];

export const options = {
  setupTimeout: '60s',
  scenarios: {
    realtime: { executor: 'ramping-vus', exec: 'realtime', stages: STAGES, gracefulRampDown: '30s' },
    browse: { executor: 'ramping-vus', exec: 'browse', stages: STAGES, gracefulRampDown: '30s' },
  },
  thresholds: {
    // Hata oranı %10'u geçerse test kendiliğinden durur (canlı kullanıcılar
    // etkilenmesin).
    rest_errors: [{ threshold: 'rate<0.10', abortOnFail: true, delayAbortEval: '1m' }],
    ws_join_ok: [{ threshold: 'rate>0.90', abortOnFail: true, delayAbortEval: '1m' }],
    http_req_duration: ['p(95)<2000'],
  },
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

function headers(token) {
  return {
    apikey: KEY,
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  };
}

function get(token, path, name) {
  const res = http.get(`${URL}/rest/v1/${path}`, { headers: headers(token), tags: { name } });
  restErrors.add(res.status >= 400 || res.status === 0);
  check(res, { [`${name} 2xx`]: (r) => r.status >= 200 && r.status < 300 });
  return res;
}

export function setup() {
  const res = http.post(
    `${URL}/auth/v1/token?grant_type=password`,
    JSON.stringify({ email: DEMO_EMAIL, password: DEMO_PASSWORD }),
    { headers: { apikey: KEY, 'Content-Type': 'application/json' } },
  );
  if (res.status !== 200) throw new Error(`demo girişi başarısız: ${res.status} ${res.body}`);
  const token = res.json('access_token');
  // Maç detayı için her sezondan birkaç maç kimliği.
  const matches = {};
  for (const s of SEASONS) {
    const r = http.get(`${URL}/rest/v1/matches?select=id&season_id=eq.${s}&limit=10`, { headers: headers(token) });
    matches[s] = r.status === 200 ? r.json().map((m) => m.id) : [];
  }
  return { token, matches };
}

function pick(list) {
  return list[Math.floor(Math.random() * list.length)];
}

export function browse(data) {
  const t = data.token;
  const season = pick(SEASONS);
  // Ana sayfa / fikstür / puan durumu: sezonun maçları, grupları, takımları.
  get(t, `matches?select=*&season_id=eq.${season}&order=match_date.asc`, 'matches_season');
  get(t, `groups?select=*&season_id=eq.${season}`, 'groups');
  get(t, `season_teams?select=team_id,group_id&season_id=eq.${season}`, 'season_teams');
  get(t, `teams?select=id,name,logo_url,first_color,second_color`, 'teams');
  sleep(5 + Math.random() * 15);
  // Maç detayı: maç, olaylar, kadro.
  const ids = data.matches[season] || [];
  if (ids.length) {
    const m = pick(ids);
    get(t, `matches?select=*&id=eq.${m}`, 'match');
    get(t, `match_events?select=*&match_id=eq.${m}`, 'match_events');
    get(t, `match_rosters?select=*&match_id=eq.${m}`, 'match_rosters');
  }
  sleep(5 + Math.random() * 15);
  // Haberler + istatistik okuması + zil sayacı.
  get(t, `news?select=*&season_id=eq.${season}&order=created_at.desc&limit=20`, 'news');
  get(t, `season_team_players?select=player_id,team_id,jersey_number&season_id=eq.${season}`, 'season_players');
  const rpc = http.post(`${URL}/rest/v1/rpc/my_unread_notification_count`, '{}', {
    headers: headers(t),
    tags: { name: 'unread_count' },
  });
  restErrors.add(rpc.status >= 400 || rpc.status === 0);
  sleep(5 + Math.random() * 15);
}

export function realtime(data) {
  const wsUrl = `${URL.replace('https://', 'wss://')}/realtime/v1/websocket?apikey=${KEY}&vsn=1.0.0`;
  const season = pick(SEASONS);
  const tables = ['matches', 'match_events', 'groups', 'news', 'season_teams'];
  const count = 3 + Math.floor(Math.random() * 3); // uygulamadaki gibi 3-5 kanal
  let ref = 0;
  const started = {};
  const res = ws.connect(wsUrl, {}, (socket) => {
    socket.on('open', () => {
      for (let i = 0; i < count; i++) {
        const table = tables[i];
        const topic = `realtime:sig:${table}:season_id=${season}:${__VU}-${__ITER}-${i}`;
        ref++;
        started[String(ref)] = Date.now();
        socket.send(JSON.stringify({
          topic,
          event: 'phx_join',
          ref: String(ref),
          join_ref: String(ref),
          payload: {
            config: {
              broadcast: { ack: false, self: false },
              presence: { key: '' },
              postgres_changes: [
                { event: 'INSERT', schema: 'public', table, filter: `season_id=eq.${season}` },
                { event: 'UPDATE', schema: 'public', table, filter: `season_id=eq.${season}` },
              ],
            },
            access_token: data.token,
          },
        }));
      }
      socket.setInterval(() => {
        ref++;
        socket.send(JSON.stringify({ topic: 'phoenix', event: 'heartbeat', payload: {}, ref: String(ref) }));
      }, 25000);
      // Uygulamayı 2-4 dk açık tutar, sonra kapatır (yeni kullanıcı gelir).
      socket.setTimeout(() => socket.close(), 120000 + Math.random() * 120000);
    });
    socket.on('message', (msg) => {
      let m;
      try { m = JSON.parse(msg); } catch (_) { return; }
      if (m.event === 'phx_reply' && started[m.ref]) {
        const ok = m.payload && m.payload.status === 'ok';
        wsJoinOk.add(ok);
        wsJoinTime.add(Date.now() - started[m.ref]);
        if (!ok) {
          const text = JSON.stringify(m.payload);
          if (/too many/i.test(text)) wsTooMany.add(1);
        }
        delete started[m.ref];
      }
      if (m.event === 'system' && m.payload && m.payload.status === 'error') {
        wsErrors.add(1);
        if (/too many/i.test(JSON.stringify(m.payload))) wsTooMany.add(1);
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
