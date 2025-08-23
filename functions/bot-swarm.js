// functions/bot-swarm.js
// Usage examples:
//   EMULATOR=1 HEARTBEAT=1 node functions/bot-swarm.js
//   USERS=300 CANCEL_RATE=0.35 WAVES=3 WAVE_GAP_MS=2000 EMULATOR=1 HEARTBEAT=1 node functions/bot-swarm.js
//   FORCE=1 FORCE_TIMES=80 FORCE_DELAY_MS=150 EMULATOR=1 HEARTBEAT=1 node functions/bot-swarm.js
//
// Notes:
// - EMULATOR=1: Firestore Emulator로 전송(없으면 프로덕션으로 전송)
// - HEARTBEAT=1: 대기 하트비트 루프 켬(유령/청소 시나리오 테스트 유용)
// - FORCE=1: 스웜 종료 후 forceMatch 함수를 여러 번 호출해서 매칭 가속

// --- Env / Project ---
const PROJECT_ID = process.env.PROJECT_ID || "wonderminute-7a4c9";

// ADDED: 실행 식별자 (감사 스냅샷에 사용)
const RUN_ID = process.env.RUN_ID || String(Date.now());

// Emulator only if explicitly requested
if (process.env.EMULATOR) {
  process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
  console.log(`⚙️  Using Firestore Emulator at ${process.env.FIRESTORE_EMULATOR_HOST}`);
}

process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: PROJECT_ID });
process.env.GCLOUD_PROJECT = PROJECT_ID;

const admin = require("firebase-admin");

// ---- Config via env ----
const USERS         = parseInt(process.env.USERS || "100", 10);        // 가짜 유저 수
const CANCEL_RATE   = Number(process.env.CANCEL_RATE || "0.25");        // 큐 진입 후 취소 확률
const WAVES         = parseInt(process.env.WAVES || "1", 10);           // 웨이브(배치) 수
const WAVE_GAP_MS   = parseInt(process.env.WAVE_GAP_MS || "1500", 10);  // 배치 간 대기
const JITTER_MS     = parseInt(process.env.JITTER_MS || "800", 10);     // 큐 진입 전 랜덤 지연
const POST_WAIT_MS  = parseInt(process.env.POST_WAIT_MS || "10000",10); // 각 봇의 사후 대기
const HEARTBEAT_ON  = !!process.env.HEARTBEAT;                          // 대기 하트비트 시뮬
const FORCE         = !!process.env.FORCE;                               // 스웜 종료 후 강제 매칭 호출
const FORCE_TIMES   = parseInt(process.env.FORCE_TIMES || "60", 10);    // 강제 호출 횟수
const FORCE_DELAYMS = parseInt(process.env.FORCE_DELAY_MS || "200",10); // 호출 간격(ms)

// ---- Admin init ----
if (!admin.apps.length) {
  // 실제 프로젝트로 돌릴 땐 GOOGLE_APPLICATION_CREDENTIALS 지정
  admin.initializeApp({ projectId: PROJECT_ID });
}
const db = admin.firestore();

// ---- Helpers ----
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const botUid = (i) => `bot:${i+1}`;

// 대기 하트비트 (선택)
async function heartbeatLoop(uid, ms = 15000, stopAfterMs = 60000) {
  const ref = db.collection("matchingQueue").doc(uid);
  const until = Date.now() + stopAfterMs;
  while (Date.now() < until) {
    await sleep(ms);
    await ref.update({ heartbeatAt: admin.firestore.FieldValue.serverTimestamp() }).catch(()=>{});
  }
}

