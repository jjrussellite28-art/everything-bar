# Everything Bar

A small, always-ready bar for Windows that you control with a game controller, a TV remote or a keyboard. Press one button from any game or app and the bar slides in on top: jump to anything you have open, launch your favorite apps, games and links, and get to quick settings without a mouse. It works like the home button on a game console.

## What it does
- **One button, anywhere.** Hold the Xbox/Guide button (or any button or combination you choose, with a hold time you set) to open the bar over a game or app.
- **Switch apps.** Shows everything you have open. Pick one to jump to it, or press X to close it.
- **Your own shortcuts.** Add any program or web link to the bar, using only the controller.
- **Freeze while you browse.** The app behind the bar is paused, so it doesn't react to your button presses. It is resumed when you switch back to it.
- **Quick settings.** Volume, on-screen keyboard, a gamepad cursor (stick = mouse), and one-press shortcuts to Network, Bluetooth, Airplane mode and Sound, plus Sleep, Restart and Shut down.
- **Light and unobtrusive.** Starts with Windows, sits idle using almost no CPU, and keeps the screen clear until you ask for it.
- **Safe to install and remove.** Per-user install (no admin rights), nothing in system folders, and a clean uninstaller.

## Install
Download **EverythingBar-Setup.exe** from the Releases page and run it. Windows may show an "unknown publisher" screen; choose **More info**, then **Run anyway**.
Uninstall from Windows Settings, then Apps.

## Build from source
Needs Flutter (Windows desktop). See `installer/README.md` for the full steps.

```
flutter create --platforms=windows .
powershell -ExecutionPolicy Bypass -File brand_windows.ps1
flutter build windows --release
```

Then compile `installer/HomeShell.iss` with Inno Setup 6 to produce the installer.
