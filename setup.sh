### Functions
export ip=$(curl -s ipv4.icanhazip.com || curl -s ifconfig.me)
export scr_dir=$(pwd)

prequisites()
{
  clear
  apt install curl -y
  apt install socat -y
  apt install screen -y
  apt install net-tools -y
  apt install htop -y

  # Check if all prerequisites are installed
  for pkg in curl socat screen net-tools htop; do
    if ! dpkg -l | grep -q "^ii  $pkg"; then
      echo "Error: $pkg is not installed correctly. Please check your system."
      exit 1
    fi
  done
  echo "All prerequisites are installed successfully."
}

setup_ssh_ws(){
  clear
  echo "[SSH-WS Installation Script]"
  echo -e "Installing Python2.7..."
  apt install python2.7 -y
  if [ $? -ne 0 ]; then
    echo "Error: Failed to install Python2.7. Exiting..."
    exit 1
  fi
  sleep 3
  echo -e "Installing Dropbear..."
  apt install dropbear -y
  if [ $? -ne 0 ]; then
    echo "Error: Failed to install Dropbear. Exiting..."
    exit 1
  fi
  sleep 3
  echo -e "Configuring Dropbear..."
  sed -i 's/NO_START=1/NO_START=0/' /etc/default/dropbear
  sed -i 's/DROPBEAR_PORT=22/DROPBEAR_PORT=69/' /etc/default/dropbear
  systemctl restart dropbear
  echo -e "Dropbear configured successfully !!"
  sleep 2
  clear
  echo -e "Configuring SSH-WS..."
  mkdir -p /usr/local/bin/websocket
  wget --no-cache --no-check-certificate -O /usr/local/bin/websocket/ws-stunnel https://raw.githubusercontent.com/crixsz/XrayMultiPath-SSH-WS/main/websocket/ws-stunnel
  chmod +x /usr/local/bin/websocket/ws-stunnel
  sleep 2
  echo -e "Creating systemd service for ws-stunnel..."
  cat <<EOF > /etc/systemd/system/ws-stunnel.service
[Unit]
Description=WebSocket Stunnel Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python /usr/local/bin/websocket/ws-stunnel
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable ws-stunnel
  systemctl start ws-stunnel
  echo -e "ws-stunnel service created and started successfully !!"
  clear
  sleep 2
  echo -e "Adding default user for SSH-WS..."
  useradd aku -M -s /bin/false
  echo "aku:aku" | chpasswd
  echo "SSH-WS installed successfully !!"
  sleep 2
}

uninstall_ssh_ws(){
  clear
  systemctl stop ws-stunnel
  systemctl disable ws-stunnel
  rm -rf /etc/systemd/system/ws-stunnel.service
  systemctl daemon-reload
  rm -rf /usr/local/bin/websocket/ws-stunnel
  apt-get purge python2.7 -y
  apt-get purge dropbear -y
  systemctl restart dropbear
  userdel aku
  clear
  echo "SSH-WS uninstalled successfully !!"
  sleep 3
}
acme_install(){
  clear
  if [ -f /root/xray.crt ] && [ -f /root/xray.key ]; then
    echo "Cert files already exist, proceeding to Xray installation..."
    sleep 3
    setup_nginx
    setup_cf_warp
    exit 0
  else
    echo "Cert files not found, generating new cert..."
    sleep 3
    clear
  fi
  echo "[Acme.sh Installation Script]"
  echo -n "Enter your domain name (Ex:something.com): "
  read domain
  clear
  echo -e "Generating cert for Xray...."
  echo -e "Installing Acme.sh..."
  sleep 3
  clear
  if [ -d /root/.acme.sh ]; then
    echo "Removing existing .acme.sh directory..."
    rm -rf /root/.acme.sh
  fi
  wget --no-cache --no-check-certificate -O acme.sh https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh
  bash acme.sh --install
  rm acme.sh
  cd "$scr_dir/.acme.sh"
  bash acme.sh --register-account -m mymail@gmail.com
  bash acme.sh --issue --standalone -d $domain --force
  if [ $? -ne 0 ]; then
    echo "Acme.sh unable to generate cert please try to check if your domain is correct, exiting..."
    exit 0
  else
    bash acme.sh --installcert -d $domain --fullchainpath /root/xray.crt --keypath /root/xray.key
    if [ $? -ne 0 ]; then
      echo "Acme.sh unable to install cert please try to check if your domain is correct, exiting..."
      exit 0
    fi
  fi
  clear
  if [ -f /root/xray.crt ] && [ -f /root/xray.key ]; then
    echo "Cert generated successfully !!"
    sleep 3
  else
    echo "Cert generation failed !!"
    sleep 3
    exit 0
  fi
}

