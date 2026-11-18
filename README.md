# G14

Fan curves, power limits, and charge control for the ASUS ROG Zephyrus G14, on the Omarchy bar.

Needs [asusctl](https://gitlab.com/asus-linux/asusctl). Written for the GA403, which has CPU, GPU, and mid fans.

## Install

```sh
omarchy plugin add https://github.com/quacknode/omarchy-g14.git --enable
```

## Use

Click the fan icon. Silent, Balanced, and Turbo are the firmware profiles Quiet, Balanced, and Performance. Draw a curve, then turn on "Use these curves". At high temperature the firmware can still hold a fan above a curve that asks for 0%.

The Armoury key is not part of the install. To bind it, add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("code:156", "G14 controls", os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.quacknode.g14/g14-toggle.sh")
```

"Start with the desktop" writes `~/.config/autostart/g14.desktop`.

## Remove

```sh
omarchy plugin remove io.github.quacknode.g14
```

Delete `~/.config/autostart/g14.desktop` if it is there, and remove the key binding if you added one.
