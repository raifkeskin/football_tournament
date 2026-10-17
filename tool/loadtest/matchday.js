// Lig Masası maç günü senaryoları (k6). Yalnız demo maçlar izlenir.
//
// Her "fan" = maç detayını açık tutan bir kişi: açılışta maç/olay/kadro/
// sürüm okuması, sonra uygulamadaki gibi Broadcast konuları match:<id>,
// season:<id>, league:<id>. Her "browser" = ana sayfa/fikstür/puan durumu
// gezen bir kişi (REST + league:<id> konusu).
// Yazan taraf matchday.sh içindeki DO döngüsüdür (aynı değerle güncelleme:
// bildirim tetiklenmez, veri değişmez).
//
// SCEN: smoke | live400 | spike | multi | reconnect | mixed | limit
import http from 'k6/http';
import ws from 'k6/ws';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

const URL = __ENV.SUPABASE_URL;
const KEY = __ENV.SUPABASE_ANON_KEY;
const SCEN = __ENV.SCEN || 'smoke';
// "maç|sezon|lig" listesi, virgülle.
const MATCHES = (__ENV.MATCHES || '').split(',').filter(Boolean).map((s) => {
  const [id, season, league] = s.split('|');
  return { id, season, league };
});
const DEMO_EMAIL = __ENV.DEMO_EMAIL || '5000000000@masterclass.com';
const DEMO_PASSWORD = __ENV.DEMO_PASSWORD || 'demo2026';
// Yeniden bağlanma fırtınası: başlangıçtan kaç sn sonra herkes kopar.
const STORMS = SCEN === 'reconnect' ? [180, 330] : [];

const wsJoinOk = Rate('ws_join_ok');
const wsJoinTime = Trend('ws_join_ms', true);
const wsErrors = Counter('ws_errors');
const wsSystemErr = Counter('ws_system_errors');
const wsClosedEarly = Counter('ws_closed_by_server');
const deliveryMs = Trend('delivery_ms', true);
const delivered = Counter('updates_delivered');
const openMs = Trend('screen_open_ms', true);
const restErrors = Rate('rest_errors');
const rateLimited = Counter('rate_limited_msgs');

const S = (d, t) => ({ duration: d, target: t });
const PLANS = {
  smoke: { fans: [S('20s', 5), S('1m', 5), S('10s', 0)] },
  live400: { fans: [S('2m', 400), S('8m', 400), S('30s', 0)] },
  spike: { fans: [S('30s', 400), S('4m', 400), S('20s', 0)] },
  multi: { fans: [S('1m', 400), S('7m', 400), S('30s', 0)] },
  reconnect: { fans: [S('1m', 400), S('6m', 400), S('20s', 0)] },
  mixed: {
    fans: [S('1m', 300), S('8m', 300), S('30s', 0)],
    browsers: [S('1m', 150), S('8m', 150), S('30s', 0)],
  },
  limit: {
    fans: [S('2m', 400), S('2m', 400), S('1m', 500), S('2m', 500),
      S('1m', 650), S('2m', 650), S('1m', 800), S('2m', 800), S('30s', 0)],
  },
};
const plan = PLANS[SCEN];
const scenarios = {
  fans: { executor: 'ramping-vus', exec: 'fan', stages: plan.fans, gracefulRampDown: '20s' },
};
if (plan.browsers) {
  scenarios.browsers = { executor: 'ramping-vus', exec: 'browse', stages: plan.browsers, gracefulRampDown: '20s' };
}

