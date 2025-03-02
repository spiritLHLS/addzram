#!/bin/bash
#From https://github.com/spiritLHLS/addzram
#Channel: https://t.me/vps_reviews
#2025.03.02

# 设置UTF-8环境
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

# 颜色定义
Green="\033[32m"
Font="\033[0m"
Red="\033[31m"
Yellow="\033[1;33m"
Blue="\033[36m"
NC="\033[0m" # No Color

_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading() { read -rp "$(_green "$1")" "$2"; }

zram_device="/dev/zram0"

# 显示人类可读的大小
human_readable_size() {
    local bytes=$1
    if [ $bytes -gt $((1024*1024*1024)) ]; then
        echo "$((bytes / 1024 / 1024 / 1024))GB"
    else
        echo "$((bytes / 1024 / 1024))MB"
    fi
}

# 获取内存大小并计算推荐的zRAM大小
calculate_zram_size() {
    local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_mb=$((mem_kb / 1024))
    local zram_mb

    # 根据物理内存大小设置zRAM大小
    if [ $mem_mb -lt 1024 ]; then
        zram_mb=$mem_mb
    elif [ $mem_mb -lt 2048 ]; then
        zram_mb=$mem_mb
    elif [ $mem_mb -lt 4096 ]; then
        zram_mb=$((mem_mb * 3 / 4))
    else
        zram_mb=$((mem_mb / 2))
    fi

    echo $zram_mb
}

# 必须以root运行脚本
check_root() {
  [[ $(id -u) != 0 ]] && _red " The script must be run as root, you can enter sudo -i and then download and run again." && exit 1
}

# 显示zRAM和系统状态
show_status() {
    _blue "\n===== 系统状态 ====="
    
    # 显示物理内存信息
    local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_mb=$((mem_kb / 1024))
    _green "\n>> 物理内存大小：${NC}$((mem_mb / 1024))GB ($mem_mb MB)"
    
    _green "\n>> SWAP状态：${NC}"
    swapon --show
    
    _green "\n>> 块设备信息：${NC}"
    lsblk
    
    _green "\n>> zRAM压缩算法：${NC}"
    cat /sys/block/zram0/comp_algorithm 2>/dev/null || echo "zRAM未加载"
    
    _green "\n>> zRAM大小：${NC}"
    if [ -f /sys/block/zram0/disksize ]; then
        size_bytes=$(cat /sys/block/zram0/disksize)
        echo "$(human_readable_size $size_bytes)"
    else
        echo "zRAM未加载"
    fi
    
    _green "\n>> 内存使用情况：${NC}"
    free -h
    echo
    read -p "按回车键继续..."
}

