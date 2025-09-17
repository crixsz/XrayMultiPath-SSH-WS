#!/bin/bash

# ================================================================
# Xray Multipath SSH-WS Installation Script
# Improved UI/UX Version
# ================================================================

### Global Variables
export ip=$(curl -s ipv4.icanhazip.com || curl -s ifconfig.me)
export scr_dir=$(pwd)

### Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

### UI Helper Functions
print_banner() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}             Xray Multipath SSH-WS Installer                 ${CYAN}║${NC}"
    echo -e "${CYAN}║${WHITE}                   Enhanced Edition                           ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
}

print_step() {
    echo -e "${BLUE}➤${NC} ${WHITE}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} ${WHITE}$1${NC}"
}

print_error() {
    echo -e "${RED}✗${NC} ${WHITE}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} ${WHITE}$1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} ${WHITE}$1${NC}"
}

show_progress() {
    local duration=$1
    local message="$2"
    echo -ne "${CYAN}$message${NC}"
    for ((i=0; i<duration; i++)); do
        echo -n "."
        sleep 1
    done
    echo -e " ${GREEN}Done!${NC}"
}

confirm_action() {
    local message="$1"
    local default="${2:-n}"
    echo
    echo -e "${YELLOW}$message${NC}"
    if [ "$default" = "y" ]; then
        read -p "$(echo -e "${WHITE}Continue? [Y/n]: ${NC}")" response
        response=${response:-y}
    else
        read -p "$(echo -e "${WHITE}Continue? [y/N]: ${NC}")" response
        response=${response:-n}
    fi
    [[ "$response" =~ ^[Yy]$ ]]
}