// 큐 등록 (gender/wantGender/heartbeatAt 포함)
async function enqueue(uid, gender, wantGender) {
  const ref = db.collection("matchingQueue").doc(uid);
  await ref.set({
    uid,
    status: "waiting",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    heartbeatAt: admin.firestore.FieldValue.serverTimestamp(),
    gender,           // "남자" | "여자"
    wantGender        // "남자" | "여자" | "all"
  }, { merge: true });

  // ADDED: 이번 실행에 들어온 큐 입력값을 감사용으로 저장
  await db.collection("swarmAudit").doc(RUN_ID)
    .collection("enqueued").doc(uid)
    .set({
      uid, gender, wantGender,
      runId: RUN_ID,
      at: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
}


// 간단 취소: 큐에서 제거(유령 시뮬)
async function cancelQueue(uid) {
  await db.collection("matchingQueue").doc(uid).delete().catch(() => {});
}

// 한 명의 봇 동작
async function runBot(uid) {
  try {
    // 유저 문서 (성별 저장)
    const gender = Math.random() < 0.5 ? "남자" : "여자";
    await db.collection("users").doc(uid).set({ gender, matchPhase: "idle" }, { merge: true });

    // 큐 진입 전 랜덤 지연
    await sleep(Math.random() * JITTER_MS);

    // 선호 랜덤
    const prefs  = ["남자", "여자", "all"];
    const wantGender = prefs[Math.floor(Math.random() * prefs.length)];

    // 큐 투입
    await enqueue(uid, gender, wantGender);

    // (선택) 대기 하트비트 시뮬
    if (HEARTBEAT_ON && Math.random() < 0.7) {
      heartbeatLoop(uid, 15000, 120000).catch(()=>{}); // 2분간 심장박동
    }

    // 일부는 3~8초 후 취소(유령/이탈 시나리오)
    if (Math.random() < CANCEL_RATE) {
      await sleep(3000 + Math.random() * 5000);
      await cancelQueue(uid);
      return { uid, action: "cancelled" };
    }

    // 나머지는 대기 → 서버 매칭/정리 로직이 처리
    await sleep(POST_WAIT_MS);
    return { uid, action: "waiting" };

  } catch (e) {
    return { uid, action: "error", error: String(e) };
  }
}

// 웨이브 실행
async function runWave(startIdx, count) {
  const uids = Array.from({ length: count }, (_, k) => botUid(startIdx + k));
  const t0 = Date.now();
  const results = await Promise.all(uids.map(runBot));
  const t1 = Date.now();
  const summary = results.reduce((acc, r) => {
    acc[r.action] = (acc[r.action] || 0) + 1;
    return acc;
  }, {});
  console.log(`🌊 Wave done in ${t1 - t0} ms | summary:`, summary);
  return summary;
}

// 집계
function mergeSummary(a, b) {
  const out = { ...a };
  for (const k of Object.keys(b)) out[k] = (out[k] || 0) + b[k];
  return out;
}

// 강제 매칭 호출
async function forceMatchingLoop(times, delayMs) {
  const base = process.env.EMULATOR
    ? `http://localhost:5001/${PROJECT_ID}/us-central1/forceMatch`
    : `https://us-central1-${PROJECT_ID}.cloudfunctions.net/forceMatch`;

  console.log(`⚡ Forcing tryPairTwo() x${times} every ${delayMs}ms`);
  for (let i = 0; i < times; i++) {
    try {
      // Node 18+/20+ 에선 fetch 글로벌 제공
      await fetch(base);
    } catch (_) {}
    await sleep(delayMs);
  }
  console.log("⚡ Force done");
}

// 메인
(async () => {
 console.log(`🚀 swarm start | USERS=${USERS}, WAVES=${WAVES}, CANCEL_RATE=${CANCEL_RATE}, HEARTBEAT=${HEARTBEAT_ON}, EMULATOR=${!!process.env.EMULATOR}, FORCE=${FORCE}`);
console.log(`[RUN] id=${RUN_ID}`); // ADDED
  let total = {};
  const perWave = Math.ceil(USERS / WAVES);
  for (let w = 0; w < WAVES; w++) {
    const start = w * perWave;
    const count = Math.min(perWave, USERS - start);
    if (count <= 0) break;

    console.log(`▶️  Wave ${w+1}/${WAVES}: ${count} users`);
    const s = await runWave(start, count);
    total = mergeSummary(total, s);

    if (w < WAVES - 1) await sleep(WAVE_GAP_MS);
  }

  console.log("✅ swarm done. aggregate summary:", total);

  if (FORCE) {
    await forceMatchingLoop(FORCE_TIMES, FORCE_DELAYMS);
  }

  await printMatchReport();

  console.log("🏁 done.");
})();

// ======== MATCH REPORTER (no server change) ========
// ======== MATCH REPORTER (top-level + collectionGroup, schema-flex) ========
// ======== MATCH REPORTER (top-level + collectionGroup, schema-flex + pref audit) ========
async function printMatchReport() {
  const ROOM_CANDIDATES = (process.env.ROOMS_COLLECTIONS || "matchedRooms,rooms,sessions,matchRooms,calls,voiceRooms,roomSessions")
    .split(",").map(s => s.trim()).filter(Boolean);

  let picked = { type: null, name: null, snap: null };

  // 1) 최상위
  for (const name of ROOM_CANDIDATES) {
    const snap = await db.collection(name).get();
    if (snap.size > (picked.snap?.size || 0)) picked = { type: "top", name, snap };
  }
  // 2) 서브컬렉션(group)
  for (const name of ROOM_CANDIDATES) {
    try {
      const gsnap = await db.collectionGroup(name).get();
      if (gsnap.size > (picked.snap?.size || 0)) picked = { type: "group", name, snap: gsnap };
    } catch(_) {}
  }

  if (!picked.snap || picked.snap.empty) {
    console.log("\n--- 매칭 결과 ---");
    console.log("방 컬렉션을 찾지 못했어요. 후보들:", ROOM_CANDIDATES);
    console.log("http://localhost:4000 에서 실제 경로를 확인하거나 ROOMS_COLLECTIONS로 이름을 지정하세요.");
    return;
  }

  console.log(`\n--- 매칭 결과 (source=${picked.type}, name="${picked.name}", rooms=${picked.snap.size}) ---`);

  // users 캐시
  const genderCache = new Map();
  async function getGender(uid) {
    if (!uid) return null;
    if (genderCache.has(uid)) return genderCache.get(uid);
    const doc = await db.collection("users").doc(uid).get();
    const g = doc.exists ? (doc.data().gender || null) : null;
    genderCache.set(uid, g);
    return g;
  }

  // participants 추출 (여러 스키마 대응)
  function extractParticipants(d) {
    if (Array.isArray(d.participants) && d.participants.length >= 2) return d.participants.slice(0, 2);
    if (Array.isArray(d.uids) && d.uids.length >= 2) return d.uids.slice(0, 2);
    if (d.user1 && d.user2) return [d.user1, d.user2];
    if (d.a && d.b) return [d.a, d.b];
    if (d.members && typeof d.members === "object") {
      const keys = Object.keys(d.members);
      if (keys.length >= 2) return keys.slice(0, 2);
    }
    if (d.participant1 && d.participant2) return [d.participant1, d.participant2];
    return [null, null];
  }

  // ADDED: 이번 실행의 감사 데이터 로드
  const auditSnap = await db.collection("swarmAudit").doc(RUN_ID).collection("enqueued").get();
  const audit = new Map();
  auditSnap.forEach(d => audit.set(d.id, d.data()));

  // 필요 시, 큐에서 바로 선호를 조회(이미 삭제됐으면 null)
  async function getPrefFromQueue(uid) {
    try {
      const q = await db.collection("matchingQueue").doc(uid).get();
      return q.exists ? (q.data().wantGender || null) : null;
    } catch { return null; }
  }

  // 선호 준수 판단
  function respects(pref, otherGender) {
    if (!pref) return false;
    if (pref === "all") return true;
    return pref === otherGender;
  }

  const matrix = { "남자-남자": 0, "남자-여자": 0, "여자-남자": 0, "여자-여자": 0, "unknown": 0 };
  let ok = 0, violation = 0, unknownPref = 0;

  const verbose = !!process.env.VERBOSE_VIOLATIONS; // 위반 케이스 상세 출력 여부

  for (const roomDoc of picked.snap.docs) {
    const data = roomDoc.data();
    const gendersField = Array.isArray(data.genders) ? data.genders.slice(0, 2) : null;

    let [u1, u2] = extractParticipants(data);
    if (!u1 || !u2) {
      console.log(`room=${roomDoc.id} | participants missing`);
      matrix.unknown++;
      continue;
    }

    let g1, g2;
    if (gendersField && gendersField.length === 2) {
      [g1, g2] = gendersField;
    } else {
      [g1, g2] = await Promise.all([getGender(u1), getGender(u2)]);
    }

    // ADDED: 선호 불러오기 (감사 스냅샷 우선, 없으면 큐에서 시도)
    const aInfo = audit.get(u1);
    const bInfo = audit.get(u2);
    const aPref = aInfo?.wantGender ?? await getPrefFromQueue(u1);
    const bPref = bInfo?.wantGender ?? await getPrefFromQueue(u2);

    console.log(`room=${roomDoc.id} | ${u1}(${g1 || "?"}/${aPref || "?"}) x ${u2}(${g2 || "?"}/${bPref || "?"})`);

    const key =
      (g1 === "남자" && g2 === "남자") ? "남자-남자" :
      (g1 === "남자" && g2 === "여자") ? "남자-여자" :
      (g1 === "여자" && g2 === "남자") ? "여자-남자" :
      (g1 === "여자" && g2 === "여자") ? "여자-여자" : "unknown";
    matrix[key]++;

    if (!aPref || !bPref) {
      unknownPref++;
    } else {
      const aOk = respects(aPref, g2);
      const bOk = respects(bPref, g1);
      if (aOk && bOk) {
        ok++;
      } else {
        violation++;
        if (verbose) {
          console.log(`  ↳ VIOLATION: aOk=${aOk}, bOk=${bOk}`);
        }
      }
    }
  }

  // 큐 요약
  try {
    const queueSnap = await db.collection("matchingQueue").get();
    const qStats = { waiting: 0, paired: 0, cancelled: 0, expired: 0, other: 0 };
    queueSnap.forEach(d => {
      const s = (d.data().status || "").toLowerCase();
      if (s === "waiting") qStats.waiting++;
      else if (s === "paired") qStats.paired++;
      else if (s === "cancelled") qStats.cancelled++;
      else if (s === "expired") qStats.expired++;
      else qStats.other++;
    });

    console.log("\n--- 성별 매칭 매트릭스 ---");
    console.log(matrix);

    console.log("\n--- 선호 준수 검증 ---");
    const totalPairs = picked.snap.size;
    const checked = ok + violation + unknownPref;
    const rate = totalPairs ? (ok / totalPairs * 100).toFixed(1) : "0.0";
    console.log({ ok, violation, unknownPref, totalPairs, checked, okRatePercent: `${rate}%` });

    console.log("\n--- 큐 상태 요약 ---");
    console.log(qStats);
  } catch (_) {
    console.log("\n--- 성별 매칭 매트릭스 ---");
    console.log(matrix);

    console.log("\n--- 선호 준수 검증 ---");
    const totalPairs = picked.snap.size;
    const rate = totalPairs ? (ok / totalPairs * 100).toFixed(1) : "0.0";
    console.log({ ok, violation, unknownPref, totalPairs, okRatePercent: `${rate}%` });
  }

  console.log("\n--- 요약 ---");
  console.log({
    source: picked.type,
    name: picked.name,
    rooms: picked.snap.size,
    pairs: picked.snap.size * 2,
    runId: RUN_ID
  });
}