setup_nginx(){
  clear
  echo "[Nginx Installation Script]"
  echo -e "Installing Nginx..."
  sleep 3
  apt-get install nginx -y
  clear
  #setup nginx config for xray (nginx.conf and xray.conf)
  echo -e "Configuring Nginx for Xray..."
  rm -rf /etc/nginx/nginx.conf
  sleep 2
  wget --no-cache --no-check-certificate -O /etc/nginx/nginx.conf https://raw.githubusercontent.com/crixsz/XrayMultiPath-SSH-WS/main/Nginx/nginx.conf
  wget --no-cache --no-check-certificate -O /etc/nginx/conf.d/xray.conf https://raw.githubusercontent.com/crixsz/XrayMultiPath-SSH-WS/main/Nginx/xray.conf
  systemctl restart nginx
  nginx_status=$(systemctl is-active nginx)
  if [ "$nginx_status" == "active" ]; then
    echo "Configured successfully"
    sleep 2
  else
    echo "Nginx is not running."
    sleep 3
    exit 0
  fi
}
setup_cf_warp(){
  clear
  echo "[Docker Setup]"
  wget --no-cache --no-check-certificate https://raw.githubusercontent.com/crixsz/DockerInstall/main/docker-install.sh && chmod +x docker-install.sh && ./docker-install.sh
  clear
  sleep 2
  if ! command -v docker &> /dev/null; then
    echo "Docker installation failed or Docker command not found. Exiting..."
    exit 1
  fi
  echo "[CF Warp Setup]"
  ## moving to https://github.com/aleskxyz/warp-svc
  docker run --restart always -d --name=warp -e FAMILIES_MODE=off -p 127.0.0.1:1080:1080 -v /usr/local/warp:/var/lib/cloudflare-warp ghcr.io/aleskxyz/warp-svc:latest
  docker ps
  sleep 5
  ## bash <(curl -fsSL git.io/warp.sh) install (warp-cli currently causes SSH to disconnect)
  ## bash <(curl -fsSL git.io/warp.sh) proxy (warp-cli currently causes SSH to disconnect)
  sleep 2
  clear
  ## bash <(curl -fsSL git.io/warp.sh) status (warp-cli currently causes SSH to disconnect)
  echo "[Moving to Xray Installation]"
  install_xray
}
install_xray() {
  # check if already exist
  if [ -f /usr/local/bin/xray ]; then
    echo "Xray Core is already installed !!"
    read -p "Do you want to uninstall currently installed Xray Core? [y/n]: " uninstall_option
    if [ "$uninstall_option" == "y" ]; then
      echo "Uninstalling currently installed Xray Core..."
      uninstall_xray
      exit 0
    else
      echo "Exiting..."
      sleep 3
      clear
      exit 0
    fi
  fi
  echo "[Xray Core Installation Script]"
  echo "Starting installation of xray core v1.5.0.."
  sleep 3
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --version 1.5.0 -u root
  sleep 2 
  clear
  echo "Xray Core installed successfully !!"
  sleep 2
  clear 
  #wget https://raw.githubusercontent.com/crixsz/XrayMultiPath-SSH-WS/main/Xray/xraymulticontroller.sh && mv xraymulticontroller.sh /usr/local/bin/xraymulticontroller && chmod +x /usr/local/bin/xraymulticontroller
  wget --no-cache --no-check-certificate https://raw.githubusercontent.com/crixsz/XrayMultiPath-SSH-WS/main/Xray/config.json && mv config.json /usr/local/etc/xray/
  wget --no-cache --no-check-certificate https://raw.githubusercontent.com/crixsz/XrayMultiPath-SSH-WS/main/Xray/none.json && mv none.json /usr/local/etc/xray/
  wget --no-cache --no-check-certificate https://raw.githubusercontent.com/crixsz/XrayMultiPath-SSH-WS/main/Xray/direct.json && mv direct.json /usr/local/etc/xray/
  if [ -f /usr/local/etc/xray/config.json ] && [ -f /usr/local/etc/xray/none.json ]; then
    echo "Successfully configured Xray config"
  else
    echo "Xray config file download failed !!"
    exit 0
  fi
  clear
  systemctl stop xray
  if pgrep xray >/dev/null; then
    echo "Xray is still running. Exiting..."
    exit 0
  fi
  rm -rf /etc/systemd/system/xray@.service
  wget --no-cache --no-check-certificate -O /etc/systemd/system/xray@.service https://raw.githubusercontent.com/crixsz/XrayMultiPath-SSH-WS/main/Xray/xray@.service
  systemctl daemon-reload
  systemctl start xray@none
  systemctl start xray
  systemctl start xray@direct
  systemctl enable xray@none
  systemctl enable xray
  systemctl enable xray@direct
  clear
  sleep 2
  echo "Xray Core installed successfully !!"
  echo ""
  echo -e "\033[0;32m[ VLESS-WS Port 80 (CF Warp) ]\033[0m"
  echo "vless://5d871382-b2ec-4d82-b5b8-712498a348e5@${ip}:80?security=&type=ws&path=/vless-ws&host=${ip}&encryption=none"
  echo ""
  echo -e "\033[0;32m[ VLESS-WS Port 443 (CF Warp) ]\033[0m"
  echo "vless://5d871382-b2ec-4d82-b5b8-712498a348e5@${ip}:443?security=tls&sni=bug.com&allowInsecure=1&type=ws&path=/vless-ws&encryption=none"
  echo ""  
  echo -e "\033[0;32m[ TROJAN-WS Port 80 (CF Warp) ]\033[0m"
  echo "trojan://trojanaku@${ip}:80?security=&type=ws&path=/trojan-ws&host=${ip}#"
  echo ""
  echo -e "\033[0;32m[ TROJAN-WS Port 443 (CF Warp) ]\033[0m"
  echo "trojan://trojankau@${ip}:443?security=&type=ws&path=/trojan-ws&host=${ip}#"
  echo ""
  echo -e "\033[0;32m[ TROJAN-WS Port 80 (Direct) ]\033[0m"
  echo "trojan://trojanaku@${ip}:80?security=&type=ws&path=/direct&host=${ip}#"
  echo ""
  echo -e "\033[0;32m[ VLESS-WS Port 80 (Direct) ]\033[0m"
  echo "vless://5d871382-b2ec-4d82-b5b8-712498a348e5@${ip}:80?security=&type=ws&path=/direct-vless&host=${ip}&encryption=none"
  echo ""
}

