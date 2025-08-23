// ------------------ 공통 의존성 ------------------
const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const axios = require("axios");
const express = require("express");
const cors = require("cors");
const { onRequest, onCall } = require("firebase-functions/v2/https");
let _joseLib;       // { createRemoteJWKSet, jwtVerify }
let _appleJWKS;     // RemoteJWKSet
// 🔊 Agora (토큰 발급용)
const { RtcTokenBuilder, RtcRole } = require("agora-access-token");
const { defineSecret } = require("firebase-functions/params");
const AGORA_APP_ID   = defineSecret("AGORA_APP_ID");
const AGORA_APP_CERT = defineSecret("AGORA_APP_CERT");
// 공통 헬퍼
function ridOf(req) { return req.get("X-Call-Rid") || "-"; }


const APPLE_AUDIENCE_BUNDLE_ID = defineSecret("APPLE_AUDIENCE_BUNDLE_ID");

// (선택) 로컬 개발 편의를 위해 .env 지원
if (process.env.NODE_ENV !== "production") {
  require("dotenv").config();
}

admin.initializeApp();
const db = admin.firestore();

// 서버 상단 공용 유틸 영역에 추가
async function getBindUidFromAuthHeader(req) {
  const auth = req.headers.authorization || "";
  const m = auth.match(/^Bearer\s+(.+)$/i);
  if (!m) return null;
  try {
    const decoded = await admin.auth().verifyIdToken(m[1]);
    return decoded.uid;          // 현재 세션의 UID
  } catch {
    return null;                 // 토큰 없거나 무효 → 바인드 없이 진행
  }
}


// ------------------ 공용 유틸 ------------------
async function verifyAuth(req) {
  // Authorization: Bearer <ID_TOKEN>
  const auth = req.headers.authorization || "";
  const [, idToken] = auth.split(" ");
  if (!idToken) throw new Error("No ID token");
  const decoded = await admin.auth().verifyIdToken(idToken);
  return decoded.uid;
}
function nowTs() { return Timestamp.now(); }
function getAgoraCreds() {
  // 우선 순위: Firebase Secret → 환경변수(.env)
  const appId   = AGORA_APP_ID.value()   || process.env.AGORA_APP_ID;
  const appCert = AGORA_APP_CERT.value() || process.env.AGORA_APP_CERT;
  return { appId, appCert };
}

// ------------------ Kakao Login (HTTPS + Express) ------------------
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || "").split(",").filter(Boolean);
// 예: "https://wonderminute.app,https://staging.wonderminute.app"
const crypto = require("crypto");
const app = express();
app.use(cors({
  origin: function(origin, cb) {
    if (!origin || ALLOWED_ORIGINS.includes(origin)) return cb(null, true);
    return cb(new Error("CORS_NOT_ALLOWED"), false);
  }
}));

// ✅ 요청 상관아이디(rid) 부여 + 1차 로그
app.use((req, _res, next) => {
  req.reqId = req.get("X-Req-Id") || (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()));
  console.log(`➡️ [kakaoLogin] rid=${req.reqId} ${req.method} ${req.path} origin=${req.headers.origin || "none"}`);
  next();
});


// ✅ JSON 파서 (용량 제한 포함)
app.use(express.json({ limit: "1mb" }));



function replyError(res, status, code, message, reqId) {
  return res.status(status).json({ error_code: code, error_message: message, req_id: reqId });
}

