#!/bin/bash

# sing-box TUIC 自动安装配置脚本
# 使用方法: sudo bash install_singbox_tuic.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用 sudo 运行此脚本${NC}"
    exit 1
fi

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}sing-box TUIC 安装配置脚本${NC}"
echo -e "${GREEN}================================${NC}"
echo ""

# 检测系统环境
echo -e "${YELLOW}正在检测系统环境...${NC}"

# 检测操作系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
    echo -e "系统: ${GREEN}${PRETTY_NAME}${NC}"
else
    echo -e "${RED}错误: 无法检测操作系统${NC}"
    exit 1
fi

# 检查必需的命令
REQUIRED_COMMANDS="curl apt-get openssl"
MISSING_COMMANDS=""

for cmd in $REQUIRED_COMMANDS; do
    if ! command -v $cmd &> /dev/null; then
        MISSING_COMMANDS="$MISSING_COMMANDS $cmd"
    fi
done

# 安装缺失的依赖
if [ ! -z "$MISSING_COMMANDS" ]; then
    echo -e "${YELLOW}检测到缺失的依赖:${MISSING_COMMANDS}${NC}"
    echo -e "${YELLOW}正在安装依赖包...${NC}"

    apt-get update -qq

    if [[ $MISSING_COMMANDS == *"curl"* ]]; then
        apt-get install -y curl
    fi

    if [[ $MISSING_COMMANDS == *"openssl"* ]]; then
        apt-get install -y openssl
    fi

    echo -e "${GREEN}✓ 依赖安装完成${NC}"
else
    echo -e "${GREEN}✓ 系统环境检测通过${NC}"
fi

echo ""

# 询问是否安装 frpc
echo -e "${YELLOW}是否需要安装 frpc 进行内网穿透? (y/n)${NC}"
read -p "请选择: " INSTALL_FRPC
INSTALL_FRPC=${INSTALL_FRPC:-n}

# 获取用户输入
read -p "请输入监听端口 (默认 25100): " LISTEN_PORT
LISTEN_PORT=${LISTEN_PORT:-25100}

read -p "请输入连接密码: " PASSWORD
while [ -z "$PASSWORD" ]; do
    echo -e "${RED}密码不能为空!${NC}"
    read -p "请输入连接密码: " PASSWORD
done

# 如果需要安装 frpc，获取 frpc 配置信息
if [ "$INSTALL_FRPC" = "y" ] || [ "$INSTALL_FRPC" = "Y" ]; then
    echo ""
    echo -e "${YELLOW}配置 frpc 内网穿透参数...${NC}"

    read -p "请输入 frps 服务器地址: " FRPS_SERVER
    while [ -z "$FRPS_SERVER" ]; do
        echo -e "${RED}服务器地址不能为空!${NC}"
        read -p "请输入 frps 服务器地址: " FRPS_SERVER
    done

    read -p "请输入 frps 服务器端口 (默认 7000): " FRPS_PORT
    FRPS_PORT=${FRPS_PORT:-7000}

    read -p "请输入 frps 认证密码: " FRPS_TOKEN
    while [ -z "$FRPS_TOKEN" ]; do
        echo -e "${RED}认证密码不能为空!${NC}"
        read -p "请输入 frps 认证密码: " FRPS_TOKEN
    done

    echo ""
    echo -e "${YELLOW}配置 TCP 穿透 (SSH)...${NC}"
    read -p "请输入 SSH 本地端口 (默认 22): " TCP_LOCAL_PORT
    TCP_LOCAL_PORT=${TCP_LOCAL_PORT:-22}

    read -p "请输入 SSH 远程端口: " TCP_REMOTE_PORT
    while [ -z "$TCP_REMOTE_PORT" ]; do
        echo -e "${RED}远程端口不能为空!${NC}"
        read -p "请输入 SSH 远程端口: " TCP_REMOTE_PORT
    done

    echo ""
    echo -e "${YELLOW}配置 UDP 穿透 (TUIC)...${NC}"
    echo -e "${GREEN}UDP 本地端口将使用 sing-box 监听端口: ${LISTEN_PORT}${NC}"
    UDP_LOCAL_PORT=$LISTEN_PORT

    read -p "请输入 UDP 远程端口 (默认 ${LISTEN_PORT}): " UDP_REMOTE_PORT
    UDP_REMOTE_PORT=${UDP_REMOTE_PORT:-$LISTEN_PORT}
