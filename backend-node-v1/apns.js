/**
 * apns.js — APNs push notification sender via HTTP/2 + JWT (ES256).
 *
 * Uses the `jose` package (already in deps) and Node's built-in `http2`.
 * Requires: APNS_KEY_PATH, APNS_KEY_ID, APNS_TEAM_ID env vars.
 */

const http2 = require("http2");
const fs = require("fs");
const { SignJWT, importPKCS8 } = require("jose");

const APNS_HOST_PROD = "https://api.push.apple.com";
const APNS_HOST_DEV = "https://api.sandbox.push.apple.com";
const BUNDLE_ID = process.env.APPLE_AUDIENCES || "com.claire.streetstamps";

let cachedKey = null;
let cachedJWT = null;
let cachedJWTExpiry = 0;

function isConfigured() {
  return !!(process.env.APNS_KEY_PATH && process.env.APNS_KEY_ID && process.env.APNS_TEAM_ID);
}

async function getSigningKey() {
  if (cachedKey) return cachedKey;
  const pem = fs.readFileSync(process.env.APNS_KEY_PATH, "utf8");
  cachedKey = await importPKCS8(pem, "ES256");
  return cachedKey;
}

async function getJWT() {
  const now = Math.floor(Date.now() / 1000);
  // APNs tokens are valid for up to 1 hour; refresh at 50 min
  if (cachedJWT && now < cachedJWTExpiry) return cachedJWT;

  const key = await getSigningKey();
  cachedJWT = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: process.env.APNS_KEY_ID })
    .setIssuer(process.env.APNS_TEAM_ID)
    .setIssuedAt(now)
    .sign(key);
  cachedJWTExpiry = now + 50 * 60;
  return cachedJWT;
}

/**
 * Send a push notification to a single device token.
 * Returns { success, status, reason } or throws on connection error.
 */
function sendPush(deviceToken, payload, options = {}) {
  return new Promise(async (resolve, reject) => {
    try {
      const jwt = await getJWT();
      const host = process.env.APNS_USE_SANDBOX === "true" ? APNS_HOST_DEV : APNS_HOST_PROD;
      const body = JSON.stringify(payload);

      const client = http2.connect(host);
      client.on("error", (err) => {
        client.close();
        reject(err);
      });

      const headers = {
        ":method": "POST",
        ":path": `/3/device/${deviceToken}`,
        "authorization": `bearer ${jwt}`,
        "apns-topic": BUNDLE_ID,
        "apns-push-type": options.pushType || "alert",
        "apns-priority": String(options.priority || 10),
      };
      if (options.expiration != null) {
        headers["apns-expiration"] = String(options.expiration);
      }
      if (options.collapseId) {
        headers["apns-collapse-id"] = options.collapseId;
      }

      const req = client.request(headers);
      const chunks = [];

      req.on("response", (responseHeaders) => {
        const status = responseHeaders[":status"];
        req.on("data", (chunk) => chunks.push(chunk));
        req.on("end", () => {
          client.close();
          const responseBody = Buffer.concat(chunks).toString("utf8");
          if (status === 200) {
            resolve({ success: true, status });
          } else {
            let reason = "";
            try { reason = JSON.parse(responseBody).reason || ""; } catch {}
            resolve({ success: false, status, reason, token: deviceToken });
          }
        });
      });

      req.on("error", (err) => {
        client.close();
        reject(err);
      });

      req.end(body);
    } catch (err) {
      reject(err);
    }
  });
}

/**
 * Send a push to multiple device tokens for a user.
 * Removes invalid tokens via the provided cleanup callback.
 */
async function sendToUser(tokens, alert, data, onInvalidToken, badge) {
  if (!isConfigured() || !tokens?.length) return;

  const payload = {
    aps: {
      alert,
      sound: "default",
    },
  };
  if (typeof badge === "number" && badge >= 0) payload.aps.badge = badge;
  if (data) payload.d = data;

  for (const { token } of tokens) {
    try {
      const result = await sendPush(token, payload);
      if (!result.success) {
        console.log(`[APNs] push failed token=${token.slice(0, 8)}... status=${result.status} reason=${result.reason}`);
        // Clean up invalid/unregistered tokens
        if (result.reason === "BadDeviceToken" || result.reason === "Unregistered" || result.status === 410) {
          if (onInvalidToken) await onInvalidToken(token);
        }
      }
    } catch (err) {
      console.error(`[APNs] send error token=${token.slice(0, 8)}...`, err.message);
    }
  }
}

module.exports = { isConfigured, sendPush, sendToUser };