app.post("/", async (req, res) => {
  const rid = req.reqId;
  try {
    console.log(`📥 [${rid}] bodyKeys=${Object.keys(req.body || {})} hasAppCheck=${!!req.header("X-Firebase-AppCheck")}`);

    await verifyAppCheck(req);
    await guardRate(req);

    const kakaoAccessToken = req.body.token;
    if (!kakaoAccessToken) return replyError(res, 400, "NO_TOKEN", "No token provided", rid);

    // ★ 추가: 사전조회 모드 파싱
    const mode = (req.query.mode || req.body?.mode || "").toString();
    const checkOnly = (mode === "check");


    console.log(`🔎 [${rid}] call Kakao /v2/user/me`);
    const kakaoResponse = await axios.get("https://kapi.kakao.com/v2/user/me", {
      headers: { Authorization: `Bearer ${kakaoAccessToken}` },
      timeout: 10000,
    });
    const kakaoId = String(kakaoResponse.data.id);
    console.log(`✅ [${rid}] kakaoId=${kakaoId}`);
       const bindUid = await getBindUidFromAuthHeader(req); 
    const extKey = `kakao:${kakaoId}`;
    const extRef = db.collection("externalIndex").doc(extKey);
    const snap = await extRef.get();

    if (snap.exists) {
      // 이미 묶여 있음 → 즉시 로그인용 토큰 발급
      const uid = snap.get("uid");
      const customToken = await admin.auth().createCustomToken(uid, { provider: "kakao" });
      return res.status(200).json({ bound: true, firebase_token: customToken, req_id: rid });
    } else if (bindUid) {
      // Authorization 헤더에 있는 현재 UID에 바인드
      await extRef.create({ uid: bindUid, provider: "kakao", createdAt: FieldValue.serverTimestamp() });
      const customToken = await admin.auth().createCustomToken(bindUid, { provider: "kakao" });
      return res.status(200).json({ bound: true, firebase_token: customToken, req_id: rid });
    } else if (checkOnly) {
      // 사전조회만: 새 UID 만들지 말고 '아직 미바인드'만 알림
      return res.status(200).json({ bound: false, req_id: rid });
    } else {
      // 최초 회원가입 루트에서만 새 UID 생성
      const userRecord = await admin.auth().createUser({});
      const uid = userRecord.uid;
      try {
        await extRef.create({ uid, provider: "kakao", createdAt: FieldValue.serverTimestamp() });
      } catch (e) {
        await admin.auth().deleteUser(uid).catch(()=>{});
        const taken = await extRef.get();
        if (!taken.exists) throw e;
      }
      const finalSnap = await extRef.get();
      const finalUid = finalSnap.get("uid");
      const customToken = await admin.auth().createCustomToken(finalUid, { provider: "kakao" });
      return res.status(200).json({ bound: true, firebase_token: customToken, req_id: rid });
    }

  } catch (error) {
    const m = error?.message || "Server error";
    const axiosStatus = error?.response?.status;
    const axiosData = error?.response?.data;
    console.error(`❌ [${rid}] error=${m} axiosStatus=${axiosStatus || "-"} data=${JSON.stringify(axiosData || {})}`);

    let code = "SERVER_ERROR", status = 500;
    if (m === "APPCHECK_MISSING") { code = "APPCHECK_MISSING"; status = 401; }
    else if (m === "RATE_LIMIT")  { code = "RATE_LIMIT";       status = 429; }
    else if (axiosStatus === 401) { code = "KAKAO_UNAUTHORIZED"; status = 401; }
    else if (axiosStatus === 400) { code = "KAKAO_BAD_REQUEST";  status = 400; }

    return replyError(res, status, code, m, rid);
  }
});

exports.kakaoLogin = onRequest(app);



// ------------------ 매칭 트리거 ------------------
// onCreate: 최초 큐 진입
exports.onJoinQueue = onDocumentCreated("matchingQueue/{uid}", async () => {
  await tryPairTwo();
});
// onWrite: 기존 문서가 'waiting' 상태로 변경될 때도 매칭 시도
exports.onQueueWrite = onDocumentWritten("matchingQueue/{uid}", async (event) => {
  const before = event.data?.before?.data();
  const after  = event.data?.after?.data();
  if (!after) return; // 삭제
  const becameWaiting = after.status === "waiting" && (!before || before.status !== "waiting");
  if (becameWaiting) await tryPairTwo();
});