prerequisites()
{
    print_banner
    print_step "Installing Prerequisites"
    echo
    
    local packages=("curl" "socat" "screen" "net-tools" "htop")
    local total=${#packages[@]}
    local current=0
    
    for pkg in "${packages[@]}"; do
        current=$((current + 1))
        echo -ne "${BLUE}[$current/$total]${NC} Installing $pkg"
        
        if apt install "$pkg" -y > /dev/null 2>&1; then
            echo -e " ${GREEN}✓${NC}"
        else
            echo -e " ${RED}✗${NC}"
            print_error "Failed to install $pkg. Please check your system."
            exit 1
        fi
    done
    
    echo
    print_step "Verifying Installation"
    sleep 1
    
    # Check if all prerequisites are installed
    local failed=0
    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg" > /dev/null 2>&1; then
            print_error "$pkg is not installed correctly"
            failed=1
        else
            print_success "$pkg installed successfully"
        fi
    done
    
    if [ $failed -eq 1 ]; then
        echo
        print_error "Some packages failed to install. Please check your system."
        exit 1
    fi
    
    echo
    print_success "All prerequisites installed successfully!"
    sleep 2
}

setup_ssh_ws(){
    print_banner
    print_step "SSH-WS Installation"
    echo
    
    print_info "Installing Python2.7, Dropbear SSH, and WebSocket services..."
    echo
    
    print_step "Installing Python2.7"
    show_progress 2 "Downloading and installing Python2.7"
    
    if ! apt install python2.7 -y > /dev/null 2>&1; then
        print_error "Failed to install Python2.7. Exiting..."
        exit 1
    fi
    print_success "Python2.7 installed successfully"
    
    echo
    print_step "Installing Dropbear SSH Server"
    show_progress 2 "Setting up Dropbear"
    
    # Set keyboard layout to US before installing dropbear
    echo "keyboard-configuration keyboard-configuration/layoutcode string us" | debconf-set-selections
    echo "keyboard-configuration keyboard-configuration/layout select English (US)" | debconf-set-selections
    
    if ! DEBIAN_FRONTEND=noninteractive apt install dropbear -y > /dev/null 2>&1; then
        print_error "Failed to install Dropbear. Exiting..."
        exit 1
    fi
    print_success "Dropbear installed successfully"
    
    echo
    print_step "Configuring Dropbear"
    sed -i 's/NO_START=1/NO_START=0/' /etc/default/dropbear
    sed -i 's/DROPBEAR_PORT=22/DROPBEAR_PORT=69/' /etc/default/dropbear
    systemctl restart dropbear
    print_success "Dropbear configured to run on port 69"
    
    echo
    print_step "Setting up WebSocket Service"
    mkdir -p /usr/local/bin/websocket
    
    echo -ne "${CYAN}Downloading ws-stunnel${NC}"
    if wget --no-cache --no-check-certificate -O /usr/local/bin/websocket/ws-stunnel https://raw.githubusercontent.com/crixsz/XrayMultiPath-SSH-WS/main/websocket/ws-stunnel > /dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
        chmod +x /usr/local/bin/websocket/ws-stunnel
        print_success "ws-stunnel downloaded and configured"
    else
        print_error "Failed to download ws-stunnel"
        exit 1
    fi
    
    echo
    print_step "Creating WebSocket systemd service"
    cat <<EOF > /etc/systemd/system/ws-stunnel.service
[Unit]
Description=WebSocket Stunnel Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python2.7 /usr/local/bin/websocket/ws-stunnel
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable ws-stunnel > /dev/null 2>&1
    systemctl start ws-stunnel
    
    if systemctl is-active --quiet ws-stunnel; then
        print_success "WebSocket service started successfully"
    else
        print_error "Failed to start WebSocket service"
        exit 1
    fi
    
    echo
    print_step "Creating SSH user account"
    useradd -m -s /bin/bash aku > /dev/null 2>&1
    echo "aku:aku" | chpasswd
    print_success "User 'aku' created with password 'aku'"

    # Remove any existing SSH restrictions for user 'aku' first
    if [ -f /etc/ssh/sshd_config ]; then
        sed -i '/# Restrict user.*aku/,/AllowStreamLocalForwarding no/d' /etc/ssh/sshd_config
        sed -i '/Match User aku/,/AllowStreamLocalForwarding no/d' /etc/ssh/sshd_config
    fi

    # Add SSH restrictions for the user
    cat <<EOF >> /etc/ssh/sshd_config

# Restrict user 'aku'
Match User aku
    ForceCommand /bin/false
    PermitTTY no
    X11Forwarding no
    AllowTcpForwarding yes
    PermitTunnel yes
    AllowAgentForwarding no
    AllowStreamLocalForwarding no
EOF

    # Reload SSH service to apply changes
    systemctl reload sshd > /dev/null 2>&1
    print_success "SSH restrictions applied for user 'aku'"
    
    echo
    print_success "SSH-WS installation completed successfully!"
    sleep 2
}

uninstall_ssh_ws(){
    print_banner
    print_step "SSH-WS Uninstallation"
    echo
    
    if ! confirm_action "This will completely remove SSH-WS components and user 'aku'."; then
        print_info "SSH-WS uninstallation cancelled."
        return 1
    fi
    
    echo
    print_step "Stopping and removing WebSocket service"
    systemctl stop ws-stunnel > /dev/null 2>&1
    systemctl disable ws-stunnel > /dev/null 2>&1
    rm -rf /etc/systemd/system/ws-stunnel.service
    systemctl daemon-reload
    print_success "WebSocket service removed"
    
    print_step "Removing WebSocket files"
    rm -rf /usr/local/bin/websocket/ws-stunnel
    print_success "WebSocket files removed"
    
    print_step "Removing Python2.7"
    apt-get purge python2.7 -y > /dev/null 2>&1
    print_success "Python2.7 removed"
    
    print_step "Removing Dropbear"
    apt-get purge dropbear -y > /dev/null 2>&1
    systemctl restart dropbear > /dev/null 2>&1
    print_success "Dropbear removed"
    
    print_step "Removing user 'aku'"
    userdel -r aku 2>/dev/null || true
    print_success "User 'aku' removed"
    
    print_step "Cleaning SSH configuration"
    if [ -f /etc/ssh/sshd_config ]; then
        sed -i '/AllowUsers.*aku/d' /etc/ssh/sshd_config
        sed -i '/DenyUsers.*aku/d' /etc/ssh/sshd_config
        sed -i '/Match User aku/d' /etc/ssh/sshd_config
        sed -i '/aku/d' /etc/ssh/sshd_config
        systemctl reload sshd || systemctl restart ssh || true > /dev/null 2>&1
        print_success "SSH configuration cleaned"
    fi
    
    echo
    print_success "SSH-WS uninstalled successfully!"
    sleep 2
}
acme_install(){
    print_banner
    print_step "SSL Certificate Generation"
    echo
    
    if [ -f /root/xray.crt ] && [ -f /root/xray.key ]; then
        print_success "SSL certificates already exist!"
        print_info "Skipping certificate generation..."
        sleep 2
        return 0
    fi
    
    print_info "SSL certificates not found. Generating new certificates..."
    echo
    
    # Domain input with validation
    while true; do
        echo -e "${YELLOW}Please enter your domain name:${NC}"
        echo -e "${CYAN}Example: yourdomain.com${NC}"
        read -p "$(echo -e "${WHITE}Domain: ${NC}")" domain
        
        if [[ -z "$domain" ]]; then
            print_error "Domain cannot be empty. Please try again."
            continue
        fi
        
        if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_error "Invalid domain format. Please enter a valid domain."
            continue
        fi
        
        break
    done
    
    echo
    print_step "Setting up Acme.sh certificate manager"
    
    # Remove existing acme.sh if present
    if [ -d /root/.acme.sh ]; then
        print_info "Removing existing Acme.sh installation"
        rm -rf /root/.acme.sh
    fi
    
    echo -ne "${CYAN}Downloading Acme.sh${NC}"
    if wget --no-cache --no-check-certificate -O acme.sh https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh > /dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
    else
        print_error "Failed to download Acme.sh"
        exit 1
    fi
    
    print_step "Installing Acme.sh"
    bash acme.sh --install > /dev/null 2>&1
    rm acme.sh
    print_success "Acme.sh installed successfully"
    
    print_step "Registering Acme.sh account"
    cd "$scr_dir/.acme.sh"
    bash acme.sh --register-account -m mymail@gmail.com > /dev/null 2>&1
    print_success "Account registered"
    
    echo
    print_step "Generating SSL certificate for domain: $domain"
    print_warning "Make sure your domain points to this server's IP: $ip"
    
    if ! confirm_action "DNS records configured correctly?"; then
        print_error "Please configure your DNS records first and try again."
        exit 1
    fi
    
    show_progress 5 "Generating certificate"
    
    if bash acme.sh --issue --standalone -d "$domain" --force > /dev/null 2>&1; then
        print_success "Certificate generated successfully"
    else
        print_error "Certificate generation failed. Please check:"
        echo -e "  ${YELLOW}•${NC} Domain DNS points to this server"
        echo -e "  ${YELLOW}•${NC} Port 80 is open and available"
        echo -e "  ${YELLOW}•${NC} No other web server is running"
        exit 1
    fi
    
    print_step "Installing certificate"
    if bash acme.sh --installcert -d "$domain" --fullchainpath /root/xray.crt --keypath /root/xray.key > /dev/null 2>&1; then
        print_success "Certificate installed successfully"
    else
        print_error "Certificate installation failed"
        exit 1
    fi
    
    # Verify certificate files
    if [ -f /root/xray.crt ] && [ -f /root/xray.key ]; then
        print_success "SSL certificate setup completed!"
        echo
        print_info "Certificate files:"
        echo -e "  ${CYAN}•${NC} Certificate: /root/xray.crt"
        echo -e "  ${CYAN}•${NC} Private Key: /root/xray.key"
        sleep 2
    else
        print_error "Certificate files not found after installation"
        exit 1
    fi
}

setup_nginx(){
    print_banner
    print_step "Nginx Web Server Setup"
    echo
    
    print_step "Installing Nginx"
    show_progress 3 "Downloading and installing Nginx"
    
    if apt-get install nginx -y > /dev/null 2>&1; then
        print_success "Nginx installed successfully"
    else
        print_error "Failed to install Nginx"
        exit 1
    fi
    
    echo
    print_step "Configuring Nginx for Xray"
    
    # Backup existing config
    if [ -f /etc/nginx/nginx.conf ]; then
        cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup 2>/dev/null
        print_info "Existing configuration backed up"
    fi
    
    rm -rf /etc/nginx/nginx.conf
    
    echo -ne "${CYAN}Downloading nginx.conf${NC}"
    if wget --no-cache --no-check-certificate -O /etc/nginx/nginx.conf https://raw.githubusercontent.com/crixsz/XrayMultiPath-SSH-WS/main/Nginx/nginx.conf > /dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
    else
        print_error "Failed to download nginx.conf"
        exit 1
    fi
    
    echo -ne "${CYAN}Downloading xray.conf${NC}"
    if wget --no-cache --no-check-certificate -O /etc/nginx/conf.d/xray.conf https://raw.githubusercontent.com/crixsz/XrayMultiPath-SSH-WS/main/Nginx/xray.conf > /dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
    else
        print_error "Failed to download xray.conf"
        exit 1
    fi
    
    print_step "Testing Nginx configuration"
    if nginx -t > /dev/null 2>&1; then
        print_success "Nginx configuration is valid"
    else
        print_error "Nginx configuration test failed"
        exit 1
    fi
    
    print_step "Starting Nginx service"
    systemctl restart nginx
    
    # Check if nginx is running
    if systemctl is-active --quiet nginx; then
        print_success "Nginx is running successfully"
    else
        print_error "Nginx failed to start"
        echo
        print_info "Checking Nginx status..."
        systemctl status nginx --no-pager
        exit 1
    fi
    
    echo
    print_success "Nginx setup completed!"
    sleep 2
}
setup_cf_warp(){
    print_banner
    print_step "Cloudflare WARP Setup"
    echo
    
    print_step "Installing Docker"
    echo -ne "${CYAN}Downloading Docker installer${NC}"
    
    if wget --no-cache --no-check-certificate https://raw.githubusercontent.com/crixsz/DockerInstall/main/docker-install.sh > /dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
        chmod +x docker-install.sh
        
        print_info "Running Docker installation script..."
        if ./docker-install.sh > /dev/null 2>&1; then
            print_success "Docker installed successfully"
        else
            print_error "Docker installation failed"
            exit 1
        fi
    else
        print_error "Failed to download Docker installer"
        exit 1
    fi
    
    echo
    print_step "Verifying Docker installation"
    sleep 2
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker installation failed or Docker command not found"
        exit 1
    fi
    print_success "Docker is ready"
    
    echo
    print_step "Setting up Cloudflare WARP container"
    
    echo -ne "${CYAN}Pulling WARP container${NC}"
    if docker run --restart=always -d --name=warp --device-cgroup-rule='c 10:200 rwm' -p 1080:1080 -e WARP_SLEEP=2 --cap-add=MKNOD --cap-add=AUDIT_WRITE --cap-add=NET_ADMIN --sysctl=net.ipv6.conf.all.disable_ipv6=0 --sysctl=net.ipv4.conf.all.src_valid_mark=1 -v ./data:/var/lib/cloudflare-warp caomingjun/warp > /dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
        print_success "WARP container started successfully"
    else
        print_error "Failed to start WARP container"
        exit 1
    fi
    
    echo
    print_step "Verifying WARP container status"
    sleep 3
    
    if docker ps | grep -q warp; then
        print_success "WARP container is running"
        echo
        print_info "Container details:"
        docker ps --filter name=warp --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        print_error "WARP container is not running"
        exit 1
    fi
    
    # Clean up installer
    rm -f docker-install.sh
    
    echo
    print_success "Cloudflare WARP setup completed!"
    print_info "WARP SOCKS proxy available at: 127.0.0.1:1080"
    sleep 2
    
    echo
    print_step "Proceeding to Xray installation"
    install_xray
}
install_xray() {
    print_banner
    print_step "Xray Core Installation"
    echo
    
    # Check if Xray is already installed
    if [ -f /usr/local/bin/xray ]; then
        print_warning "Xray Core is already installed!"
        echo
        if confirm_action "Do you want to uninstall the current installation?"; then
            print_info "Uninstalling current Xray Core..."
            uninstall_xray
            return 0
        else
            print_info "Installation cancelled."
            exit 0
        fi
    fi
    
    print_step "Installing Xray Core v1.5.0"
    show_progress 3 "Downloading and installing Xray Core"
    
    if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --version 1.5.0 -u root > /dev/null 2>&1; then
        print_success "Xray Core v1.5.0 installed successfully"
    else
        print_error "Failed to install Xray Core"
        exit 1
    fi
    
    echo
    print_step "Downloading Xray configuration files"
    
    local configs=("config.json" "none.json" "direct.json")
    local base_url="https://raw.githubusercontent.com/crixsz/XrayMultiPath-SSH-WS/main/Xray"
    
    for config in "${configs[@]}"; do
        echo -ne "${CYAN}Downloading $config${NC}"
        if wget --no-cache --no-check-certificate "$base_url/$config" -O "/usr/local/etc/xray/$config" > /dev/null 2>&1; then
            echo -e " ${GREEN}✓${NC}"
        else
            echo -e " ${RED}✗${NC}"
            print_error "Failed to download $config"
            exit 1
        fi
    done
    
    print_success "All configuration files downloaded"
    
    echo
    print_step "Setting up Xray services"
    
    # Stop any running Xray instances
    systemctl stop xray > /dev/null 2>&1
    
    # Verify no Xray processes are running
    if pgrep xray >/dev/null; then
        print_error "Xray processes are still running. Please stop them manually."
        exit 1
    fi
    
    # Setup systemd service
    rm -rf /etc/systemd/system/xray@.service
    echo -ne "${CYAN}Downloading Xray service file${NC}"
    
    if wget --no-cache --no-check-certificate -O /etc/systemd/system/xray@.service https://raw.githubusercontent.com/crixsz/XrayMultiPath-SSH-WS/main/Xray/xray@.service > /dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
    else
        print_error "Failed to download Xray service file"
        exit 1
    fi
    
    print_step "Starting Xray services"
    systemctl daemon-reload
    
    local services=("xray@none" "xray" "xray@direct")
    for service in "${services[@]}"; do
        echo -ne "${CYAN}Starting $service${NC}"
        if systemctl start "$service" > /dev/null 2>&1 && systemctl enable "$service" > /dev/null 2>&1; then
            echo -e " ${GREEN}✓${NC}"
        else
            echo -e " ${RED}✗${NC}"
            print_error "Failed to start $service"
        fi
    done
    
    echo
    print_step "Verifying Xray services"
    sleep 2
    
    local all_running=true
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            print_success "$service is running"
        else
            print_error "$service is not running"
            all_running=false
        fi
    done
    
    if [ "$all_running" = false ]; then
        print_error "Some Xray services failed to start"
        exit 1
    fi
    
    echo
    print_success "Xray Core installation completed successfully!"
    
    # Display connection information
    display_connection_info
}

display_connection_info() {
    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}                    CONNECTION INFORMATION                    ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${GREEN}Server IP:${NC} ${WHITE}$ip${NC}"
    echo -e "${GREEN}Installation Status:${NC} ${WHITE}Complete${NC}"
    echo
    echo -e "${YELLOW}┌─ VLESS Connections ─────────────────────────────────────────┐${NC}"
    echo -e "${GREEN}Port 80 (CF Warp):${NC}"
    echo -e "${WHITE}vless://5d871382-b2ec-4d82-b5b8-712498a348e5@${ip}:80?security=&type=ws&path=/vless-ws&host=${ip}&encryption=none${NC}"
    echo
    echo -e "${GREEN}Port 443 (CF Warp):${NC}"
    echo -e "${WHITE}vless://5d871382-b2ec-4d82-b5b8-712498a348e5@${ip}:443?security=tls&sni=bug.com&allowInsecure=1&type=ws&path=/vless-ws&encryption=none${NC}"
    echo
    echo -e "${GREEN}Port 80 (Direct):${NC}"
    echo -e "${WHITE}vless://5d871382-b2ec-4d82-b5b8-712498a348e5@${ip}:80?security=&type=ws&path=/direct-vless&host=${ip}&encryption=none${NC}"
    echo -e "${YELLOW}└─────────────────────────────────────────────────────────────┘${NC}"
    echo
    echo -e "${YELLOW}┌─ TROJAN Connections ────────────────────────────────────────┐${NC}"
    echo -e "${GREEN}Port 80 (CF Warp):${NC}"
    echo -e "${WHITE}trojan://trojanaku@${ip}:80?security=&type=ws&path=/trojan-ws&host=${ip}${NC}"
    echo
    echo -e "${GREEN}Port 443 (CF Warp):${NC}"
    echo -e "${WHITE}trojan://trojanaku@${ip}:443?security=tls&sni=bug.com&allowInsecure=1&type=ws&path=/trojan-ws&host=${ip}${NC}"
    echo
    echo -e "${GREEN}Port 80 (Direct):${NC}"
    echo -e "${WHITE}trojan://trojanaku@${ip}:80?security=&type=ws&path=/direct&host=${ip}${NC}"
    echo -e "${YELLOW}└─────────────────────────────────────────────────────────────┘${NC}"
    echo
    echo -e "${CYAN}💡 Tips:${NC}"
    echo -e "  ${YELLOW}•${NC} CF Warp connections use Cloudflare's network"
    echo -e "  ${YELLOW}•${NC} Direct connections bypass Cloudflare"
    echo -e "  ${YELLOW}•${NC} SSH-WS user: ${WHITE}aku${NC} | password: ${WHITE}aku${NC}"
    echo -e "  ${YELLOW}•${NC} Dropbear SSH port: ${WHITE}69${NC}"
    echo
    echo -e "${GREEN}✨ Installation completed successfully! ✨${NC}"
    echo
}

