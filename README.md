# OmaShowKeys

![OmaShowKeys preview](preview.png)

wshowkeys-style keycast pill for [Omarchy](https://omarchy.org): shows pressed
keys at the bottom center, then fades out.
Theme-aware, bar button with on/off switch, separate key-settings window.

## Install

```bash
omarchy plugin add https://github.com/syaifulmain/omarchy-showkeys.git --enable --yes
```

## Update

```bash
omarchy plugin update syaifulmain.showkeys --yes
omarchy-restart-shell
```

## Uninstall

```bash
pkexec ~/.config/omarchy/plugins/syaifulmain.showkeys/bin/showkeys-revoke
omarchy plugin remove syaifulmain.showkeys --yes
```

## Keyboard access

Click the bar button → **Grant keyboard access** → enter your password.
No logout needed. Without it, the popup shows `NO INPUT ACCESS`.

## Settings

```json
{ "id": "syaifulmain.showkeys", "enabled": true, "maxKeys": 5, "hideDelayMs": 1000, "scale": 1, "bgMode": "default", "showBorder": true }
```

Popup holds the on/off switch. “Key settings…” opens a tabbed window — Keys (rename + show switch per key, searchable), Display (hide / max keys / size / background / border / position).

## IPC

```bash
omarchy-shell syaifulmain.showkeys preview 'Ctrl + Shift + T'
omarchy-shell syaifulmain.showkeys flip
omarchy-shell syaifulmain.showkeys config
omarchy-shell syaifulmain.showkeys tab 1
```

## Credits

- Keycasting lineage: [wshowkeys](https://github.com/ammgws/wshowkeys),
  [screenkey](https://gitlab.com/screenkey/screenkey)