uninstall_xray(){
  systemctl stop xray
  systemctl stop xray@none
  systemctl stop xray@direct
  systemctl disable xray
  systemctl disable xray@none
  systemctl disable xray@direct
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
  apt-get purge nginx nginx-common -y
  apt-get purge python2.7 -y
  apt-get purge dropbear -y
  # remove docker and all its container
  docker rm -f $(docker ps -a -q)
  docker rmi -f $(docker images -a -q)
  docker system prune -a -f
  systemctl reset-failed
  systemctl daemon-reload
  rm -rf /usr/local/etc/xray
  rm -rf /etc/systemd/system/xray.service
  rm -rf /etc/systemd/system/xray@.service
  rm -rf /etc/systemd/system/xray@.service.d
  rm -rf /etc/systemd/system/xray.service.d
  rm -rf /root/docker-install.sh
  rm -rf /usr/local/bin/xray
  rm -rf
  clear
  echo "Xray Core uninstalled successfully !!"
  sleep 3
}
## Main output
clear
echo -e "\033[0;34m[ Xray Dual Config Multipath + CF Warp Installation Script ]\033[0m"
echo ""
echo "1) Install Xray Core (Dual config) + Acme.sh + Nginx + CF Warp + SSH WS"
echo "2) Uninstall Xray Core (Dual config) + Acme.sh + Nginx + CF Warp + SSH WS"
echo "3) Exit"
echo ""
read -p "Select an option [1-3]: " option

case $option in
  1)
    prequisites
    acme_install
    setup_nginx
    setup_ssh_ws
    setup_cf_warp
    ;;
  2)
    echo "Uninstalling All related files..."
    uninstall_xray
    uninstall_ssh_ws
    ;;
  3)
    echo "Exiting..."
    exit 0
    ;;
  *)
    echo "Invalid option. Please select a valid option."
    ;;
esac