// ------------------ Idempotent 매칭 트랜잭션 ------------------
async function tryPairTwo() {
  await db.runTransaction(async (tx) => {
    // 1) A 한 명 (최장 대기)
    const aQuery = db.collection("matchingQueue")
      .where("status", "==", "waiting")
      .orderBy("createdAt", "asc")
      .limit(1);
    const aSnap = await tx.get(aQuery);
    if (aSnap.empty) return;

    const a = aSnap.docs[0];
    const aRef = a.ref;
    const aUid = a.get("uid") || a.id;
    const aGender = a.get("gender");
    const aWant   = a.get("wantGender"); // "남자" | "여자" | "all"

    if (!aGender || !aWant) {
      tx.update(aRef, { status: "error_missing_fields" });
      return;
    }

    // 2) A 기준, 호환되는 B 쿼리 만들기
    // B는 반드시 A를 받아줘야 함 (B.wantGender ∈ {A.gender, "all"})
    let baseBQuery = db.collection("matchingQueue")
      .where("status", "==", "waiting")
      .where("wantGender", "in", [aGender, "all"])
      .orderBy("createdAt", "asc");

    if (aWant !== "all") {
      // A가 특정 성별을 원하면 B.gender 고정
      baseBQuery = db.collection("matchingQueue")
        .where("status", "==", "waiting")
        .where("gender", "==", aWant)
        .where("wantGender", "in", [aGender, "all"])
        .orderBy("createdAt", "asc");
    }

    // ✅ 후보를 여러 명 가져와서 자기 자신을 스킵
    const bSnap = await tx.get(baseBQuery.limit(5));
    if (bSnap.empty) return;

    const bDoc = bSnap.docs.find(d => ((d.get("uid") || d.id) !== aUid));
    if (!bDoc) return; // 후보가 전부 자기 자신뿐이면 다음 기회에

    const b = bDoc;
    const bRef = b.ref;
    const bUid = b.get("uid") || b.id;

    // 3) 중복/활성 체크 (양쪽 모두 방 없음이어야 함)
    const aUserRef = db.collection("users").doc(aUid);
    const bUserRef = db.collection("users").doc(bUid);
    const [aUserDoc, bUserDoc] = await Promise.all([tx.get(aUserRef), tx.get(bUserRef)]);
    if ((aUserDoc.exists && aUserDoc.get("activeRoomId")) ||
        (bUserDoc.exists && bUserDoc.get("activeRoomId"))) return;

    // 4) 잠금 → 방 생성 → 상태 업데이트
    tx.update(aRef, { status: "locking" });
    tx.update(bRef, { status: "locking" });

    const roomRef = db.collection("matchedRooms").doc();
    tx.set(roomRef, {
      user1: aUid,
      user2: bUid,
      users: [aUid, bUid],
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
      heartbeat: { [aUid]: nowTs(), [bUid]: nowTs() },
    });

    tx.set(aUserRef, { activeRoomId: roomRef.id, matchPhase: "matched" }, { merge: true });
    tx.set(bUserRef, { activeRoomId: roomRef.id, matchPhase: "matched" }, { merge: true });

    tx.delete(aRef);
    tx.delete(bRef);
  });
}


// ------------------ 강제 매칭(디버그/운영용) ------------------
exports.forceMatch = onRequest(async (_req, res) => {
  try {
    await tryPairTwo();
    res.json({ ok: true });
  } catch (e) {
    console.error("forceMatch error:", e);
    res.status(500).json({ ok: false, error: e.message });
  }
});

// ------------------ 매칭 취소 (HTTPS) ------------------
exports.cancelMatch = onRequest(async (req, res) => {
  try {
    const uid = await verifyAuth(req);
    await db.runTransaction(async (tx) => {
      const userRef = db.collection("users").doc(uid);
      const userDoc = await tx.get(userRef);
      const roomId = userDoc.get("activeRoomId");

      if (!roomId) {
        // 큐만 청소 + 내 상태 idle 보증
        tx.set(userRef, { matchPhase: "idle", activeRoomId: FieldValue.delete() }, { merge: true });
        tx.delete(db.collection("matchingQueue").doc(uid));
        return;
      }

      const roomRef = db.collection("matchedRooms").doc(roomId);
      const roomDoc = await tx.get(roomRef);
      if (!roomDoc.exists) {
        tx.set(userRef, { matchPhase: "idle", activeRoomId: FieldValue.delete() }, { merge: true });
        tx.delete(db.collection("matchingQueue").doc(uid));
        return;
      }

      const d = roomDoc.data() || {};
      const users = d.users || [d.user1, d.user2].filter(Boolean);

      // 방 삭제 + 모든 참가자 상태 초기화 + 큐 정리
      tx.delete(roomRef);
      users.forEach((u) => {
        if (!u) return;
        tx.set(db.collection("users").doc(u), { matchPhase: "idle", activeRoomId: FieldValue.delete() }, { merge: true });
        tx.delete(db.collection("matchingQueue").doc(u));
      });
    });

    res.status(200).json({ ok: true });
  } catch (e) {
    console.error("cancelMatch error:", e);
    res.status(400).json({ ok: false, error: e.message });
  }
});

