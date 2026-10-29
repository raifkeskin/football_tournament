// Drive'dan maç fotoğrafı alma (cron drive_sync_tick, 15 dk).
//
// app_private_settings.drive_root_folder_id klasörü (servis hesabıyla
// paylaşılmış) en çok 4 kat aşağı taranır. Adında maç kodu (#LM + maç
// kimliğinin ilk 6 hanesi) geçen klasördeki (ve alt klasörlerindeki)
// fotoğraflar 1600 piksel JPEG olarak media/matches/drive/ altına kopyalanır
// ve maça "Önemli An" (ekranda "Maçtan Fotoğraflar") olarak eklenir.
// drive_media_seen: alınan dosya bir daha alınmaz, uygulamada silinen geri
// gelmez.
//
// Önce drive_folder_seasons'taki sezonların eksik klasörleri açılır:
// <kök> / <Turnuva Yıl> / <N. Hafta> / <Ev - Dep | #LM…> / <Takım> Takım
// Fotosu (her iki takım için; drive_folders). Takım klasöründeki fotoğraf o
// takımın "Takım Fotosu" olur, maç klasöründeki diğerleri "Önemli An".
//
// Gizli ayar: GOOGLE_DRIVE_SA_JSON (servis hesabı anahtarı).
// JWT doğrulaması kapalı yayınlanır (`--no-verify-jwt`); çağrı
// `x-sync-secret` = app_private_settings.drive_sync_secret ile yetkilenir.

import { createClient } from "jsr:@supabase/supabase-js@2";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const DRIVE = "https://www.googleapis.com/drive/v3/files";
const FOLDER = "application/vnd.google-apps.folder";
const MAX_DEPTH = 4;
/// Bir çalıştırmada en çok bu kadar fotoğraf (süre sınırı); kalanı sonraki tura.
const MAX_FILES = 30;
const MEDIA_TYPE = "Önemli An";

type DriveFile = {
  id: string;
  name: string;
  mimeType: string;
  thumbnailLink?: string;
  size?: string;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function b64url(data: ArrayBuffer | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/// Servis hesabıyla salt okunur Drive erişim belirteci.
async function accessToken(): Promise<string> {
  const sa = JSON.parse(Deno.env.get("GOOGLE_DRIVE_SA_JSON") ?? "{}");
  if (!sa.client_email || !sa.private_key) throw new Error("GOOGLE_DRIVE_SA_JSON eksik.");
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    // Klasör açmak için tam yetki; hesap yalnız paylaşılan klasörü görür.
    scope: "https://www.googleapis.com/auth/drive",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = String(sa.private_key).replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claim}`));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claim}.${b64url(sig)}`,
    }),
  });
  const body = await res.json();
  if (!res.ok || !body.access_token) throw new Error(`Drive belirteci alınamadı: ${JSON.stringify(body)}`);
  return body.access_token;
}

async function children(token: string, parent: string): Promise<DriveFile[]> {
  const out: DriveFile[] = [];
  let page = "";
  do {
    const u = new URL(DRIVE);
    u.searchParams.set("q", `'${parent}' in parents and trashed = false`);
    u.searchParams.set("fields", "nextPageToken, files(id, name, mimeType, thumbnailLink, size)");
    u.searchParams.set("pageSize", "1000");
    u.searchParams.set("supportsAllDrives", "true");
    u.searchParams.set("includeItemsFromAllDrives", "true");
    if (page) u.searchParams.set("pageToken", page);
    const res = await fetch(u, { headers: { Authorization: `Bearer ${token}` } });
    const body = await res.json();
    if (!res.ok) throw new Error(`Drive listesi okunamadı: ${JSON.stringify(body)}`);
    out.push(...(body.files ?? []));
    page = body.nextPageToken ?? "";
  } while (page);
  return out;
}

async function createFolder(token: string, parent: string, name: string): Promise<string> {
  const res = await fetch(`${DRIVE}?supportsAllDrives=true&fields=id`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ name, mimeType: FOLDER, parents: [parent] }),
  });
  const body = await res.json();
  if (!res.ok || !body.id) throw new Error(`Klasör açılamadı (${name}): ${JSON.stringify(body)}`);
  return body.id;
}

const clean = (s: string) => s.replace(/[\/]/g, "-").replace(/\s+/g, " ").trim();

