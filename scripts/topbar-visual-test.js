const { spawnSync } = require("node:child_process");
const path = require("node:path");

const projectRoot = path.resolve(__dirname, "..");
const appBinary = path.join(projectRoot, "dist", "DeskMD.app", "Contents", "MacOS", "DeskMD");

const result = spawnSync(appBinary, ["--topbar-visual-test"], {
  encoding: "utf8",
  timeout: 15000
});

if (result.error) {
  throw result.error;
}

if (result.status !== 0) {
  throw new Error(`Topbar layout app exited with ${result.status}\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}`);
}

if (!result.stdout.includes("Topbar layout test result: passed:")) {
  throw new Error(`Topbar layout test did not report passed.\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}`);
}

if (!result.stdout.includes("passed:desktop:") || !result.stdout.includes("passed:narrow:")) {
  throw new Error(`Topbar layout test did not cover both desktop and narrow widths.\nSTDOUT:\n${result.stdout}`);
}

console.log(result.stdout.trim());
console.log("Topbar layout test passed");