// ------------------ 방 입장(라이브 전환, 권장) ------------------
exports.enterRoom = onRequest(async (req, res) => {
  const rid = ridOf(req);
  try {
    console.log(`➡️ [enterRoom] rid=${rid} body=${JSON.stringify(req.body||{})}`);
    const uid = await verifyAuth(req);
    const { roomId } = req.body || {};
    if (!roomId) throw new Error("Missing roomId");

    const roomRef    = db.collection("matchedRooms").doc(roomId);
    const csRef      = db.collection("callSessions").doc(roomId);

    await db.runTransaction(async (tx) => {
      // ===== 모든 읽기 먼저 =====
      const roomSnap = await tx.get(roomRef);
      if (!roomSnap.exists) throw new Error("Room not found");
      const users = roomSnap.get("users") || [];
      if (!users.includes(uid)) throw new Error("Not a participant");

      const csSnap = await tx.get(csRef);

      // ===== 이제부터 쓰기만 =====
      // call session 생성/업데이트 (읽기 금지)
      ensureCallSessionWritesOnly(tx, { csRef, csSnap, roomId, users });

      // room 갱신(하트비트 포함)
      tx.update(roomRef, {
        status: "active",              // 용어 통일 추천: active vs live 중 하나로
        [`heartbeat.${uid}`]: nowTs() // 외부 I/O 없는 로컬 계산 OK
      });

      // (선택) users/* 업데이트가 필요하면 여기에 함께 몰아넣기 (쓰기만!)
    });

    console.log(`⬅️ [enterRoom] rid=${rid} ok roomId=${roomId} uid=${uid}`);
    res.json({ ok: true });
  } catch (e) {
    console.error(`🧨 [enterRoom] rid=${rid} error=${e.message}`);
    res.status(400).json({ ok: false, error: e.message });
  }
});



// ------------------ 하트비트(통화 중) ------------------
// heartbeat
exports.heartbeat = onRequest(async (req, res) => {
  const rid = ridOf(req);
  try {
    const uid = await verifyAuth(req);
    const userRef = db.collection("users").doc(uid);
    const userDoc = await userRef.get();
    if (!userDoc.exists) { console.log(`ℹ️ [heartbeat] rid=${rid} uid=${uid} no userDoc`); return res.json({ ok: true, note: "user doc missing (skip heartbeat)" }); }
    const roomId = userDoc.get("activeRoomId");
    if (!roomId) { console.log(`ℹ️ [heartbeat] rid=${rid} uid=${uid} no activeRoom`); return res.json({ ok: true, note: "no active room" }); }
    await userRef.update({ lastHeartbeat: nowTs() });
    await db.collection("matchedRooms").doc(roomId).update({ [`heartbeat.${uid}`]: nowTs() });
    console.log(`✅ [heartbeat] rid=${rid} uid=${uid} roomId=${roomId}`);
    res.json({ ok: true });
  } catch (e) {
    console.error(`🧨 [heartbeat] rid=${rid} error=${e.message}`);
    res.status(400).json({ ok: false, error: e.message });
  }
});


// ------------------ 오래된 방/유령 정리 (스케줄러) ------------------
exports.cleanupStaleMatches = onSchedule("every 1 minutes", async () => {
  const batch = db.batch();
  const now = Date.now();

  const PENDING_TIMEOUT_MS = 60 * 1000;  // 테스트용
  const LIVE_STALE_MS      = 20 * 1000;  // 하트비트 끊긴 방

  const rooms = await db.collection("matchedRooms").get();
  rooms.forEach((doc) => {
    const d = doc.data() || {};
    const users = d.users || [d.user1, d.user2].filter(Boolean);
    const hb    = d.heartbeat || {};
    const status = d.status || "pending";

    const newest = Math.max(...users.map(u => hb[u]?.toMillis?.() ?? 0), 0);
    const oldest = Math.min(...users.map(u => hb[u]?.toMillis?.() ?? 0).filter(Boolean));

    let expired = false;
    if (status === "pending") {
      // ① pending이 너무 오래 지속
      expired = users.some(u => !hb[u]) || (oldest && (oldest < now - PENDING_TIMEOUT_MS));
    } else if (status === "active") {
      // ② live인데 참가자 전원 또는 상대가 일정기간 무응답
      const allStale = users.every(u => !hb[u] || hb[u].toMillis() < now - LIVE_STALE_MS);
      expired = allStale;
    }

    if (expired) {
      users.forEach(u => {
        if (!u) return;
        batch.set(db.collection("users").doc(u), { activeRoomId: FieldValue.delete(), matchPhase: "idle" }, { merge: true });
        batch.delete(db.collection("matchingQueue").doc(u));
      });
      batch.delete(doc.ref);
    }
  });

  // 2) dangling user self-heal
  const usersWithRoom = await db.collection("users")
    .where("activeRoomId", "!=", null)
    .get();

  for (const doc of usersWithRoom.docs) {
    const rid = doc.get("activeRoomId");
    if (!rid) continue;
    const roomSnap = await db.collection("matchedRooms").doc(rid).get();
    if (!roomSnap.exists) {
      batch.set(doc.ref, { activeRoomId: FieldValue.delete(), matchPhase: "idle" }, { merge: true });
      batch.delete(db.collection("matchingQueue").doc(doc.id)); // 혹시 잔재가 있으면
    }
  }

  await batch.commit();
});

