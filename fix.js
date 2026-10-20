#!/usr/bin/env node
/**
 * Cross-platform fixer for Google Antigravity VS Code extension download loop.
 * Works on Windows, macOS, and Linux.
 */

import fs from "node:fs";
import path from "node:path";
import os from "node:os";

const isRestore = process.argv.includes("--restore") || process.argv.includes("-r");

console.log("\x1b[36m==========================================================\x1b[0m");
console.log("   VS Code Google Antigravity Backend Re-download Fixer   ");
console.log("\x1b[36m==========================================================\x1b[0m\n");

const homeDir = os.homedir();
const candidateDirs = [
  path.join(homeDir, ".vscode", "extensions"),
  path.join(homeDir, ".vscode-insiders", "extensions"),
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
      // ignore
    }
  }
}

if (extensionDirs.length === 0) {
  console.error("\x1b[31m[-] Could not find any 'google.google-antigravity' extension installed.\x1b[0m");
  process.exit(1);
}

for (const extDir of extensionDirs) {
  const extJsPath = path.join(extDir, "extension.js");
  const bakPath = path.join(extDir, "extension.js.bak");

  console.log(`\x1b[34m[i] Target extension:\x1b[0m ${path.basename(extDir)}`);

  if (!fs.existsSync(extJsPath)) {
    console.warn(`\x1b[33m[!] extension.js not found in ${extDir}\x1b[0m`);
    continue;
  }

  if (isRestore) {
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
    console.log(`\x1b[32m[+] Created backup at: ${bakPath}\x1b[0m`);
  } else {
    console.log("\x1b[34m[i] Existing backup found. Preserving original backup.\x1b[0m");
  }

  let code = fs.readFileSync(extJsPath, "utf8");

  const target = 'Ha(a,["--version"],{timeout:5E3})';
  const replacement = 'Ha(a,["--version"],{timeout:3E4})';

  if (code.includes(target)) {
    code = code.replace(target, replacement);
    fs.writeFileSync(extJsPath, code, "utf8");
    console.log("\x1b[32m[+] Successfully increased version check timeout from 5s to 30s!\x1b[0m");
  } else if (code.includes(replacement)) {
    console.log("\x1b[34m[i] File is already patched with 30s timeout.\x1b[0m");
  } else {
    // Regex fallback
    const regex = /(Ha\([^)]*--version[^)]*\{timeout:)5E3(\})/g;
    if (regex.test(code)) {
      code = code.replace(regex, "$13E4$2");
      fs.writeFileSync(extJsPath, code, "utf8");
      console.log("\x1b[32m[+] Successfully patched using regex replacement!\x1b[0m");
    } else {
      console.warn("\x1b[33m[!] Target pattern not found. The extension might already be patched or updated.\x1b[0m");
    }
  }
}

if (process.platform === "win32") {
  const geminiBin = path.join(homeDir, ".gemini", "bin");
  console.log("\n\x1b[36m--- Windows Defender Optimization ---\x1b[0m");
  console.log("To prevent Windows Defender from delaying binary execution on startup,");
  console.log("open PowerShell as Administrator and run:");
  console.log(`\x1b[32m    Add-MpPreference -ExclusionPath "${geminiBin}"\x1b[0m`);
}

console.log("\n\x1b[32m[+] Done! Restart VS Code for changes to take effect.\x1b[0m");
