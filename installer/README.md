# Install Everything Bar (safe, per-user)

1. Install Inno Setup 6 (free): https://jrsoftware.org/isdl.php
2. In PowerShell: `cd C:\everything-bar` then `flutter build windows --release`
3. Open `installer\HomeShell.iss` in Inno Setup and press Compile (Ctrl+F9).
4. Run `installer\output\EverythingBar-Setup.exe`.

Installs to `%LOCALAPPDATA%\HomeShell`, no admin needed, one startup entry for you only.
**Update:** `git pull`, rebuild (step 2), rerun Setup. It replaces files and keeps your items.
**Uninstall:** Windows Settings > Apps > Everything Bar. It removes the files and the startup entry
and asks whether to delete saved items too.
**Game Bar:** Settings > Gaming > Xbox Game Bar > turn off the controller-button option.
Turn it back on to restore.