// ------------------ 대기열 유령 정리 (스케줄러, 권장) ------------------
exports.cleanupWaitingQueue = onSchedule("every 1 minutes", async () => {
  // 하트비트 기준으로 2분 이상 무응답 waiting 제거 (정책에 맞게 조절)
  const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - 2 * 60 * 1000);

  // 인덱스 필요: status ASC, heartbeatAt ASC
  const snap = await db.collection("matchingQueue")
    .where("status", "==", "waiting")
    .where("heartbeatAt", "<", cutoff)
    .get();

  const batch = db.batch();
  snap.forEach(doc => batch.delete(doc.ref));
  await batch.commit();
});

// ------------------ Agora 토큰 발급 (HTTPS) ------------------
exports.getAgoraToken = onRequest({ secrets: [AGORA_APP_ID, AGORA_APP_CERT] }, async (req, res) => {
  try {
    const uid = await verifyAuth(req);
    const roomId = (req.body && req.body.roomId) ?? req.query.roomId;
    const rtcUid = Number((req.body && req.body.rtcUid) ?? req.query.rtcUid);
    if (!roomId || !rtcUid) throw new Error("Missing roomId or rtcUid");

    const { appId, appCert } = getAgoraCreds();
    if (!appId || !appCert) throw new Error("Missing Agora credentials");

    const expireSeconds = 60 * 30; // 30분
    const now = Math.floor(Date.now() / 1000);
    const privilegeExpiredTs = now + expireSeconds;

    const token = RtcTokenBuilder.buildTokenWithUid(
      appId, appCert, String(roomId), rtcUid, RtcRole.PUBLISHER, privilegeExpiredTs
    );

    res.json({ token, appId, channel: String(roomId), rtcUid, expireSeconds });
  } catch (e) {
    console.error("getAgoraToken error:", e);
    res.status(400).json({ error: e.message });
  }
});

function ensureCallSessionWritesOnly(tx, { csRef, csSnap, roomId, users }) {
  if (!csSnap.exists) {
    const nowMs  = Date.now(); // 트랜잭션 내에서 로컬 시간 사용은 괜찮음(외부 I/O 아님)
    const started = Timestamp.fromMillis(nowMs);
    const ends    = Timestamp.fromMillis(nowMs + 10 * 60 * 1000);

    tx.set(csRef, {
      roomId,
      users,
      status: "active", // 기존 "active" 사용 중이면 통일하세요
      startedAt: started,
      endsAt: ends,
      extensionHistory: [],
      maxMinutesCap: 60,
      createdAt: FieldValue.serverTimestamp(),
    });
  } else {
    // 이미 있으면 상태만 보정하거나 heartbeat/필드 업데이트가 필요하면 여기서 "쓰기만"
    tx.update(csRef, { status: "active" });
  }
}



// ------------------ 통화 연장 (Callable) ------------------
exports.extendSession = onCall(async (req) => {
  const ctx = req.auth;
  if (!ctx) throw new Error("unauthenticated");
  const { roomId, addSeconds } = req.data || {};
  if (!roomId) throw new Error("Missing roomId");
  if (![420, 600].includes(addSeconds)) throw new Error("Invalid addSeconds");

  const ref = db.collection("callSessions").doc(roomId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new Error("session not found");
    const s = snap.data();
    if (s.status !== "active") throw new Error("not active");

    const now = Timestamp.now();
    const endsAt = s.endsAt?.toDate ? s.endsAt.toDate() : new Date();
    const base = (endsAt > new Date()) ? endsAt : new Date(); // 남은 시간 0이어도 확장
    const nextEnds = new Date(base.getTime() + addSeconds * 1000);

    // 총 길이 상한
    if (s.maxMinutesCap) {
      const started = s.startedAt?.toDate ? s.startedAt.toDate() : new Date();
      const maxEnd = new Date(started.getTime() + s.maxMinutesCap * 60 * 1000);
      if (nextEnds > maxEnd) throw new Error("over cap");
    }

    tx.update(ref, {
      endsAt: Timestamp.fromDate(nextEnds),
      extensionHistory: FieldValue.arrayUnion({
        by: ctx.uid, seconds: addSeconds, at: now,
      })
    });
  });

  return { ok: true };
});

