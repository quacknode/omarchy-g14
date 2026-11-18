#!/usr/bin/env python3

import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.abspath(__file__))
PRESETS = os.path.join(ROOT, "presets.json")
AUTOSTART = os.path.expanduser("~/.config/autostart/g14.desktop")


def autostart_entry():
    exe = os.path.join(ROOT, "g14.py")
    return (
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Version=1.0\n"
        "Name=G14 controls\n"
        "Comment=Re-apply Zephyrus G14 curves and power limits at login\n"
        f"Exec=/usr/bin/python3 {exe} boot\n"
        "X-GNOME-Autostart-enabled=true\n"
        "NoDisplay=true\n"
    )
PROFILES = ("Quiet", "Balanced", "Performance")
FANS = ("cpu", "gpu", "mid")
DEFAULT_CURVE = "20c:0,55c:0,63c:40,70c:84,77c:128,85c:176,90c:209,95c:242"
ATTRS = {
    "spl": "ppt_pl1_spl",
    "sppt": "ppt_pl2_sppt",
    "fppt": "ppt_pl3_fppt",
    "tgp": "nv_tgp",
    "gboost": "nv_dynamic_boost",
    "gtemp": "nv_temp_target",
}
CPU_KEYS = ("spl", "sppt", "fppt")


class CmdError(Exception):
    pass


def run(args):
    proc = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return proc.returncode, proc.stdout, proc.stderr


def clean(text):
    lines = []
    for line in (text or "").splitlines():
        if line.startswith("[WARN"):
            continue
        stripped = line.strip()
        if stripped:
            lines.append(stripped)
    return lines


def run_ok(args):
    code, out, err = run(args)
    if code != 0:
        lines = clean(err) or clean(out)
        raise CmdError(lines[-1] if lines else "command failed")
    return out


def canon(name):
    key = str(name or "").strip().lower()
    for profile in PROFILES:
        if profile.lower() == key:
            return profile
    raise CmdError("unknown profile")


def parse_curves(text):
    fans = {}
    pattern = re.compile(
        r"fan:\s*(\w+),\s*pwm:\s*\(([^)]*)\),\s*temp:\s*\(([^)]*)\),\s*enabled:\s*(true|false)",
        re.I,
    )
    for match in pattern.finditer(text or ""):
        temps = [int(part.strip()) for part in match.group(3).split(",") if part.strip()]
        pwms = [int(part.strip()) for part in match.group(2).split(",") if part.strip()]
        fans[match.group(1).lower()] = {
            "temp": temps,
            "pwm": pwms,
            "enabled": match.group(4).lower() == "true",
        }
    return fans


def parse_armoury(text):
    result = {}
    name = None
    for line in (text or "").splitlines():
        if line and not line.startswith(" ") and line.endswith(":"):
            name = line[:-1].strip()
            result[name] = {}
            continue
        if not name:
            continue
        ranged = re.search(r"current:\s*(\d+)\.\.\[(\d+)\]\.\.(\d+)", line)
        if ranged:
            result[name] = {
                "min": int(ranged.group(1)),
                "value": int(ranged.group(2)),
                "max": int(ranged.group(3)),
            }
            continue
        enum = re.search(r"current:\s*\[(.*)\]", line)
        if enum:
            selected = None
            for part in enum.group(1).split(","):
                part = part.strip()
                if part.startswith("(") and part.endswith(")"):
                    selected = part[1:-1]
            result[name] = {"value": selected}
            continue
        scalar = re.search(r"current:\s*(\d+)\s*$", line)
        if scalar and "value" not in result[name]:
            result[name] = {"value": int(scalar.group(1))}
    return result


def limit_block(armoury, attr):
    info = armoury.get(attr, {})
    value = int(info.get("value", 0) or 0)
    return {
        "min": int(info.get("min", value)),
        "max": int(info.get("max", value)),
        "value": value,
    }


def read_profiles():
    out = run_ok(["asusctl", "profile", "get"])
    active = ac = battery = "Quiet"
    for line in out.splitlines():
        match = re.search(r"Active profile:\s*(\w+)", line)
        if match:
            active = canon(match.group(1))
        match = re.search(r"AC profile\s+(\w+)", line)
        if match:
            ac = canon(match.group(1))
        match = re.search(r"Battery profile\s+(\w+)", line)
        if match:
            battery = canon(match.group(1))
    return active, ac, battery


def read_curves():
    curves = {}
    for profile in PROFILES:
        out = run_ok(["asusctl", "fan-curve", "--mod-profile", profile])
        curves[profile] = parse_curves(out)
    return curves


def read_charge():
    out = run_ok(["asusctl", "battery", "info"])
    match = re.search(r"(\d+)\s*%", out)
    return int(match.group(1)) if match else 100


def read_leds():
    raw = read_text("/sys/class/leds/asus::kbd_backlight/brightness", "")
    return {"0": "off", "1": "low", "2": "med", "3": "high"}.get(raw, "med")


