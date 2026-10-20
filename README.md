# VS Code Google Antigravity Backend Re-Download Fix

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Windows | macOS | Linux](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-green.svg)](#)

A fast, lightweight, and non-destructive hotfix for the bug in the **Google Antigravity** VS Code extension (`google.google-antigravity`) that causes it to repeatedly re-download the **~202 MB** backend binary (`agy.exe`) every time you open a project or start VS Code.

---

## 🛑 The Issue

When opening projects in VS Code with the Google Antigravity extension installed, a recurring notification appears:

> **"Installing Antigravity Backend...: Downloading Antigravity Backend (win32-x64)..."**

Even after the download completes and reaches 100%, reopening the project or starting VS Code the next day triggers the entire 202 MB download all over again. In internal logs, the binary is frequently re-downloaded dozens of times (consuming 10+ GB of bandwidth and causing noticeable startup lag).

---

## 🔍 Root Cause Analysis

1. **Extension Activation Routine**:  
   Every time VS Code opens a project, the extension activates and runs a self-check to verify if the local CLI backend (`~/.gemini/bin/agy.exe`) is installed and meets version requirements.
2. **The 5-Second Timeout Race Condition**:  
   Inside `extension.js` (function `gb`), the version check executes:
   ```javascript
   Ha(a, ["--version"], { timeout: 5000 })
   ```
   On Windows, `agy.exe` is a **~202 MB executable**. During project opening, VS Code indexes files and launches language servers, saturating CPU/disk I/O. Simultaneously, **Windows Defender** intercepts and performs real-time antimalware scanning on the 202 MB binary.
3. **The False-Alarm Trigger**:  
   Because the execution timeout is capped at only **5 seconds (5000 ms)**, cold starts frequently exceed 5 seconds. Node.js aborts the process with `SIGTERM` / timeout:
   ```text
   [INSTALL] Failed to execute binary C:\Users\<user>\.gemini\bin\agy.exe: Error: Command failed: ... --version
   ```
4. **The Endless Re-Download Loop**:  
   The extension catches this timeout and erroneously concludes that **no valid backend exists** or that the file is corrupt. It immediately launches a full download of the 202 MB binary from Google Cloud Storage, overwriting the file.  
   Because the version validation cache is only held in memory during that session, closing VS Code resets the state, causing the exact same race condition to occur every time VS Code opens.

---

## ⚡ Quick Fix (Automated)

### Option 1: Double-Click or PowerShell (Windows)

Clone the repository and run:
```powershell
git clone https://github.com/HeshamNoaman/vscode-antigravity-backend-fix.git
cd vscode-antigravity-backend-fix
.\fix.ps1
```
*Or simply double-click `fix.bat`.*

### Option 2: Node.js (Universal / Cross-Platform)

Compatible with all Node.js versions (Node 14+):
```bash
node fix.js
```

The script will:
1. Locate your installed `google.google-antigravity` extension across VS Code, Insiders, VSCodium, and Cursor.
2. Automatically create a pristine backup (`extension.js.bak`) that is never overwritten by subsequent runs.
3. Safely update the version check timeout from **5 seconds** (`5E3`) to **30 seconds** (`3E4`) using atomic writes.
4. Validate the changes.

---

## 🚀 Recommended: Windows Defender Exclusion

To make the Antigravity backend start in **under 300 ms** (by preventing Windows Defender from repeatedly scanning the 202 MB binary):

Open **PowerShell as Administrator** and run:
```powershell
Add-MpPreference -ExclusionPath "$HOME\.gemini\bin\agy.exe"
```
*(Notice: Scoped strictly to the `agy.exe` binary file rather than the entire folder for maximum security).*

Alternatively, add it via the Windows Security GUI:
1. Open **Windows Security** → **Virus & threat protection**.
2. Click **Manage settings** under *Virus & threat protection settings*.
3. Scroll down to **Exclusions** → **Add or remove exclusions**.
4. Click **Add an exclusion** → **File** → Select:
   ```
   C:\Users\<YourUsername>\.gemini\bin\agy.exe
   ```

---

## 🛠️ Manual Fix (Without Scripts)

If you prefer to edit manually:
1. Navigate to:
   ```text
   %USERPROFILE%\.vscode\extensions\google.google-antigravity-<version>\
   ```
2. Open `extension.js` in any text editor.
3. Search for:
   ```javascript
   Ha(a,["--version"],{timeout:5E3})
   ```
4. Replace `5E3` with `3E4` (30 seconds):
   ```javascript
   Ha(a,["--version"],{timeout:3E4})
   ```
5. Save the file and restart VS Code.

---

## 🔄 Reverting / Restoring

To revert back to the original unmodified extension:

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

## 🇸🇦 ملخص المشكلة والحل (بالعربية)

### المشكلة:
عند فتح أي مشروع في VS Code مع إضافة **Google Antigravity**، يظهر إشعار دائم يقوم بتحميل ملف الباك إند:
`Downloading Antigravity Backend (win32-x64)...`
وحتى بعد اكتمال التحميل بنسبة 100%، يتكرر التحميل في كل مرة يُعاد فيها تشغيل البرنامج أو فتح المشروع.

### سبب المشكلة:
- حجم ملف التشغيل `agy.exe` يبلغ حوالي **202 ميجابايت**.
- عند تشغيل VS Code، تقوم الإضافة بالتحقق من إصدار الملف عبر تشغيل `agy.exe --version` مع مهلة انتظار (Timeout) محددة بـ **5 ثوانٍ فقط**.
- في بيئة ويندوز، يقوم مضاد الفيروسات (Windows Defender) بفحص الملف، ومع الضغط الأولي لفتح المشروع يستغرق الأمر أكثر من 5 ثوانٍ، فيفشل الأمر ويعتبر البرنامج أن الملف غير موجود أو تالف، مما يدفعه لإعادة تحميل الـ 202 ميجابايت بالكامل من جديد في كل مرة.

### الحل:
تشغيل السكربت (`fix.ps1` أو `fix.bat`) لرفع مهلة الانتظار إلى 30 ثانية باستخدام كتابة آمنة للملفات (Atomic Writes)، مع إضافة مسار الملف `~/.gemini/bin/agy.exe` إلى استثناءات Windows Defender ليعمل البرنامج بسرعة فائقة وبدون أي تحميل متكرر.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
