#!/usr/bin/env node
/**
 * Cross-platform fixer for Google Antigravity VS Code extension download loop.
 * Compatible with all Node.js LTS versions (Node 14+).
 */

const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const readline = require("node:readline");

const args = process.argv.slice(2);
const isRestore = args.includes("--restore") || args.includes("-r");
const isTimeoutOnly = args.includes("--timeout") || args.includes("-t");
const isFull = args.includes("--full") || args.includes("-f");
const isHelp = args.includes("--help") || args.includes("-h");

if (isHelp) {
  console.log(`
Usage: node fix.js [options]

Options:
  --full, -f        Apply Full Fix (30s timeout + interactive update confirmation prompt) [Default]
  --timeout, -t     Apply Timeout Fix only (increase timeout from 5s to 30s)
  --restore, -r     Restore original extension.js from backup
  --help, -h        Show this help message

Running with no flags opens an interactive menu.
`);
  process.exit(0);
}

function promptMenu() {
  return new Promise((resolve) => {
    if (!process.stdin.isTTY) {
      return resolve("full");
    }

    console.log("\x1b[36m==========================================================\x1b[0m");
    console.log("   VS Code Google Antigravity Backend Re-download Fixer   ");
    console.log("\x1b[36m==========================================================\x1b[0m\n");
    console.log("Select an option:");
    console.log("  \x1b[32m[1] Full Fix (30s Timeout + Update Prompt & Snooze)\x1b[0m \x1b[33m[Recommended]\x1b[0m");
    console.log("      - Fixes Defender timeout (5s -> 30s)");
    console.log("      - Prompts before downloading daily updates (Update / Later 1 day / Skip 3 days)");
    console.log("  [2] Timeout Fix Only");
    console.log("      - Increases timeout to 30s without update prompt");
    console.log("  [3] Restore Original Extension from Backup");
    console.log("  [4] Exit\n");

    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
    });

    rl.question("Enter choice [1-4] (default 1): ", (answer) => {
      rl.close();
      const choice = answer.trim();
      if (choice === "2") resolve("timeout");
      else if (choice === "3") resolve("restore");
      else if (choice === "4") resolve("exit");
      else resolve("full");
    });
  });
}