/// Sezonların eksik turnuva / hafta / maç klasörlerini açar; açılan sayısı.
async function ensureFolders(token: string, root: string, seasonIds: string[]): Promise<number> {
  if (!seasonIds.length) return 0;
  const { data: known } = await admin.from("drive_folders").select("key, folder_id");
  const folders = new Map((known ?? []).map((r) => [r.key as string, r.folder_id as string]));
  let created = 0;
  async function ensure(key: string, parent: string, name: string): Promise<string> {
    const have = folders.get(key);
    if (have) return have;
    const id = await createFolder(token, parent, name);
    await admin.from("drive_folders").insert({ key, folder_id: id });
    folders.set(key, id);
    created++;
    return id;
  }
  for (const seasonId of seasonIds) {
    const { data: season } = await admin
      .from("seasons")
      .select("id, season_year, leagues(name)")
      .eq("id", seasonId)
      .maybeSingle();
    if (!season) continue;
    // deno-lint-ignore no-explicit-any
    const league = clean(String((season as any).leagues?.name ?? "Turnuva"));
    const seasonDir = await ensure(
      `season:${seasonId}`,
      root,
      [league, season.season_year].filter(Boolean).join(" "),
    );
    const { data: matches } = await admin
      .from("matches")
      .select("id, week, home_team_id, away_team_id")
      .eq("season_id", seasonId)
      .is("deleted_at", null)
      .order("week")
      .order("match_date");
    const list = matches ?? [];
    const missing = list.filter((m) =>
      !folders.has(`match:${m.id}`) ||
      !folders.has(`team:${m.id}:${m.home_team_id}`) ||
      !folders.has(`team:${m.id}:${m.away_team_id}`)
    );
    if (!missing.length) continue;
    const teamIds = [...new Set(missing.flatMap((m) => [m.home_team_id, m.away_team_id]))];
    const { data: teams } = await admin.from("teams").select("id, name").in("id", teamIds);
    const teamName = new Map((teams ?? []).map((t) => [t.id, clean(String(t.name ?? ""))]));
    for (const m of missing) {
      const parent = m.week == null
        ? seasonDir
        : await ensure(`week:${seasonId}:${m.week}`, seasonDir, `${m.week}. Hafta`);
      const code = m.id.replace(/-/g, "").slice(0, 6).toUpperCase();
      const name = `${teamName.get(m.home_team_id) ?? "Ev Sahibi"} - ${
        teamName.get(m.away_team_id) ?? "Deplasman"
      } | #LM${code}`;
      const matchDir = await ensure(`match:${m.id}`, parent, name);
      for (const t of [m.home_team_id, m.away_team_id]) {
        await ensure(`team:${m.id}:${t}`, matchDir, `${teamName.get(t) ?? "Takım"} Takım Fotosu`);
      }
    }
  }
  return created;
}

function codeOf(name: string): string | undefined {
  return name.match(/#LM([0-9a-f]{6})\b/i)?.[1]?.toLowerCase();
}

const fold = (s: string) =>
  s.toLocaleLowerCase("tr").replace(/ı/g, "i").normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, " ").trim();

type Found = { file: DriveFile; teamId?: string };

/// Klasörün (ve alt klasörlerinin) fotoğrafları. Takım klasörü (açtığımız
/// ya da adı "<Takım> Takım Fotosu" olan) altındakiler o takıma bağlanır.
async function imagesUnder(
  token: string,
  folderId: string,
  teamOf: (folder: DriveFile) => string | undefined,
  depth = 0,
  teamId?: string,
): Promise<Found[]> {
  const items = await children(token, folderId);
  const found: Found[] = items
    .filter((f) => f.mimeType.startsWith("image/"))
    .map((file) => ({ file, teamId }));
  if (depth < 2) {
    for (const f of items.filter((f) => f.mimeType === FOLDER)) {
      found.push(...await imagesUnder(token, f.id, teamOf, depth + 1, teamId ?? teamOf(f)));
    }
  }
  return found;
}

