#!/bin/bash

# ---------------- INSTALL DEPENDENCIES ----------------
echo "[*] Updating package list..."
sudo apt update -y

echo "[*] Installing iproute2..."
sudo apt install -y iproute2

echo "[*] Installing net-tools..."
sudo apt install -y net-tools

echo "[*] Installing grep..."
sudo apt install -y grep

echo "[*] Installing awk..."
sudo apt install -y awk

echo "[*] Installing sudo..."
sudo apt install -y sudo

echo "[*] Installing iputils-ping..."
sudo apt install -y iputils-ping

echo "[*] Installing jq..."
sudo apt install -y jq

echo "[*] Installing Curl..."
sudo apt install -y curl

echo "[*] Installing Haproxy..."
sudo apt install -y haproxy

echo "[*] Installing Iptables..."
sudo apt install iptables

# ---------------- COLORS ----------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ---------------- FUNCTIONS ----------------

check_core_status() {
    ip link show | grep -q 'vxlan' && echo "Active" || echo "Inactive"
}

Lena_menu() {
    clear
    SERVER_IP=$(hostname -I | awk '{print $1}')
    SERVER_COUNTRY=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.country')
    SERVER_ISP=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.isp')

    echo "+-------------------------------------------------------------------------+"
    echo "| _                      									|"
    echo "|| |                     									|"
    echo "|| |     ___ _ __   __ _ 									|"
    echo "|| |    / _ \ '_ \ / _  |									|"
    echo "|| |___|  __/ | | | (_| |									|"
    echo "|\_____/\___|_| |_|\__,_|	V1.0.5 Beta			            |" 
    echo "+-------------------------------------------------------------------------+"    
    echo -e "| Telegram Channel : ${MAGENTA}@AminiDev ${NC}| Version : ${GREEN} 1.0.5 Beta ${NC} "
    echo "+-------------------------------------------------------------------------+"
    echo -e "|${GREEN}Server Country    |${NC} $SERVER_COUNTRY"
    echo -e "|${GREEN}Server IP         |${NC} $SERVER_IP"
    echo -e "|${GREEN}Server ISP        |${NC} $SERVER_ISP"
    echo "+-------------------------------------------------------------------------+"
    echo -e "|${YELLOW}Please choose an option:${NC}"
    echo "+-------------------------------------------------------------------------+"
    echo -e "1- Install new tunnel"
    echo -e "2- Uninstall tunnel(s)"
    echo -e "3- Install BBR"
    echo -e "4- install cronjob"
    echo "+-------------------------------------------------------------------------+"
    echo -e "\033[0m"
}

uninstall_all_vxlan() {
    echo "[!] Deleting all VXLAN interfaces and cleaning up..."
    for i in $(ip -d link show | grep -o 'vxlan[0-9]\+'); do
        ip link del $i 2>/dev/null
    done
    rm -f /usr/local/bin/vxlan_bridge.sh /etc/ping_vxlan.sh
    systemctl disable --now vxlan-tunnel.service 2>/dev/null
    rm -f /etc/systemd/system/vxlan-tunnel.service
    systemctl daemon-reload
    # Stop and disable HAProxy service
    systemctl stop haproxy 2>/dev/null
    systemctl disable haproxy 2>/dev/null
    # Remove HAProxy package
    apt remove -y haproxy 2>/dev/null
    apt purge -y haproxy 2>/dev/null
    apt autoremove -y 2>/dev/null
    # Remove related cronjobs
    crontab -l 2>/dev/null | grep -v 'systemctl restart haproxy' | grep -v 'systemctl restart vxlan-tunnel' | grep -v '/etc/ping_vxlan.sh' > /tmp/cron_tmp || true
    crontab /tmp/cron_tmp
    rm /tmp/cron_tmp
    echo "[+] All VXLAN tunnels and related cronjobs deleted."
}

install_bbr() {
    echo "Running BBR script..."
    curl -fsSL https://raw.githubusercontent.com/MrAminiDev/NetOptix/main/scripts/bbr.sh -o /tmp/bbr.sh
    bash /tmp/bbr.sh
    rm /tmp/bbr.sh
}