async function main() {
  let mode = "full";

  if (isRestore) {
    mode = "restore";
  } else if (isTimeoutOnly) {
    mode = "timeout";
  } else if (isFull) {
    mode = "full";
  } else {
    mode = await promptMenu();
  }

  if (mode === "exit") {
    console.log("Exiting. No changes made.");
    process.exit(0);
  }

  const homeDir = os.homedir();
  const candidateDirs = [
    path.join(homeDir, ".vscode", "extensions"),
    path.join(homeDir, ".vscode-insiders", "extensions"),
    path.join(homeDir, ".vscode-oss", "extensions"),
    path.join(homeDir, ".cursor", "extensions"),
  ];

  let extensionDirs = [];

  for (const dir of candidateDirs) {
    if (fs.existsSync(dir)) {
      try {
        const items = fs.readdirSync(dir);
        for (const item of items) {
          if (item.startsWith("google.google-antigravity")) {
            extensionDirs.push(path.join(dir, item));
          }
        }
      } catch {
        // ignore unreadable directories
      }
    }
  }

  if (extensionDirs.length === 0) {
    console.error("\x1b[31m[-] Could not find any 'google.google-antigravity' extension installed.\x1b[0m");
    process.exit(1);
  }

  function writeAtomicSync(filePath, content) {
    const tmpPath = filePath + ".tmp";
    try {
      fs.writeFileSync(tmpPath, content, "utf8");
      fs.renameSync(tmpPath, filePath);
    } catch (err) {
      if (fs.existsSync(tmpPath)) {
        try { fs.unlinkSync(tmpPath); } catch {}
      }
      throw err;
    }
  }

  for (const extDir of extensionDirs) {
    const extJsPath = path.join(extDir, "extension.js");
    const bakPath = path.join(extDir, "extension.js.bak");

    console.log(`\n\x1b[34m[i] Target extension:\x1b[0m ${path.basename(extDir)}`);

    if (!fs.existsSync(extJsPath)) {
      console.warn(`\x1b[33m[!] extension.js not found in ${extDir}\x1b[0m`);
      continue;
    }

    if (mode === "restore") {
      if (fs.existsSync(bakPath)) {
        fs.copyFileSync(bakPath, extJsPath);
        console.log("\x1b[32m[+] Restored original extension.js from backup.\x1b[0m");
      } else {
        console.warn("\x1b[33m[!] No backup found to restore.\x1b[0m");
      }
      continue;
    }

    if (!fs.existsSync(bakPath)) {
      fs.copyFileSync(extJsPath, bakPath);
      console.log(`\x1b[32m[+] Created pristine backup at: ${bakPath}\x1b[0m`);
    } else {
      console.log("\x1b[34m[i] Existing backup found. Preserving original backup.\x1b[0m");
    }

    let code = fs.readFileSync(extJsPath, "utf8");
    let modified = false;

    // 1. Timeout Patch (5s -> 30s)
    const target = 'Ha(a,["--version"],{timeout:5E3})';
    const replacement = 'Ha(a,["--version"],{timeout:3E4})';

    if (code.includes(target)) {
      code = code.replace(target, replacement);
      modified = true;
      console.log("\x1b[32m[+] Increased version check timeout from 5s to 30s.\x1b[0m");
    } else if (code.includes(replacement)) {
      console.log("\x1b[34m[i] Timeout fix (30s) is already applied.\x1b[0m");
    } else {
      const regex = /(Ha\([^)]*--version[^)]*\{timeout:\s*)5E3(\s*\})/g;
      if (regex.test(code)) {
        code = code.replace(regex, (match, prefix, suffix) => prefix + "3E4" + suffix);
        modified = true;
        console.log("\x1b[32m[+] Increased version check timeout using regex match.\x1b[0m");
      }
    }

    // 2. Interactive Update Confirmation Prompt & Snooze (Full Fix)
    if (mode === "full") {
      if (code.includes("antigravity.updatePostponedUntil")) {
        console.log("\x1b[34m[i] Interactive update confirmation prompt is already active.\x1b[0m");
      } else {
        const regex1 = /(var d=b\(await c\(hb\(w,Ga\.MIN_AGY_VERSION,k\)\)\);let ja=Ga\.MIN_AGY_VERSION;a=!1;if\(d\)\{)/;
        const inj1 = '$1let _pu=g.globalState.get("antigravity.updatePostponedUntil");if(_pu&&Date.now()<_pu){k.appendLine(`[INSTALL] Update checks are postponed until ${new Date(_pu).toLocaleString()}. Continuing with existing binary v${d}.`);return w;}';

        const regex2 = /(Skipping download\.`\),\s*w;)(let Ub=)/;
        const inj2 = '$1if(d&&!cb(d,ja)){let _ans=b(await c(l.window.showInformationMessage(`Antigravity Backend update (v${ja}) is available (current: v${d}). Update now?`,"Update","Later (1 day)","Skip for 3 days")));if(_ans!=="Update"){let _hrs=_ans==="Skip for 3 days"?72:24;b(await c(g.globalState.update("antigravity.updatePostponedUntil",Date.now()+_hrs*3600000)));k.appendLine(`[INSTALL] User chose \'${_ans||"Dismiss"}\'. Postponing updates for ${_hrs}h. Continuing with existing binary v${d}.\`);return w;}}$2';

        if (regex1.test(code) && regex2.test(code)) {
          code = code.replace(regex1, inj1);
          code = code.replace(regex2, inj2);
          modified = true;
          console.log("\x1b[32m[+] Enabled interactive update prompt & snooze (1-day / 3-day quiet mode).\x1b[0m");
        } else {
          console.warn("\x1b[33m[!] Could not match update prompt injection points. Extension minification may differ.\x1b[0m");
        }
      }
    }

    if (modified) {
      writeAtomicSync(extJsPath, code);
      console.log("\x1b[32m[+] Successfully applied and saved patches!\x1b[0m");
    } else {
      console.log("\x1b[34m[i] No new modifications required.\x1b[0m");
    }
  }

  if (process.platform === "win32") {
    const geminiBinExe = path.join(homeDir, ".gemini", "bin", "agy.exe");
    console.log("\n\x1b[36m--- Windows Defender Optimization ---\x1b[0m");
    console.log("To prevent Windows Defender from delaying binary execution on startup,");
    console.log("open PowerShell as Administrator and run:");
    console.log(`\x1b[32m    Add-MpPreference -ExclusionPath "${geminiBinExe}"\x1b[0m`);
  }

  console.log("\n\x1b[32m[+] Done! Restart VS Code for changes to take effect.\x1b[0m");
}

main().catch((err) => {
  console.error("\x1b[31m[-] Error:\x1b[0m", err);
  process.exit(1);
});