/// 1600 piksel JPEG: Drive'ın küçük resmi (dönüş düzeltilmiş); yoksa orijinal.
async function photoBytes(token: string, f: DriveFile): Promise<{ bytes: Uint8Array; type: string }> {
  const auth = { Authorization: `Bearer ${token}` };
  if (f.thumbnailLink) {
    const url = f.thumbnailLink.replace(/=s\d+(-[a-z0-9-]+)?$/i, "=s1600");
    const res = await fetch(url, { headers: auth });
    const type = res.headers.get("content-type") ?? "";
    if (res.ok && type.startsWith("image/")) {
      return { bytes: new Uint8Array(await res.arrayBuffer()), type };
    }
  }
  if (Number(f.size ?? 0) > 8 * 1024 * 1024) throw new Error("Dosya çok büyük ve küçük resmi yok.");
  const res = await fetch(`${DRIVE}/${f.id}?alt=media&supportsAllDrives=true`, { headers: auth });
  if (!res.ok) throw new Error(`İndirilemedi (${res.status}).`);
  return { bytes: new Uint8Array(await res.arrayBuffer()), type: f.mimeType };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST bekleniyor." }, 405);
  const { data: settings } = await admin
    .from("app_private_settings")
    .select("key, value")
    .in("key", ["drive_sync_secret", "drive_root_folder_id", "drive_folder_seasons"]);
  const s = Object.fromEntries((settings ?? []).map((r) => [r.key, r.value]));
  const given = req.headers.get("x-sync-secret") ?? "";
  if (!s.drive_sync_secret || given !== s.drive_sync_secret) return json({ error: "Yetkisiz." }, 401);
  if (!s.drive_root_folder_id) return json({ error: "Kök klasör yok." }, 400);

  const report = { created: 0, folders: 0, added: 0, skipped: [] as string[], errors: [] as string[] };
  try {
    const token = await accessToken();
    try {
      const seasons = JSON.parse(s.drive_folder_seasons ?? "[]");
      report.created = await ensureFolders(token, s.drive_root_folder_id, Array.isArray(seasons) ? seasons : []);
    } catch (e) {
      report.errors.push(e instanceof Error ? e.message : String(e));
    }

    // Kodlu maç klasörlerini bul.
    const matchFolders: { id: string; name: string; code: string }[] = [];
    let level = [s.drive_root_folder_id as string];
    for (let depth = 0; depth < MAX_DEPTH && level.length; depth++) {
      const next: string[] = [];
      for (const parent of level) {
        for (const f of await children(token, parent)) {
          if (f.mimeType !== FOLDER) continue;
          const code = codeOf(f.name);
          if (code) matchFolders.push({ id: f.id, name: f.name, code });
          else next.push(f.id);
        }
      }
      level = next;
    }
    report.folders = matchFolders.length;

    const { data: teamKeys } = await admin.from("drive_folders").select("key, folder_id").like("key", "team:%");
    const teamFolders = new Map((teamKeys ?? []).map((r) => [r.key as string, r.folder_id as string]));

    let budget = MAX_FILES;
    for (const folder of matchFolders) {
      if (budget <= 0) break;
      const { data: matchId } = await admin.rpc("drive_match_by_code", { p_code: folder.code });
      if (!matchId) {
        report.skipped.push(`${folder.name}: maç bulunamadı`);
        continue;
      }
      const { data: match } = await admin
        .from("matches")
        .select("home_team_id, away_team_id")
        .eq("id", matchId)
        .single();
      const sides = [match?.home_team_id, match?.away_team_id].filter(Boolean) as string[];
      const { data: teamRows } = await admin.from("teams").select("id, name").in("id", sides);
      const teamFolder = new Map(
        sides.map((t) => [teamFolders.get(`team:${matchId}:${t}`), t] as const).filter(([f]) => f),
      );
      const teamOf = (f: DriveFile) => {
        const known = teamFolder.get(f.id);
        if (known) return known;
        const n = fold(f.name);
        if (!n.includes("takim foto")) return undefined;
        return (teamRows ?? []).find((t) => n.startsWith(fold(String(t.name ?? ""))))?.id;
      };
      const found = await imagesUnder(token, folder.id, teamOf);
      if (!found.length) continue;
      const { data: seenRows } = await admin
        .from("drive_media_seen")
        .select("file_id")
        .in("file_id", found.map((x) => x.file.id));
      const seen = new Set((seenRows ?? []).map((r) => r.file_id));
      for (const { file: f, teamId } of found) {
        if (budget <= 0) break;
        if (seen.has(f.id)) continue;
        budget--;
        // Önce sahiplen: aynı anda iki çalıştırma aynı dosyayı almasın.
        const { error: claimErr } = await admin
          .from("drive_media_seen")
          .insert({ file_id: f.id, match_id: matchId, folder_name: folder.name });
        if (claimErr) continue;
        try {
          const { bytes, type } = await photoBytes(token, f);
          const ext = type.includes("png") ? "png" : type.includes("webp") ? "webp" : "jpg";
          const path = `matches/drive/${matchId}/${f.id}.${ext}`;
          const up = await admin.storage.from("media").upload(path, bytes, {
            contentType: type,
            cacheControl: "31536000",
            upsert: true,
          });
          if (up.error) throw up.error;
          const url = admin.storage.from("media").getPublicUrl(path).data.publicUrl;
          const { data: media, error } = await admin
            .from("match_media")
            .insert({
              match_id: matchId,
              media_type: teamId ? "Takım Fotosu" : MEDIA_TYPE,
              team_id: teamId ?? null,
              url,
            })
            .select("id")
            .single();
          if (error) {
            await admin.storage.from("media").remove([path]);
            throw error;
          }
          await admin.from("drive_media_seen").update({ media_id: media.id }).eq("file_id", f.id);
          report.added++;
        } catch (e) {
          // Sahiplenme geri alınır, sonraki turda yeniden denenir.
          await admin.from("drive_media_seen").delete().eq("file_id", f.id);
          report.errors.push(`${folder.name}/${f.name}: ${e instanceof Error ? e.message : JSON.stringify(e)}`);
        }
      }
    }
  } catch (e) {
    report.errors.push(e instanceof Error ? e.message : String(e));
  }
  if (report.created || report.added || report.errors.length) console.log(JSON.stringify(report));
  return json(report);
});
