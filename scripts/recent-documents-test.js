const { spawnSync } = require("node:child_process");
const path = require("node:path");

const projectRoot = path.resolve(__dirname, "..");
const appBinary = path.join(projectRoot, "dist", "DeskMD.app", "Contents", "MacOS", "DeskMD");

const result = spawnSync(appBinary, ["--recent-documents-test"], {
  encoding: "utf8",
  timeout: 10000
});

if (result.error) {
  throw result.error;
}

if (result.status !== 0) {
  throw new Error(`Recent documents app exited with ${result.status}\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}`);
}

if (!result.stdout.includes("Recent documents test result: passed")) {
  throw new Error(`Recent documents test did not report passed.\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}`);
}

console.log(result.stdout.trim());
console.log("Recent documents test passed");