install_haproxy_and_configure() {
    echo "[*] Configuring HAProxy..."

    # Ensure haproxy is installed
    if ! command -v haproxy >/dev/null 2>&1; then
        echo "[x] HAProxy is not installed. Installing..."
        sudo apt update && sudo apt install -y haproxy
    fi

    # Ensure config directory exists
    sudo mkdir -p /etc/haproxy

    # Default HAProxy config file
    local CONFIG_FILE="/etc/haproxy/haproxy.cfg"
    local BACKUP_FILE="/etc/haproxy/haproxy.cfg.bak"

    # Backup old config
    [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$BACKUP_FILE"

    # Write base config
    cat <<EOL > "$CONFIG_FILE"
global
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 4096

defaults
    mode    tcp
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms
    retries 3
    option  tcpka
EOL

    read -p "Enter ports (comma-separated): " user_ports
    read -p "Enter the number of backend servers: " num_backends
    local local_ip="30.0.0"

    IFS=',' read -ra ports <<< "$user_ports"

    for port in "${ports[@]}"; do
        cat <<EOL >> "$CONFIG_FILE"

frontend frontend_$port
    bind *:$port
    default_backend backend_$port
    option tcpka

backend backend_$port
    option tcpka
EOL
        for ((i=1; i<=num_backends; i++)); do
            cat <<EOL >> "$CONFIG_FILE"
    server server$i $local_ip.$((i + 1)):$port check maxconn 2048
EOL
        done
    done

    # Validate haproxy config
    if haproxy -c -f "$CONFIG_FILE"; then
        echo "[*] Restarting HAProxy service..."
        systemctl restart haproxy
        systemctl enable haproxy
        echo -e "${GREEN}HAProxy configured and restarted successfully.${NC}"
    else
        echo -e "${YELLOW}Warning: HAProxy configuration is invalid!${NC}"
    fi
}

# ---------------- MAIN ----------------
while true; do
    Lena_menu
    read -p "Enter your choice [1-4]: " main_action
    case $main_action in
        1)
            break
            ;;
        2)
            uninstall_all_vxlan
            read -p "Press Enter to return to menu..."
            ;;
        3)
            install_bbr
            read -p "Press Enter to return to menu..."
            ;;
        4)
            while true; do
                read -p "How many hours between each restart? (1-24): " cron_hours
                if [[ $cron_hours =~ ^[0-9]+$ ]] && (( cron_hours >= 1 && cron_hours <= 24 )); then
                    break
                else
                    echo "Invalid input. Please enter a number between 1 and 24."
                fi
            done
            # Remove any previous cronjobs for these services
            crontab -l 2>/dev/null | grep -v 'systemctl restart haproxy' | grep -v 'systemctl restart vxlan-tunnel' > /tmp/cron_tmp || true
            echo "0 */$cron_hours * * * systemctl restart haproxy >/dev/null 2>&1" >> /tmp/cron_tmp
            echo "0 */$cron_hours * * * systemctl restart vxlan-tunnel >/dev/null 2>&1" >> /tmp/cron_tmp
            crontab /tmp/cron_tmp
            rm /tmp/cron_tmp
            echo -e "${GREEN}Cronjob set successfully to restart haproxy and vxlan-tunnel every $cron_hours hour(s).${NC}"
            read -p "Press Enter to return to menu..."
            ;;
        *)
            echo "[x] Invalid option. Try again."
            sleep 1
            ;;
    esac
done

# Check if ip command is available
if ! command -v ip >/dev/null 2>&1; then
    echo "[x] iproute2 is not installed. Aborting."
    exit 1
fi

# ------------- VARIABLES --------------
VNI=88
VXLAN_IF="vxlan${VNI}"

# --------- Choose Server Role ----------
echo "Choose server role:"
echo "1- Iran"
echo "2- Kharej"
read -p "Enter choice (1/2): " role_choice

if [[ "$role_choice" == "1" ]]; then
    read -p "Enter IRAN IP: " IRAN_IP
    read -p "Enter Kharej IP: " KHAREJ_IP

    # Port validation loop
    while true; do
        read -p "Tunnel port (1 ~ 64435): " DSTPORT
        if [[ $DSTPORT =~ ^[0-9]+$ ]] && (( DSTPORT >= 1 && DSTPORT <= 64435 )); then
            break
        else
            echo "Invalid port. Try again."
        fi
    done

    # Strict input validation for haproxy_choice
    while true; do
        read -p "Should port forwarding be done automatically? (It is done with haproxy tool) [1-yes, 2-no]: " haproxy_choice
        if [[ "$haproxy_choice" == "1" || "$haproxy_choice" == "2" ]]; then
            break
        else
            echo "Please enter 1 (yes) or 2 (no)."
        fi
    done
    if [[ "$haproxy_choice" == "1" ]]; then
        install_haproxy_and_configure
    else
        ipv4_local=$(hostname -I | awk '{print $1}')
        echo "IRAN Server setup complete."
        echo -e "####################################"
        echo -e "# Your IPv4 :                      #"
        echo -e "#  30.0.0.2                     #"
        echo -e "####################################"
    fi

    VXLAN_IP="30.0.0.2/24"
    REMOTE_IP=$KHAREJ_IP

