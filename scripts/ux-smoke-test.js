const { execFileSync, spawnSync } = require("node:child_process");
const path = require("node:path");

const projectRoot = path.resolve(__dirname, "..");
const appBinary = path.join(projectRoot, "dist", "DeskMD.app", "Contents", "MacOS", "DeskMD");

execFileSync("printf", ["DESKMD_COPY_SENTINEL"], { stdio: ["ignore", "pipe", "inherit"] });
execFileSync("sh", ["-c", "printf 'DESKMD_COPY_SENTINEL' | pbcopy"]);

const result = spawnSync(appBinary, ["--ux-smoke-test"], {
  encoding: "utf8",
  timeout: 10000
});

if (result.error) {
  throw result.error;
}

if (result.status !== 0) {
  throw new Error(`UX smoke app exited with ${result.status}\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}`);
}

if (!result.stdout.includes("passed:")) {
  throw new Error(`UX smoke test did not report passed.\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}`);
}

const clipboard = execFileSync("pbpaste", { encoding: "utf8" });
if (!clipboard.includes("UX Smoke")) {
  throw new Error(`clipboard did not include UX Smoke. Clipboard was: ${JSON.stringify(clipboard)}`);
}

console.log(result.stdout.trim());
console.log("UX smoke test passed");
