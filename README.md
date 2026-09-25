# OmaShowKeys

![OmaShowKeys preview](preview.png)

wshowkeys-style keycast pill for [Omarchy](https://omarchy.org): shows pressed
keys at the bottom center, then fades out. Theme-aware, toggled from the bar.

## Bar controls

- Left click: open or close popup.
- Right click: toggle **Show key presses** visibility without opening popup.
- Scroll up: enable **Show key presses**.
- Scroll down: disable **Show key presses**.
- Middle click: no action.

## Install

```bash
omarchy plugin add https://github.com/syaifulmain/omarchy-omashowkeys.git --enable --yes
```

## Update

```bash
omarchy plugin update syaifulmain.omashowkeys --yes
omarchy-restart-shell
```

## Uninstall

```bash
omarchy plugin remove syaifulmain.omashowkeys --yes
```

## Settings

Defaults:

- Hide after: 1 s
- Max keys: 5
- Size: 1x
- Background: Default
- Border: Shown
- Position: Bottom center

The popup holds the on/off switch. “Key settings…” opens a tabbed window —
Keys (rename + show switch per key, searchable), Display (hide / max keys /
size / background / border / position).

## Shortcut

No binding is installed for you. To toggle the keycast from the keyboard, add
your own binding.

In `~/.config/hypr/bindings.conf`:

```conf
bindd = SUPER SHIFT, K, OmaShowKeys, exec, omarchy-shell syaifulmain.omashowkeys flip
```

Or in `~/.config/hypr/bindings.lua`, same style as the Ports example:

```lua
o.bind("SUPER + SHIFT + K", "OmaShowKeys", "omarchy-shell syaifulmain.omashowkeys flip")
```

Change `SUPER + SHIFT + K` to any combo you like.

## IPC

```bash
omarchy-shell syaifulmain.omashowkeys preview 'Ctrl + Shift + T'
omarchy-shell syaifulmain.omashowkeys flip
omarchy-shell syaifulmain.omashowkeys config
omarchy-shell syaifulmain.omashowkeys tab 1
omarchy-shell syaifulmain.omashowkeys state
```

## Credits

- Keycasting lineage: [wshowkeys](https://github.com/ammgws/wshowkeys),
  [screenkey](https://gitlab.com/screenkey/screenkey)
- Event-source approach: [omarchy-keycast](https://github.com/devmobasa/omarchy-keycast)
