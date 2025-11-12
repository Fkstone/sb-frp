#!/bin/bash

# sing-box & frpc 完全卸载脚本
# 使用方法: sudo bash uninstall_singbox_frpc.sh

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

echo -e "${RED}================================${NC}"
echo -e "${RED}sing-box & frpc 卸载脚本${NC}"
echo -e "${RED}================================${NC}"
echo ""
echo -e "${YELLOW}此脚本将完全卸载以下内容:${NC}"
echo "  - sing-box 程序和服务"
echo "  - frpc 程序和服务"
echo "  - 所有配置文件"
echo "  - 所有证书文件"
echo ""
echo -e "${RED}警告: 此操作不可恢复!${NC}"
read -p "确定要继续吗? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${GREEN}取消卸载${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}开始卸载...${NC}"
echo ""

# 卸载 sing-box
if systemctl list-unit-files | grep -q "sing-box.service"; then
    echo -e "${YELLOW}正在卸载 sing-box...${NC}"
    
    # 停止并禁用服务
    if systemctl is-active --quiet sing-box; then
        echo "停止 sing-box 服务..."
        systemctl stop sing-box
    fi
    
    if systemctl is-enabled --quiet sing-box 2>/dev/null; then
        echo "禁用 sing-box 服务..."
        systemctl disable sing-box
    fi
    
    # 删除 systemd 服务文件
    if [ -f /etc/systemd/system/sing-box.service ]; then
        echo "删除 sing-box 服务文件..."
        rm -f /etc/systemd/system/sing-box.service
    fi
    
    systemctl daemon-reload
    
    echo -e "${GREEN}✓ sing-box 服务已停止并删除${NC}"
fi

# 删除 sing-box 配置和证书
if [ -d /etc/sing-box ]; then
    echo "删除 sing-box 配置目录..."
    rm -rf /etc/sing-box
    echo -e "${GREEN}✓ sing-box 配置已删除${NC}"
fi

# 卸载 sing-box 软件包
if dpkg -l | grep -q sing-box; then
    echo "卸载 sing-box 软件包..."
    apt-get remove --purge -y sing-box 2>/dev/null || true
    echo -e "${GREEN}✓ sing-box 软件包已卸载${NC}"
fi

# 删除 sing-box 软件源
if [ -f /etc/apt/sources.list.d/sagernet.sources ]; then
    echo "删除 sing-box 软件源..."
    rm -f /etc/apt/sources.list.d/sagernet.sources
    echo -e "${GREEN}✓ sing-box 软件源已删除${NC}"
fi

# 删除 sing-box GPG 密钥
if [ -f /etc/apt/keyrings/sagernet.asc ]; then
    echo "删除 sing-box GPG 密钥..."
    rm -f /etc/apt/keyrings/sagernet.asc
    echo -e "${GREEN}✓ sing-box GPG 密钥已删除${NC}"
fi

echo ""

# 卸载 frpc
if systemctl list-unit-files | grep -q "frpc.service"; then
    echo -e "${YELLOW}正在卸载 frpc...${NC}"
    
    # 停止并禁用服务
    if systemctl is-active --quiet frpc; then
        echo "停止 frpc 服务..."
        systemctl stop frpc
    fi
    
    if systemctl is-enabled --quiet frpc 2>/dev/null; then
        echo "禁用 frpc 服务..."
        systemctl disable frpc
    fi
    
    # 删除 systemd 服务文件
    if [ -f /etc/systemd/system/frpc.service ]; then
        echo "删除 frpc 服务文件..."
        rm -f /etc/systemd/system/frpc.service
    fi
    
    systemctl daemon-reload
    
    echo -e "${GREEN}✓ frpc 服务已停止并删除${NC}"
fi

# 删除 frpc 程序
if [ -f /usr/local/bin/frpc ]; then
    echo "删除 frpc 程序文件..."
    rm -f /usr/local/bin/frpc
    echo -e "${GREEN}✓ frpc 程序已删除${NC}"
fi

# 删除 frpc 配置
if [ -d /etc/frpc ]; then
    echo "删除 frpc 配置目录..."
    rm -rf /etc/frpc
    echo -e "${GREEN}✓ frpc 配置已删除${NC}"
fi

echo ""

# 清理 APT 缓存
echo -e "${YELLOW}清理系统缓存...${NC}"
apt-get autoremove -y 2>/dev/null || true
apt-get autoclean -y 2>/dev/null || true
echo -e "${GREEN}✓ 系统缓存已清理${NC}"

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}卸载完成!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo -e "${YELLOW}已删除的内容:${NC}"
echo "  ✓ sing-box 服务"
echo "  ✓ sing-box 软件包"
echo "  ✓ sing-box 配置文件 (/etc/sing-box)"
echo "  ✓ sing-box 证书文件"
echo "  ✓ sing-box 软件源"
echo "  ✓ frpc 服务"
echo "  ✓ frpc 程序 (/usr/local/bin/frpc)"
echo "  ✓ frpc 配置文件 (/etc/frpc)"
echo ""
echo -e "${GREEN}所有组件已成功卸载!${NC}"
echo ""
