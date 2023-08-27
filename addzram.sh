#!/bin/bash
#From https://github.com/spiritLHLS/addzram
#Channel: https://t.me/vps_reviews
#2023.08.27

utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "UTF-8|utf8")
if [[ -z "$utf8_locale" ]]; then
  echo "No UTF-8 locale found"
else
  export LC_ALL="$utf8_locale"
  export LANG="$utf8_locale"
  export LANGUAGE="$utf8_locale"
  echo "Locale set to $utf8_locale"
fi
[[ $(id -u) != 0 ]] && red " The script must be run as root, you can enter sudo -i and then download and run again." && exit 1
if ! lsmod | grep -q zram; then
    echo "Loading zram module..."
    modprobe zram
fi
if ! command -v zramctl > /dev/null; then
    echo "zramctl command not found. Please make sure zramctl is installed."
    exit 1
fi
if ! command -v mkswap > /dev/null || ! command -v swapon > /dev/null; then
    echo "mkswap or swapon command not found. Please make sure these commands are installed."
    exit 1
fi
total_memory=$(free -m | awk '/^Mem:/{print $2}')
zram_size=$((total_memory / 2))
zramctl /dev/zram0 --algorithm zstd --size "${zram_size}M"
mkswap /dev/zram0
swapon --priority 100 /dev/zram0
echo "ZRAM setup complete. ZRAM device /dev/zram0 with size ${zram_size}M and algorithm zstd is now active as swap."
zramctl
swapon --show