# 添加zRAM
add_zram() {
  modprobe zram
  if [ $? -ne 0 ]; then
    _yellow "Not find zram module, please install it in kernel manually."
    exit 1
  fi
  if [ -f /sys/block/zram0/comp_algorithm ]; then
    rm -rf /usr/local/bin/zram_algorithm
    output=$(cat /sys/block/zram0/comp_algorithm)
    IFS=' ' read -ra words <<<"$output"
    for word in "${words[@]}"; do
      if ! echo "$word" | grep -qE '^[0-9]+$'; then
        clean_word="${word//[\[\]]/}"
        echo "$clean_word" >>/usr/local/bin/zram_algorithm
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

  # 显示算法选择
  readarray -t lines </usr/local/bin/zram_algorithm
  for ((i = 0; i < ${#lines[@]}; i++)); do
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

  # 计算推荐的zRAM大小
  recommended_size=$(calculate_zram_size)
  _green "Please enter the zram value in megabytes (MB) (leave blank and press Enter for recommended size: ${recommended_size}MB):"
  reading "请输入zram数值，以MB计算(留空回车则默认为推荐大小 ${recommended_size}MB):" zram_size
  if [ -z "$zram_size" ]; then
    zram_size=$recommended_size
  fi

  # 设置zRAM
  if [ -d "/sys/block/zram0" ]; then
    zramctl /dev/zram0 --algorithm ${selected_algorithm} --size "${zram_size}M"
  else
    zramctl --find --size "${zram_size}MB" --algorithm "${selected_algorithm}"
  fi
  if [ $? -ne 0 ]; then
    echo "ZRAM device $zram_device exists, cannot be duplicated, if you need to reset, please select 'Remove zram' first."
    echo "ZRAM 设备 $zram_device 已存在，无法重复设置，如需重新设置请先选择删除"
    exit 1
  fi
  mkswap /dev/zram0
  swapon --priority 100 /dev/zram0
  
  # 创建systemd服务以实现开机自启
  cat > /etc/systemd/system/zram.service << EOF
[Unit]
Description=Swap with zram
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=true
ExecStartPre=/sbin/modprobe zram
ExecStartPre=/bin/bash -c 'echo ${selected_algorithm} > /sys/block/zram0/comp_algorithm'
ExecStartPre=/bin/bash -c 'echo ${zram_size}M > /sys/block/zram0/disksize'
ExecStartPre=/sbin/mkswap /dev/zram0
ExecStart=/sbin/swapon -p 100 /dev/zram0
ExecStop=/sbin/swapoff /dev/zram0

[Install]
WantedBy=multi-user.target
EOF

  # 重新加载systemd配置
  systemctl daemon-reload
  systemctl enable zram.service
  
  _green "ZRAM setup complete. ZRAM device /dev/zram0 with size ${zram_size}M and use ${selected_algorithm} algorithm."
  _blue "ZRAM 设置成功，ZRAM 设备路径为 /dev/zram0 大小为 ${zram_size}M 同时使用 ${selected_algorithm} 算法"
  _green "Service has been configured for auto-start on boot."
  _blue "已配置为开机自启动。"
  check_zram
}

# 删除zRAM
del_zram() {
  if [ -e "$zram_device" ]; then
    echo "ZRAM device $zram_device exists and is being deleted..."
    echo "ZRAM 设备 $zram_device 存在，正在删除..."
    
    # 停止并禁用服务
    if [ -f /etc/systemd/system/zram.service ]; then
        systemctl stop zram.service
        systemctl disable zram.service
        rm -f /etc/systemd/system/zram.service
        systemctl daemon-reload
    fi
    
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

# 检查zRAM状态
check_zram() {
  _blue "\n===== zRAM 状态 ====="
  
  # 检查模块是否加载
  if lsmod | grep -q "^zram"; then
    _green ">> zRAM模块已加载"
  else
    _yellow ">> zRAM模块未加载"
  fi
  
  # 检查设备是否存在
  if [ -e "$zram_device" ]; then
    _green ">> zRAM设备已创建"
    zramctl
    echo ""
    
    # 显示压缩信息
    if [ -f /sys/block/zram0/comp_algorithm ]; then
      _green ">> 当前压缩算法："
      cat /sys/block/zram0/comp_algorithm
    fi
    
    # 检查swap状态
    if grep -q "$zram_device" /proc/swaps; then
      _green ">> zRAM swap已启用"
      swapon --show
    else
      _yellow ">> zRAM设备存在但未启用为swap"
    fi
    
    # 检查服务状态
    if [ -f /etc/systemd/system/zram.service ]; then
      _green ">> 服务状态："
      systemctl status zram.service --no-pager
    fi
  else
    _yellow ">> zRAM设备不存在"
  fi
  
  echo ""
  read -p "按回车键继续..."
}

# 主菜单
main() {
  check_root
  clear
  free -m
  echo -e "—————————————————————————————————————————————————————————————"
  echo -e "${Green}Linux VPS one click add/remove zram script ${Font}"
  echo -e "${Green}1, 添加zRAM${Font}"
  echo -e "${Green}2, 删除zRAM${Font}"
  echo -e "${Green}3, 查看详细状态${Font}"
  echo -e "${Green}4, 验证zRAM运行状态${Font}"
  echo -e "—————————————————————————————————————————————————————————————"
  while true; do
    _green "Please enter a number"
    reading "请输入数字 [1-4]:" num
    case "$num" in
    1)
      add_zram
      break
      ;;
    2)
      del_zram
      break
      ;;
    3)
      show_status
      main
      break
      ;;
    4)
      check_zram
      main
      break
      ;;
    *)
      echo "输入错误，请重新输入"
      ;;
    esac
  done
}

main
