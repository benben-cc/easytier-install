#!/bin/bash
set -uo pipefail

INSTALL_DIR="/usr/local/easytier"
CORE_BIN="easytier-core"
CONFIG_FILE="config.yaml"
TARGET_CORE="${INSTALL_DIR}/${CORE_BIN}"
TARGET_CONFIG="${INSTALL_DIR}/${CONFIG_FILE}"
SERVICE_NAME="easytier"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
RUN_USER="root"
DEFAULT_HOSTNAME="ali"
DEFAULT_INSTANCE_NAME="ali"
DEFAULT_IPV4="10.0.0.10/24"
DEFAULT_NETWORK_NAME="123"
DEFAULT_NETWORK_SECRET="123"
LOG_FILE="${INSTALL_DIR}/${SERVICE_NAME}.log"
MANAGER_SCRIPT="${INSTALL_DIR}/${SERVICE_NAME}-manager.sh"
GLOBAL_CMD="/usr/local/bin/et"
DOWNLOAD_URL="https://gitee.com/zyhhtu/easytier/releases/download/easytier-script/easytier-core"

LIGHT_BLUE="\033[94m"
BLUE="\033[34m"
DARK_BLUE="\033[36m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

info() { echo -e "${BLUE}[INFO] $1${RESET}"; }
error() { echo -e "${RED}[ERROR] $1${RESET}"; }
warn() { echo -e "${YELLOW}[WARN] $1${RESET}"; }
prompt() { echo -e "${BLUE}[PROMPT] $1${RESET}"; }

is_installed() {
    [ -f "${SERVICE_FILE}" ] && [ -f "${TARGET_CORE}" ] && [ -f "${TARGET_CONFIG}" ]
}

get_running_status() {
    if timeout 2 systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
        echo -e "${GREEN}运行中${RESET}"
    else
        systemctl is-failed --quiet "${SERVICE_NAME}" 2>/dev/null && echo -e "${RED}启动失败（auto-restart）${RESET}" || echo -e "${RED}已停止${RESET}"
    fi
}

get_auto_start_status() {
    timeout 2 systemctl is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null && echo -e "${GREEN}已开启${RESET}" || echo -e "${RED}已关闭${RESET}"
}

validate_log_file() {
    [ -d "${INSTALL_DIR}" ] || { error "安装目录不存在：${INSTALL_DIR}"; return 1; }
    [ -f "${LOG_FILE}" ] || touch "${LOG_FILE}" || { error "创建日志文件失败"; return 1; }
    chown "${RUN_USER}:${RUN_USER}" "${LOG_FILE}" && chmod 640 "${LOG_FILE}" || { error "设置日志文件权限失败"; return 1; }
    info "日志文件验证通过：${LOG_FILE}"
}

check_uuidgen() {
    command -v uuidgen &> /dev/null || { error "未找到uuidgen！Debian/Ubuntu: apt install -y uuid-runtime; CentOS/RHEL: yum install -y util-linux"; exit 1; }
}

check_download_tool() {
    if command -v wget &> /dev/null; then
        DOWNLOAD_TOOL="wget"
    elif command -v curl &> /dev/null; then
        DOWNLOAD_TOOL="curl"
    else
        error "未找到wget或curl！请先安装：Debian/Ubuntu: apt install -y wget; CentOS/RHEL: yum install -y wget"
        exit 1
    fi
}

download_core_bin() {
    check_download_tool
    info "开始从远程下载核心文件：${DOWNLOAD_URL}"
    rm -f "${TARGET_CORE}" 2>/dev/null
    if [ "${DOWNLOAD_TOOL}" = "wget" ]; then
        wget -q -O "${TARGET_CORE}" "${DOWNLOAD_URL}" || { error "wget下载失败"; return 1; }
    else
        curl -s -L -o "${TARGET_CORE}" "${DOWNLOAD_URL}" || { error "curl下载失败"; return 1; }
    fi
    [ -f "${TARGET_CORE}" ] || { error "核心文件下载后不存在"; return 1; }
    chmod +x "${TARGET_CORE}" || { error "设置核心文件执行权限失败"; return 1; }
    info "✅ 核心文件下载完成：${TARGET_CORE}"
}