export const options = {
  setupTimeout: '60s',
  scenarios,
  thresholds: {
    // Canlı kullanıcılar etkilenmesin: hata %15'i geçerse test durur.
    rest_errors: [{ threshold: 'rate<0.15', abortOnFail: true, delayAbortEval: '1m' }],
    ws_join_ok: [{ threshold: 'rate>0.70', abortOnFail: SCEN !== 'limit', delayAbortEval: '1m' }],
  },
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

function headers(token) {
  return { apikey: KEY, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
}

function get(token, path, name) {
  const res = http.get(`${URL}/rest/v1/${path}`, { headers: headers(token), tags: { name } });
  restErrors.add(res.status >= 400 || res.status === 0);
  check(res, { [`${name} 2xx`]: (r) => r.status >= 200 && r.status < 300 });
  return res;
}

export function setup() {
  if (!MATCHES.length) throw new Error('MATCHES gerekli');
  const res = http.post(
    `${URL}/auth/v1/token?grant_type=password`,
    JSON.stringify({ email: DEMO_EMAIL, password: DEMO_PASSWORD }),
    { headers: { apikey: KEY, 'Content-Type': 'application/json' } },
  );
  if (res.status !== 200) throw new Error(`demo girişi başarısız: ${res.status}`);
  return { token: res.json('access_token'), start: Date.now() };
}

function joinTopic(socket, ref, topic, token) {
  socket.send(JSON.stringify({
    topic: `realtime:${topic}`,
    event: 'phx_join',
    ref: String(ref),
    join_ref: String(ref),
    payload: {
      config: { broadcast: { ack: false, self: false }, presence: { key: '' }, private: true },
      access_token: token,
    },
  }));
}

// Bir websocket oturumu: konulara katılır, gelen yayınları ölçer.
function session(token, topics, lifeMs) {
  const wsUrl = `${URL.replace('https://', 'wss://')}/realtime/v1/websocket?apikey=${KEY}&vsn=1.0.0`;
  let ref = 0;
  const started = {};
  let closedByUs = false;
  const res = ws.connect(wsUrl, {}, (socket) => {
    socket.on('open', () => {
      for (const t of topics) {
        ref++;
        started[String(ref)] = Date.now();
        joinTopic(socket, ref, t, token);
      }
      socket.setInterval(() => {
        socket.send(JSON.stringify({ topic: 'phoenix', event: 'heartbeat', payload: {}, ref: String(++ref) }));
      }, 25000);
      socket.setTimeout(() => { closedByUs = true; socket.close(); }, lifeMs);
    });
    socket.on('message', (msg) => {
      let m;
      try { m = JSON.parse(msg); } catch (_) { return; }
      if (m.event === 'phx_reply' && started[m.ref]) {
        const ok = m.payload && m.payload.status === 'ok';
        wsJoinOk.add(ok);
        wsJoinTime.add(Date.now() - started[m.ref]);
        if (!ok && /rate|too many|limit/i.test(JSON.stringify(m.payload))) rateLimited.add(1);
        if (!ok && Math.random() < 0.05) console.warn(`JOINFAIL ${JSON.stringify(m.payload).slice(0, 300)}`);
        delete started[m.ref];
        return;
      }
      if (m.event === 'system' && m.payload && m.payload.status === 'error') {
        wsSystemErr.add(1);
        if (Math.random() < 0.05) console.warn(`SYSERR ${JSON.stringify(m.payload).slice(0, 300)}`);
        if (/rate|too many|limit/i.test(JSON.stringify(m.payload))) rateLimited.add(1);
        return;
      }
      if (m.event === 'phx_error' || m.event === 'phx_close') {
        if (Math.random() < 0.05) console.warn(`PHX ${m.event} ${m.topic} ${JSON.stringify(m.payload).slice(0, 200)}`);
        wsErrors.add(1);
        return;
      }
      if (m.event === 'broadcast') {
        const rec = (m.payload && m.payload.payload && m.payload.payload.record) || {};
        if (rec.updated_at) deliveryMs.add(Date.now() - Date.parse(rec.updated_at));
        delivered.add(1);
      }
    });
    socket.on('error', () => wsErrors.add(1));
    socket.on('close', () => { if (!closedByUs) wsClosedEarly.add(1); });
  });
  check(res, { 'ws 101': (r) => r && r.status === 101 });
  if (!res || res.status !== 101) {
    wsJoinOk.add(false);
    wsErrors.add(1);
    sleep(3);
  }
}

// Oturum süresi: normalde 2-4 dk; fırtına senaryosunda bir sonraki
// fırtına anına kadar (herkes aynı anda kopar, hemen geri bağlanır).
function lifeFor(data) {
  const elapsed = (Date.now() - data.start) / 1000;
  for (const s of STORMS) if (elapsed < s) return (s - elapsed) * 1000;
  if (SCEN === 'live400' || SCEN === 'multi' || SCEN === 'limit' || SCEN === 'spike') {
    return 300000 + Math.random() * 300000; // maçı uzun izler
  }
  return 120000 + Math.random() * 120000;
}

export function fan(data) {
  const t = data.token;
  const m = MATCHES[(__VU - 1) % MATCHES.length];
  // Ekran açılışı (uygulamadaki gibi paralel).
  const s = Date.now();
  const reqs = [
    ['match', `matches?select=*&id=eq.${m.id}`],
    ['match_events', `match_events?select=*&match_id=eq.${m.id}&order=minute.asc`],
    ['match_rosters', `match_rosters?select=*&match_id=eq.${m.id}`],
    ['data_versions', `data_versions?select=*&scope=in.(season:${m.season},teams,players)`],
  ].map(([name, path]) => ({
    method: 'GET', url: `${URL}/rest/v1/${path}`, params: { headers: headers(t), tags: { name } },
  }));
  const rs = http.batch(reqs);
  for (const r of rs) restErrors.add(r.status >= 400 || r.status === 0);
  openMs.add(Date.now() - s);
  session(t, [`match:${m.id}`, `season:${m.season}`, `league:${m.league}`], lifeFor(data));
}

export function browse(data) {
  const t = data.token;
  const m = MATCHES[Math.floor(Math.random() * MATCHES.length)];
  const s = Date.now();
  http.batch([
    ['matches_season', `matches?select=*&season_id=eq.${m.season}&order=match_date.asc`],
    ['groups', `groups?select=*&season_id=eq.${m.season}`],
    ['season_teams', `season_teams?select=team_id,group_id&season_id=eq.${m.season}`],
    ['news', `news?select=*&season_id=eq.${m.season}&order=created_at.desc&limit=20`],
  ].map(([name, path]) => ({
    method: 'GET', url: `${URL}/rest/v1/${path}`, params: { headers: headers(t), tags: { name } },
  }))).forEach((r) => restErrors.add(r.status >= 400 || r.status === 0));
  openMs.add(Date.now() - s);
  get(t, `season_team_players?select=player_id,team_id,jersey_number&season_id=eq.${m.season}`, 'season_players');
  // Ana sayfa açıkken lig konusunu dinler (canlı skor şeridi).
  session(t, [`league:${m.league}`], 30000 + Math.random() * 60000);
}
