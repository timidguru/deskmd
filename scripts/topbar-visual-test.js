const { spawnSync } = require("node:child_process");
const path = require("node:path");

const projectRoot = path.resolve(__dirname, "..");
const appBinary = path.join(projectRoot, "dist", "DeskMD.app", "Contents", "MacOS", "DeskMD");

function runTopbarTest(label, args) {
  const result = spawnSync(appBinary, args, {
    encoding: "utf8",
    timeout: 15000
  });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    throw new Error(`${label} topbar app exited with ${result.status}\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}`);
  }

  if (!result.stdout.includes("Topbar layout test result: passed:")) {
    throw new Error(`${label} topbar test did not report passed.\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}`);
  }

  if (!result.stdout.includes("passed:desktop:") || !result.stdout.includes("passed:narrow:")) {
    throw new Error(`${label} topbar test did not cover both desktop and narrow widths.\nSTDOUT:\n${result.stdout}`);
  }

  return result.stdout.trim();
}

const systemOutput = runTopbarTest("System appearance", ["--topbar-visual-test"]);
const darkOutput = runTopbarTest("Dark appearance", ["--topbar-visual-test", "--force-dark-appearance"]);

if (!darkOutput.includes('"appearance":"dark"')) {
  throw new Error(`Dark appearance test did not verify dark appearance.\nSTDOUT:\n${darkOutput}`);
}

console.log(systemOutput);
console.log(darkOutput);
console.log("Topbar layout and dark appearance tests passed");