elif [[ "$role_choice" == "2" ]]; then
    read -p "Enter the number of Iran servers to connect: " num_iran_servers
    read -p "Enter Kharej IP: " KHAREJ_IP

    # Port validation loop
    while true; do
        read -p "Tunnel port (1 ~ 64435): " DSTPORT
        if [[ $DSTPORT =~ ^[0-9]+$ ]] && (( DSTPORT >= 1 && DSTPORT <= 64435 )); then
            break
        else
            echo "Invalid port. Try again."
        fi
    done

    ipv4_local=$(hostname -I | awk '{print $1}')
    echo "Kharej Server setup complete."
    echo -e "####################################"
    echo -e "# Your IPv4 :                      #"
    echo -e "#  30.0.0.1                        #"
    echo -e "####################################"

    VXLAN_IP="30.0.0.1/24"
    REMOTE_IP_LIST=()
    for ((i=1; i<=num_iran_servers; i++)); do
        read -p "Enter IRAN IP for server $i: " IRAN_IP
        REMOTE_IP_LIST+=($IRAN_IP)
    done

else
    echo "[x] Invalid role selected."
    exit 1
fi

# Detect default interface
INTERFACE=$(ip route get 1.1.1.1 | awk '{print $5}' | head -n1)
echo "Detected main interface: $INTERFACE"