uninstall_xray(){
    print_banner
    print_step "Complete System Uninstallation"
    echo
    
    if ! confirm_action "This will remove ALL components (Xray, Nginx, Docker, SSH-WS, etc.)"; then
        print_info "Uninstallation cancelled."
        return 1
    fi
    
    echo
    print_step "Stopping Xray services"
    local services=("xray" "xray@none" "xray@direct")
    for service in "${services[@]}"; do
        echo -ne "${CYAN}Stopping $service${NC}"
        systemctl stop "$service" > /dev/null 2>&1
        systemctl disable "$service" > /dev/null 2>&1
        echo -e " ${GREEN}✓${NC}"
    done
    
    print_step "Removing Xray Core"
    if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge > /dev/null 2>&1; then
        print_success "Xray Core removed"
    else
        print_warning "Xray Core removal may have failed"
    fi
    
    print_step "Removing Nginx"
    apt-get purge nginx nginx-common -y > /dev/null 2>&1
    print_success "Nginx removed"
    
    # SSH-WS Uninstallation (without confirmation)
    print_step "Stopping and removing WebSocket service"
    systemctl stop ws-stunnel > /dev/null 2>&1
    systemctl disable ws-stunnel > /dev/null 2>&1
    rm -rf /etc/systemd/system/ws-stunnel.service
    systemctl daemon-reload > /dev/null 2>&1
    print_success "WebSocket service removed"
    
    print_step "Removing WebSocket files"
    rm -rf /usr/local/bin/websocket/ws-stunnel
    print_success "WebSocket files removed"
    
    print_step "Removing Python2.7"
    apt-get purge python2.7 -y > /dev/null 2>&1
    print_success "Python2.7 removed"
    
    print_step "Removing Dropbear"
    apt-get purge dropbear -y > /dev/null 2>&1
    print_success "Dropbear removed"
    
    print_step "Removing user 'aku'"
    userdel -r aku 2>/dev/null || true
    print_success "User 'aku' removed"
    
    print_step "Cleaning SSH configuration"
    if [ -f /etc/ssh/sshd_config ]; then
        # Remove all SSH restrictions related to user 'aku' using range deletion
        sed -i '/# Restrict user.*aku/,/AllowStreamLocalForwarding no/d' /etc/ssh/sshd_config
        sed -i '/Match User aku/,/AllowStreamLocalForwarding no/d' /etc/ssh/sshd_config
        # Remove any standalone lines that might remain
        sed -i '/AllowUsers.*aku/d' /etc/ssh/sshd_config
        sed -i '/DenyUsers.*aku/d' /etc/ssh/sshd_config
        sed -i '/Match User aku/d' /etc/ssh/sshd_config
        # Clean up any remaining configuration blocks
        sed -i '/ForceCommand \/bin\/false/d' /etc/ssh/sshd_config
        sed -i '/PermitTTY no/d' /etc/ssh/sshd_config
        sed -i '/AllowTcpForwarding yes/d' /etc/ssh/sshd_config
        sed -i '/PermitTunnel yes/d' /etc/ssh/sshd_config
        sed -i '/AllowAgentForwarding no/d' /etc/ssh/sshd_config
        sed -i '/AllowStreamLocalForwarding no/d' /etc/ssh/sshd_config
        systemctl reload sshd || systemctl restart ssh || true > /dev/null 2>&1
        print_success "SSH configuration cleaned"
    fi
    
    print_step "Cleaning Docker containers and images"
    if command -v docker &> /dev/null; then
        docker rm -f $(docker ps -a -q) > /dev/null 2>&1 || true
        docker rmi -f $(docker images -a -q) > /dev/null 2>&1 || true
        docker system prune -a -f > /dev/null 2>&1 || true
        print_success "Docker cleaned"
    fi
    
    print_step "Cleaning systemd"
    systemctl reset-failed > /dev/null 2>&1
    systemctl daemon-reload > /dev/null 2>&1
    print_success "Systemd cleaned"
    
    print_step "Removing configuration files"
    local dirs_to_remove=(
        "/usr/local/etc/xray"
        "/etc/systemd/system/xray.service"
        "/etc/systemd/system/xray@.service"
        "/etc/systemd/system/xray@.service.d"
        "/etc/systemd/system/xray.service.d"
        "/root/docker-install.sh"
        "/usr/local/bin/xray"
    )
    
    for dir in "${dirs_to_remove[@]}"; do
        if [ -e "$dir" ]; then
            rm -rf "$dir"
            echo -e "${CYAN}Removed:${NC} $dir"
        fi
    done
    
    echo
    print_success "Complete uninstallation finished!"
    print_info "System has been restored to clean state"
    sleep 2
}
# Main Menu Function
show_main_menu() {
    print_banner
    echo -e "${WHITE}Welcome to the Xray Multipath Installation System${NC}"
    echo -e "${CYAN}Your Server IP: ${WHITE}$ip${NC}"
    echo
    echo -e "${YELLOW}┌─ Available Options ──────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│${NC}                                                              ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${GREEN}1)${NC} ${WHITE}Full Installation${NC}                                     ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}     ${CYAN}→${NC} Xray Core + Nginx + CF Warp + SSH-WS + SSL        ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}                                                              ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${RED}2)${NC} ${WHITE}Complete Uninstallation${NC}                              ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}     ${CYAN}→${NC} Remove all components and configurations           ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}                                                              ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  ${BLUE}3)${NC} ${WHITE}Exit${NC}                                                 ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}     ${CYAN}→${NC} Exit the installer                                 ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}                                                              ${YELLOW}│${NC}"
    echo -e "${YELLOW}└──────────────────────────────────────────────────────────────┘${NC}"
    echo
    echo -e "${CYAN}ℹ${NC} ${WHITE}Choose an option and press Enter${NC}"
    echo
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        echo -e "${YELLOW}Please run: ${WHITE}sudo bash $0${NC}"
        exit 1
    fi
}

