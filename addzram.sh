#!/bin/bash
#From https://github.com/spiritLHLS/addzram
#Channel: https://t.me/vps_reviews
#2025.03.02

# 设置UTF-8环境
utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "UTF-8|utf8")
if [[ -z "$utf8_locale" ]]; then
  echo "No UTF-8 locale found"
  echo "未找到UTF-8语言环境"
else
  export LC_ALL="$utf8_locale"
  export LANG="$utf8_locale"
  export LANGUAGE="$utf8_locale"
  echo "Locale set to $utf8_locale"
  echo "语言环境设置为 $utf8_locale"
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
  [[ $(id -u) != 0 ]] && _red " The script must be run as root, you can enter sudo -i and then download and run again." && _red " 脚本必须以root身份运行，您可以输入sudo -i，然后重新下载并运行。" && exit 1
}

# 检查zram模块是否可用并尝试安装
check_zram_module() {
  if ! lsmod | grep -q "^zram" && ! modprobe zram; then
    _yellow "Not find zram module, trying to install it..."
    _yellow "未找到zram模块，尝试安装..."
    # 检测可用的包管理器
    if command -v apt-get >/dev/null 2>&1; then
      _green "apt-get is available, installing zram-tools..."
      _green "检测到apt-get可用，正在安装zram-tools..."
      apt-get update
      apt-get install -y zram-tools
    elif command -v apt >/dev/null 2>&1; then
      _green "apt is available, installing zram-tools..."
      _green "检测到apt可用，正在安装zram-tools..."
      apt update
      apt install -y zram-tools
    elif command -v dnf >/dev/null 2>&1; then
      _green "dnf is available, installing kmod-zram..."
      _green "检测到dnf可用，正在安装kmod-zram..."
      dnf install -y kmod-zram
    elif command -v yum >/dev/null 2>&1; then
      _green "yum is available, installing kmod-zram..."
      _green "检测到yum可用，正在安装kmod-zram..."
      yum install -y kmod-zram
    elif command -v pacman >/dev/null 2>&1; then
      _green "pacman is available, installing zram-generator..."
      _green "检测到pacman可用，正在安装zram-generator..."
      pacman -Sy --noconfirm zram-generator
    elif command -v zypper >/dev/null 2>&1; then
      _green "zypper is available, installing zram..."
      _green "检测到zypper可用，正在安装zram..."
      zypper install -y zram
    else
      _red "No supported package manager found. Please install zram module manually."
      _red "未找到支持的包管理器，请手动安装zram模块。"
      echo "For Debian/Ubuntu: apt install zram-tools"
      echo "For RHEL/CentOS: yum install kmod-zram"
      echo "For Fedora: dnf install kmod-zram"
      echo "For Arch Linux: pacman -S zram-generator"
      echo "For openSUSE: zypper install zram"
      echo "对于Debian/Ubuntu系统: apt install zram-tools"
      echo "对于RHEL/CentOS系统: yum install kmod-zram"
      echo "对于Fedora系统: dnf install kmod-zram"
      echo "对于Arch Linux系统: pacman -S zram-generator"
      echo "对于openSUSE系统: zypper install zram"
      exit 1
    fi
    # 再次尝试加载
    if ! modprobe zram; then
      _red "Failed to load zram module. Please install it manually."
      _red "加载zram模块失败。请手动安装。"
      exit 1
    fi
  fi
  _green "ZRAM module is available."
  _green "ZRAM模块可用。"
}

# 显示zRAM和系统状态
show_status() {
    _blue "\n===== System Status / 系统状态 ====="
    
    # 显示物理内存信息
    local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_mb=$((mem_kb / 1024))
    _green "\n>> Physical Memory / 物理内存大小：${NC}$((mem_mb / 1024))GB ($mem_mb MB)"
    
    _green "\n>> SWAP Status / SWAP状态：${NC}"
    swapon --show
    
    _green "\n>> Block Devices / 块设备信息：${NC}"
    lsblk
    
    _green "\n>> ZRAM Compression Algorithm / zRAM压缩算法：${NC}"
    cat /sys/block/zram0/comp_algorithm 2>/dev/null || echo "ZRAM not loaded / zRAM未加载"
    
    _green "\n>> ZRAM Size / zRAM大小：${NC}"
    if [ -f /sys/block/zram0/disksize ]; then
        size_bytes=$(cat /sys/block/zram0/disksize)
        echo "$(human_readable_size $size_bytes)"
    else
        echo "ZRAM not loaded / zRAM未加载"
    fi
    
    _green "\n>> Memory Usage / 内存使用情况：${NC}"
    free -h
    echo
    read -p "Press Enter to continue... / 按回车键继续..." dummy
}

