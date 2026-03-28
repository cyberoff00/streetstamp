import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const deployScriptPath = path.join(__dirname, "..", "deploy-safe.sh");

test("deploy-safe uploads all required migrations including 003-user-blocks-reports.sql", () => {
  const script = fs.readFileSync(deployScriptPath, "utf8");

  assert.match(script, /backend-node-v1\/migrations\/001-create-tables\.sql/);
  assert.match(script, /backend-node-v1\/migrations\/002-migrate-data\.js/);
  assert.match(script, /backend-node-v1\/migrations\/003-user-blocks-reports\.sql/);
});