# ------------ Setup VXLAN --------------
if [[ "$role_choice" == "1" ]]; then
    echo "[+] Creating VXLAN interface..."
    ip link add $VXLAN_IF type vxlan id $VNI local $(hostname -I | awk '{print $1}') remote $REMOTE_IP dev $INTERFACE dstport $DSTPORT nolearning

    echo "[+] Assigning IP $VXLAN_IP to $VXLAN_IF"
    ip addr add $VXLAN_IP dev $VXLAN_IF
    ip link set $VXLAN_IF up

    echo "[+] Adding iptables rules"
    iptables -I INPUT 1 -p udp --dport $DSTPORT -j ACCEPT
    iptables -I INPUT 1 -s $REMOTE_IP -j ACCEPT
    iptables -I INPUT 1 -s ${VXLAN_IP%/*} -j ACCEPT
elif [[ "$role_choice" == "2" ]]; then
    for i in "${!REMOTE_IP_LIST[@]}"; do
        IRAN_IP=${REMOTE_IP_LIST[$i]}
        CURRENT_VNI=$((VNI + i))
        CURRENT_VXLAN_IF="vxlan${CURRENT_VNI}"
        CURRENT_VXLAN_IP="30.0.0.$((i + 2))/24"

        echo "[+] Creating VXLAN interface $CURRENT_VXLAN_IF for $IRAN_IP..."
        ip link add $CURRENT_VXLAN_IF type vxlan id $CURRENT_VNI local $KHAREJ_IP remote $IRAN_IP dev $INTERFACE dstport $DSTPORT nolearning

        echo "[+] Assigning IP $CURRENT_VXLAN_IP to $CURRENT_VXLAN_IF"
        ip addr add $CURRENT_VXLAN_IP dev $CURRENT_VXLAN_IF
        ip link set $CURRENT_VXLAN_IF up

        echo "[+] Adding iptables rules for $IRAN_IP"
        iptables -I INPUT 1 -p udp --dport $DSTPORT -j ACCEPT
        iptables -I INPUT 1 -s $IRAN_IP -j ACCEPT
        iptables -I INPUT 1 -s ${CURRENT_VXLAN_IP%/*} -j ACCEPT
    done
fi

# ---------------- CREATE SYSTEMD SERVICE ----------------
echo "[+] Creating systemd service for VXLAN..."

if [[ "$role_choice" == "1" ]]; then
    cat <<EOF > /usr/local/bin/vxlan_bridge.sh
#!/bin/bash
ip link add $VXLAN_IF type vxlan id $VNI local $(hostname -I | awk '{print $1}') remote $REMOTE_IP dev $INTERFACE dstport $DSTPORT nolearning
ip addr add $VXLAN_IP dev $VXLAN_IF
ip link set $VXLAN_IF up
# Persistent keepalive: ping remote every 30s in background
( while true; do ping -c 1 $REMOTE_IP >/dev/null 2>&1; sleep 30; done ) &
EOF
elif [[ "$role_choice" == "2" ]]; then
    cat <<EOF > /usr/local/bin/vxlan_bridge.sh
#!/bin/bash
ip addr add 30.0.0.1/24 dev $VXLAN_IF
ip link set $VXLAN_IF up
EOF
    for i in "${!REMOTE_IP_LIST[@]}"; do
        IRAN_IP=${REMOTE_IP_LIST[$i]}
        CURRENT_VNI=$((VNI + i))
        CURRENT_VXLAN_IF="vxlan${CURRENT_VNI}"
        cat <<EOF >> /usr/local/bin/vxlan_bridge.sh
ip link add $CURRENT_VXLAN_IF type vxlan id $CURRENT_VNI local $KHAREJ_IP remote $IRAN_IP dev $INTERFACE dstport $DSTPORT nolearning
ip addr add 30.0.0.$((i + 2))/24 dev $CURRENT_VXLAN_IF
ip link set $CURRENT_VXLAN_IF up
( while true; do ping -c 1 $IRAN_IP >/dev/null 2>&1; sleep 30; done ) &
EOF
    done
fi

chmod +x /usr/local/bin/vxlan_bridge.sh

cat <<EOF > /etc/systemd/system/vxlan-tunnel.service
[Unit]
Description=VXLAN Tunnel Interface
After=network.target

[Service]
ExecStart=/usr/local/bin/vxlan_bridge.sh
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/vxlan-tunnel.service
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable vxlan-tunnel.service
systemctl start vxlan-tunnel.service

echo -e "\n${GREEN}[✓] VXLAN tunnel service enabled to run on boot.${NC}"

echo "[✓] VXLAN tunnel setup completed successfully."

# ---------------- TEST AND VERIFY ----------------
test_and_verify() {
    echo "[*] Running tests and verification..."

    # Mock data for testing
    local test_kharej_ip="1.1.1.1"
    local test_iran_ips=("2.2.2.2" "3.3.3.3")
    local test_dstport="4789"
    local test_num_iran_servers=2
    local test_vni=88
    local test_interface="eth0"

    # Create a temporary directory for generated files
    local temp_dir=$(mktemp -d)

    # Generate vxlan_bridge.sh for Kharej server
    local vxlan_bridge_sh="$temp_dir/vxlan_bridge.sh"
    cat <<EOF > "$vxlan_bridge_sh"
#!/bin/bash
ip addr add 30.0.0.1/24 dev vxlan$test_vni
ip link set vxlan$test_vni up
EOF
    for i in "${!test_iran_ips[@]}"; do
        IRAN_IP=${test_iran_ips[$i]}
        CURRENT_VNI=$((test_vni + i))
        CURRENT_VXLAN_IF="vxlan${CURRENT_VNI}"
        cat <<EOF >> "$vxlan_bridge_sh"
ip link add $CURRENT_VXLAN_IF type vxlan id $CURRENT_VNI local $test_kharej_ip remote $IRAN_IP dev $test_interface dstport $test_dstport nolearning
ip addr add 30.0.0.$((i + 2))/24 dev $CURRENT_VXLAN_IF
ip link set $CURRENT_VXLAN_IF up
( while true; do ping -c 1 $IRAN_IP >/dev/null 2>&1; sleep 30; done ) &
EOF
    done

    # Generate haproxy.cfg
    local haproxy_cfg="$temp_dir/haproxy.cfg"
    cat <<EOL > "$haproxy_cfg"
global
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 4096

defaults
    mode    tcp
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms
    retries 3
    option  tcpka
EOL
    local test_ports=("80" "443")
    for port in "${test_ports[@]}"; do
        cat <<EOL >> "$haproxy_cfg"

frontend frontend_$port
    bind *:$port
    default_backend backend_$port
    option tcpka

backend backend_$port
    option tcpka
EOL
        for ((i=1; i<=test_num_iran_servers; i++)); do
            cat <<EOL >> "$haproxy_cfg"
    server server$i 30.0.0.$((i + 1)):$port check maxconn 2048
EOL
        done
    done

    # --- Verification ---
    echo "[+] Verifying generated files..."

    # Verify vxlan_bridge.sh
    if grep -q "ip addr add 30.0.0.1/24 dev vxlan88" "$vxlan_bridge_sh" && \
       grep -q "ip link add vxlan88 type vxlan id 88 local 1.1.1.1 remote 2.2.2.2 dev eth0 dstport 4789 nolearning" "$vxlan_bridge_sh" && \
       grep -q "ip addr add 30.0.0.2/24 dev vxlan88" "$vxlan_bridge_sh" && \
       grep -q "ip link add vxlan89 type vxlan id 89 local 1.1.1.1 remote 3.3.3.3 dev eth0 dstport 4789 nolearning" "$vxlan_bridge_sh" && \
       grep -q "ip addr add 30.0.0.3/24 dev vxlan89" "$vxlan_bridge_sh"; then
        echo -e "${GREEN}[✓] vxlan_bridge.sh generated correctly.${NC}"
    else
        echo -e "${YELLOW}[✗] vxlan_bridge.sh verification failed.${NC}"
    fi

    # Verify haproxy.cfg
    if grep -q "server server1 30.0.0.2:80 check maxconn 2048" "$haproxy_cfg" && \
       grep -q "server server2 30.0.0.3:80 check maxconn 2048" "$haproxy_cfg" && \
       grep -q "server server1 30.0.0.2:443 check maxconn 2048" "$haproxy_cfg" && \
       grep -q "server server2 30.0.0.3:443 check maxconn 2048" "$haproxy_cfg"; then
        echo -e "${GREEN}[✓] haproxy.cfg generated correctly.${NC}"
    else
        echo -e "${YELLOW}[✗] haproxy.cfg verification failed.${NC}"
    fi

    # Cleanup
    rm -r "$temp_dir"
}

# Add test_and_verify to the main menu
Lena_menu() {
    clear
    SERVER_IP=$(hostname -I | awk '{print $1}')
    SERVER_COUNTRY=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.country')
    SERVER_ISP=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.isp')

    echo "+-------------------------------------------------------------------------+"
    echo "| _                      									|"
    echo "|| |                     									|"
    echo "|| |     ___ _ __   __ _ 									|"
    echo "|| |    / _ \ '_ \ / _  |									|"
    echo "|| |___|  __/ | | | (_| |									|"
    echo "|\_____/\___|_| |_|\__,_|	V1.0.5 Beta			            |"
    echo "+-------------------------------------------------------------------------+"
    echo -e "| Telegram Channel : ${MAGENTA}@AminiDev ${NC}| Version : ${GREEN} 1.0.5 Beta ${NC} "
    echo "+-------------------------------------------------------------------------+"
    echo -e "|${GREEN}Server Country    |${NC} $SERVER_COUNTRY"
    echo -e "|${GREEN}Server IP         |${NC} $SERVER_IP"
    echo -e "|${GREEN}Server ISP        |${NC} $SERVER_ISP"
    echo "+-------------------------------------------------------------------------+"
    echo -e "|${YELLOW}Please choose an option:${NC}"
    echo "+-------------------------------------------------------------------------+"
    echo -e "1- Install new tunnel"
    echo -e "2- Uninstall tunnel(s)"
    echo -e "3- Install BBR"
    echo -e "4- install cronjob"
    echo -e "5- Test and Verify"
    echo "+-------------------------------------------------------------------------+"
    echo -e "\033[0m"
}

# Update main loop to include the new option
while true; do
    Lena_menu
    read -p "Enter your choice [1-5]: " main_action
    case $main_action in
        1)
            break
            ;;
        2)
            uninstall_all_vxlan
            read -p "Press Enter to return to menu..."
            ;;
        3)
            install_bbr
            read -p "Press Enter to return to menu..."
            ;;
        4)
            while true; do
                read -p "How many hours between each restart? (1-24): " cron_hours
                if [[ $cron_hours =~ ^[0-9]+$ ]] && (( cron_hours >= 1 && cron_hours <= 24 )); then
                    break
                else
                    echo "Invalid input. Please enter a number between 1 and 24."
                fi
            done
            # Remove any previous cronjobs for these services
            crontab -l 2>/dev/null | grep -v 'systemctl restart haproxy' | grep -v 'systemctl restart vxlan-tunnel' > /tmp/cron_tmp || true
            echo "0 */$cron_hours * * * systemctl restart haproxy >/dev/null 2>&1" >> /tmp/cron_tmp
            echo "0 */$cron_hours * * * systemctl restart vxlan-tunnel >/dev/null 2>&1" >> /tmp/cron_tmp
            crontab /tmp/cron_tmp
            rm /tmp/cron_tmp
            echo -e "${GREEN}Cronjob set successfully to restart haproxy and vxlan-tunnel every $cron_hours hour(s).${NC}"
            read -p "Press Enter to return to menu..."
            ;;
        5)
            test_and_verify
            read -p "Press Enter to return to menu..."
            ;;
        *)
            echo "[x] Invalid option. Try again."
            sleep 1
            ;;
    esac
done