fi

# 获取节点名称
echo ""
read -p "请输入节点名称 (默认 zhishixuebao): " NODE_NAME
NODE_NAME=${NODE_NAME:-zhishixuebao}

CERT_DAYS=3650

echo ""
echo -e "${YELLOW}正在安装 sing-box...${NC}"

# 添加 sing-box 仓库并安装
echo "添加 GPG 密钥..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
chmod a+r /etc/apt/keyrings/sagernet.asc

echo "添加软件源..."
echo 'Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc' | tee /etc/apt/sources.list.d/sagernet.sources > /dev/null

echo "更新软件源..."
apt-get update

echo "安装 sing-box..."
apt-get install -y sing-box

echo -e "${GREEN}✓ sing-box 安装完成${NC}"
echo ""

# 生成 UUID
echo -e "${YELLOW}正在生成 UUID...${NC}"
UUID=$(sing-box generate uuid)
echo -e "${GREEN}✓ UUID 生成完成: ${UUID}${NC}"
echo ""

# 生成自签名证书
echo -e "${YELLOW}正在生成自签名证书...${NC}"
CERT_DIR="/etc/sing-box"
mkdir -p "$CERT_DIR"

# 获取服务器 IPv4 地址
SERVER_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || curl -4 -s ipinfo.io/ip)
if [ -z "$SERVER_IP" ]; then
    echo -e "${YELLOW}警告: 无法自动获取服务器 IPv4 地址，使用 127.0.0.1${NC}"
    SERVER_IP="127.0.0.1"
fi

# 生成证书
openssl req -x509 -nodes -newkey rsa:4096 \
    -keyout "$CERT_DIR/key.pem" \
    -out "$CERT_DIR/cert.pem" \
    -days "$CERT_DAYS" \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=Department/CN=${SERVER_IP}" \
    2>/dev/null

chmod 600 "$CERT_DIR/key.pem"
chmod 644 "$CERT_DIR/cert.pem"

echo -e "${GREEN}✓ 证书生成完成${NC}"
echo ""

# 生成配置文件
echo -e "${YELLOW}正在生成配置文件...${NC}"
cat > "$CERT_DIR/config.json" <<EOF
{
    "dns": {
        "strategy": "prefer_ipv6"
    },
    "inbounds": [
        {
            "type": "tuic",
            "listen": "::",
            "listen_port": ${LISTEN_PORT},
            "users": [
                {
                    "uuid": "${UUID}",
                    "password": "${PASSWORD}"
                }
            ],
            "congestion_control": "bbr",
            "tls": {
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "${CERT_DIR}/cert.pem",
                "key_path": "${CERT_DIR}/key.pem"
            }
        }
    ],
    "outbounds": [
        {
            "type": "direct"
        }
    ]
}
EOF

echo -e "${GREEN}✓ 配置文件生成完成${NC}"
echo ""

# 配置 systemd 服务
echo -e "${YELLOW}正在配置 systemd 服务...${NC}"
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStart=/usr/bin/sing-box run -c ${CERT_DIR}/config.json
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sing-box
systemctl start sing-box

echo -e "${GREEN}✓ sing-box 服务已启动${NC}"
echo ""

