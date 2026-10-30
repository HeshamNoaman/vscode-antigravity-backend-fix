# Google Antigravity VS Code Extension Backend Patcher — Engineering Directives

## Architecture & Version Compatibility (v1.8.x – v1.10.x+)

The Google Antigravity extension periodically changes internal minified variable names and function signatures during updates. To ensure patch durability across versions:

### 1. Invariable Injection Anchors
- **Timeout & Retry Anchor**:
  Matches `Pa(a, ["--version"], {timeout: <literal|identifier>})` regardless of whether timeout is literal (`5E3`, `3E4`) or a variable (`u` from `DEFAULT_VERSION_CHECK_TIMEOUT_MS = 15E3`).
  - Regex: `/let\s*\{stdout:\s*([a-zA-Z0-9_$]+),\s*stderr:\s*([a-zA-Z0-9_$]+)\}\s*=\s*([a-zA-Z0-9_$]+)\(await\s+([a-zA-Z0-9_$]+)\(([a-zA-Z0-9_$]+)\(([a-zA-Z0-9_$]+),\s*\["--version"\]\s*,\s*\{timeout:\s*([^}]+)\}\)\)\)/`
  - Always bumps `DEFAULT_VERSION_CHECK_TIMEOUT_MS` to `3E4` if present.

- **Installer Parameter Discovery**:
  Matches parameter destructuring flexibly regardless of property ordering, and accommodates future non-lowered ES2020 nullish coalescing (`??`):
  - Regex: `/let\s*\{(?=[^}]*\bcontext:\s*([a-zA-Z0-9_$]+))(?=[^}]*\boutputChannel:\s*([a-zA-Z0-9_$]+))[^}]*\}\s*=\s*[a-zA-Z0-9_$]+,\s*([a-zA-Z0-9_$]+)\s*=\s*[a-zA-Z0-9_$]+(?:!=null\?[a-zA-Z0-9_$]+:[a-zA-Z0-9_$]+\(\)|\?\?[a-zA-Z0-9_$]+\(\))/`

- **Installer Release URL Discovery**:
  Discovers `releaseBaseUrl=${<var>}` directly within the update check block to avoid matching helper function parameters, with an expanded 1000-character search window:
  - Regex: `/Initializing update check[\s\S]{1,1000}?Checking for updates at releaseBaseUrl=\$\{([a-zA-Z0-9_$]+)\}/`

- **Download Function Gatekeeper**:
  In v1.10.0, the download function is declared inside a comma-separated `let` statement (`let he=()=>..., Tc=async(Zb,Nd)=>{`).
  - **Rule 1**: Code MUST be injected **inside** the function body (`{ <injected_gatekeeper> ... }`), NEVER prepended before the function identifier.
  - **Rule 2**: Use standard ES2017 `await` directly; NEVER invoke transpiler async context helpers like `b(await c(...))`.
  - **Rule 3**: Gatekeeper MUST be self-contained and declare its own local configuration (`_agyCfg`, `_agyMode`, `_agySnooze`) to prevent `ReferenceError`s if the entrance injection does not run.
  - **Rule 4**: Use asynchronous child process execution (`require("child_process").execFile` with Promise) instead of synchronous `execFileSync` to keep the VS Code extension host single-threaded event loop responsive during Windows Defender scans.
  - Regex: `/(?:let\s+|,)([a-zA-Z0-9_$]+)\s*=\s*async\s*(?:\([a-zA-Z0-9_$,\s]*\)|[a-zA-Z0-9_$]+)\s*=>\s*\{(?=[\s\S]{1,1000}\[INSTALL\] Checking Antigravity releases)/`

- **ServerManager Singleton**:
  - Dynamically extracts identifier via `([a-zA-Z0-9_$]+)\.AntigravityServerManager\.getInstance\(\)`.
  - Fallbacks: `pc` (v1.9.0), `$c` (v1.10.0).

### 2. Replacer Macro & Replacement Safety
- In JavaScript (`fix.js`), always pass a function callback `code.replace(target, () => rep)` to eliminate macro substitution vulnerabilities with `$` identifiers (`$c`, `$&`, `$'`).

### 3. PowerShell Script Safety
- Do NOT use complex nested template literals inside PowerShell double-quoted strings for generated JS.
- Use standard JavaScript string concatenation (`+`) in `fix.ps1` for injected code to eliminate PowerShell variable expansion ambiguities (`$urlVar`, `${process.platform}`).
- Use literal bullet `•` rather than escaped unicode strings (`\u2022`).

### 4. Dual Pre-Write AST / Syntax Verification
- **Node.js (`fix.js`)**: Must compile with `new (require("node:vm")).Script(code)` in memory before touching disk.
- **PowerShell (`fix.ps1`)**: Must validate with `node -c <extJsPath>.check.js` before atomic replacement.