// ------------------ 통화 종료 (Callable) ------------------
exports.endSession = onCall(async (req) => {
  const rid = (req.rawRequest && req.rawRequest.get && req.rawRequest.get("X-Call-Rid")) || "-";
  const ctx = req.auth;
  if (!ctx) throw new Error("unauthenticated");
  const { roomId } = req.data || {};
  if (!roomId) throw new Error("Missing roomId");

  console.log(`➡️ [endSession] rid=${rid} roomId=${roomId} by=${ctx.uid}`);

  await db.runTransaction(async (tx) => {
    const roomRef = db.collection("matchedRooms").doc(roomId);
    const csRef   = db.collection("callSessions").doc(roomId);

    const roomSnap = await tx.get(roomRef);
    if (!roomSnap.exists) {
      // ✅ callSessions에서 users를 읽어 유저 상태도 정리 (방이 이미 사라진 레이스 처리)
      const csSnap = await tx.get(csRef);
      if (csSnap.exists) {
        const users = csSnap.get("users") || [];
        users.forEach(u => {
          if (!u) return;
          tx.set(db.collection("users").doc(u),
                 { matchPhase: "idle", activeRoomId: FieldValue.delete() },
                 { merge: true });
          tx.delete(db.collection("matchingQueue").doc(u));
        });
      }
      tx.set(csRef, { status: "ended" }, { merge: true });
      return;
    }

    // (기존 로직 유지)
    const d = roomSnap.data() || {};
    const users = d.users || [d.user1, d.user2].filter(Boolean);

    // 1) 세션/방 상태 종료
    tx.set(csRef,   { status: "ended" }, { merge: true });
    tx.set(roomRef, { status: "ended" }, { merge: true });

    // 2) 양쪽 유저 상태 원복 + 큐 정리
    users.forEach((u) => {
      if (!u) return;
      tx.set(db.collection("users").doc(u), { matchPhase: "idle", activeRoomId: FieldValue.delete() }, { merge: true });
      tx.delete(db.collection("matchingQueue").doc(u));
    });

    // 3) 방 문서 삭제 → 클라이언트 워처가 REMOVE 수신하며 즉시 정리
    tx.delete(roomRef);
  });

  console.log(`⬅️ [endSession] rid=${rid} done`);
  return { ok: true };
});



// ------------------ 세션 만료 자동 종료 (스케줄러) ------------------
exports.cleanupExpiredSessions = onSchedule("every 1 minutes", async () => {
  const nowMs = Date.now();
  const sessions = await db.collection("callSessions")
    .where("status", "==", "active").get();

  for (const doc of sessions.docs) {
    const d = doc.data();
    const ends = d.endsAt?.toMillis?.() ?? 0;
    if (!ends || ends > nowMs) continue;

    const roomRef = db.collection("matchedRooms").doc(doc.id);
    const roomSnap = await roomRef.get();

    const batch = db.batch();
    // 1) 세션 상태 종료
    batch.set(doc.ref, { status: "ended" }, { merge: true });

    if (roomSnap.exists) {
      const r = roomSnap.data() || {};
      const users = r.users || [r.user1, r.user2].filter(Boolean);

      // 2) 룸 상태 종료 + 유저 상태 초기화 + 큐 제거
      batch.set(roomRef, { status: "ended" }, { merge: true });
      users.forEach(u => {
        if (!u) return;
        batch.set(db.collection("users").doc(u), { matchPhase: "idle", activeRoomId: FieldValue.delete() }, { merge: true });
        batch.delete(db.collection("matchingQueue").doc(u));
      });

      // 3) 룸 문서 삭제 (워처들이 REMOVE 수신하며 즉시 클린업)
      batch.delete(roomRef);
    } else {
      // 룸이 이미 없으면 최소 상태만 종료 (dangling user는 cleanupStaleMatches가 회수)
      batch.set(roomRef, { status: "ended" }, { merge: true });
    }

    await batch.commit();
  }
});



