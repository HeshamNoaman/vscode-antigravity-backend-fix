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
  --full, -f        Apply Full Fix (30s timeout + prompt with download size & settings control) [Default]
  --timeout, -t     Apply Timeout Fix only (increase timeout from 5s to 30s)
  --restore, -r     Restore original extension from backup
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
    console.log("  \x1b[32m[1] Full Fix (Timeout + Update Confirmation & Settings)\x1b[0m \x1b[33m[Recommended]\x1b[0m");
    console.log("      - Fixes Defender timeout (5s -> 30s)");
    console.log("      - Prompts before downloading updates with exact download size");
    console.log("      - Options: Update / Later (1 day) / Skip for 3 days / Disable permanently");
    console.log("      - Adds Manual Check command and VS Code settings configuration");
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

  for (const extDir of extensionDirs) {
    const extJsPath = path.join(extDir, "extension.js");
    const extJsBak = path.join(extDir, "extension.js.bak");
    const pkgJsonPath = path.join(extDir, "package.json");
    const pkgJsonBak = path.join(extDir, "package.json.bak");

    console.log(`\n\x1b[34m[i] Target extension:\x1b[0m ${path.basename(extDir)}`);

    if (!fs.existsSync(extJsPath)) {
      console.warn(`\x1b[33m[!] extension.js not found in ${extDir}\x1b[0m`);
      continue;
    }

    if (mode === "restore") {
      let restored = false;
      if (fs.existsSync(extJsBak)) {
        fs.copyFileSync(extJsBak, extJsPath);
        console.log("\x1b[32m[+] Restored original extension.js from backup.\x1b[0m");
        restored = true;
      }
      if (fs.existsSync(pkgJsonBak)) {
        fs.copyFileSync(pkgJsonBak, pkgJsonPath);
        console.log("\x1b[32m[+] Restored original package.json from backup.\x1b[0m");
        restored = true;
      }
      if (!restored) {
        console.warn("\x1b[33m[!] No backup files found to restore.\x1b[0m");
      }
      continue;
    }

    // Create backups if not already present
    if (!fs.existsSync(extJsBak)) {
      fs.copyFileSync(extJsPath, extJsBak);
      console.log(`\x1b[32m[+] Created pristine backup: ${path.basename(extJsBak)}\x1b[0m`);
    } else {
      console.log("\x1b[34m[i] Existing extension.js backup found. Preserving original.\x1b[0m");
    }

    if (fs.existsSync(pkgJsonPath) && !fs.existsSync(pkgJsonBak)) {
      fs.copyFileSync(pkgJsonPath, pkgJsonBak);
      console.log(`\x1b[32m[+] Created pristine backup: ${path.basename(pkgJsonBak)}\x1b[0m`);
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

    // 2. Full Fix: Enhanced Prompt, Download Size, Confirmation, and Settings
    if (mode === "full") {
      // Injection 1: Settings & Snooze Check Before Remote Fetch
      const regex1 = /(var d=b\(await c\(hb\(w,Ga\.MIN_AGY_VERSION,k\)\)\);let ja=Ga\.MIN_AGY_VERSION;a=!1;if\(d\)\{)/;
      const inj1 = '$1' +
        'let _cfg=l.workspace.getConfiguration("antigravity");' +
        'let _mode=_cfg.get("updateCheckMode")||"prompt";' +
        'if(!globalThis.__agyForceCheck){' +
          'if(_mode==="disabled"){k.appendLine(`[INSTALL] Automatic update checks are disabled in settings (antigravity.updateCheckMode=disabled). Continuing with existing binary v${d}.`);return w;}' +
          'let _snooze=_cfg.get("updateSnoozeUntil")||g.globalState.get("antigravity.updatePostponedUntil");' +
          'if(_snooze&&Date.now()<Number(_snooze)){k.appendLine(`[INSTALL] Update checks are silenced until ${new Date(Number(_snooze)).toLocaleString()}. Continuing with existing binary v${d}.`);return w;}' +
        '}';

      // Injection 2: Prompt with Download Size, 4 Options, and Confirmation Messages
      const regex2 = /(Skipping download\.`\),\s*w;)(let Ub=)/;
      const inj2 = '$1' +
        'if(d&&!cb(d,ja)&&l.workspace.getConfiguration("antigravity").get("updateCheckMode")!=="always"){' +
          'globalThis.__agyPromptShown=true;' +
          'let _sz="~76 MB (~202 MB uncompressed)";' +
          'try{' +
            'let _murl=`${V}/manifests/${process.platform==="win32"?"windows":process.platform}_${process.arch==="x64"?"amd64":process.arch}.json`;' +
            'let _mres=b(await c(ta(_murl,{signal:AbortSignal.timeout(1500)})));' +
            'if(_mres&&_mres.status===200){' +
              'let _mdata=b(await c(_mres.json()));' +
              'let _bin=tb(_mdata,process.platform,process.arch);' +
              'if(_bin&&_bin.url){' +
                'let _hres=b(await c(ta(_bin.url,{method:"HEAD",signal:AbortSignal.timeout(1500)})));' +
                'let _cl=_hres&&_hres.headers&&_hres.headers.get("content-length");' +
                'if(_cl){_sz=`${(Number(_cl)/(1024*1024)).toFixed(1)} MB (~202 MB uncompressed)`;}' +
              '}' +
            '}' +
          '}catch(_e){}' +
          'let _promptMsg=`Antigravity Backend Update (v${ja}) is available (current: v${d}). Update now?\\n\\nDownload size: ${_sz}`;' +
          'let _ans=b(await c(l.window.showInformationMessage(_promptMsg,"Update","Later (1 day)","Skip for 3 days","Disable update checks permanently")));' +
          'if(_ans==="Update"){' +
            'b(await c(g.globalState.update("antigravity.updatePostponedUntil",0)));' +
            'try{l.workspace.getConfiguration("antigravity").update("updateSnoozeUntil",0,l.ConfigurationTarget.Global);}catch(_e){}' +
          '}else if(_ans==="Later (1 day)"){' +
            'let _until=Date.now()+86400000;' +
            'b(await c(g.globalState.update("antigravity.updatePostponedUntil",_until)));' +
            'try{l.workspace.getConfiguration("antigravity").update("updateSnoozeUntil",_until,l.ConfigurationTarget.Global);}catch(_e){}' +
            'l.window.showInformationMessage("Antigravity update check delayed for 1 day. Note: This preference cannot be changed from the popup; you can modify it in Extension Settings or via Command Palette.");' +
            'k.appendLine(`[INSTALL] User chose \'Later (1 day)\'. Continuing with existing binary v${d}.`);' +
            'return w;' +
          '}else if(_ans==="Skip for 3 days"){' +
            'let _until=Date.now()+259200000;' +
            'b(await c(g.globalState.update("antigravity.updatePostponedUntil",_until)));' +
            'try{l.workspace.getConfiguration("antigravity").update("updateSnoozeUntil",_until,l.ConfigurationTarget.Global);}catch(_e){}' +
            'l.window.showInformationMessage("Antigravity update checks paused for 3 days. Note: This preference cannot be changed from the popup; you can modify it in Extension Settings or via Command Palette.");' +
            'k.appendLine(`[INSTALL] User chose \'Skip for 3 days\'. Continuing with existing binary v${d}.`);' +
            'return w;' +
          '}else if(_ans==="Disable update checks permanently"){' +
            'b(await c(g.globalState.update("antigravity.updatePostponedUntil",Number.MAX_SAFE_INTEGER)));' +
            'try{' +
              'let _c=l.workspace.getConfiguration("antigravity");' +
              '_c.update("updateCheckMode","disabled",l.ConfigurationTarget.Global);' +
              '_c.update("updateSnoozeUntil",Number.MAX_SAFE_INTEGER,l.ConfigurationTarget.Global);' +
            '}catch(_e){}' +
            'l.window.showInformationMessage("Automatic update checks disabled permanently. Note: This preference cannot be changed from the popup; you can re-enable checks in Extension Settings or run \'Antigravity: Check for Backend Updates\' from the Command Palette.");' +
            'k.appendLine(`[INSTALL] User chose \'Disable update checks permanently\'. Continuing with existing binary v${d}.`);' +
            'return w;' +
          '}else{' +
            'return w;' +
          '}' +
        '}$2';

      // Injection 3: Register Manual Check & Configure Settings Commands
      const regex3 = /(a\.subscriptions\.push\(l\.commands\.registerCommand\("antigravity\.openSettings",\s*async\s+[a-zA-Z0-9_]+\s*=>\s*\{.*?\}\)\);)/;
      const inj3 = '$1' +
        'a.subscriptions.push(l.commands.registerCommand("antigravity.checkForBackendUpdates",async()=>{' +
          'l.window.withProgress({location:l.ProgressLocation.Notification,title:"Checking for Antigravity backend updates..."},async()=>{' +
            'globalThis.__agyForceCheck=true;' +
            'globalThis.__agyPromptShown=false;' +
            'try{' +
              'let _cfg=l.workspace.getConfiguration("antigravity");' +
              'await _cfg.update("updateSnoozeUntil",0,l.ConfigurationTarget.Global);' +
              'await a.globalState.update("antigravity.updatePostponedUntil",0);' +
              'await cc.AntigravityServerManager.getInstance().acquireInstalledBinaryPath(a);' +
              'if(!globalThis.__agyPromptShown){' +
                'l.window.showInformationMessage("Antigravity backend is up to date.");' +
              '}' +
            '}catch(_err){l.window.showErrorMessage(`Update check failed: ${_err.message}`);}' +
            'finally{delete globalThis.__agyForceCheck;delete globalThis.__agyPromptShown;}' +
          '});' +
        '}));' +
        'a.subscriptions.push(l.commands.registerCommand("antigravity.configureUpdateSettings",async()=>{' +
          'let _pick=await l.window.showQuickPick([' +
            '{label:"$(check) Enable Automatic Updates (Prompt on update)",description:"Prompt before downloading with download size",action:"prompt"},' +
            '{label:"$(clock) Pause Updates for 1 Day",description:"Silence update checks for 24 hours",action:"pause1d"},' +
            '{label:"$(clock) Pause Updates for 3 Days",description:"Silence update checks for 72 hours",action:"pause3d"},' +
            '{label:"$(clock) Pause Updates for 1 Week",description:"Silence update checks for 7 days",action:"pause7d"},' +
            '{label:"$(circle-slash) Disable Automatic Updates Permanently",description:"Never check automatically; manual check only",action:"disabled"},' +
            '{label:"$(gear) Open Antigravity Settings",description:"Open VS Code Settings filtered to Antigravity",action:"settings"}' +
          '],{placeHolder:"Configure Antigravity Backend Update Behavior"});' +
          'if(!_pick)return;' +
          'let _cfg=l.workspace.getConfiguration("antigravity");' +
          'if(_pick.action==="prompt"){' +
            'await _cfg.update("updateCheckMode","prompt",l.ConfigurationTarget.Global);' +
            'await _cfg.update("updateSnoozeUntil",0,l.ConfigurationTarget.Global);' +
            'await a.globalState.update("antigravity.updatePostponedUntil",0);' +
            'l.window.showInformationMessage("Antigravity updates set to Prompt mode. Snooze cleared.");' +
          '}else if(_pick.action==="pause1d"){' +
            'let _u=Date.now()+86400000;' +
            'await _cfg.update("updateSnoozeUntil",_u,l.ConfigurationTarget.Global);' +
            'await a.globalState.update("antigravity.updatePostponedUntil",_u);' +
            'l.window.showInformationMessage("Antigravity updates paused for 1 day.");' +
          '}else if(_pick.action==="pause3d"){' +
            'let _u=Date.now()+259200000;' +
            'await _cfg.update("updateSnoozeUntil",_u,l.ConfigurationTarget.Global);' +
            'await a.globalState.update("antigravity.updatePostponedUntil",_u);' +
            'l.window.showInformationMessage("Antigravity updates paused for 3 days.");' +
          '}else if(_pick.action==="pause7d"){' +
            'let _u=Date.now()+7*86400000;' +
            'await _cfg.update("updateSnoozeUntil",_u,l.ConfigurationTarget.Global);' +
            'await a.globalState.update("antigravity.updatePostponedUntil",_u);' +
            'l.window.showInformationMessage("Antigravity updates paused for 1 week.");' +
          '}else if(_pick.action==="disabled"){' +
            'await _cfg.update("updateCheckMode","disabled",l.ConfigurationTarget.Global);' +
            'await _cfg.update("updateSnoozeUntil",Number.MAX_SAFE_INTEGER,l.ConfigurationTarget.Global);' +
            'await a.globalState.update("antigravity.updatePostponedUntil",Number.MAX_SAFE_INTEGER);' +
            'l.window.showInformationMessage("Antigravity automatic update checks disabled permanently.");' +
          '}else if(_pick.action==="settings"){' +
            'l.commands.executeCommand("workbench.action.openSettings","antigravity");' +
          '}' +
        '}));';

      // Clean previously applied basic snooze if present to avoid duplicate injections
      if (code.includes("antigravity.checkForBackendUpdates")) {
        console.log("\x1b[34m[i] Enhanced update prompt and commands are already active.\x1b[0m");
      } else {
        // If an earlier simple patch exists, restore clean base from backup first
        if (code.includes("antigravity.updatePostponedUntil") && fs.existsSync(extJsBak)) {
          code = fs.readFileSync(extJsBak, "utf8");
          // Re-apply timeout fix
          code = code.replace(target, replacement);
        }

        if (regex1.test(code) && regex2.test(code)) {
          code = code.replace(regex1, inj1);
          code = code.replace(regex2, inj2);
          if (regex3.test(code)) {
            code = code.replace(regex3, inj3);
          } else {
            console.warn("\x1b[33m[!] Could not match openSettings registration point for commands in extension.js.\x1b[0m");
          }
          modified = true;
          console.log("\x1b[32m[+] Injected update prompt with download size & command palette controls.\x1b[0m");
        } else {
          console.warn("\x1b[33m[!] Could not match injection points in extension.js.\x1b[0m");
        }
      }

      // 3. Update package.json to contribute settings & commands in VS Code
      if (fs.existsSync(pkgJsonPath)) {
        try {
          const pkg = JSON.parse(fs.readFileSync(pkgJsonPath, "utf8"));
          let pkgModified = false;

          pkg.contributes = pkg.contributes || {};
          pkg.contributes.commands = pkg.contributes.commands || [];
          pkg.contributes.configuration = pkg.contributes.configuration || {};
          pkg.contributes.configuration.properties = pkg.contributes.configuration.properties || {};

          const commandsToAdd = [
            {
              command: "antigravity.checkForBackendUpdates",
              title: "Check for Backend Updates",
              category: "Antigravity"
            },
            {
              command: "antigravity.configureUpdateSettings",
              title: "Configure Backend Update Settings",
              category: "Antigravity"
            }
          ];

          for (const cmd of commandsToAdd) {
            if (!pkg.contributes.commands.some((c) => c.command === cmd.command)) {
              pkg.contributes.commands.push(cmd);
              pkgModified = true;
            }
          }

          if (!pkg.contributes.configuration.properties["antigravity.updateCheckMode"]) {
            pkg.contributes.configuration.properties["antigravity.updateCheckMode"] = {
              type: "string",
              enum: ["prompt", "disabled", "always"],
              default: "prompt",
              description: "Controls how Antigravity backend updates are handled: 'prompt' asks before downloading, 'disabled' stops automatic checks, 'always' auto-downloads."
            };
            pkgModified = true;
          }

          if (!pkg.contributes.configuration.properties["antigravity.updateSnoozeUntil"]) {
            pkg.contributes.configuration.properties["antigravity.updateSnoozeUntil"] = {
              type: "number",
              default: 0,
              description: "Timestamp (epoch ms) until which automatic update prompts are silenced."
            };
            pkgModified = true;
          }

          if (pkgModified) {
            writeAtomicSync(pkgJsonPath, JSON.stringify(pkg, null, 2) + "\n");
            console.log("\x1b[32m[+] Updated package.json with configuration settings & commands.\x1b[0m");
          } else {
            console.log("\x1b[34m[i] package.json already contains configuration settings.\x1b[0m");
          }
        } catch (err) {
          console.warn("\x1b[33m[!] Could not update package.json: " + err.message + "\x1b[0m");
        }
      }
    }

    if (modified) {
      writeAtomicSync(extJsPath, code);
      console.log("\x1b[32m[+] Successfully applied and saved patches to extension.js!\x1b[0m");
    } else {
      console.log("\x1b[34m[i] No new modifications required for extension.js.\x1b[0m");
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