# 安装和配置 frpc
if [ "$INSTALL_FRPC" = "y" ] || [ "$INSTALL_FRPC" = "Y" ]; then
    echo -e "${YELLOW}正在安装 frpc...${NC}"

    # 检查下载工具
    if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}安装 wget...${NC}"
        apt-get install -y wget
    fi

    # 检测系统架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            FRPC_ARCH="amd64"
            ;;
        aarch64|arm64)
            FRPC_ARCH="arm64"
            ;;
        armv7l)
            FRPC_ARCH="arm"
            ;;
        *)
            echo -e "${RED}错误: 不支持的系统架构 ${ARCH}${NC}"
            exit 1
            ;;
    esac

    # 获取最新版本
    FRPC_VERSION=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep tag_name | cut -d '"' -f 4)
    if [ -z "$FRPC_VERSION" ]; then
        echo -e "${YELLOW}无法获取最新版本，使用默认版本 v0.61.1${NC}"
        FRPC_VERSION="v0.61.1"
    fi

    # 下载 frpc
    FRPC_FILE="frp_${FRPC_VERSION#v}_linux_${FRPC_ARCH}"
    DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/${FRPC_VERSION}/${FRPC_FILE}.tar.gz"

    echo "下载 frpc ${FRPC_VERSION}..."
    cd /tmp
    wget -q --show-progress "$DOWNLOAD_URL" -O frpc.tar.gz || curl -L "$DOWNLOAD_URL" -o frpc.tar.gz

    # 解压并安装
    tar -xzf frpc.tar.gz
    cp ${FRPC_FILE}/frpc /usr/local/bin/
    chmod +x /usr/local/bin/frpc

    # 清理临时文件
    rm -rf frpc.tar.gz ${FRPC_FILE}

    echo -e "${GREEN}✓ frpc 安装完成${NC}"

    # 创建配置目录
    FRPC_DIR="/etc/frpc"
    mkdir -p "$FRPC_DIR"

    # 生成随机标识符
    RANDOM_ID=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)

    # 生成 frpc 配置文件
    echo -e "${YELLOW}正在生成 frpc 配置文件...${NC}"
    cat > "$FRPC_DIR/frpc.toml" <<EOF
serverAddr = "${FRPS_SERVER}"
serverPort = ${FRPS_PORT}
auth.method = "token"
auth.token = "${FRPS_TOKEN}"

[[proxies]]
name = "tcp_ssh_${RANDOM_ID}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${TCP_LOCAL_PORT}
remotePort = ${TCP_REMOTE_PORT}

[[proxies]]
name = "udp_tuic_${RANDOM_ID}"
type = "udp"
localIP = "127.0.0.1"
localPort = ${UDP_LOCAL_PORT}
remotePort = ${UDP_REMOTE_PORT}
EOF

    echo -e "${GREEN}✓ frpc 配置文件生成完成${NC}"

    # 配置 frpc systemd 服务
    echo -e "${YELLOW}正在配置 frpc 服务...${NC}"
    cat > /etc/systemd/system/frpc.service <<EOF
[Unit]
Description=frpc service
After=network.target syslog.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frpc -c ${FRPC_DIR}/frpc.toml
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable frpc
    systemctl start frpc

    echo -e "${GREEN}✓ frpc 服务已启动${NC}"
    echo ""
fi

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}安装配置完成!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo -e "${YELLOW}sing-box 连接信息:${NC}"
echo -e "服务器地址: ${GREEN}${SERVER_IP}${NC}"
echo -e "端口: ${GREEN}${LISTEN_PORT}${NC}"
echo -e "UUID: ${GREEN}${UUID}${NC}"
echo -e "密码: ${GREEN}${PASSWORD}${NC}"
echo -e "拥塞控制: ${GREEN}bbr${NC}"
echo -e "ALPN: ${GREEN}h3${NC}"
echo ""

if [ "$INSTALL_FRPC" = "y" ] || [ "$INSTALL_FRPC" = "Y" ]; then
    echo -e "${YELLOW}frpc 内网穿透信息:${NC}"
    echo -e "frps 服务器: ${GREEN}${FRPS_SERVER}:${FRPS_PORT}${NC}"
    echo -e "SSH 穿透: ${GREEN}${FRPS_SERVER}:${TCP_REMOTE_PORT}${NC} -> ${GREEN}127.0.0.1:${TCP_LOCAL_PORT}${NC}"
    echo -e "TUIC 穿透: ${GREEN}${FRPS_SERVER}:${UDP_REMOTE_PORT}${NC} -> ${GREEN}127.0.0.1:${UDP_LOCAL_PORT}${NC}"
    echo ""
    echo -e "${GREEN}客户端连接地址应使用: ${FRPS_SERVER}:${UDP_REMOTE_PORT}${NC}"
    echo ""