// ------------------ Apple Login (HTTPS) ------------------
exports.appleLogin = onRequest({ secrets: [APPLE_AUDIENCE_BUNDLE_ID] }, async (req, res) => {
  try {
    await verifyAppCheck(req);
    await guardRate(req);
    

    const { identityToken, rawNonceHash, appleUserId } = req.body || {};
    if (!identityToken && !appleUserId) return res.status(400).json({ error: "No token" });

    let appleSub = appleUserId;
    if (identityToken) {
      const expectedAudience = APPLE_AUDIENCE_BUNDLE_ID.value();
      const claims = await verifyAppleIdentityToken(identityToken, expectedAudience, rawNonceHash);
      appleSub = claims.sub;
    }
    if (!appleSub) return res.status(400).json({ error: "Invalid token" });
        // ★ 추가: 사전조회 모드 파싱
    const mode = (req.query.mode || req.body?.mode || "").toString();
    const checkOnly = (mode === "check");
    const bindUid = await getBindUidFromAuthHeader(req);
    const extKey = `apple:${appleSub}`;
    const extRef = db.collection("externalIndex").doc(extKey);
    const snap = await extRef.get();

    if (snap.exists) {
      const uid = snap.get("uid");
      const customToken = await admin.auth().createCustomToken(uid, { provider: "apple" });
      return res.status(200).json({ bound: true, firebase_token: customToken });
    } else if (bindUid) {
      await extRef.create({ uid: bindUid, provider: "apple", createdAt: FieldValue.serverTimestamp() });
      const customToken = await admin.auth().createCustomToken(bindUid, { provider: "apple" });
      return res.status(200).json({ bound: true, firebase_token: customToken });
    } else if (checkOnly) {
      return res.status(200).json({ bound: false });
    } else {
      const userRecord = await admin.auth().createUser({});
      const uid = userRecord.uid;
      try {
        await extRef.create({ uid, provider: "apple", createdAt: FieldValue.serverTimestamp() });
      } catch (e) {
        await admin.auth().deleteUser(uid).catch(() => {});
        const taken = await extRef.get();
        if (!taken.exists) throw e;
      }
      const finalSnap = await extRef.get();
      const finalUid = finalSnap.get("uid");
      const customToken = await admin.auth().createCustomToken(finalUid, { provider: "apple" });
      return res.status(200).json({ bound: true, firebase_token: customToken });
    }

  } catch (e) {
    console.error("❌ appleLogin error:", e);
    return res.status(500).json({ error: e.message || "Server error" });
  }
});


// helper
async function verifyAppleIdentityToken(idToken, expectedAudience, expectedNonceHash) {
  const jose = await ensureJose(); // 동적 import 보장
  const { payload } = await jose.jwtVerify(idToken, _appleJWKS, {
    algorithms: ["RS256"],
    issuer: "https://appleid.apple.com",
    audience: expectedAudience,
  });
  if (expectedNonceHash && payload.nonce !== expectedNonceHash) {
    throw new Error("INVALID_NONCE");
  }
  return payload;
}


async function guardRate(req) {
  try {
    const ip = (req.headers["x-forwarded-for"] || req.ip || "").toString().split(",")[0].trim();
    const day = new Date().toISOString().slice(0,10);
    const ref = db.collection("rate").doc(`${ip}:${day}`);
    await db.runTransaction(async (tx) => {
      const s = await tx.get(ref);
      const cnt = (s.exists ? s.get("count") : 0) + 1;
      if (cnt > 200) throw new Error("RATE_LIMIT"); // 정책에 맞게 조절
      tx.set(ref, { count: cnt, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    });
  } catch {
    throw new Error("RATE_LIMIT");
  }
}

async function verifyAppCheck(req) {
  const token = req.header("X-Firebase-AppCheck");
  if (!token) throw new Error("APPCHECK_MISSING");
  await admin.appCheck().verifyToken(token); // 유효하지 않으면 throw
}

async function ensureJose() {
  if (!_joseLib) {
    _joseLib = await import('jose'); // ESM 동적 import
  }
  if (!_appleJWKS) {
    _appleJWKS = _joseLib.createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));
  }
  return _joseLib;
}

