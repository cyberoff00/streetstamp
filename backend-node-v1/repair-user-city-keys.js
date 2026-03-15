const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || "postgresql://streetstamps:streetstamps@localhost:5432/streetstamps"
});

const STATE_KEY = process.env.PG_STATE_KEY || "global";
const TARGET_USER_ID = String(process.env.TARGET_USER_ID || "").trim();
const TARGET_EMAIL = String(process.env.TARGET_EMAIL || "").trim().toLowerCase();
const APPLY = ["1", "true", "yes"].includes(String(process.env.APPLY || "").trim().toLowerCase());
const CITY_ID_REWRITES = parseJSONEnv("CITY_ID_REWRITES");
const TITLE_TO_CITY_ID = parseJSONEnv("TITLE_TO_CITY_ID");

function parseJSONEnv(name) {
  const base64Raw = String(process.env[`${name}_BASE64`] || "").trim();
  if (base64Raw) {
    try {
      return JSON.parse(Buffer.from(base64Raw, "base64").toString("utf8"));
    } catch (error) {
      throw new Error(`${name}_BASE64 must decode to valid JSON: ${error.message}`);
    }
  }
  const raw = String(process.env[name] || "").trim();
  if (!raw) return {};
  try {
    return JSON.parse(raw);
  } catch (error) {
    throw new Error(`${name} must be valid JSON: ${error.message}`);
  }
}

function normalizeText(value) {
  return String(value || "")
    .trim()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
}

function cityNameFromID(cityID) {
  return String(cityID || "").split("|")[0].trim();
}

function rewrittenCityID(raw) {
  const trimmed = String(raw || "").trim();
  if (!trimmed) return "";
  return String(CITY_ID_REWRITES[trimmed] || trimmed).trim();
}

function preferredCardFor(cards, requestedID) {
  const rewritten = rewrittenCityID(requestedID);
  return cards.find((card) => String(card.id || "").trim() === rewritten) || null;
}

function inferCityID({ journey, cards }) {
  const title = String(journey.title || "").trim();
  if (!title) return "";

  const titleRewrite = String(TITLE_TO_CITY_ID[title] || "").trim();
  if (titleRewrite && preferredCardFor(cards, titleRewrite)) {
    return rewrittenCityID(titleRewrite);
  }

  const normalizedTitle = normalizeText(title);
  if (!normalizedTitle) return "";

  const exact = cards.find((card) => {
    const cardName = normalizeText(card.name);
    const cardKeyName = normalizeText(cityNameFromID(card.id));
    return cardName === normalizedTitle || cardKeyName === normalizedTitle;
  });
  if (exact) return String(exact.id || "").trim();

  const fuzzy = cards.find((card) => {
    const cardName = normalizeText(card.name);
    const cardKeyName = normalizeText(cityNameFromID(card.id));
    return (
      (cardName && (cardName.includes(normalizedTitle) || normalizedTitle.includes(cardName))) ||
      (cardKeyName && (cardKeyName.includes(normalizedTitle) || normalizedTitle.includes(cardKeyName)))
    );
  });
  return fuzzy ? String(fuzzy.id || "").trim() : "";
}

function dedupeCards(cards) {
  const byID = new Map();
  for (const card of cards || []) {
    const nextID = rewrittenCityID(card?.id);
    if (!nextID) continue;
    const existing = byID.get(nextID);
    const next = {
      id: nextID,
      name: String(card?.name || cityNameFromID(nextID)).trim() || cityNameFromID(nextID),
      countryISO2: String(card?.countryISO2 || "").trim() || null
    };
    if (!existing) {
      byID.set(nextID, next);
      continue;
    }
    byID.set(nextID, {
      id: nextID,
      name: existing.name || next.name,
      countryISO2: existing.countryISO2 || next.countryISO2
    });
  }
  return Array.from(byID.values()).sort((a, b) => a.id.localeCompare(b.id));
}

function summarizeJourneys(journeys) {
  const counts = new Map();
  for (const journey of journeys || []) {
    const cityID = String(journey?.cityID || "").trim();
    counts.set(cityID, (counts.get(cityID) || 0) + 1);
  }
  return Array.from(counts.entries())
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([cityID, count]) => ({ cityID, count }));
}

(async () => {
  try {
    if (!TARGET_USER_ID && !TARGET_EMAIL) {
      throw new Error("Provide TARGET_USER_ID or TARGET_EMAIL");
    }

    const result = await pool.query("SELECT state FROM app_state WHERE key = $1", [STATE_KEY]);
    if (!result.rows[0]?.state) {
      throw new Error(`app_state ${STATE_KEY} not found`);
    }
    const db = result.rows[0].state;

    const entry = Object.entries(db.users || {}).find(([userID, user]) => {
      if (TARGET_USER_ID && userID === TARGET_USER_ID) return true;
      if (TARGET_EMAIL && String(user?.email || "").trim().toLowerCase() === TARGET_EMAIL) return true;
      return false;
    });
    if (!entry) {
      throw new Error("target user not found");
    }

    const [userID, user] = entry;
    const originalJourneys = Array.isArray(user.journeys) ? user.journeys : [];
    const originalCards = Array.isArray(user.cityCards) ? user.cityCards : [];
    const repairedCards = dedupeCards(originalCards);
    const repairedJourneys = originalJourneys.map((journey) => {
      const next = { ...journey };
      const currentCityID = rewrittenCityID(journey?.cityID);
      const matchedCurrent = currentCityID && preferredCardFor(repairedCards, currentCityID);
      if (matchedCurrent) {
        next.cityID = currentCityID;
        return next;
      }

      const inferredCityID = inferCityID({ journey: next, cards: repairedCards });
      next.cityID = inferredCityID || null;
      return next;
    });

    const referencedCityIDs = new Set(
      repairedJourneys
        .map((journey) => String(journey?.cityID || "").trim())
        .filter(Boolean)
    );
    const finalCards = repairedCards.filter((card) => {
      const id = String(card.id || "").trim();
      if (!id) return false;
      if (id === "Unknown|") return referencedCityIDs.has(id);
      return true;
    });

    const summary = {
      userID,
      email: user.email || null,
      displayName: user.displayName || null,
      journeyCount: repairedJourneys.length,
      cityCardCountBefore: originalCards.length,
      cityCardCountAfter: finalCards.length,
      cityIDSummaryBefore: summarizeJourneys(originalJourneys),
      cityIDSummaryAfter: summarizeJourneys(repairedJourneys),
      cityCardsBefore: originalCards.map((card) => String(card?.id || "").trim()).sort(),
      cityCardsAfter: finalCards.map((card) => String(card.id || "").trim()).sort()
    };

    console.log(JSON.stringify(summary, null, 2));

    if (!APPLY) {
      console.log("\nDry run only. Set APPLY=true to persist.");
      return;
    }

    user.cityCards = finalCards;
    user.journeys = repairedJourneys;
    await pool.query("UPDATE app_state SET state = $1, updated_at = NOW() WHERE key = $2", [db, STATE_KEY]);
    console.log("\nApplied repair successfully.");
  } finally {
    await pool.end();
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
