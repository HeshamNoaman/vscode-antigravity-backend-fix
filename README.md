# VS Code Google Antigravity Backend Re-Download Fix

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Windows | macOS | Linux](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-green.svg)](#)

A fast, lightweight, and non-destructive hotfix for the issues in the **Google Antigravity** VS Code extension (`google.google-antigravity`) that cause recurring **~202 MB** backend binary (`agy.exe`) downloads every time you open a project or start VS Code.

---

## 🔍 The Issues & Root Causes

### 1. The 5-Second Timeout Race Condition (Windows Defender)
Every time VS Code opens, the extension checks if the local binary (`~/.gemini/bin/agy.exe`) is valid by executing:
```javascript
Ha(a, ["--version"], { timeout: 5000 })
```
On Windows, `agy.exe` is a **~202 MB executable**. On startup, disk I/O and **Windows Defender real-time scanning** frequently delay execution past 5 seconds. The extension catches this timeout, assumes the binary is missing or broken, and triggers a full 202 MB download.

### 2. Rapid Daily Upstream Releases Without Confirmation
Google publishes backend releases almost daily (e.g., `1.4.3` -> `1.4.4` -> `1.4.5`). Whenever a new patch release is found, the extension automatically wipes the working local binary and re-downloads 200MB in the background—causing project lockups (`spawn EBUSY`) and wasting dozens of gigabytes of bandwidth.

---

## ⚡ Quick Fix (Automated Menu)

### Option 1: Double-Click or PowerShell (Windows)

Clone the repository and run:
```powershell
git clone https://github.com/HeshamNoaman/vscode-antigravity-backend-fix.git
cd vscode-antigravity-backend-fix
.\fix.ps1
```
*Or simply double-click `fix.bat`.*

You will be presented with an interactive menu:
```text
Select an option:
  [1] Full Fix (30s Timeout + Update Prompt & Snooze) [Recommended]
      - Fixes Defender timeout (5s -> 30s)
      - Prompts before downloading daily updates (Update / Later 1 day / Skip 3 days)
  [2] Timeout Fix Only
      - Increases timeout to 30s without update prompt
  [3] Restore Original Extension from Backup
  [4] Exit
```

Non-interactive flags:
```powershell
.\fix.ps1 -Full         # Recommended: Timeout + Prompt & Snooze
.\fix.ps1 -TimeoutOnly  # Timeout only
.\fix.ps1 -Restore      # Revert to original backup
```

---

### Option 2: Node.js (Universal / Cross-Platform)

Compatible with all Node.js versions (Node 14+):
```bash
node fix.js
```

Non-interactive flags:
```bash
node fix.js --full      # Recommended
node fix.js --timeout   # Timeout only
node fix.js --restore   # Revert to original backup
```

---

## 💡 What the "Full Fix" Adds

When an update is detected, instead of silently triggering a 200MB background download, VS Code will display a clean prompt:

> **"Antigravity Backend update (v1.4.5) is available (current: v1.4.4). Update now?"**  
> `[Update]` `[Later (1 day)]` `[Skip for 3 days]`

- **Update**: Downloads the new release immediately.
- **Later (1 day)**: Postpones checks for 24 hours and uses your existing binary seamlessly.
- **Skip for 3 days**: Silences update checks for 72 hours.

---

## 🚀 Recommended: Windows Defender Exclusion

To make the Antigravity backend start in **under 300 ms** (by preventing Windows Defender from repeatedly scanning the 202 MB binary):

Open **PowerShell as Administrator** and run:
```powershell
Add-MpPreference -ExclusionPath "$HOME\.gemini\bin\agy.exe"
```
*(Notice: Scoped strictly to the `agy.exe` binary file rather than the entire folder for maximum security).*

---

## 🔄 Reverting / Restoring

To revert back to the original unmodified extension at any time:

- **PowerShell**:
  ```powershell
  .\fix.ps1 -Restore
  ```
- **Batch**:
  ```cmd
  fix.bat -Restore
  ```
- **Node.js**:
  ```bash
  node fix.js --restore
  ```

---

## 📖 شرح المشكلة والحل (بالعربية)

### المشكلة:
عند فتح أي مشروع في VS Code مع إضافة **Google Antigravity**، يظهر إشعار متكرر يومياً وبشكل مزعج:  
`Downloading Antigravity Backend (win32-x64)...`  
حتى بعد اكتمال التحميل، يتكرر تنزيل الملف بالكامل (~202 ميجابايت) عند إعادة فتح المشروع أو إطلاق تحديث يومي جديد.

### أسباب المشكلة:
1. **مهلة الفحص (5 ثوانٍ فقط):** فحص إصدار `agy.exe` يستغرق وقتاً أطول من 5 ثوانٍ بسبب مسح Windows Defender لملف بحجم 202 ميجابايت، فيفترض المحرر أن الملف مفقود ويبدأ التحميل.
2. **التحديثات التلقائية المستمرة:** تصدر تحديثات شبه يومية، وتقوم الإضافة بالتنزيل التلقائي دون سؤال المستخدم مما يسبب بطء واستهلاك للإنترنت وتعارض فتح النوافذ (`spawn EBUSY`).

### الحل:
الاسكربت يوفر قائمة تفاعلية سهلة:
- **الحل الكامل [1] (موصى به):** رفع مهلة الفحص إلى 30 ثانية + إظهار رسالة تأكيد عند وجود تحديث جديد مع خيار تأجيل التحديث (يوم أو 3 أيام).
- **إصلاح المهلة فقط [2]:** رفع المهلة إلى 30 ثانية دون رسالة التأكيد.
- **استعادة النسخة الأصلية [3]:** الرجوع للنسخة الأصلية غير المعدلة في أي وقت.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
