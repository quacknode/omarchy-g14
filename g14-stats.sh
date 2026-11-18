#!/bin/sh
want_gpu=0
[ "$1" = "--gpu" ] && want_gpu=1

cpu=0
igpu=0
cpu_rpm=0
gpu_rpm=0
mid_rpm=0

for h in /sys/class/hwmon/hwmon*; do
  name=$(cat "$h/name" 2>/dev/null) || continue
  case "$name" in
    k10temp)
      cpu=$(cat "$h/temp1_input" 2>/dev/null || echo 0)
      ;;
    amdgpu)
      igpu=$(cat "$h/temp1_input" 2>/dev/null || echo 0)
      ;;
    asus)
      i=1
      while [ -e "$h/fan${i}_input" ]; do
        label=$(cat "$h/fan${i}_label" 2>/dev/null)
        rpm=$(cat "$h/fan${i}_input" 2>/dev/null || echo 0)
        case "$label" in
          cpu_fan) cpu_rpm=$rpm ;;
          gpu_fan) gpu_rpm=$rpm ;;
          mid_fan) mid_rpm=$rpm ;;
        esac
        i=$((i + 1))
      done
      ;;
  esac
done

nvjson=null
if [ "$want_gpu" = 1 ]; then
  for pci in /sys/bus/pci/devices/*; do
    [ "$(cat "$pci/vendor" 2>/dev/null)" = "0x10de" ] || continue
    case $(cat "$pci/class" 2>/dev/null) in
      0x0300*) ;;
      *) continue ;;
    esac
    [ "$(cat "$pci/power/runtime_status" 2>/dev/null)" = "active" ] || continue
    nv=$(timeout 1 nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -cd '0-9')
    [ -n "$nv" ] && nvjson=$nv
    break
  done
fi

boost=$(cat /sys/devices/system/cpu/cpufreq/boost 2>/dev/null || echo 1)
ac=$(cat /sys/class/power_supply/ACAD/online 2>/dev/null || echo 0)
raw=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo quiet)
profile=$(printf '%s' "$raw" | awk '{ print toupper(substr($0,1,1)) substr($0,2) }')

cpu=$(( ${cpu:-0} / 1000 ))
igpu=$(( ${igpu:-0} / 1000 ))

printf '{"ok":true,"cpu":%s,"igpu":%s,"gpu":%s,"fans":[%s,%s,%s],"boost":%s,"ac":%s,"profile":"%s"}\n' \
  "${cpu:-0}" "${igpu:-0}" "$nvjson" \
  "${cpu_rpm:-0}" "${gpu_rpm:-0}" "${mid_rpm:-0}" \
  "${boost:-1}" "${ac:-0}" "$profile"