fi

# 生成 TUIC 链接
if [ "$INSTALL_FRPC" = "y" ] || [ "$INSTALL_FRPC" = "Y" ]; then
    # 使用 frpc 穿透后的地址
    TUIC_SERVER="${FRPS_SERVER}"
    TUIC_PORT="${UDP_REMOTE_PORT}"
else
    # 使用本机地址
    TUIC_SERVER="${SERVER_IP}"
    TUIC_PORT="${LISTEN_PORT}"
fi

# URL 编码节点名称
NODE_NAME_ENCODED=$(echo -n "$NODE_NAME" | od -An -tx1 | tr ' ' % | tr -d '\n')

TUIC_LINK="tuic://${UUID}:${PASSWORD}@${TUIC_SERVER}:${TUIC_PORT}?congestion_control=bbr&alpn=h3&udp_relay_mode=native&allow_insecure=1&disable_sni=1#${NODE_NAME_ENCODED}"

echo -e "${YELLOW}TUIC 分享链接:${NC}"
echo -e "${GREEN}${TUIC_LINK}${NC}"
echo ""
echo -e "${YELLOW}导入说明:${NC}"
echo "  1. 复制上方完整链接"
echo "  2. 在 v2rayN/v2rayNG/Shadowrocket 等客户端中导入"
echo "  3. 由于使用自签名证书，连接配置中需要:"
echo "     - allow_insecure=1 (允许不安全证书)"
echo "     - disable_sni=1 (禁用 SNI)"
echo ""

echo -e "${YELLOW}配置文件位置:${NC}"
echo -e "sing-box 配置: ${GREEN}${CERT_DIR}/config.json${NC}"
echo -e "证书文件: ${GREEN}${CERT_DIR}/cert.pem${NC}"
echo -e "密钥文件: ${GREEN}${CERT_DIR}/key.pem${NC}"

if [ "$INSTALL_FRPC" = "y" ] || [ "$INSTALL_FRPC" = "Y" ]; then
    echo -e "frpc 配置: ${GREEN}${FRPC_DIR}/frpc.toml${NC}"
fi

echo ""
echo -e "${YELLOW}管理命令:${NC}"
echo -e "sing-box 启动: ${GREEN}systemctl start sing-box${NC}"
echo -e "sing-box 停止: ${GREEN}systemctl stop sing-box${NC}"
echo -e "sing-box 重启: ${GREEN}systemctl restart sing-box${NC}"
echo -e "sing-box 状态: ${GREEN}systemctl status sing-box${NC}"
echo -e "sing-box 日志: ${GREEN}journalctl -u sing-box -f${NC}"

if [ "$INSTALL_FRPC" = "y" ] || [ "$INSTALL_FRPC" = "Y" ]; then
    echo ""
    echo -e "frpc 启动: ${GREEN}systemctl start frpc${NC}"
    echo -e "frpc 停止: ${GREEN}systemctl stop frpc${NC}"
    echo -e "frpc 重启: ${GREEN}systemctl restart frpc${NC}"
    echo -e "frpc 状态: ${GREEN}systemctl status frpc${NC}"
    echo -e "frpc 日志: ${GREEN}journalctl -u frpc -f${NC}"
fi

echo ""
echo -e "${RED}注意事项:${NC}"
echo -e "1. 这是自签名证书，客户端需要允许不安全的证书或跳过证书验证"

if [ "$INSTALL_FRPC" = "y" ] || [ "$INSTALL_FRPC" = "Y" ]; then
    echo -e "2. 使用内网穿透时，客户端应连接到: ${GREEN}${FRPS_SERVER}:${UDP_REMOTE_PORT}${NC}"
    echo -e "3. 请确保 frps 服务器已正确配置并运行"
    echo -e "4. SSH 可通过 ${GREEN}ssh -p ${TCP_REMOTE_PORT} user@${FRPS_SERVER}${NC} 连接"
else
    echo -e "2. 请确保服务器防火墙已开放 UDP 端口 ${LISTEN_PORT}"
    echo -e "3. 如使用云服务器，请在安全组中开放该端口"
fi

echo ""
