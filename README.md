Lightweight toolbar plugin for fan curves, power limits, and charge control on the ASUS ROG Zephyrus G14.

Needs [asusctl](https://gitlab.com/asus-linux/asusctl). Written for the GA403, which has CPU, GPU, and mid fans.

Matches to your system's theme and provides the same functionality as G-helper.

## Install

```sh
omarchy plugin add https://github.com/quacknode/omarchy-g14.git --enable
```

## Use

Click the fan icon. Silent, Balanced, and Turbo are the firmware profiles Quiet, Balanced, and Performance. Draw a curve, then turn on "Use these curves". At high temperature the firmware can still hold a fan above a curve if the chip is overheating.

The M4 key (Armoury) is not part of the install. To bind it, add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("code:156", "G14 controls", os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.quacknode.g14/g14-toggle.sh")
```

"Start with the desktop" writes `~/.config/autostart/g14.desktop`.

## Remove

```sh
omarchy plugin remove io.github.quacknode.g14
```

Delete `~/.config/autostart/g14.desktop` if it is there, and remove the key binding if you added one.


<img width="766" height="1800" alt="image" src="https://github.com/user-attachments/assets/b93ac1f4-9cf7-4978-be39-237a4489169f" />

