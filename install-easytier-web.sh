#!/bin/bash
set -uo pipefail

INSTALL_DIR="/usr/local/easytier"
CORE_BIN="easytier-core"
WEB_BIN="easytier-web-embed"
TARGET_CORE="${INSTALL_DIR}/${CORE_BIN}"
TARGET_WEB="${INSTALL_DIR}/${WEB_BIN}"
SERVICE_NAME="easytier"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
RUN_USER="root"

DEFAULT_HOSTNAME="shanghai"
DEFAULT_WEB_USER="admin"
WG_PORT="22020"

LOG_FILE="${INSTALL_DIR}/${SERVICE_NAME}.log"
MANAGER_SCRIPT="${INSTALL_DIR}/${SERVICE_NAME}-manager.sh"
GLOBAL_CMD="/usr/bin/et"

DOWNLOAD_URL="https://raw.githubusercontent.com/benben-cc/easytier-install/refs/heads/main/easytier-core"
WEB_DOWNLOAD_URL="https://raw.githubusercontent.com/benben-cc/easytier-install/refs/heads/main/easytier-web-embed"

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
    [ -f "${SERVICE_FILE}" ] && [ -f "${TARGET_CORE}" ] && [ -f "${TARGET_WEB}" ]
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

get_public_ip() {
    local public_ip=""
    
    if public_ip=$(curl -s -4 icanhazip.com 2>/dev/null | tr -d '\n' | tr -d ' '); then
        if [[ "${public_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "${public_ip}"
            return 0
        fi
    fi
    
    if public_ip=$(curl -s -4 ipinfo.io/ip 2>/dev/null | tr -d '\n' | tr -d ' '); then
        if [[ "${public_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "${public_ip}"
            return 0
        fi
    fi
    
    if public_ip=$(curl -s -4 ifconfig.me 2>/dev/null | tr -d '\n' | tr -d ' '); then
        if [[ "${public_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "${public_ip}"
            return 0
        fi
    fi
    
    public_ip=$(hostname -I | awk '{print $1}' 2>/dev/null | tr -d ' ')
    if [[ "${public_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "${public_ip}"
        return 0
    fi
    
    echo ""
    return 1
}

download_web_bin() {
    check_download_tool
    info "开始从远程下载Web程序：${WEB_DOWNLOAD_URL}"
    rm -f "${TARGET_WEB}" 2>/dev/null
    if [ "${DOWNLOAD_TOOL}" = "wget" ]; then
        wget -q -O "${TARGET_WEB}" "${WEB_DOWNLOAD_URL}" || { error "wget下载Web程序失败"; return 1; }
    else
        curl -s -L -o "${TARGET_WEB}" "${WEB_DOWNLOAD_URL}" || { error "curl下载Web程序失败"; return 1; }
    fi
    [ -f "${TARGET_WEB}" ] || { error "Web程序下载后不存在"; return 1; }
    chmod +x "${TARGET_WEB}" || { error "设置Web程序执行权限失败"; return 1; }
    info "✅ Web程序下载完成：${TARGET_WEB}"
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

collect_user_params() {
    prompt "配置核心启动参数（回车使用默认值）"
    read -p "请输入hostname（默认：${DEFAULT_HOSTNAME}）：" custom_hostname
    read -p "请输入Web用户名（默认：${DEFAULT_WEB_USER}）：" custom_web_user

    CUSTOM_HOSTNAME=$(echo "${custom_hostname:-"${DEFAULT_HOSTNAME}"}" | tr -d ' ')
    CUSTOM_WEB_USER=$(echo "${custom_web_user:-"${DEFAULT_WEB_USER}"}" | tr -d ' ')

    info "正在自动获取公网IP..."
    PUBLIC_IP=$(get_public_ip)
    if [ -z "${PUBLIC_IP}" ] || ! [[ "${PUBLIC_IP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        error "❌ 公网IP获取失败！请手动设置IP"
        read -p "请输入IP地址：" manual_ip
        manual_ip=$(echo "${manual_ip}" | tr -d ' ')
        if [[ "${manual_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            PUBLIC_IP="${manual_ip}"
            info "使用手动输入IP：${PUBLIC_IP}"
        else
            error "无效IP地址！"
            exit 1
        fi
    else
        info "✅ 公网IP获取成功：${PUBLIC_IP}"
    fi

    info "✅ 参数配置完成"
    info "  - hostname：${CUSTOM_HOSTNAME}"
    info "  - Web用户名：${CUSTOM_WEB_USER}"
    info "  - 绑定IP：${PUBLIC_IP}"
    info "  - 绑定端口：${WG_PORT}"
    info "  - 最终启动命令：${TARGET_CORE} --hostname ${CUSTOM_HOSTNAME} -w udp://${PUBLIC_IP}:${WG_PORT}/${CUSTOM_WEB_USER}"
}

func_clear_log() {
    is_installed || { error "未安装服务"; return 1; }
    
    local log_files=()
    shopt -s nullglob
    log_files=("${INSTALL_DIR}/easytier"*.log)
    shopt -u nullglob
    
    if [ ${#log_files[@]} -eq 0 ]; then
        info "未找到任何 easytier*.log 格式的日志文件，无需清空"
        return 0
    fi
    
    info "找到以下 ${#log_files[@]} 个日志文件："
    for file in "${log_files[@]}"; do
        echo "  - ${file}"
    done
    
    warn "⚠️  确认清空以上所有日志文件？（清空后不可恢复）"
    read -p "请输入 y 确认清空，其他键取消：" confirm
    [[ ! "${confirm}" =~ ^[Yy]$ ]] && { info "已取消清空日志"; return 0; }
    
    local fail_count=0
    local success_files=()
    for file in "${log_files[@]}"; do
        if > "${file}"; then
            success_files+=("${file}")
        else
            error "清空失败：${file}"
            ((fail_count++))
        fi
    done
    
    if [ ${#success_files[@]} -gt 0 ]; then
        info "✅ 成功清空 ${#success_files[@]} 个日志文件："
        for file in "${success_files[@]}"; do
            echo "  - ${file}"
        done
    fi
    
    if [ ${fail_count} -gt 0 ]; then
        error "❌ 有 ${fail_count} 个日志文件清空失败，请检查文件权限"
        return 1
    fi
}

func_install() {
    info "开始安装EasyTier服务..."
    info "📌 安装后默认开启开机自启"
    
    rm -rf "${INSTALL_DIR}" && mkdir -p "${INSTALL_DIR}" && chown -R "${RUN_USER}:${RUN_USER}" "${INSTALL_DIR}" && chmod 750 "${INSTALL_DIR}"
    
    download_web_bin || return 1
    download_core_bin || return 1
    
    collect_user_params || return 1
    
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
ExecStart=/bin/bash -c '${TARGET_WEB} & sleep 2; ${TARGET_CORE} --hostname "${CUSTOM_HOSTNAME}" -w "udp://${PUBLIC_IP}:${WG_PORT}/${CUSTOM_WEB_USER}" >> ${LOG_FILE} 2>&1; wait'
StandardOutput=null
StandardError=null
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
    info "📌 启动顺序执行中：Web程序 → 等待2秒 → Core程序"
    
    sleep 5
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        info "✅ 安装启动成功！"
        info "服务状态：$(get_running_status) | 开机自启：$(get_auto_start_status)"
        info "Core启动命令：${TARGET_CORE} --hostname ${CUSTOM_HOSTNAME} -w udp://${PUBLIC_IP}:${WG_PORT}/${CUSTOM_WEB_USER}"
        systemctl status "${SERVICE_NAME}" --no-pager
    else
        warn "⚠️  服务安装完成但启动失败"
        warn "排查步骤："
        warn "  1. 单独测试Web程序：${TARGET_WEB}"
        warn "  2. 单独测试Core程序：${TARGET_CORE} --hostname ${CUSTOM_HOSTNAME} -w udp://${PUBLIC_IP}:${WG_PORT}/${CUSTOM_WEB_USER}"
        warn "  3. 查看日志：sudo tail -f ${LOG_FILE}"
        warn "  4. 查看Systemd日志：sudo journalctl -u ${SERVICE_NAME} -n 20"
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

func_start() {
    is_installed || { error "未安装"; return 1; }
    validate_log_file && systemctl start "${SERVICE_NAME}" && sleep 3 && {
        systemctl is-active --quiet "${SERVICE_NAME}" && info "✅ 启动成功" || error "启动失败"
    } || error "日志验证失败"
}

func_stop() {
    is_installed || { error "未安装"; return 1; }
    systemctl stop "${SERVICE_NAME}" && sleep 2 && info "✅ 停止成功" || error "停止失败"
}

func_restart() {
    is_installed || { error "未安装"; return 1; }
    systemctl daemon-reload
    validate_log_file && systemctl restart "${SERVICE_NAME}" && sleep 3 && {
        systemctl is-active --quiet "${SERVICE_NAME}" && info "✅ 重启成功" || error "重启失败"
    } || error "日志验证失败"
}

func_toggle_auto_start() {
    is_installed || { error "未安装服务"; return 1; }
    current_status=$(systemctl is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null && echo "enabled" || echo "disabled")
    info "当前开机自启状态：$(get_auto_start_status)"
    
    if [ "${current_status}" = "enabled" ]; then
        prompt "是否关闭开机自启？(y/N)"
        read -p "请输入：" choice
        [[ "${choice}" =~ ^[Yy]$ ]] && {
            systemctl disable "${SERVICE_NAME}" && info "✅ 开机自启已关闭" || error "关闭失败"
        } || info "已取消关闭"
    else
        prompt "是否开启开机自启？(y/N)"
        read -p "请输入：" choice
        [[ "${choice}" =~ ^[Yy]$ ]] && {
            systemctl enable "${SERVICE_NAME}" && info "✅ 开机自启已开启" || error "开启失败"
        } || info "已取消开启"
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
            "🗑️ 清空日志"
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
        0) info "感谢使用，再见！---张亚豪"; exit 0 ;;
        1) is_installed && func_start || func_install ;;
        2) is_installed && func_stop || error "无效序号：未安装服务" ;;
        3) is_installed && func_restart || error "无效序号：未安装服务" ;;
        4) is_installed && func_log || error "无效序号：未安装服务" ;;
        5) is_installed && func_clear_log || error "无效序号：未安装服务" ;;
        6) is_installed && func_toggle_auto_start || error "无效序号：未安装服务" ;;
        7) is_installed && func_uninstall || error "无效序号：未安装服务" ;;
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

main_ui
