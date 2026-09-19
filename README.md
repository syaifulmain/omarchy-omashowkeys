# OmaShowKeys

![OmaShowKeys preview](preview.png)

wshowkeys-style keycast pill for [Omarchy](https://omarchy.org): shows pressed
keys at the bottom center, then fades out.
Theme-aware, bar button with on/off switch, separate key-settings window.

## Install

```bash
omarchy plugin add https://github.com/syaifulmain/omarchy-omashowkeys.git --enable --yes
```

## Keyboard access

Showing key presses needs read access to `/dev/input/event*`. Copy the fixed
setup command from the bar button (**Copy setup command**) or paste it from
here. It installs a udev rule (`uaccess` on keyboards) — run it in a terminal:

```bash
sudo bash -c 'printf "%s\n" "# syaifulmain.omashowkeys: let the active local user read keyboards." "SUBSYSTEM==\"input\", KERNEL==\"event*\", ENV{ID_INPUT_KEYBOARD}==\"1\", TAG+=\"uaccess\"" > /etc/udev/rules.d/71-syaifulmain-omashowkeys.rules && udevadm control --reload-rules && udevadm trigger --subsystem-match=input --action=change'
```

The root command is self-contained text — nothing is executed from this plugin
directory. logind applies the `uaccess` ACL right after `udevadm trigger`, so no
logout is needed. Without access, the popup shows `NO INPUT ACCESS` and a
**Copy setup command** button. KeyMonitor rescans every 5 s and picks devices up
alone.

## Shortcut

Shortcut: `SUPER + SHIFT + K`.

## Update

```bash
omarchy plugin update syaifulmain.omashowkeys --yes
omarchy-restart-shell
```

## Uninstall

```bash
sudo bash -c 'rm -f /etc/udev/rules.d/71-syaifulmain-omashowkeys.rules && udevadm control --reload-rules && udevadm trigger --subsystem-match=input --action=change'
omarchy plugin remove syaifulmain.omashowkeys --yes
```

## Settings

```json
{ "id": "syaifulmain.omashowkeys", "enabled": true, "maxKeys": 5, "hideDelayMs": 1000, "scale": 1, "bgMode": "default", "showBorder": true }
```

Popup holds the on/off switch. “Key settings…” opens a tabbed window — Keys (rename + show switch per key, searchable), Display (hide / max keys / size / background / border / position).

## IPC

```bash
omarchy-shell syaifulmain.omashowkeys preview 'Ctrl + Shift + T'
omarchy-shell syaifulmain.omashowkeys flip
omarchy-shell syaifulmain.omashowkeys config
omarchy-shell syaifulmain.omashowkeys tab 1
```

## Credits

- Keycasting lineage: [wshowkeys](https://github.com/ammgws/wshowkeys),
  [screenkey](https://gitlab.com/screenkey/screenkey)
