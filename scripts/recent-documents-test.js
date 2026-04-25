const { spawnSync } = require("node:child_process");
const path = require("node:path");

const projectRoot = path.resolve(__dirname, "..");
const appBinary = path.join(projectRoot, "dist", "DeskMD.app", "Contents", "MacOS", "DeskMD");

function runPhase(phase) {
  const result = spawnSync(appBinary, [`--recent-documents-test-phase=${phase}`], {
    encoding: "utf8",
    timeout: 10000
  });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    throw new Error(`Recent documents app exited with ${result.status} during ${phase}\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}`);
  }

  return result;
}

const seedResult = runPhase("seed");
if (!seedResult.stdout.includes("Recent documents test seed result: passed")) {
  throw new Error(`Recent documents seed phase did not report passed.\nSTDOUT:\n${seedResult.stdout}\nSTDERR:\n${seedResult.stderr}`);
}

const verifyResult = runPhase("verify");
if (!verifyResult.stdout.includes("Recent documents test result: passed")) {
  throw new Error(`Recent documents verify phase did not report passed.\nSTDOUT:\n${verifyResult.stdout}\nSTDERR:\n${verifyResult.stderr}`);
}

console.log(seedResult.stdout.trim());
console.log(verifyResult.stdout.trim());
console.log("Recent documents test passed");