def read_text(path, default=""):
    try:
        with open(path) as handle:
            return handle.read().strip()
    except OSError:
        return default


def on_ac():
    return read_text("/sys/class/power_supply/ACAD/online", "1") == "1"


def gpu_mode(armoury):
    disabled = str(armoury.get("dgpu_disable", {}).get("value", "0"))
    mux = str(armoury.get("gpu_mux_mode", {}).get("value", "1"))
    if disabled == "1":
        return "eco"
    if mux == "0":
        return "ultimate"
    return "hybrid"


def build_snapshot():
    active, ac, battery = read_profiles()
    armoury_text = run_ok(["asusctl", "armoury", "list"])
    armoury = parse_armoury(armoury_text)
    return {
        "ok": True,
        "profile": active,
        "acProfile": ac,
        "batteryProfile": battery,
        "ac": 1 if on_ac() else 0,
        "curves": read_curves(),
        "limits": {key: limit_block(armoury, attr) for key, attr in ATTRS.items()},
        "charge": read_charge(),
        "leds": read_leds(),
        "boost": 1 if read_text("/sys/devices/system/cpu/cpufreq/boost", "1") == "1" else 0,
        "gpuMode": gpu_mode(armoury),
        "reboot": read_text("/sys/devices/virtual/firmware-attributes/asus-armoury/pending_reboot", "0") == "1",
        "autostart": autostart_on(),
    }


def emit(extra=None):
    snap = build_snapshot()
    if extra:
        snap.update(extra)
    print(json.dumps(snap))


def load_presets():
    if not os.path.exists(PRESETS):
        return {}
    try:
        with open(PRESETS) as handle:
            data = json.load(handle)
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def save_presets(data):
    os.makedirs(os.path.dirname(PRESETS), exist_ok=True)
    tmp = PRESETS + ".tmp"
    with open(tmp, "w") as handle:
        json.dump(data, handle)
    os.replace(tmp, PRESETS)


def apply_preset(profile):
    saved = load_presets().get(profile)
    if not isinstance(saved, dict) or not saved:
        return False
    pairs = [(key, saved[key]) for key in ATTRS if key in saved]
    if not pairs:
        return False
    apply_limits(pairs, profile, remember=False)
    return True


def current_limits():
    armoury = parse_armoury(run_ok(["asusctl", "armoury", "list"]))
    values = {}
    for key, attr in ATTRS.items():
        info = armoury.get(attr, {})
        if "value" in info:
            values[key] = int(info["value"])
        values.setdefault("_ranges", {})[key] = info
    return values


def set_attr(key, value):
    run_ok(["asusctl", "armoury", "set", ATTRS[key], str(int(value))])


def apply_limits(pairs, profile, remember=True):
    current = current_limits()
    ranges = current.get("_ranges", {})
    wanted = {}
    for key, value in pairs:
        if key not in ATTRS:
            raise CmdError("unknown limit")
        value = int(value)
        info = ranges.get(key, {})
        if "min" in info:
            value = max(int(info["min"]), value)
        if "max" in info:
            value = min(int(info["max"]), value)
        wanted[key] = value

    if all(key in wanted for key in CPU_KEYS):
        if wanted["sppt"] < wanted["spl"]:
            wanted["sppt"] = wanted["spl"]
        if wanted["fppt"] < wanted["sppt"]:
            wanted["fppt"] = wanted["sppt"]

    order_up = ("fppt", "sppt", "spl", "tgp", "gboost", "gtemp")
    order_down = ("spl", "sppt", "fppt", "tgp", "gboost", "gtemp")
    raised = [key for key in order_up if key in wanted and wanted[key] > current.get(key, wanted[key])]
    lowered = [key for key in order_down if key in wanted and wanted[key] < current.get(key, wanted[key])]
    for key in raised + lowered:
        set_attr(key, wanted[key])

    if remember:
        presets = load_presets()
        slot = presets.get(profile, {})
        if not isinstance(slot, dict):
            slot = {}
        for key in wanted:
            slot[key] = wanted[key]
        presets[profile] = slot
        save_presets(presets)


def profile_enabled(profile):
    fans = parse_curves(run_ok(["asusctl", "fan-curve", "--mod-profile", profile]))
    return any(info.get("enabled") for info in fans.values())


def cmd_apply(profile, fan, data):
    profile = canon(profile)
    fan = fan.lower()
    if fan not in ("cpu", "gpu", "mid"):
        raise CmdError("unknown fan")
    points = [part.strip() for part in data.split(",") if part.strip()]
    if len(points) != 8:
        raise CmdError("a curve needs 8 points")
    keep = profile_enabled(profile)
    run_ok(["asusctl", "fan-curve", "--mod-profile", profile, "--fan", fan, "--data", ",".join(points)])
    if keep:
        run_ok(["asusctl", "fan-curve", "--mod-profile", profile, "--enable-fan-curves", "true"])