# System information display
show_system_info() {
    echo -e "${CYAN}System Information:${NC}"
    echo -e "  ${YELLOW}•${NC} OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")"
    echo -e "  ${YELLOW}•${NC} Kernel: $(uname -r)"
    echo -e "  ${YELLOW}•${NC} Architecture: $(uname -m)"
    echo -e "  ${YELLOW}•${NC} Server IP: ${WHITE}$ip${NC}"
    echo
}

## Main execution
main() {
    # Check if running as root
    check_root
    
    while true; do
        show_main_menu
        read -p "$(echo -e "${WHITE}Select option [1-3]: ${NC}")" option
        
        case $option in
            1)
                print_info "Starting full installation process..."
                show_system_info
                
                if confirm_action "Proceed with full installation?"; then
                    prerequisites
                    setup_ssh_ws
                    acme_install
                    setup_nginx
                    setup_cf_warp
                    break
                else
                    print_info "Installation cancelled by user."
                fi
                ;;
            2)
                print_info "Starting complete uninstallation..."
                uninstall_xray
                break
                ;;
            3)
                print_banner
                echo -e "${GREEN}Thank you for using Xray Multipath Installer!${NC}"
                echo -e "${CYAN}Visit: ${WHITE}https://github.com/crixsz/XrayMultiPath-SSH-WS${NC}"
                echo
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 1, 2, or 3."
                sleep 2
                ;;
        esac
    done
}

# Start the script
main "$@"