# 添加zRAM
add_zram() {
  # 检查zram模块
  check_zram_module
  
  # 准备算法文件
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
  
  # 检查必要命令
  if ! command -v zramctl >/dev/null; then
    _yellow "zramctl command not found. Please make sure zramctl is installed."
    _yellow "未找到zramctl命令。请确保已安装zramctl。"
    
    # 尝试安装zramctl
    if [ -f /etc/debian_version ]; then
      _green "Trying to install util-linux package..."
      _green "尝试安装util-linux包..."
      apt-get update && apt-get install -y util-linux
    elif [ -f /etc/redhat-release ]; then
      _green "Trying to install util-linux package..."
      _green "尝试安装util-linux包..."
      yum install -y util-linux
    fi
    
    # 再次检查
    if ! command -v zramctl >/dev/null; then
      _red "Failed to install zramctl. Please install it manually."
      _red "安装zramctl失败。请手动安装。"
      exit 1
    fi
  fi
  
  if ! command -v mkswap >/dev/null || ! command -v swapon >/dev/null; then
    _yellow "mkswap or swapon command not found. Please make sure these commands are installed."
    _yellow "未找到mkswap或swapon命令。请确保已安装这些命令。"
    
    # 尝试安装必要的工具
    if [ -f /etc/debian_version ]; then
      _green "Trying to install util-linux package..."
      _green "尝试安装util-linux包..."
      apt-get update && apt-get install -y util-linux
    elif [ -f /etc/redhat-release ]; then
      _green "Trying to install util-linux package..."
      _green "尝试安装util-linux包..."
      yum install -y util-linux
    fi
    
    # 再次检查
    if ! command -v mkswap >/dev/null || ! command -v swapon >/dev/null; then
      _red "Failed to install required tools. Please install them manually."
      _red "安装所需工具失败。请手动安装。"
      exit 1
    fi
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

  # 检查是否已存在zram设备
  if grep -q /dev/zram /proc/swaps; then
    _yellow "ZRAM device already exists. Removing it first..."
    _yellow "ZRAM设备已存在。首先将其删除..."
    swapoff /dev/zram0 2>/dev/null
    echo 1 > /sys/block/zram0/reset 2>/dev/null
    sleep 1
  fi

  # 设置zRAM
  if [ -d "/sys/block/zram0" ]; then
    zramctl /dev/zram0 --algorithm ${selected_algorithm} --size "${zram_size}M"
  else
    zramctl --find --size "${zram_size}MB" --algorithm "${selected_algorithm}"
  fi
  
  if [ $? -ne 0 ]; then
    _red "Failed to set up ZRAM. Please check the logs."
    _red "设置ZRAM失败。请检查日志。"
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

  # 创建模块加载配置
  echo "zram" > /etc/modules-load.d/zram.conf
  echo "options zram num_devices=1" > /etc/modprobe.d/zram.conf

  # 重新加载systemd配置
  systemctl daemon-reload
  systemctl enable zram.service
  
  _green "ZRAM setup complete. ZRAM device /dev/zram0 with size ${zram_size}M and use ${selected_algorithm} algorithm."
  _green "ZRAM 设置成功，ZRAM 设备路径为 /dev/zram0 大小为 ${zram_size}M 同时使用 ${selected_algorithm} 算法"
  _green "Service has been configured for auto-start on boot."
  _green "服务已配置为开机自启动。"
  check_zram
}

# 删除zRAM
del_zram() {
  if [ -e "$zram_device" ] || grep -q /dev/zram /proc/swaps; then
    echo "ZRAM device $zram_device exists and is being deleted..."
    echo "ZRAM 设备 $zram_device 存在，正在删除..."
    
    # 停止并禁用服务
    if [ -f /etc/systemd/system/zram.service ]; then
        systemctl stop zram.service
        systemctl disable zram.service
        rm -f /etc/systemd/system/zram.service
        systemctl daemon-reload
    fi
    
    # 删除模块加载配置
    rm -f /etc/modules-load.d/zram.conf
    rm -f /etc/modprobe.d/zram.conf
    
    # 停用并重置zram设备
    swapoff /dev/zram0 2>/dev/null
    if [ -e /sys/block/zram0/reset ]; then
        echo 1 > /sys/block/zram0/reset
    fi
    
    if lsmod | grep -q "^zram"; then
        rmmod zram 2>/dev/null
    fi
    
    if [ $? -ne 0 ]; then
      _yellow "Deletion failed, please check the log yourself."
      _yellow "删除失败，请自行检查日志。"
    else
      _green "Deleted successfully!"
      _green "删除成功！"
    fi
  else
    _yellow "ZRAM device $zram_device does not exist and cannot be deleted."
    _yellow "ZRAM 设备 $zram_device 不存在，无法删除。"
  fi
  check_zram
}