generate_custom_config() {
    prompt "配置核心参数（回车使用默认值）"
    read -p "hostname（默认：${DEFAULT_HOSTNAME}）：" custom_hostname
    read -p "instance_name（默认：${DEFAULT_INSTANCE_NAME}）：" custom_instance_name
    read -p "ipv4（默认：${DEFAULT_IPV4}）：" custom_ipv4
    read -p "network_name（默认：${DEFAULT_NETWORK_NAME}）：" custom_network_name
    read -p "network_secret（默认：${DEFAULT_NETWORK_SECRET}）：" custom_network_secret

    custom_hostname=${custom_hostname:-"${DEFAULT_HOSTNAME}"}
    custom_instance_name=${custom_instance_name:-"${DEFAULT_INSTANCE_NAME}"}
    custom_ipv4=${custom_ipv4:-"${DEFAULT_IPV4}"}
    custom_network_name=${custom_network_name:-"${DEFAULT_NETWORK_NAME}"}
    custom_network_secret=${custom_network_secret:-"${DEFAULT_NETWORK_SECRET}"}

    check_uuidgen
    custom_instance_id=$(uuidgen)
    info "自动生成instance_id：${custom_instance_id}"

    cat > "${TARGET_CONFIG}" <<EOF
hostname = "${custom_hostname}"
instance_name = "${custom_instance_name}"
instance_id = "${custom_instance_id}"
ipv4 = "${custom_ipv4}"
dhcp = false
listeners = [
    "tcp://0.0.0.0:11010",
    "udp://0.0.0.0:11010",
    "wg://0.0.0.0:11011",
]
rpc_portal = "0.0.0.0:0"

[network_identity]
network_name = "${custom_network_name}"
network_secret = "${custom_network_secret}"

[flags]
enable_kcp_proxy = true
private_mode = true
EOF

    chown "${RUN_USER}:${RUN_USER}" "${TARGET_CONFIG}" && chmod 640 "${TARGET_CONFIG}" || { error "配置文件权限设置失败"; return 1; }
    info "✅ 配置文件生成完成：${TARGET_CONFIG}"
    info "  - hostname: ${custom_hostname}"
    info "  - instance_name: ${custom_instance_name}"
    info "  - ipv4: ${custom_ipv4}"
    info "  - network_name: ${custom_network_name}"
    info "  - network_secret: ${custom_network_secret}"
    info "  - instance_id: ${custom_instance_id}"
}

func_install() {
    info "开始安装EasyTier服务..."
    info "📌 安装后默认开启开机自启"
    rm -rf "${INSTALL_DIR}" && mkdir -p "${INSTALL_DIR}" && chown -R "${RUN_USER}:${RUN_USER}" "${INSTALL_DIR}" && chmod 750 "${INSTALL_DIR}"
    download_core_bin || return 1
    generate_custom_config || return 1
    validate_log_file || return 1
    cp -f "$0" "${MANAGER_SCRIPT}" && chmod +x "${MANAGER_SCRIPT}"
    ln -sf "${MANAGER_SCRIPT}" "${GLOBAL_CMD}"
    info "全局快捷方式创建完成：sudo et"

    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=EasyTier Core Service
After=network.target

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${TARGET_CORE} -c ${TARGET_CONFIG}
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 "${SERVICE_FILE}"
    systemctl daemon-reload
    
    systemctl enable --now "${SERVICE_NAME}"
    info "已开启开机自启并启动服务"
    
    sleep 3
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        info "✅ 安装启动成功！"
        info "服务状态：$(get_running_status) | 开机自启：$(get_auto_start_status)"
        systemctl status "${SERVICE_NAME}" --no-pager
    else
        warn "⚠️  服务安装完成但启动失败"
        warn "排查：1. sudo ${TARGET_CORE} -c ${TARGET_CONFIG} 2. sudo tail -f ${LOG_FILE} 3. sudo journalctl -u ${SERVICE_NAME} -n 20"
    fi
}

func_uninstall() {
    is_installed || { error "未检测到已安装服务"; return 1; }
    warn "⚠️  卸载将删除所有相关文件（不可恢复）"
    read -p "确认卸载？(y/N)：" confirm
    [[ ! "${confirm}" =~ ^[Yy]$ ]] && { info "已取消"; return 0; }
    systemctl stop "${SERVICE_NAME}" 2>/dev/null
    systemctl disable "${SERVICE_NAME}" 2>/dev/null
    rm -f "${SERVICE_FILE}" && systemctl daemon-reload
    rm -rf "${INSTALL_DIR}" "${GLOBAL_CMD}"
    info "✅ 卸载完成"
}

func_start() { is_installed || { error "未安装"; return 1; }; validate_log_file && systemctl start "${SERVICE_NAME}" && sleep 2 && { systemctl is-active --quiet "${SERVICE_NAME}" && info "✅ 启动成功" || error "启动失败"; } || error "日志验证失败"; }
func_stop() { is_installed || { error "未安装"; return 1; }; systemctl stop "${SERVICE_NAME}" && sleep 2 && info "✅ 停止成功" || error "停止失败"; }
func_restart() { is_installed || { error "未安装"; return 1; }; validate_log_file && systemctl restart "${SERVICE_NAME}" && sleep 2 && { systemctl is-active --quiet "${SERVICE_NAME}" && info "✅ 重启成功" || error "重启失败"; } || error "日志验证失败"; }

