# OptSwitch

A native, lightweight, crash-proof, and 100% offline Windows-style `Option + Tab` (`Alt + Tab`) window switcher for macOS (Apple Silicon `arm64`). Built purely with native Apple frameworks (`AppKit`, `CoreGraphics`, `ApplicationServices`, and `Foundation`).

---

## Why OptSwitch is 100% Offline & Safe

1. **Zero Network Access:**
   - Contains **no** `URLSession`, `Network`, sockets, HTTP, or WebSocket code anywhere in the codebase.
   - Explicitly locked down in `Resources/OptSwitch.entitlements` with `com.apple.security.network.client = false` and `com.apple.security.network.server = false`. Nothing ever leaves your Mac.
2. **Zero Third-Party Dependencies:**
   - Uses **zero** external Swift packages, CocoaPods, or third-party binaries. Every line of code is inspectable local Swift.
3. **Anti-Injection Startup Audit (`SecurityAudit.swift`):**
   - Verifies at startup that no dynamic library injection variables (`DYLD_INSERT_LIBRARIES`, `DYLD_FORCE_FLAT_NAMESPACE`, etc.) are attached to the process, refusing to launch if tampering is detected, and strips any proxy environment variables.
4. **Crash-Proof `CGEventTap` & Memory Guardrails:**
   - The keyboard event tap callback executes in microseconds and dispatches all UI and window updates asynchronously to the main thread so `WindowServer` can never freeze.
   - Automatic watchdog recovery immediately re-enables the event tap if macOS ever times it out.
   - Window discovery and thumbnail downscaling (`max 320x200`) run strictly inside `autoreleasepool` blocks once per switcher session, keeping RAM flat (~22 MB).

---

## Building & Packaging `OptSwitch.app`

Run the automated build, self-test, and bundle script from the project root:

```bash
bash scripts/bundle_app.sh
```

This compiles a release `arm64` binary, runs the 100-iteration memory leak and security self-test, creates `OptSwitch.app`, and signs it locally with `Resources/OptSwitch.entitlements`.

To launch the app:

```bash
open OptSwitch.app
```

---

## Granting macOS Permissions

1. **Accessibility Permission (Required for `Option + Tab` and focusing windows):**
   - On first launch, if Accessibility is not yet granted, OptSwitch displays a clean setup window with an **Open System Settings** button.
   - Open **System Settings -> Privacy & Security -> Accessibility**.
   - Enable the toggle next to **OptSwitch** (if rebuilding, toggle it off and back on, or re-add `OptSwitch.app`).
2. **Screen Recording Permission (Optional for live window thumbnails & titles):**
   - Without Screen Recording permission, OptSwitch still works cleanly using application icons.
   - To enable live window thumbnails, click **Grant Preview Access** in the setup window or enable **OptSwitch** in **System Settings -> Privacy & Security -> Screen & System Audio Recording**.

---

## Keyboard Shortcuts & Controls

| Shortcut / Action | Description |
| :--- | :--- |
| **`Option + Tab`** | Open the window switcher HUD and cycle forward through open windows |
| **`Option + Shift + Tab`** | Cycle backward through open windows |
| **Release `Option`** | Activate the highlighted window and bring that exact window to the front |
| **`Escape` (while switcher is open)** | Cancel switching and close the HUD without changing focus |
| **Mouse Click on Card** | Immediately switch to the clicked window |
| **`Control + Option + Escape`** | **Emergency Panic Killswitch:** Immediately disables the keyboard tap and quits OptSwitch |

You can also click the **OptSwitch** icon in the macOS Menu Bar at any time to check status, pause/resume the switcher, open the permissions window, or quit.

---

## Pushing to GitHub

To push this repository to a new GitHub repository:

```bash
git remote add origin https://github.com/<your-username>/OptSwitch.git
git branch -M main
git push -u origin main
```