# 检查zRAM状态
check_zram() {
  _blue "\n===== ZRAM Status / ZRAM 状态 ====="
  
  # 检查模块是否加载
  if lsmod | grep -q "^zram"; then
    _green ">> ZRAM module loaded / ZRAM模块已加载"
  else
    _yellow ">> ZRAM module not loaded / ZRAM模块未加载"
  fi
  
  # 检查设备是否存在
  if [ -e "$zram_device" ]; then
    _green ">> ZRAM device created / ZRAM设备已创建"
    zramctl
    echo ""
    
    # 显示压缩信息
    if [ -f /sys/block/zram0/comp_algorithm ]; then
      _green ">> Current compression algorithm / 当前压缩算法："
      cat /sys/block/zram0/comp_algorithm
    fi
    
    # 检查swap状态
    if grep -q "$zram_device" /proc/swaps; then
      _green ">> ZRAM swap enabled / ZRAM swap已启用"
      swapon --show
    else
      _yellow ">> ZRAM device exists but not enabled as swap / ZRAM设备存在但未启用为swap"
    fi
    
    # 检查服务状态
    if [ -f /etc/systemd/system/zram.service ]; then
      _green ">> Service status / 服务状态："
      systemctl status zram.service --no-pager
    fi
  else
    _yellow ">> ZRAM device does not exist / ZRAM设备不存在"
  fi
  
  echo ""
  read -p "Press Enter to continue... / 按回车键继续..." dummy
}

# 验证zRAM运行状态
verify_zram() {
    _blue "\n===== Verifying ZRAM / 验证ZRAM状态 ====="
    
    # 检查模块是否加载
    if lsmod | grep -q "^zram"; then
        _green "ZRAM module is loaded / ZRAM模块已加载"
    else
        _red "ZRAM module is not loaded / ZRAM模块未加载"
        return 1
    fi
    
    # 检查设备是否存在
    if [ -e /sys/block/zram0 ]; then
        _green "ZRAM device is created / ZRAM设备已创建"
    else
        _red "ZRAM device is not created / ZRAM设备未创建"
        return 1
    fi
    
    # 检查swap状态
    if grep -q /dev/zram0 /proc/swaps; then
        _green "ZRAM swap is enabled / ZRAM swap已启用"
        echo -e "\nSwap details / Swap详情："
        grep /dev/zram0 /proc/swaps
    else
        _red "ZRAM swap is not enabled / ZRAM swap未启用"
        return 1
    fi
    
    # 检查服务状态
    if [ -f /etc/systemd/system/zram.service ]; then
        _green "\nService status / 服务状态："
        systemctl status zram.service --no-pager
    else
        _yellow "\nNo systemd service found / 未找到systemd服务"
    fi
    
    # 显示压缩信息
    if [ -f /sys/block/zram0/comp_algorithm ]; then
        _green "\nCurrent compression algorithm / 当前压缩算法："
        cat /sys/block/zram0/comp_algorithm
    fi
    
    # 显示性能统计
    if [ -f /sys/block/zram0/mm_stat ]; then
        _green "\nMemory statistics / 内存统计："
        cat /sys/block/zram0/mm_stat
    fi
    
    if [ -f /sys/block/zram0/stat ]; then
        _green "\nIO statistics / IO统计："
        cat /sys/block/zram0/stat
    fi
    
    echo ""
    read -p "Press Enter to continue... / 按回车键继续..." dummy
}

# 主菜单
main() {
  check_root
  clear
  free -m
  echo -e "—————————————————————————————————————————————————————————————"
  echo -e "${Green}Linux VPS one click add/remove zram script ${Font}"
  echo -e "${Green}Linux VPS 一键添加/删除 zram 脚本 ${Font}"
  echo -e "${Green}1, Add zram / 添加zRAM${Font}"
  echo -e "${Green}2, Remove zram / 删除zRAM${Font}"
  echo -e "${Green}3, Show detailed status / 查看详细状态${Font}"
  echo -e "${Green}4, Verify zRAM status / 验证zRAM运行状态${Font}"
  echo -e "—————————————————————————————————————————————————————————————"
  while true; do
    _green "Please enter a number / 请输入数字"
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
      verify_zram
      main
      break
      ;;
    *)
      echo "Invalid input, please retry / 输入错误，请重新输入"
      ;;
    esac
  done
}

main