func_toggle_auto_start() {
    is_installed || { error "未安装服务"; return 1; }
    current_status=$(systemctl is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null && echo "enabled" || echo "disabled")
    info "当前开机自启状态：$(get_auto_start_status)"
    
    if [ "${current_status}" = "enabled" ]; then
        prompt "是否关闭开机自启？(y/N)"
        read -p "请输入：" choice
        [[ "${choice}" =~ ^[Yy]$ ]] && { systemctl disable "${SERVICE_NAME}" && info "✅ 开机自启已关闭" || error "关闭失败"; } || info "已取消关闭"
    else
        prompt "是否开启开机自启？(y/N)"
        read -p "请输入：" choice
        [[ "${choice}" =~ ^[Yy]$ ]] && { systemctl enable "${SERVICE_NAME}" && info "✅ 开机自启已开启" || error "开启失败"; } || info "已取消开启"
    fi
}

func_log() {
    is_installed || { error "未安装服务"; return 1; }
    info "📜 实时日志（按 Enter 键返回面板，Ctrl+C 强制退出）"
    echo -e "${YELLOW}日志文件路径：${LOG_FILE}${RESET}"
    
    if [ -f "${LOG_FILE}" ]; then
        tail -f "${LOG_FILE}" &
    else
        warn "日志文件不存在，查看systemd日志..."
        journalctl -u "${SERVICE_NAME}" -f &
    fi
    
    tail_pid=$!
    read -r -s -n 1
    kill -TERM "${tail_pid}" 2>/dev/null
    wait "${tail_pid}" 2>/dev/null
    info "已返回主面板"
}

main_ui() {
    clear
    echo -e "${LIGHT_BLUE}========================================================${RESET}"
    echo "      EasyTier 管理面板(全局命令:et) ---张亚豪"
    echo -e "${LIGHT_BLUE}========================================================${RESET}"
    if is_installed; then
        echo -e "📌 服务名：${SERVICE_NAME}" " 安装目录：${INSTALL_DIR}"
    else
        echo -e "📌 当前状态：${RED}未安装${RESET}"
    fi
    echo -e "${LIGHT_BLUE}========================================================${RESET}"
    echo -e "${BLUE}请选择操作（输入序号回车）：${RESET}"
    
    local options=()
    if is_installed; then
        options=(
            "🚪 退出工具"
            "📥 启动服务"
            "📤 停止服务"
            "🔄 重启服务"
            "📜 实时日志"
            "⚙️  开机自启"
            "🗑️ 卸载服务"
        )
    else
        options=(
            "🚪 退出工具"
            "📥 安装服务"
        )
    fi
    for i in "${!options[@]}"; do
        echo -e "  ${DARK_BLUE}${i})${RESET} ${options[$i]}"
    done
    
    if is_installed; then
        echo -e "${BLUE}========================================================${RESET}"
        echo -e "📌 当前状态：${GREEN}已安装${RESET}"
        echo -e "📌 运行状态：$(get_running_status)"
        echo -e "📌 开机自启：$(get_auto_start_status)"
    fi
    
    local max_index=$(( ${#options[@]} - 1 ))
    echo -e "${LIGHT_BLUE}========================================================${RESET}"
    echo -n -e "📌 请输入操作序号（0-${max_index}）：${DARK_BLUE}"
    read -r choice
    echo -e "${RESET}${LIGHT_BLUE}========================================================${RESET}"
    
    case "${choice}" in
        0) info "感谢使用，再见！"; exit 0 ;;
        1) is_installed && func_start || func_install ;;
        2) is_installed && func_stop || error "无效序号：未安装服务" ;;
        3) is_installed && func_restart || error "无效序号：未安装服务" ;;
        4) is_installed && func_log || error "无效序号：未安装服务" ;;
        5) is_installed && func_toggle_auto_start || error "无效序号：未安装服务" ;;
        6) is_installed && func_uninstall || error "无效序号：未安装服务" ;;
        *) error "无效序号，请输入 0-${max_index}" ;;
    esac
    
    echo -e "\n${DARK_BLUE}========================================================${RESET}"
    echo -e "📌 操作完成！按回车键返回主界面...${RESET}"
    echo -e "${DARK_BLUE}========================================================${RESET}"
    read -r -s -n 1
    main_ui
}

if [ "$(id -u)" -ne 0 ]; then
    error "请用root权限运行！"
    echo "  方式1：sudo ./脚本名.sh"
    echo "  方式2：sudo et（安装后全局命令）"
    exit 1
fi

while true; do
    main_ui
done