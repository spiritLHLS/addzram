#!/bin/bash
#From https://github.com/spiritLHLS/addzram
#Channel: https://t.me/vps_reviews
#2023.08.30

utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "UTF-8|utf8")
if [[ -z "$utf8_locale" ]]; then
  echo "No UTF-8 locale found"
else
  export LC_ALL="$utf8_locale"
  export LANG="$utf8_locale"
  export LANGUAGE="$utf8_locale"
  echo "Locale set to $utf8_locale"
fi
if [ ! -d /usr/local/bin ]; then
    mkdir -p /usr/local/bin
fi

# 自定义字体彩色和其他配置
Green="\033[32m"
Font="\033[0m"
Red="\033[31m"
_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading() { read -rp "$(_green "$1")" "$2"; }
zram_device="/dev/zram0"

# 必须以root运行脚本
check_root() {
  [[ $(id -u) != 0 ]] && _red " The script must be run as root, you can enter sudo -i and then download and run again." && exit 1
}

add_zram() {
  modprobe zram
  if [ $? -ne 0 ]; then
    _yellow "Not find zram module, please install it in kernel manually."
    exit 1
  fi
  if [ -f /sys/block/zram0/comp_algorithm ]; then
    rm -rf /usr/local/bin/zram_algorithm
    output=$(cat /sys/block/zram0/comp_algorithm)
    IFS=' ' read -ra words <<< "$output"
    for word in "${words[@]}"; do
        if ! echo "$word" | grep -qE '^[0-9]+$'; then
            clean_word="${word//[\[\]]/}"
            echo "$clean_word" >> /usr/local/bin/zram_algorithm
        fi
    done
  fi
  if ! command -v zramctl >/dev/null; then
    _yellow "zramctl command not found. Please make sure zramctl is installed."
    exit 1
  fi
  if ! command -v mkswap >/dev/null || ! command -v swapon >/dev/null; then
    _yellow "mkswap or swapon command not found. Please make sure these commands are installed."
    exit 1
  fi
  readarray -t lines < /usr/local/bin/zram_algorithm
  for (( i=0; i<${#lines[@]}; i++ )); do
      if [[ "${lines[$i]}" == *"zstd"* ]]; then
          # 移动元素到第一位
          temp="${lines[$i]}"
          unset lines[$i]
          lines=("$temp" "${lines[@]}")
      fi
  done
  for i in "${!lines[@]}"; do
      _blue "[$i] ${lines[$i]}"
  done
  _green "Enter the serial number of the algorithm to be used (leaving a blank carriage return defaults to zstd):"
  reading "请输入要使用的算法的序号(留空回车则默认zstd):" selected_index
  if [[ $selected_index =~ ^[0-9]+$ ]] && [ "$selected_index" -ge 0 ] && [ "$selected_index" -lt "${#lines[@]}" ]; then
      selected_algorithm="${lines[$selected_index]}"
  else
      selected_algorithm="zstd"
  fi
  _green "Please enter the zram value in megabytes (MB) (leave blank and press Enter for default, which is half of the memory):"
  reading "请输入zram数值，以MB计算(留空回车则默认为内存的一半):" zram_size
  if [ -z "$zram_size" ]; then
    total_memory=$(free -m | awk '/^Mem:/{print $2}')
    zram_size=$((total_memory / 2))
  fi
  if [ -d "/sys/block/zram0" ]; then
    zramctl /dev/zram0 --algorithm ${selected_algorithm} --size "${zram_size}M"
  else
    zramctl --find --size "${zram_size}MB" --algorithm "${selected_algorithm}"
  fi
  if [ $? -ne 0 ]; then
    echo "ZRAM device $zram_device exists, cannot be duplicated, if you need to reset, please select ‘Remove zram’ first."
    echo "ZRAM 设备 $zram_device 已存在，无法重复设置，如需重新设置请先选择删除"
    exit 1
  fi
  mkswap /dev/zram0
  swapon --priority 100 /dev/zram0
  _green "ZRAM setup complete. ZRAM device /dev/zram0 with size ${zram_size}M and use ${selected_algorithm} algorithm."
  _blue "ZRAM 设置成功，ZRAM 设备路径为 /dev/zram0 大小为 ${zram_size}M 同时使用 ${selected_algorithm} 算法"
  check_zram
}

del_zram() {
  if [ -e "$zram_device" ]; then
      echo "ZRAM device $zram_device exists and is being deleted..."
      echo "ZRAM 设备 $zram_device 存在，正在删除..."
      swapoff "$zram_device" && zramctl --reset "$zram_device"
      if [ $? -ne 0 ]; then
        _yellow "Deletion failed, please check the log yourself."
        _yellow "删除失败，请自行检查日志。"
      else
        _green "Deleted successfully!"
        _blue "删除成功！"
      fi
  else
      _yellow "ZRAM device $zram_device does not exist and cannot be deleted."
      _blue "ZRAM 设备 $zram_device 不存在，无法删除。"
  fi
  check_zram
}

check_zram() {
  if [ -e "$zram_device" ]; then
    zramctl
    echo ""
  fi
  swapon --show
}

#开始菜单
main() {
  check_root
  check_zram
  clear
  free -m
  echo -e "—————————————————————————————————————————————————————————————"
  echo -e "${Green}Linux VPS one click add/remove zram script ${Font}"
  echo -e "${Green}1, Add zram${Font}"
  echo -e "${Green}2, Remove zram${Font}"
  echo -e "—————————————————————————————————————————————————————————————"
  while true; do
    _green "Please enter a number"
    reading "请输入数字 [1-2]:" num
    case "$num" in
    1)
      add_zram
      break
      ;;
    2)
      del_zram
      break
      ;;
    *)
      echo "输入错误，请重新输入"
      ;;
    esac
  done
}

main
