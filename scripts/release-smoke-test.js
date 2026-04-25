const { spawnSync } = require("node:child_process");
const path = require("node:path");

const projectRoot = path.resolve(__dirname, "..");
const releaseScript = path.join(projectRoot, "scripts", "notarize-macos-app.sh");

const result = spawnSync(releaseScript, [], {
  cwd: projectRoot,
  encoding: "utf8",
  timeout: 10000,
  env: {
    ...process.env,
    DEVELOPER_ID_APPLICATION: "",
    APPLE_NOTARY_PROFILE: "",
    APPLE_ID: "",
    APPLE_TEAM_ID: "",
    APPLE_APP_SPECIFIC_PASSWORD: ""
  }
});

if (result.error) {
  throw result.error;
}

if (result.status === 0) {
  throw new Error(`release smoke test unexpectedly succeeded.\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}`);
}

const combinedOutput = `${result.stdout}\n${result.stderr}`;
if (!combinedOutput.includes("DEVELOPER_ID_APPLICATION is required for release signing.")) {
  throw new Error(`release smoke test did not fail with the expected missing-signing message.\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}`);
}

if (!combinedOutput.includes("Usage: ./scripts/notarize-macos-app.sh")) {
  throw new Error(`release smoke test did not print usage guidance.\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}`);
}

console.log("Release smoke test passed");