def autostart_on():
    return os.path.isfile(AUTOSTART)


def cmd_autostart(flag):
    on = str(flag).lower() in ("1", "true", "on", "yes")
    if on:
        os.makedirs(os.path.dirname(AUTOSTART), exist_ok=True)
        tmp = AUTOSTART + ".tmp"
        with open(tmp, "w") as handle:
            handle.write(autostart_entry())
        os.replace(tmp, AUTOSTART)
        return
    try:
        os.remove(AUTOSTART)
    except FileNotFoundError:
        pass


def cmd_boot():
    last = None
    for _ in range(5):
        try:
            active, _, _ = read_profiles()
            apply_preset(active)
            if profile_enabled(active):
                run_ok(["asusctl", "fan-curve", "--mod-profile", active, "--enable-fan-curves", "true"])
            return
        except CmdError as exc:
            last = exc
            time.sleep(1)
    if last:
        raise last


def cmd_default(profile):
    profile = canon(profile)
    for fan in FANS:
        run_ok(["asusctl", "fan-curve", "--mod-profile", profile, "--fan", fan, "--data", DEFAULT_CURVE])
    run_ok(["asusctl", "fan-curve", "--mod-profile", profile, "--enable-fan-curves", "true"])


def cmd_enable(profile, flag):
    value = "true" if str(flag).lower() in ("1", "true", "on", "yes") else "false"
    run_ok(["asusctl", "fan-curve", "--mod-profile", canon(profile), "--enable-fan-curves", value])


def cmd_use(profile):
    profile = canon(profile)
    run_ok(["asusctl", "profile", "set", profile])
    run_ok(["asusctl", "profile", "set", "-a" if on_ac() else "-b", profile])
    apply_preset(profile)


def cmd_remember(which, profile):
    flag = {"ac": "-a", "battery": "-b"}.get(which)
    if not flag:
        raise CmdError("say ac or battery")
    run_ok(["asusctl", "profile", "set", flag, canon(profile)])


def cmd_gpu(mode):
    mode = mode.lower()
    if mode == "hybrid":
        writes = (("dgpu_disable", "0"), ("gpu_mux_mode", "1"))
    elif mode == "eco":
        writes = (("dgpu_disable", "1"),)
    elif mode == "ultimate":
        writes = (("dgpu_disable", "0"), ("gpu_mux_mode", "0"))
    else:
        raise CmdError("unknown gpu mode")
    for attr, value in writes:
        run_ok(["asusctl", "armoury", "set", attr, value])


def cmd_battery(limit):
    limit = int(limit)
    if limit < 20 or limit > 100:
        raise CmdError("charge limit is 20 to 100")
    run_ok(["asusctl", "battery", "limit", str(limit)])


def cmd_leds(level):
    level = level.lower()
    if level not in ("off", "low", "med", "high"):
        raise CmdError("brightness is off, low, med, or high")
    run_ok(["asusctl", "leds", "set", level])


def cmd_boost(value):
    bit = "1" if str(value) in ("1", "true", "on") else "0"
    path = "/sys/devices/system/cpu/cpufreq/boost"
    try:
        with open(path, "w") as handle:
            handle.write(bit)
    except OSError as exc:
        raise CmdError(str(exc)) from exc


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help", "help"):
        print("usage: g14.py snapshot|use|remember|apply|enable|default|limits|battery|leds|boost|gpu|autostart|boot")
        return
    cmd = args[0]
    if cmd == "snapshot":
        emit()
        return
    if cmd == "use" and len(args) == 2:
        cmd_use(args[1])
    elif cmd == "remember" and len(args) == 3:
        cmd_remember(args[1], args[2])
    elif cmd == "apply" and len(args) == 4:
        cmd_apply(args[1], args[2], args[3])
    elif cmd == "enable" and len(args) == 3:
        cmd_enable(args[1], args[2])
    elif cmd == "default" and len(args) == 2:
        cmd_default(args[1])
    elif cmd == "limits" and len(args) >= 4 and len(args) % 2 == 0:
        pairs = list(zip(args[2::2], args[3::2]))
        apply_limits(pairs, canon(args[1]))
    elif cmd == "battery" and len(args) == 2:
        cmd_battery(args[1])
    elif cmd == "leds" and len(args) == 2:
        cmd_leds(args[1])
    elif cmd == "boost" and len(args) == 2:
        cmd_boost(args[1])
    elif cmd == "gpu" and len(args) == 2:
        cmd_gpu(args[1])
    elif cmd == "autostart" and len(args) == 2:
        cmd_autostart(args[1])
    elif cmd == "boot" and len(args) == 1:
        cmd_boot()
    else:
        raise CmdError("unknown command")
    note = None
    if cmd == "gpu":
        note = "GPU mode is stored for the next boot."
    emit({"note": note} if note else None)


if __name__ == "__main__":
    try:
        main()
    except CmdError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
