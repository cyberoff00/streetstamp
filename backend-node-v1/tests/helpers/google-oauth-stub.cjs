const { OAuth2Client } = require("google-auth-library");

const raw = process.env.TEST_GOOGLE_OAUTH_FIXTURES || "{}";
let fixtures = {};
try {
  fixtures = JSON.parse(raw);
} catch {
  fixtures = {};
}

OAuth2Client.prototype.verifyIdToken = async function verifyIdToken(options = {}) {
  const token = String(options.idToken || "");
  const payload = fixtures[token];
  if (!payload) {
    throw new Error(`missing google oauth fixture for token: ${token}`);
  }
  return {
    getPayload() {
      return payload;
    }
  };
};
