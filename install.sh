#!/bin/bash

# =============================================================================
# Traefik-CrowdSec-Stack Installation Script
# =============================================================================
# Dieses Script installiert entweder:
# 1. Frontend Traefik (vorgeschalteter Proxy mit SSL/TLS)
# 2. Backend Stack (Standard mit SSL/TLS)
# 3. Backend Stack (mit vorgeschaltetem Traefik-Proxy)
# =============================================================================

# Farben für die Ausgabe
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
cyan='\033[0;36m'
red='\033[0;31m'
bold='\033[1m'
nc='\033[0m' # Kein Farbcode

# =============================================================================
# Hilfsfunktionen
# =============================================================================

# Banner anzeigen
show_banner() {
    clear
    echo -e "${cyan}${bold}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║              Traefik-CrowdSec-Stack Installer                        ║
║                                                                      ║
║  Automatische Installation von:                                      ║
║  • Frontend Traefik (vorgeschalteter Proxy)                          ║
║  • Backend Stack (Traefik + CrowdSec + Bouncer)                      ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${nc}"
}

# Funktion zum Ausgeben eines Schritts
show_step() {
    echo -e "${yellow}[$1/$2] $3...${nc}"
}

# Funktion zum Anzeigen, dass ein Schritt abgeschlossen ist
step_done() {
    echo -e "${green}✓ $1 abgeschlossen${nc}"
}

# Funktion für Fehler
error_exit() {
    echo -e "${red}✗ Fehler: $1${nc}" >&2
    exit 1
}

# Funktion für Bestätigungsfragen
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response

    if [ "$default" = "y" ]; then
        read -p "$prompt [Y/n]: " response
        response=${response:-y}
    else
        read -p "$prompt [y/N]: " response
        response=${response:-n}
    fi

    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# =============================================================================
# Installationsverzeichnis Setup
# =============================================================================

setup_installation_directory() {
    local mode=$1

    # Installationsverzeichnis verwenden (wurde im Konfigurationsmenü gesetzt)
    INSTALL_DIR="$CONFIG_INSTALL_DIR"

    echo -e "\n${bold}${cyan}Installationsverzeichnis wird vorbereitet${nc}\n"
    echo -e "${yellow}Zielverzeichnis:${nc} $INSTALL_DIR"

    # Prüfen ob Verzeichnis existiert
    if [ -d "$INSTALL_DIR" ]; then
        echo -e "${yellow}Verzeichnis existiert bereits!${nc}"
        if ! confirm "Möchten Sie die bestehende Installation aktualisieren/neu konfigurieren?" "n"; then
            error_exit "Installation abgebrochen"
        fi
    else
        if ! confirm "Verzeichnis erstellen und dort installieren?" "y"; then
            error_exit "Installation abgebrochen"
        fi

        # Verzeichnis erstellen
        mkdir -p "$INSTALL_DIR" || error_exit "Konnte Verzeichnis nicht erstellen: $INSTALL_DIR"
        echo -e "${green}✓ Verzeichnis erstellt${nc}"
    fi

    # Aktuelles Source-Verzeichnis merken
    SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Benötigte Dateien kopieren je nach Modus
    echo -e "\n${cyan}Kopiere benötigte Dateien...${nc}"

    case "$mode" in
        "frontend")
            mkdir -p "$INSTALL_DIR"/{compose,data/traefik-frontend/certs} /var/log/traefik
            cp -r "$SOURCE_DIR/frontend/traefik.yml.sample" "$INSTALL_DIR/compose/" 2>/dev/null || true
            cp -r "$SOURCE_DIR/data/traefik-frontend/traefik.yml.sample" "$INSTALL_DIR/data/traefik-frontend/" 2>/dev/null || true
            cp -r "$SOURCE_DIR/data/traefik-frontend/certs/acme.json.sample" "$INSTALL_DIR/data/traefik-frontend/certs/" 2>/dev/null || true
            cp "$SOURCE_DIR/docker-compose.frontend.yml" "$INSTALL_DIR/" 2>/dev/null || true
            cp "$SOURCE_DIR/.env.frontend.sample" "$INSTALL_DIR/.env.sample" 2>/dev/null || true
            ;;
        "backend-standard")
            mkdir -p "$INSTALL_DIR"/{compose,data}
            cp -r "$SOURCE_DIR/backend"/* "$INSTALL_DIR/compose/" 2>/dev/null || true
            cp -r "$SOURCE_DIR/data"/* "$INSTALL_DIR/data/" 2>/dev/null || true
            cp "$SOURCE_DIR/docker-compose.yml" "$INSTALL_DIR/" 2>/dev/null || true
            cp "$SOURCE_DIR/.env.sample" "$INSTALL_DIR/" 2>/dev/null || true
            ;;
        "backend-proxy")
            mkdir -p "$INSTALL_DIR"/{compose,data}
            cp -r "$SOURCE_DIR/backend"/* "$INSTALL_DIR/compose/" 2>/dev/null || true
            cp -r "$SOURCE_DIR/data"/* "$INSTALL_DIR/data/" 2>/dev/null || true
            cp "$SOURCE_DIR/docker-compose.yml.proxy.sample" "$INSTALL_DIR/docker-compose.yml" 2>/dev/null || true
            cp "$SOURCE_DIR/.env.sample" "$INSTALL_DIR/" 2>/dev/null || true
            ;;
    esac

    echo -e "${green}✓ Dateien kopiert${nc}"

    # In Zielverzeichnis wechseln
    cd "$INSTALL_DIR" || error_exit "Konnte nicht in Zielverzeichnis wechseln"
    echo -e "${green}✓ Arbeitsverzeichnis: $INSTALL_DIR${nc}\n"

    # Verzeichnis für spätere Verwendung exportieren
    export INSTALL_DIR
}

# =============================================================================
# Hauptmenü
# =============================================================================

# Basis-Verzeichnis konfigurieren
configure_base_directory() {
    clear
    echo -e "${bold}${cyan}Basis-Verzeichnis konfigurieren${nc}\n"
    echo -e "${yellow}Das Basis-Verzeichnis ist der Hauptordner, unter dem alle"
    echo -e "Installationen abgelegt werden.${nc}\n"
    echo -e "Aktuell: ${green}$CONFIG_BASE_DIR${nc}\n"

    read -p "Neues Basis-Verzeichnis [Enter = keine Änderung]: " new_base_dir

    if [ -n "$new_base_dir" ]; then
        # Tilde-Expansion
        new_base_dir="${new_base_dir/#\~/$HOME}"
        CONFIG_BASE_DIR="$new_base_dir"
        echo -e "\n${green}✓ Basis-Verzeichnis gesetzt auf: $CONFIG_BASE_DIR${nc}"
    else
        echo -e "\n${yellow}Keine Änderung${nc}"
    fi

    sleep 2
}

show_main_menu() {
    # Basis-Verzeichnis initialisieren falls noch nicht gesetzt
    if [ -z "$CONFIG_BASE_DIR" ]; then
        CONFIG_BASE_DIR="/opt/containers"
    fi

    while true; do
        show_banner
        echo -e "${bold}Bitte wählen Sie den Installationsmodus:${nc}\n"

        echo -e "${cyan}B)${nc} Basis-Verzeichnis         ${green}[$CONFIG_BASE_DIR]${nc}\n"

        echo -e "${cyan}1)${nc} Frontend Traefik ${blue}(vorgeschalteter Proxy mit SSL/TLS)${nc}"
        echo -e "   → Für LXC Container oder zentrale Traefik-Instanz"
        echo -e "   → Übernimmt SSL/TLS-Zertifikate"
        echo -e "   → Verbindet sich mit Backend-Traefiks per HTTP\n"

        echo -e "${cyan}2)${nc} Backend Stack - Standard ${blue}(mit SSL/TLS)${nc}"
        echo -e "   → Traefik + CrowdSec + Socket-Proxy + Bouncer"
        echo -e "   → Traefik übernimmt SSL/TLS-Zertifikate"
        echo -e "   → Ports 80 und 443 exponiert\n"

        echo -e "${cyan}3)${nc} Backend Stack - Proxy-Modus ${blue}(ohne SSL/TLS)${nc}"
        echo -e "   → Traefik + CrowdSec + Socket-Proxy + Bouncer"
        echo -e "   → Für Betrieb mit vorgeschaltetem Traefik"
        echo -e "   → Nur Port 80 exponiert (HTTP)\n"

        echo -e "${cyan}0)${nc} Beenden\n"

        read -p "Ihre Auswahl [B/0-3]: " INSTALL_MODE

        case $INSTALL_MODE in
            [bB])
                configure_base_directory
                ;;
            1)
                INSTALL_TYPE="frontend"
                echo -e "\n${green}Frontend Traefik gewählt${nc}\n"
                return 0
                ;;
            2)
                INSTALL_TYPE="backend-standard"
                echo -e "\n${green}Backend Stack - Standard gewählt${nc}\n"
                return 0
                ;;
            3)
                INSTALL_TYPE="backend-proxy"
                echo -e "\n${green}Backend Stack - Proxy-Modus gewählt${nc}\n"
                return 0
                ;;
            0)
                echo -e "\n${yellow}Installation abgebrochen.${nc}"
                exit 0
                ;;
            *)
                echo -e "\n${red}Ungültige Auswahl!${nc}"
                sleep 2
                ;;
        esac
    done
}

# =============================================================================
# Netzwerk-Konfiguration
# =============================================================================

# Netzwerk-Interface erkennen
detect_network_interface() {
    # Primäres Interface finden (ignoriere lo)
    INTERFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
    if [ -z "$INTERFACE" ]; then
        # Fallback: Erstes nicht-lo Interface
        INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | head -n1)
    fi
    echo "$INTERFACE"
}

# Aktuelle netplan-Konfiguration auslesen
read_current_netplan() {
    local netplan_file=$(find /etc/netplan -name "*.yaml" -o -name "*.yml" 2>/dev/null | head -n1)

    if [ -n "$netplan_file" ]; then
        echo -e "${cyan}Aktuelle netplan-Konfiguration gefunden: $netplan_file${nc}"

        # Aktuelle IP auslesen
        CURRENT_IP=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
        CURRENT_CIDR=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | cut -d'/' -f2)
        CURRENT_GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)

        echo -e "${yellow}Aktuelle Konfiguration:${nc}"
        echo -e "  Interface: $INTERFACE"
        echo -e "  IP-Adresse: $CURRENT_IP${CURRENT_CIDR:+/$CURRENT_CIDR}"
        echo -e "  Gateway: $CURRENT_GATEWAY"
    else
        echo -e "${yellow}Keine netplan-Konfiguration gefunden.${nc}"
    fi
}

# Prüfen ob wir in einem LXC-Container sind
is_lxc_container() {
    [ -f /proc/1/environ ] && grep -qa container=lxc /proc/1/environ
    return $?
}

# Netplan-Konfiguration anwenden
apply_network_config() {
    local interface=$1
    local ip_address=$2
    local gateway=$3
    local dns_servers=${4:-"8.8.8.8,1.1.1.1"}

    # Netplan-Datei finden oder erstellen
    local netplan_file=$(find /etc/netplan -name "*.yaml" -o -name "*.yml" 2>/dev/null | head -n1)

    if [ -z "$netplan_file" ]; then
        netplan_file="/etc/netplan/00-installer-config.yaml"
        echo -e "${yellow}Erstelle neue netplan-Konfiguration: $netplan_file${nc}"
    else
        # Backup erstellen
        cp "$netplan_file" "${netplan_file}.backup-$(date +%Y%m%d-%H%M%S)"
        echo -e "${cyan}Backup erstellt: ${netplan_file}.backup-$(date +%Y%m%d-%H%M%S)${nc}"
    fi

    # DNS-Server array erstellen
    IFS=',' read -ra DNS_ARRAY <<< "$dns_servers"
    local dns_yaml=""
    for dns in "${DNS_ARRAY[@]}"; do
        dns_yaml+="        - $dns\n"
    done

    # Netplan-Konfiguration schreiben
    cat > "$netplan_file" << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $interface:
      addresses:
        - $ip_address
      routes:
        - to: default
          via: $gateway
      nameservers:
        addresses:
$(echo -e "$dns_yaml")
EOF

    # Rechte setzen
    chmod 600 "$netplan_file"

    echo -e "${cyan}Wende netplan-Konfiguration an...${nc}"

    # LXC-Container erkennen und alternative Methode verwenden
    if is_lxc_container; then
        echo -e "${yellow}LXC-Container erkannt - verwende alternativen Ansatz...${nc}"

        # In LXC-Containern netplan generate und dann systemd-networkd neu starten
        if netplan generate 2>/dev/null && systemctl restart systemd-networkd; then
            echo -e "${green}✓ Netzwerk-Konfiguration erfolgreich angewendet${nc}"
            sleep 2  # Kurz warten bis Netzwerk neu konfiguriert ist

            # Neue Konfiguration anzeigen
            echo -e "\n${yellow}Neue Netzwerk-Konfiguration:${nc}"
            ip -4 addr show "$interface" | grep inet
            return 0
        else
            echo -e "${red}✗ Fehler beim Anwenden der Konfiguration${nc}"
            echo -e "${yellow}Backup wiederherstellen mit:${nc} mv ${netplan_file}.backup-* $netplan_file && netplan generate && systemctl restart systemd-networkd"
            return 1
        fi
    else
        # Standard-Methode für normale Systeme
        if netplan apply; then
            echo -e "${green}✓ Netzwerk-Konfiguration erfolgreich angewendet${nc}"

            # Neue Konfiguration anzeigen
            echo -e "\n${yellow}Neue Netzwerk-Konfiguration:${nc}"
            ip -4 addr show "$interface" | grep inet
            return 0
        else
            echo -e "${red}✗ Fehler beim Anwenden der Konfiguration${nc}"
            echo -e "${yellow}Backup wiederherstellen mit:${nc} mv ${netplan_file}.backup-* $netplan_file && netplan apply"
            return 1
        fi
    fi
}

configure_network() {
    echo -e "\n${bold}Netzwerk-Konfiguration${nc}\n"

    # Netzwerk-Interface erkennen
    INTERFACE=$(detect_network_interface)

    if confirm "Möchten Sie die IP-Adresse dieser Maschine konfigurieren?" "n"; then
        echo -e "\n${cyan}Aktuelle Netzwerk-Konfiguration wird ausgelesen...${nc}\n"
        read_current_netplan

        echo -e "\n${bold}Neue IP-Konfiguration:${nc}"

        # IP-Adresse
        read -p "IP-Adresse (z.B. 172.16.16.140) [${CURRENT_IP}]: " NEW_IP
        NEW_IP=${NEW_IP:-$CURRENT_IP}

        # CIDR/Subnet
        read -p "CIDR/Subnetz (z.B. 24 für /24) [${CURRENT_CIDR:-24}]: " NEW_CIDR
        NEW_CIDR=${NEW_CIDR:-${CURRENT_CIDR:-24}}

        # Gateway
        read -p "Gateway (z.B. 172.16.16.1) [${CURRENT_GATEWAY}]: " NEW_GATEWAY
        NEW_GATEWAY=${NEW_GATEWAY:-$CURRENT_GATEWAY}

        # DNS-Server
        read -p "DNS-Server (kommagetrennt) [8.8.8.8,1.1.1.1]: " NEW_DNS
        NEW_DNS=${NEW_DNS:-"8.8.8.8,1.1.1.1"}

        echo -e "\n${yellow}Folgende Konfiguration wird angewendet:${nc}"
        echo -e "  Interface: ${cyan}$INTERFACE${nc}"
        echo -e "  IP-Adresse: ${cyan}$NEW_IP/$NEW_CIDR${nc}"
        echo -e "  Gateway: ${cyan}$NEW_GATEWAY${nc}"
        echo -e "  DNS: ${cyan}$NEW_DNS${nc}"

        if confirm "\nKonfiguration jetzt anwenden?" "y"; then
            CONFIGURE_IP=true
        else
            echo -e "${yellow}IP-Konfiguration übersprungen${nc}"
            CONFIGURE_IP=false
        fi
    else
        CONFIGURE_IP=false
    fi

    if confirm "Möchten Sie den Hostnamen dieser Maschine ändern?" "n"; then
        CURRENT_HOSTNAME=$(hostname)
        read -p "Neuer Hostname [$CURRENT_HOSTNAME]: " NEW_HOSTNAME
        NEW_HOSTNAME=${NEW_HOSTNAME:-$CURRENT_HOSTNAME}
        CONFIGURE_HOSTNAME=true
    else
        CONFIGURE_HOSTNAME=false
    fi
}

# =============================================================================
# Konfigurationsmenü
# =============================================================================

# Installationskonfiguration speichern
save_installation_config() {
    # Source-Verzeichnis ermitteln (wo install.sh liegt)
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_file="${script_dir}/.install.conf"

    echo -e "${cyan}Speichere Installationskonfiguration...${nc}"
    echo -e "${cyan}Speicherort: $config_file${nc}"

    cat > "$config_file" << EOF
# Traefik Installation Configuration
# Generiert am: $(date '+%Y-%m-%d %H:%M:%S')
# WARNUNG: Passwörter werden aus Sicherheitsgründen NICHT gespeichert!

# Installationstyp und -verzeichnis
INSTALL_TYPE=$INSTALL_TYPE
CONFIG_BASE_DIR=$CONFIG_BASE_DIR
CONFIG_INSTALL_DIR=$CONFIG_INSTALL_DIR

# Netzwerk-Konfiguration
CONFIG_IP_ENABLED=$CONFIG_IP_ENABLED
CONFIG_IP=$CONFIG_IP
CONFIG_CIDR=$CONFIG_CIDR
CONFIG_GATEWAY=$CONFIG_GATEWAY
CONFIG_DNS=$CONFIG_DNS

# Hostname
CONFIG_HOSTNAME_ENABLED=$CONFIG_HOSTNAME_ENABLED
CONFIG_HOSTNAME=$CONFIG_HOSTNAME

# Dashboard
CONFIG_DASHBOARD_DOMAIN=$CONFIG_DASHBOARD_DOMAIN
CONFIG_DASHBOARD_USER=$CONFIG_DASHBOARD_USER

# Let's Encrypt
CONFIG_ACME_EMAIL=$CONFIG_ACME_EMAIL
CONFIG_ACME_STAGING=$CONFIG_ACME_STAGING

# Dashboard (Passwort-Hash wird gespeichert, nicht das Plaintext-Passwort)
CONFIG_DASHBOARD_PASS_HASH=$CONFIG_DASHBOARD_PASS

# Backend-VMs (nur Frontend-Modus)
CONFIG_BACKEND_IPS="${CONFIG_BACKEND_IPS[*]}"
EOF

    chmod 600 "$config_file"
    echo -e "${green}✓ Konfiguration gespeichert in: $config_file${nc}"

    # Alte .install.conf im aktuellen Verzeichnis löschen (falls vorhanden)
    if [ -f ".install.conf" ] && [ "$(realpath .install.conf)" != "$(realpath $config_file)" ]; then
        rm -f ".install.conf"
        echo -e "${yellow}ℹ Alte .install.conf aus Installationsverzeichnis entfernt${nc}"
    fi
}

# Installationskonfiguration laden
load_installation_config() {
    # Source-Verzeichnis ermitteln (wo install.sh liegt)
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_file="${script_dir}/.install.conf"

    if [ ! -f "$config_file" ]; then
        return 1
    fi

    echo -e "${cyan}Lade gespeicherte Installationskonfiguration...${nc}"

    # Source the config file
    source "$config_file"

    # Backend IPs als Array laden
    if [ -n "$CONFIG_BACKEND_IPS" ] && [ "$CONFIG_BACKEND_IPS" != " " ]; then
        # Nur wenn nicht leer und nicht nur Leerzeichen
        read -ra CONFIG_BACKEND_IPS <<< "$CONFIG_BACKEND_IPS"
        # Leere Elemente aus Array entfernen
        local temp_ips=()
        for ip in "${CONFIG_BACKEND_IPS[@]}"; do
            if [ -n "$ip" ]; then
                temp_ips+=("$ip")
            fi
        done
        CONFIG_BACKEND_IPS=("${temp_ips[@]}")
    else
        # Leeres Array wenn keine IPs
        CONFIG_BACKEND_IPS=()
    fi

    # Passwort-Hash wiederherstellen
    if [ -n "$CONFIG_DASHBOARD_PASS_HASH" ]; then
        CONFIG_DASHBOARD_PASS="$CONFIG_DASHBOARD_PASS_HASH"
    fi

    echo -e "${green}✓ Konfiguration geladen${nc}"
    return 0
}

# =============================================================================
# Backend-Management via SSH
# =============================================================================

# SSH-Key für Backend-Zugriff generieren/laden
setup_ssh_key() {
    local ssh_key_path="$HOME/.ssh/traefik_backend_rsa"

    if [ -f "$ssh_key_path" ]; then
        echo -e "${green}✓ SSH-Key existiert bereits: $ssh_key_path${nc}"
        return 0
    fi

    echo -e "${cyan}Generiere SSH-Key für Backend-Zugriff...${nc}"
    ssh-keygen -t rsa -b 4096 -f "$ssh_key_path" -N "" -C "traefik-backend-management"

    if [ $? -eq 0 ]; then
        echo -e "${green}✓ SSH-Key erfolgreich erstellt${nc}"
        return 0
    else
        echo -e "${red}✗ Fehler beim Erstellen des SSH-Keys${nc}"
        return 1
    fi
}

# SSH Public Key anzeigen
show_ssh_public_key() {
    local ssh_key_path="$HOME/.ssh/traefik_backend_rsa"

    clear
    echo -e "${bold}${cyan}SSH Public Key für Backend-Zugriff${nc}\n"

    if [ ! -f "${ssh_key_path}.pub" ]; then
        echo -e "${yellow}SSH-Key existiert noch nicht.${nc}"
        if confirm "Möchten Sie den SSH-Key jetzt generieren?" "y"; then
            setup_ssh_key
        else
            return 1
        fi
    fi

    echo -e "${yellow}Kopieren Sie diesen Public Key beim Erstellen des LXC-Containers:${nc}\n"
    echo -e "${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${nc}"
    cat "${ssh_key_path}.pub"
    echo -e "${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${nc}\n"

    echo -e "${cyan}In Proxmox:${nc}"
    echo -e "  1. LXC Container erstellen"
    echo -e "  2. Bei 'SSH public keys' den obigen Key einfügen"
    echo -e "  3. Container starten und DHCP-IP notieren\n"

    read -p "Drücken Sie Enter wenn Sie fortfahren möchten..."
}

# Backend hinzufügen
add_backend() {
    clear
    echo -e "${bold}${cyan}Backend hinzufügen${nc}\n"

    # Hostname
    local hostname
    while true; do
        read -p "Hostname des Backends (z.B. backend1): " hostname
        if [ -n "$hostname" ]; then
            break
        fi
        echo -e "${red}Hostname darf nicht leer sein${nc}"
    done

    # Ziel-IP
    local target_ip
    local cidr
    while true; do
        read -p "Ziel-IP-Adresse (z.B. 192.168.1.100): " target_ip
        if [[ $target_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            break
        fi
        echo -e "${red}Ungültige IP-Adresse${nc}"
    done

    read -p "CIDR [24]: " cidr
    cidr=${cidr:-24}

    # Domain auto-generieren
    local auto_domain=""
    if [ -n "$CONFIG_DASHBOARD_DOMAIN" ]; then
        # Extrahiere domain.tld aus traefik.domain.tld
        local base_domain=$(echo "$CONFIG_DASHBOARD_DOMAIN" | cut -d'.' -f2-)
        auto_domain="traefik.${hostname}.${base_domain}"
    fi

    echo -e "\n${yellow}Automatisch generierte Domain: ${cyan}${auto_domain}${nc}"
    read -p "Dashboard-Domain [$auto_domain]: " custom_domain
    local domain=${custom_domain:-$auto_domain}

    # Zu Arrays hinzufügen
    BACKEND_HOSTNAMES+=("$hostname")
    BACKEND_TARGET_IPS+=("$target_ip")
    BACKEND_TARGET_CIDR+=("$cidr")
    BACKEND_DHCP_IPS+=("")  # Wird später gefüllt
    BACKEND_DOMAINS+=("$domain")
    BACKEND_STATUS+=("pending")

    echo -e "\n${green}✓ Backend hinzugefügt:${nc}"
    echo -e "  Hostname: $hostname"
    echo -e "  Ziel-IP: $target_ip/$cidr"
    echo -e "  Dashboard: $domain"

    sleep 2
}

# Backends auflisten
list_backends() {
    if [ ${#BACKEND_HOSTNAMES[@]} -eq 0 ]; then
        echo -e "${yellow}Keine Backends konfiguriert${nc}"
        return
    fi

    echo -e "${bold}Konfigurierte Backends:${nc}\n"
    for i in "${!BACKEND_HOSTNAMES[@]}"; do
        local status_color="${yellow}"
        [ "${BACKEND_STATUS[$i]}" = "installed" ] && status_color="${green}"
        [ "${BACKEND_STATUS[$i]}" = "configured" ] && status_color="${cyan}"

        echo -e "${bold}$((i+1)).${nc} ${BACKEND_HOSTNAMES[$i]}"
        echo -e "   Ziel-IP: ${BACKEND_TARGET_IPS[$i]}/${BACKEND_TARGET_CIDR[$i]}"
        echo -e "   DHCP-IP: ${BACKEND_DHCP_IPS[$i]:-nicht gesetzt}"
        echo -e "   Domain: ${BACKEND_DOMAINS[$i]}"
        echo -e "   Status: ${status_color}${BACKEND_STATUS[$i]}${nc}\n"
    done
}

# Backend remote konfigurieren (IP + Hostname)
configure_backend_remote() {
    local index=$1

    if [ -z "$index" ] || [ $index -ge ${#BACKEND_HOSTNAMES[@]} ]; then
        echo -e "${red}Ungültiger Backend-Index${nc}"
        return 1
    fi

    local hostname="${BACKEND_HOSTNAMES[$index]}"
    local target_ip="${BACKEND_TARGET_IPS[$index]}"
    local cidr="${BACKEND_TARGET_CIDR[$index]}"

    clear
    echo -e "${bold}${cyan}Backend konfigurieren: $hostname${nc}\n"

    # DHCP-IP abfragen
    local dhcp_ip
    while true; do
        read -p "Aktuelle DHCP-IP des Backends: " dhcp_ip
        if [[ $dhcp_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            break
        fi
        echo -e "${red}Ungültige IP-Adresse${nc}"
    done

    BACKEND_DHCP_IPS[$index]="$dhcp_ip"

    # SSH-Verbindung testen
    echo -e "\n${cyan}Teste SSH-Verbindung zu $dhcp_ip...${nc}"
    local ssh_key="$HOME/.ssh/traefik_backend_rsa"

    if ! ssh -i "$ssh_key" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${BACKEND_SSH_USER}@${dhcp_ip}" "echo 'SSH OK'" &>/dev/null; then
        echo -e "${red}✗ SSH-Verbindung fehlgeschlagen${nc}"
        echo -e "${yellow}Bitte prüfen Sie:${nc}"
        echo -e "  • LXC Container läuft"
        echo -e "  • SSH Public Key wurde beim Container-Setup eingefügt"
        echo -e "  • IP-Adresse ist korrekt"
        read -p "Drücken Sie Enter um fortzufahren..."
        return 1
    fi
    echo -e "${green}✓ SSH-Verbindung erfolgreich${nc}"

    # Gateway ableiten
    local gateway=$(echo "$target_ip" | awk -F. '{print $1"."$2"."$3".1"}')
    read -p "Gateway [$gateway]: " custom_gateway
    gateway=${custom_gateway:-$gateway}

    # DNS
    read -p "DNS-Server [8.8.8.8,1.1.1.1]: " dns_servers
    dns_servers=${dns_servers:-8.8.8.8,1.1.1.1}

    echo -e "\n${cyan}Konfiguriere Backend remote...${nc}"

    # Netzwerk-Interface ermitteln
    local interface=$(ssh -i "$ssh_key" "${BACKEND_SSH_USER}@${dhcp_ip}" \
        "ip -4 route | grep default | awk '{print \$5}' | head -n1" 2>/dev/null)

    if [ -z "$interface" ]; then
        interface="eth0"
        echo -e "${yellow}⚠ Interface nicht erkannt, verwende: $interface${nc}"
    fi

    # Netplan-Konfiguration
    local netplan_config="network:
  version: 2
  renderer: networkd
  ethernets:
    $interface:
      dhcp4: false
      addresses:
        - $target_ip/$cidr
      routes:
        - to: default
          via: $gateway
      nameservers:
        addresses: [$(echo $dns_servers | tr ',' ', ')]"

    # Remote anwenden
    ssh -i "$ssh_key" -o ServerAliveInterval=5 -o ServerAliveCountMax=1 "${BACKEND_SSH_USER}@${dhcp_ip}" "bash -s" <<EOF
        echo '$netplan_config' > /etc/netplan/01-netcfg.yaml
        chmod 600 /etc/netplan/01-netcfg.yaml
        hostnamectl set-hostname $hostname
        echo "127.0.1.1 $hostname" >> /etc/hosts

        # Netplan im Hintergrund mit Delay anwenden, damit SSH sich sauber beenden kann
        nohup bash -c 'sleep 3; netplan apply' >/dev/null 2>&1 &

        echo "Konfiguration wird angewendet..."
        exit 0
EOF

    local ssh_result=$?

    # SSH wird wahrscheinlich mit einem Fehler beenden (Connection lost), das ist OK
    echo -e "${cyan}Warte auf Netzwerk-Rekonfiguration...${nc}"
    sleep 5

    # Teste Verbindung zur neuen IP
    echo -e "${cyan}Teste Verbindung zur neuen IP: $target_ip${nc}"
    local retries=0
    while [ $retries -lt 10 ]; do
        if ssh -i "$ssh_key" -o ConnectTimeout=3 -o StrictHostKeyChecking=no "${BACKEND_SSH_USER}@${target_ip}" "echo 'OK'" &>/dev/null; then
            echo -e "${green}✓ Backend konfiguriert und erreichbar${nc}"
            echo -e "${green}✓ Neue IP: $target_ip${nc}"
            BACKEND_STATUS[$index]="configured"
            sleep 2
            return 0
        fi
        echo -ne "\r${yellow}Warte auf Backend... [Versuch $((retries + 1))/10]${nc}"
        sleep 2
        retries=$((retries + 1))
    done

    echo -e "\n${yellow}⚠ Backend nicht unter neuer IP erreichbar${nc}"
    echo -e "${yellow}Bitte prüfen Sie die Netzwerk-Konfiguration manuell${nc}"
    read -p "Drücken Sie Enter um fortzufahren..."
    return 1
}

# Backend remote installieren
install_backend_remote() {
    local index=$1

    if [ -z "$index" ] || [ $index -ge ${#BACKEND_HOSTNAMES[@]} ]; then
        echo -e "${red}Ungültiger Index${nc}"
        return 1
    fi

    if [ "${BACKEND_STATUS[$index]}" != "configured" ]; then
        echo -e "${red}Backend muss erst konfiguriert werden${nc}"
        read -p "Enter..."
        return 1
    fi

    local hostname="${BACKEND_HOSTNAMES[$index]}"
    local target_ip="${BACKEND_TARGET_IPS[$index]}"
    local domain="${BACKEND_DOMAINS[$index]}"

    clear
    echo -e "${bold}${cyan}Backend installieren: $hostname${nc}\n"

    local ssh_key="$HOME/.ssh/traefik_backend_rsa"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local remote_tmp="/tmp/traefik-install"

    echo -e "${cyan}[1/5] Erstelle temporäres Verzeichnis...${nc}"
    ssh -i "$ssh_key" "${BACKEND_SSH_USER}@${target_ip}" "mkdir -p $remote_tmp"

    echo -e "${cyan}[2/5] Kopiere Dateien...${nc}"
    rsync -avz -e "ssh -i $ssh_key" \
        --exclude='.git' \
        --exclude='data/*/certs/*' \
        --exclude='.install.conf' \
        "$script_dir/" "${BACKEND_SSH_USER}@${target_ip}:${remote_tmp}/"

    echo -e "${cyan}[3/5] Erstelle Remote-Konfiguration...${nc}"

    local remote_config="INSTALL_TYPE=backend-proxy
CONFIG_BASE_DIR=/opt/containers
CONFIG_INSTALL_DIR=/opt/containers/traefik-backend
CONFIG_DASHBOARD_DOMAIN=$domain
CONFIG_DASHBOARD_USER=$CONFIG_DASHBOARD_USER
CONFIG_DASHBOARD_PASS_HASH=$CONFIG_DASHBOARD_PASS
CONFIG_IP_ENABLED=false
CONFIG_HOSTNAME_ENABLED=false"

    ssh -i "$ssh_key" "${BACKEND_SSH_USER}@${target_ip}" \
        "echo '$remote_config' > ${remote_tmp}/.install.conf && chmod 600 ${remote_tmp}/.install.conf"

    echo -e "${cyan}[4/5] Starte Installation...${nc}\n"

    # Installation ohne interaktives Terminal (-t entfernt)
    ssh -i "$ssh_key" "${BACKEND_SSH_USER}@${target_ip}" "cd $remote_tmp && sudo bash ./install.sh && cd / && rm -rf $remote_tmp" 2>&1 | grep -v "unknown terminal"

    if [ $? -eq 0 ]; then
        echo -e "\n${green}✓ Installation erfolgreich${nc}"
        BACKEND_STATUS[$index]="installed"

        echo -e "${cyan}[5/5] Aktualisiere Frontend...${nc}"
        update_frontend_http_provider

        echo -e "${green}✓ Abgeschlossen${nc}"
        echo -e "${cyan}Dashboard:${nc} https://$domain"
        sleep 3
        return 0
    else
        echo -e "\n${red}✗ Fehler${nc}"
        read -p "Enter..."
        return 1
    fi
}

# Frontend HTTP Provider aktualisieren
update_frontend_http_provider() {
    local traefik_config="$CONFIG_INSTALL_DIR/data/traefik-frontend/traefik.yml"

    if [ ! -f "$traefik_config" ]; then
        echo -e "${yellow}⚠ traefik.yml nicht gefunden${nc}"
        return 1
    fi

    local endpoints=""
    for i in "${!BACKEND_HOSTNAMES[@]}"; do
        if [ "${BACKEND_STATUS[$i]}" = "installed" ]; then
            endpoints="$endpoints\n    - \"http://${BACKEND_TARGET_IPS[$i]}/api\""
        fi
    done

    if [ -z "$endpoints" ]; then
        return 1
    fi

    sed -i '/# http:/,/# *pollInterval:/c\  http:\n    endpoints:'"$endpoints"'\n    pollInterval: "10s"' "$traefik_config"

    if [ "$(docker ps -q -f name=traefik-frontend)" ]; then
        (cd "$CONFIG_INSTALL_DIR" && docker compose restart traefik-frontend)
    fi
}

# Backend-Management-Menü
manage_backends() {
    while true; do
        clear
        echo -e "${bold}${cyan}Backend-Management${nc}\n"

        list_backends

        echo -e "\n${cyan}Aktionen:${nc}"
        echo -e "${cyan}1)${nc} SSH Public Key anzeigen"
        echo -e "${cyan}2)${nc} Backend hinzufügen"
        echo -e "${cyan}3)${nc} Backend konfigurieren"
        echo -e "${cyan}4)${nc} Backend installieren"
        echo -e "${cyan}5)${nc} Backend entfernen"
        echo -e "${cyan}0)${nc} Zurück\n"

        read -p "Auswahl: " choice

        case $choice in
            1) show_ssh_public_key ;;
            2) add_backend ;;
            3)
                if [ ${#BACKEND_HOSTNAMES[@]} -eq 0 ]; then
                    echo -e "${yellow}Keine Backends${nc}"
                    sleep 2
                else
                    read -p "Backend-Nummer: " num
                    configure_backend_remote $((num - 1))
                fi
                ;;
            4)
                if [ ${#BACKEND_HOSTNAMES[@]} -eq 0 ]; then
                    echo -e "${yellow}Keine Backends${nc}"
                    sleep 2
                else
                    read -p "Backend-Nummer: " num
                    install_backend_remote $((num - 1))
                fi
                ;;
            5)
                if [ ${#BACKEND_HOSTNAMES[@]} -eq 0 ]; then
                    echo -e "${yellow}Keine Backends${nc}"
                    sleep 2
                else
                    read -p "Backend-Nummer: " num
                    local idx=$((num - 1))
                    if [ $idx -ge 0 ] && [ $idx -lt ${#BACKEND_HOSTNAMES[@]} ]; then
                        unset 'BACKEND_HOSTNAMES[$idx]'
                        unset 'BACKEND_TARGET_IPS[$idx]'
                        unset 'BACKEND_TARGET_CIDR[$idx]'
                        unset 'BACKEND_DHCP_IPS[$idx]'
                        unset 'BACKEND_DOMAINS[$idx]'
                        unset 'BACKEND_STATUS[$idx]'
                        BACKEND_HOSTNAMES=("${BACKEND_HOSTNAMES[@]}")
                        BACKEND_TARGET_IPS=("${BACKEND_TARGET_IPS[@]}")
                        BACKEND_TARGET_CIDR=("${BACKEND_TARGET_CIDR[@]}")
                        BACKEND_DHCP_IPS=("${BACKEND_DHCP_IPS[@]}")
                        BACKEND_DOMAINS=("${BACKEND_DOMAINS[@]}")
                        BACKEND_STATUS=("${BACKEND_STATUS[@]}")
                        echo -e "${green}✓ Entfernt${nc}"
                        sleep 2
                    fi
                fi
                ;;
            0) return 0 ;;
            *) echo -e "${yellow}Ungültig${nc}"; sleep 1 ;;
        esac
    done
}

# Globale Konfigurationsvariablen initialisieren
init_config_vars() {
    # Installationsverzeichnis
    CONFIG_BASE_DIR="${CONFIG_BASE_DIR:-/opt/containers}"
    CONFIG_INSTALL_DIR=""

    # IP-Konfiguration
    CONFIG_IP_ENABLED=false
    CONFIG_IP=""
    CONFIG_CIDR=""
    CONFIG_GATEWAY=""
    CONFIG_DNS="8.8.8.8,1.1.1.1"

    # Hostname
    CONFIG_HOSTNAME_ENABLED=false
    CONFIG_HOSTNAME=$(hostname)

    # Dashboard-Domain
    CONFIG_DASHBOARD_DOMAIN=""

    # Let's Encrypt E-Mail
    CONFIG_ACME_EMAIL=""
    CONFIG_ACME_STAGING=false

    # Dashboard-Benutzer
    CONFIG_DASHBOARD_USER=""
    CONFIG_DASHBOARD_PASS=""

    # Backend-VMs (nur für Frontend-Modus)
    CONFIG_BACKEND_IPS=()

    # Backend-Management (erweiterte Konfiguration)
    BACKEND_HOSTNAMES=()       # Ziel-Hostname für Backend
    BACKEND_TARGET_IPS=()      # Ziel-IP-Adresse
    BACKEND_TARGET_CIDR=()     # CIDR (z.B. 24)
    BACKEND_DHCP_IPS=()        # Aktuelle DHCP-IP (temporär)
    BACKEND_DOMAINS=()         # Dashboard-Domain (auto-generiert oder custom)
    BACKEND_STATUS=()          # Status: pending, configured, installed
    BACKEND_SSH_USER="root"    # SSH-User für Backend-Zugriff
}

# Netplan-Konfiguration auslesen
read_netplan_config() {
    local interface=$1
    local netplan_file=$(find /etc/netplan -name "*.yaml" -o -name "*.yml" 2>/dev/null | head -n1)

    if [ -z "$netplan_file" ]; then
        echo "none"
        return
    fi

    # Prüfen ob DHCP konfiguriert ist
    if grep -q "dhcp4.*true" "$netplan_file" 2>/dev/null; then
        echo "dhcp"
        return
    fi

    # Statische Konfiguration
    echo "static"
}

# IP-Einstellungen konfigurieren
configure_ip_settings() {
    clear
    echo -e "${bold}${cyan}IP-Einstellungen konfigurieren${nc}\n"

    INTERFACE=$(detect_network_interface)

    if confirm "Möchten Sie die IP-Adresse dieser Maschine konfigurieren?" "$CONFIG_IP_ENABLED"; then
        CONFIG_IP_ENABLED=true

        echo -e "\n${cyan}Aktuelle Netzwerk-Konfiguration wird ausgelesen...${nc}\n"

        # Aktuelle IP auslesen
        CURRENT_IP=$(ip -4 addr show "$INTERFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
        CURRENT_CIDR=$(ip -4 addr show "$INTERFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | cut -d'/' -f2)
        CURRENT_GATEWAY=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -n1)

        # Netplan-Konfigurationstyp auslesen
        NETPLAN_TYPE=$(read_netplan_config "$INTERFACE")

        # DNS-Server auslesen
        CURRENT_DNS=$(grep "nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')

        echo -e "${yellow}Aktuelle Netzwerk-Konfiguration:${nc}"
        echo -e "  Interface: ${cyan}$INTERFACE${nc}"

        case "$NETPLAN_TYPE" in
            "dhcp")
                echo -e "  Konfigurationstyp: ${cyan}DHCP${nc}"
                echo -e "  Aktuelle IP: ${cyan}${CURRENT_IP:-nicht gesetzt}${CURRENT_CIDR:+/$CURRENT_CIDR}${nc} (via DHCP)"
                ;;
            "static")
                echo -e "  Konfigurationstyp: ${cyan}Statisch${nc}"
                echo -e "  IP-Adresse: ${cyan}${CURRENT_IP:-nicht gesetzt}${CURRENT_CIDR:+/$CURRENT_CIDR}${nc}"
                ;;
            "none")
                echo -e "  Konfigurationstyp: ${yellow}Keine netplan-Konfiguration gefunden${nc}"
                echo -e "  Aktuelle IP: ${cyan}${CURRENT_IP:-nicht gesetzt}${CURRENT_CIDR:+/$CURRENT_CIDR}${nc}"
                ;;
        esac

        echo -e "  Gateway: ${cyan}${CURRENT_GATEWAY:-nicht gesetzt}${nc}"
        echo -e "  DNS-Server: ${cyan}${CURRENT_DNS:-nicht gesetzt}${nc}"

        echo -e "\n${bold}Neue IP-Konfiguration:${nc}"

        # IP-Adresse
        read -p "IP-Adresse (z.B. 172.16.16.140) [${CONFIG_IP:-$CURRENT_IP}]: " NEW_IP
        CONFIG_IP=${NEW_IP:-${CONFIG_IP:-$CURRENT_IP}}

        # CIDR/Subnet
        read -p "CIDR/Subnetz (z.B. 24 für /24) [${CONFIG_CIDR:-$CURRENT_CIDR:-24}]: " NEW_CIDR
        CONFIG_CIDR=${NEW_CIDR:-${CONFIG_CIDR:-${CURRENT_CIDR:-24}}}

        # Gateway
        read -p "Gateway (z.B. 172.16.16.1) [${CONFIG_GATEWAY:-$CURRENT_GATEWAY}]: " NEW_GATEWAY
        CONFIG_GATEWAY=${NEW_GATEWAY:-${CONFIG_GATEWAY:-$CURRENT_GATEWAY}}

        # DNS-Server
        read -p "DNS-Server (kommagetrennt) [${CONFIG_DNS}]: " NEW_DNS
        CONFIG_DNS=${NEW_DNS:-$CONFIG_DNS}

        echo -e "\n${green}✓ IP-Einstellungen gespeichert${nc}"
        sleep 2
    else
        CONFIG_IP_ENABLED=false
        echo -e "${yellow}IP-Konfiguration wird nicht geändert${nc}"
        sleep 2
    fi
}

# Hostname konfigurieren
configure_hostname_settings() {
    clear
    echo -e "${bold}${cyan}Hostname konfigurieren${nc}\n"

    CURRENT_HOSTNAME=$(hostname)
    echo -e "${yellow}Aktueller Hostname:${nc} $CURRENT_HOSTNAME"

    if confirm "Möchten Sie den Hostnamen ändern?" "$CONFIG_HOSTNAME_ENABLED"; then
        CONFIG_HOSTNAME_ENABLED=true
        read -p "Neuer Hostname [${CONFIG_HOSTNAME}]: " NEW_HOSTNAME
        CONFIG_HOSTNAME=${NEW_HOSTNAME:-$CONFIG_HOSTNAME}
        echo -e "${green}✓ Hostname gespeichert: $CONFIG_HOSTNAME${nc}"
        sleep 2
    else
        CONFIG_HOSTNAME_ENABLED=false
        echo -e "${yellow}Hostname wird nicht geändert${nc}"
        sleep 2
    fi
}

# Dashboard-Domain konfigurieren
configure_dashboard_domain() {
    clear
    echo -e "${bold}${cyan}Dashboard-Domain konfigurieren${nc}\n"

    # Funktion zur Domain-Validierung
    validate_domain() {
        local domain_regex="^([a-zA-Z0-9][-a-zA-Z0-9]*\.)+[a-zA-Z]{2,}$"
        [[ $1 =~ $domain_regex ]]
    }

    while true; do
        if [ -n "$CONFIG_DASHBOARD_DOMAIN" ]; then
            read -p "Dashboard-Domain (ohne http/https und ohne '/') [$CONFIG_DASHBOARD_DOMAIN]: " input_domain
            dashboard_domain=${input_domain:-$CONFIG_DASHBOARD_DOMAIN}
        else
            read -p "Dashboard-Domain (ohne http/https und ohne '/'): " dashboard_domain
        fi

        # Bereinigung
        dashboard_domain=$(echo "$dashboard_domain" | sed -e 's|^http[s]\?://||' -e 's|/$||')

        if [ -z "$dashboard_domain" ]; then
            echo -e "${yellow}Domain nicht gesetzt${nc}"
            sleep 2
            return
        fi

        if validate_domain "$dashboard_domain"; then
            CONFIG_DASHBOARD_DOMAIN="$dashboard_domain"
            echo -e "${green}✓ Dashboard-Domain gespeichert: $CONFIG_DASHBOARD_DOMAIN${nc}"
            sleep 2
            return
        else
            echo -e "${red}Ungültiges Domain-Format. Bitte versuchen Sie es erneut.${nc}"
        fi
    done
}

# Let's Encrypt E-Mail konfigurieren
configure_acme_email() {
    clear
    echo -e "${bold}${cyan}Let's Encrypt E-Mail konfigurieren${nc}\n"

    # Funktion zur E-Mail-Validierung
    validate_email() {
        local email_regex="^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"
        [[ $1 =~ $email_regex ]]
    }

    while true; do
        if [ -n "$CONFIG_ACME_EMAIL" ]; then
            read -p "E-Mail-Adresse für Let's Encrypt [$CONFIG_ACME_EMAIL]: " input_email
            acme_email=${input_email:-$CONFIG_ACME_EMAIL}
        else
            read -p "E-Mail-Adresse für Let's Encrypt: " acme_email
        fi

        if [ -z "$acme_email" ]; then
            echo -e "${yellow}E-Mail nicht gesetzt${nc}"
            sleep 2
            return
        fi

        if validate_email "$acme_email"; then
            CONFIG_ACME_EMAIL="$acme_email"
            echo -e "${green}✓ E-Mail-Adresse gespeichert: $CONFIG_ACME_EMAIL${nc}"
            sleep 2
            return
        else
            echo -e "${red}Ungültige E-Mail-Adresse. Bitte versuchen Sie es erneut.${nc}"
        fi
    done
}

# Let's Encrypt Staging-Modus konfigurieren
configure_acme_staging() {
    clear
    echo -e "${bold}${cyan}Let's Encrypt Modus konfigurieren${nc}\n"

    echo -e "${yellow}Let's Encrypt hat ein Rate-Limit für Produktions-Zertifikate.${nc}"
    echo -e "${yellow}Für Tests sollten Sie den Staging-Modus verwenden!${nc}\n"

    echo -e "${cyan}Production-Modus:${nc}"
    echo -e "  • Echte, gültige SSL-Zertifikate"
    echo -e "  • ${red}Rate-Limit: 5 Zertifikate pro Woche${nc}\n"

    echo -e "${cyan}Staging-Modus:${nc}"
    echo -e "  • Test-Zertifikate (nicht vertrauenswürdig)"
    echo -e "  • ${green}Kein Rate-Limit${nc}"
    echo -e "  • Ideal zum Testen der Konfiguration\n"

    if [ "$CONFIG_ACME_STAGING" = true ]; then
        echo -e "Aktuell: ${yellow}Staging-Modus (Test)${nc}\n"
    else
        echo -e "Aktuell: ${green}Production-Modus${nc}\n"
    fi

    if confirm "Staging-Modus aktivieren?" "$CONFIG_ACME_STAGING"; then
        CONFIG_ACME_STAGING=true
        echo -e "\n${yellow}✓ Staging-Modus aktiviert - Test-Zertifikate werden verwendet${nc}"
    else
        CONFIG_ACME_STAGING=false
        echo -e "\n${green}✓ Production-Modus - Echte Zertifikate werden verwendet${nc}"
    fi

    sleep 2
}

# Dashboard-Benutzer konfigurieren
configure_dashboard_user() {
    clear
    echo -e "${bold}${cyan}Dashboard-Benutzer konfigurieren${nc}\n"

    # Benutzername
    if [ -n "$CONFIG_DASHBOARD_USER" ]; then
        read -p "Dashboard-Benutzername [$CONFIG_DASHBOARD_USER]: " input_user
        dashboard_user=${input_user:-$CONFIG_DASHBOARD_USER}
    else
        read -p "Dashboard-Benutzername: " dashboard_user
    fi

    if [ -z "$dashboard_user" ]; then
        echo -e "${yellow}Benutzername nicht gesetzt${nc}"
        sleep 2
        return
    fi

    CONFIG_DASHBOARD_USER="$dashboard_user"

    # Passwort
    if confirm "Möchten Sie ein neues Passwort setzen?" "y"; then
        read -sp "Passwort: " pwd
        echo

        if [ -z "$pwd" ]; then
            echo -e "${yellow}Passwort nicht gesetzt${nc}"
            sleep 2
            return
        fi

        # Passwort-Hash generieren (für Traefik basicauth)
        if command -v htpasswd &> /dev/null; then
            CONFIG_DASHBOARD_PASS=$(htpasswd -nb "$CONFIG_DASHBOARD_USER" "$pwd" | sed 's/\$/\$\$/g')
            echo -e "${green}✓ Dashboard-Benutzer gespeichert: $CONFIG_DASHBOARD_USER${nc}"
        else
            echo -e "${yellow}htpasswd nicht verfügbar - wird später installiert${nc}"
            # Temporär Passwort speichern für spätere Hash-Generierung
            CONFIG_DASHBOARD_PASS_PLAIN="$pwd"
        fi
    fi

    sleep 2
}

# Backend-VMs konfigurieren (nur Frontend-Modus)
configure_backend_vms() {
    clear
    echo -e "${bold}${cyan}Backend-VMs konfigurieren${nc}\n"

    if [ ${#CONFIG_BACKEND_IPS[@]} -gt 0 ]; then
        echo -e "${yellow}Aktuell konfigurierte Backend-VMs:${nc}"
        for i in "${!CONFIG_BACKEND_IPS[@]}"; do
            echo -e "  $((i+1)). ${CONFIG_BACKEND_IPS[$i]}"
        done
        echo

        if confirm "Möchten Sie die Liste neu konfigurieren?" "n"; then
            CONFIG_BACKEND_IPS=()
        else
            echo -e "${green}Bestehende Backend-VMs beibehalten${nc}"
            sleep 2
            return
        fi
    fi

    echo -e "${cyan}Geben Sie die IP-Adressen Ihrer Backend-VMs ein:${nc}"
    echo -e "${yellow}(Eine pro Zeile, leere Zeile zum Beenden)${nc}\n"

    while true; do
        read -p "Backend-VM IP $(( ${#CONFIG_BACKEND_IPS[@]} + 1 )) (Enter zum Beenden): " backend_ip
        [ -z "$backend_ip" ] && break
        CONFIG_BACKEND_IPS+=("$backend_ip")
        echo -e "${green}✓ Hinzugefügt: $backend_ip${nc}"
    done

    if [ ${#CONFIG_BACKEND_IPS[@]} -gt 0 ]; then
        echo -e "\n${green}✓ ${#CONFIG_BACKEND_IPS[@]} Backend-VM(s) konfiguriert${nc}"
    else
        echo -e "\n${yellow}Keine Backend-VMs konfiguriert${nc}"
    fi

    sleep 2
}

# Installationsverzeichnis konfigurieren
configure_install_directory() {
    clear
    echo -e "${bold}${cyan}Installationsverzeichnis konfigurieren${nc}\n"

    # Standard-Unterverzeichnisnamen ermitteln
    local default_subdir=""
    local current_subdir=""

    case "$INSTALL_TYPE" in
        "frontend")
            default_subdir="traefik-frontend"
            ;;
        "backend-standard")
            default_subdir="traefik-backend"
            ;;
        "backend-proxy")
            default_subdir="traefik-backend-proxy"
            ;;
    esac

    # Aktuelles Unterverzeichnis aus CONFIG_INSTALL_DIR extrahieren falls gesetzt
    if [ -n "$CONFIG_INSTALL_DIR" ]; then
        current_subdir="${CONFIG_INSTALL_DIR##*/}"
    else
        current_subdir="$default_subdir"
    fi

    echo -e "${yellow}Stammverzeichnis:${nc} ${cyan}$CONFIG_BASE_DIR${nc} ${blue}(im Hauptmenü änderbar)${nc}"
    echo -e "${yellow}Unterverzeichnis:${nc} ${cyan}$current_subdir${nc}\n"
    echo -e "${yellow}Vollständiger Pfad:${nc} ${green}$CONFIG_BASE_DIR/$current_subdir${nc}\n"

    read -p "Neues Unterverzeichnis [Enter = $current_subdir]: " new_subdir

    if [ -n "$new_subdir" ]; then
        # Vollständigen Pfad zusammensetzen
        CONFIG_INSTALL_DIR="${CONFIG_BASE_DIR}/${new_subdir}"
        echo -e "\n${green}✓ Installationsverzeichnis: $CONFIG_INSTALL_DIR${nc}"
    else
        # Standard beibehalten
        CONFIG_INSTALL_DIR="${CONFIG_BASE_DIR}/${current_subdir}"
        echo -e "\n${yellow}Keine Änderung - verwende: $CONFIG_INSTALL_DIR${nc}"
    fi

    sleep 2
}

# Konfigurationsmenü anzeigen
show_configuration_menu() {
    local install_type=$1
    local mode_name=""

    # Modus-Namen festlegen
    case "$install_type" in
        "frontend") mode_name="Frontend Traefik" ;;
        "backend-standard") mode_name="Backend Stack (Standard)" ;;
        "backend-proxy") mode_name="Backend Stack (Proxy-Modus)" ;;
    esac

    # Konfigurationsvariablen initialisieren
    init_config_vars

    # Bestehende Konfiguration einlesen falls vorhanden
    load_existing_config "$install_type"

    while true; do
        show_banner
        echo -e "${bold}${cyan}Konfigurationsübersicht - $mode_name${nc}\n"

        # IP-Einstellungen
        if [ "$CONFIG_IP_ENABLED" = true ]; then
            echo -e "${cyan}1)${nc} IP-Einstellungen        ${green}[Aktiviert: $CONFIG_IP/$CONFIG_CIDR via $CONFIG_GATEWAY]${nc}"
        else
            echo -e "${cyan}1)${nc} IP-Einstellungen        ${yellow}[Nicht konfiguriert]${nc}"
        fi

        # Hostname
        if [ "$CONFIG_HOSTNAME_ENABLED" = true ]; then
            echo -e "${cyan}2)${nc} Hostname                ${green}[Wird geändert zu: $CONFIG_HOSTNAME]${nc}"
        else
            echo -e "${cyan}2)${nc} Hostname                ${yellow}[Wird nicht geändert: $(hostname)]${nc}"
        fi

        # Dashboard-Domain
        if [ -n "$CONFIG_DASHBOARD_DOMAIN" ]; then
            echo -e "${cyan}3)${nc} Dashboard-Domain        ${green}[$CONFIG_DASHBOARD_DOMAIN]${nc}"
        else
            echo -e "${cyan}3)${nc} Dashboard-Domain        ${yellow}[Nicht konfiguriert]${nc}"
        fi

        # Let's Encrypt E-Mail (nicht im Proxy-Modus)
        if [ "$install_type" != "backend-proxy" ]; then
            if [ -n "$CONFIG_ACME_EMAIL" ]; then
                echo -e "${cyan}4)${nc} Let's Encrypt E-Mail    ${green}[$CONFIG_ACME_EMAIL]${nc}"
            else
                echo -e "${cyan}4)${nc} Let's Encrypt E-Mail    ${yellow}[Nicht konfiguriert]${nc}"
            fi
        fi

        # Dashboard-Benutzer
        if [ -n "$CONFIG_DASHBOARD_USER" ] && [ -n "$CONFIG_DASHBOARD_PASS" ]; then
            echo -e "${cyan}5)${nc} Dashboard-Benutzer      ${green}[$CONFIG_DASHBOARD_USER + Passwort]${nc}"
        elif [ -n "$CONFIG_DASHBOARD_USER" ]; then
            echo -e "${cyan}5)${nc} Dashboard-Benutzer      ${yellow}[$CONFIG_DASHBOARD_USER - Passwort fehlt!]${nc}"
        else
            echo -e "${cyan}5)${nc} Dashboard-Benutzer      ${yellow}[Nicht konfiguriert]${nc}"
        fi

        # Backend-VMs (nur Frontend-Modus)
        if [ "$install_type" = "frontend" ]; then
            if [ ${#CONFIG_BACKEND_IPS[@]} -gt 0 ]; then
                echo -e "${cyan}6)${nc} Backend-VMs             ${green}[${#CONFIG_BACKEND_IPS[@]} VM(s): ${CONFIG_BACKEND_IPS[*]}]${nc}"
            else
                echo -e "${cyan}6)${nc} Backend-VMs             ${yellow}[Keine konfiguriert]${nc}"
            fi
        fi

        # Installationsverzeichnis
        if [ -z "$CONFIG_INSTALL_DIR" ]; then
            case "$install_type" in
                "frontend") CONFIG_INSTALL_DIR="${CONFIG_BASE_DIR}/traefik-frontend" ;;
                "backend-standard") CONFIG_INSTALL_DIR="${CONFIG_BASE_DIR}/traefik-backend" ;;
                "backend-proxy") CONFIG_INSTALL_DIR="${CONFIG_BASE_DIR}/traefik-backend-proxy" ;;
            esac
        fi
        echo -e "${cyan}7)${nc} Installationsverzeichnis ${green}[$CONFIG_INSTALL_DIR]${nc}"

        # Let's Encrypt Staging (nicht im Proxy-Modus)
        if [ "$install_type" != "backend-proxy" ]; then
            if [ "$CONFIG_ACME_STAGING" = true ]; then
                echo -e "${cyan}8)${nc} Let's Encrypt Modus     ${yellow}[Staging - Test-Zertifikate]${nc}"
            else
                echo -e "${cyan}8)${nc} Let's Encrypt Modus     ${green}[Production]${nc}"
            fi
        fi

        # Installation starten / Abbrechen
        echo -e "\n${cyan}9)${nc} ${green}${bold}Installation starten${nc}"
        echo -e "${cyan}0)${nc} Abbrechen\n"

        read -p "Ihre Auswahl [0-9]: " config_choice

        case $config_choice in
            1) configure_ip_settings ;;
            2) configure_hostname_settings ;;
            3) configure_dashboard_domain ;;
            4)
                if [ "$install_type" != "backend-proxy" ]; then
                    configure_acme_email
                else
                    echo -e "${yellow}Ungültige Auswahl${nc}"
                    sleep 1
                fi
                ;;
            5) configure_dashboard_user ;;
            6)
                if [ "$install_type" = "frontend" ]; then
                    manage_backends
                else
                    echo -e "${yellow}Ungültige Auswahl${nc}"
                    sleep 1
                fi
                ;;
            7) configure_install_directory ;;
            8)
                if [ "$install_type" != "backend-proxy" ]; then
                    configure_acme_staging
                else
                    echo -e "${yellow}Ungültige Auswahl${nc}"
                    sleep 1
                fi
                ;;
            9)
                # Validierung vor Start
                if validate_configuration "$install_type"; then
                    return 0
                fi
                ;;
            0)
                error_exit "Installation abgebrochen"
                ;;
            *)
                echo -e "${yellow}Ungültige Auswahl${nc}"
                sleep 1
                ;;
        esac
    done
}

# Bestehende Konfiguration einlesen
load_existing_config() {
    local install_type=$1

    # Zuerst versuchen .install.conf zu laden
    if load_installation_config; then
        echo -e "${green}✓ Gespeicherte Konfiguration wiederverwendet${nc}"
        sleep 1
        return 0
    fi

    # Fallback: Aus .env und config-Dateien auslesen
    if [ "$install_type" = "frontend" ]; then
        # Frontend-Konfiguration einlesen
        if [ -f ".env" ]; then
            CONFIG_ACME_EMAIL=$(grep "^ACME_EMAIL=" .env 2>/dev/null | cut -d'=' -f2)
            local dashboard_host=$(grep "^SERVICES_TRAEFIK_LABELS_TRAEFIK_HOST=" .env 2>/dev/null | cut -d'=' -f2)
            # Extrahiere Domain aus HOST(`domain`)
            CONFIG_DASHBOARD_DOMAIN=$(echo "$dashboard_host" | grep -oP 'HOST\(`\K[^`]+')
        fi

        if [ -f "compose/traefik.yml" ]; then
            # Dashboard-Benutzer auslesen
            CONFIG_DASHBOARD_USER=$(grep -oP 'basicauth.users:.*"\K[^:]+' compose/traefik.yml 2>/dev/null | head -n1)
        fi

        if [ -f "data/traefik-frontend/traefik.yml" ]; then
            # Backend IPs auslesen
            mapfile -t CONFIG_BACKEND_IPS < <(grep -oP 'http://\K[0-9.]+(?=/api)' data/traefik-frontend/traefik.yml 2>/dev/null)
        fi
    else
        # Backend-Konfiguration einlesen
        if [ -f "data/traefik/traefik.yml" ]; then
            CONFIG_ACME_EMAIL=$(grep -oP 'email:\s*"\K[^"]+' data/traefik/traefik.yml 2>/dev/null | head -n1)
        fi

        if [ -f ".env" ]; then
            local dashboard_host=$(grep "^SERVICES_TRAEFIK_LABELS_TRAEFIK_HOST=" .env 2>/dev/null | cut -d'=' -f2)
            # Extrahiere Domain aus HOST(`domain`)
            CONFIG_DASHBOARD_DOMAIN=$(echo "$dashboard_host" | grep -oP 'HOST\(`\K[^`]+')
        fi
    fi

    # Bereinige ungültige Werte
    [ "$CONFIG_ACME_EMAIL" = "your@email.com" ] && CONFIG_ACME_EMAIL=""
    [ "$CONFIG_DASHBOARD_DOMAIN" = "traefik.yourdomain.com" ] && CONFIG_DASHBOARD_DOMAIN=""
}

# Konfiguration validieren
validate_configuration() {
    local install_type=$1
    local errors=()

    # Dashboard-Domain ist Pflicht
    [ -z "$CONFIG_DASHBOARD_DOMAIN" ] && errors+=("Dashboard-Domain muss konfiguriert sein")

    # Let's Encrypt E-Mail ist Pflicht (außer Proxy-Modus)
    if [ "$install_type" != "backend-proxy" ]; then
        [ -z "$CONFIG_ACME_EMAIL" ] && errors+=("Let's Encrypt E-Mail muss konfiguriert sein")
    fi

    # Dashboard-Benutzer ist Pflicht
    [ -z "$CONFIG_DASHBOARD_USER" ] && errors+=("Dashboard-Benutzer muss konfiguriert sein")

    # Dashboard-Passwort prüfen (wenn User gesetzt aber kein Pass)
    if [ -n "$CONFIG_DASHBOARD_USER" ] && [ -z "$CONFIG_DASHBOARD_PASS" ]; then
        errors+=("Dashboard-Passwort fehlt (Benutzer: $CONFIG_DASHBOARD_USER)")
    fi

    if [ ${#errors[@]} -gt 0 ]; then
        echo -e "\n${red}${bold}Folgende Konfigurationen fehlen:${nc}"
        for error in "${errors[@]}"; do
            echo -e "${red}  ✗ $error${nc}"
        done
        echo -e "\n${yellow}Bitte konfigurieren Sie die fehlenden Werte im Menü.${nc}"
        read -p "Drücken Sie Enter um fortzufahren..."
        return 1
    fi

    # Bestätigung
    clear
    echo -e "${bold}${cyan}Konfiguration abgeschlossen${nc}\n"
    echo -e "${yellow}Die Installation wird mit folgenden Einstellungen gestartet:${nc}\n"

    [ "$CONFIG_IP_ENABLED" = true ] && echo -e "  ${cyan}IP:${nc} $CONFIG_IP/$CONFIG_CIDR (Gateway: $CONFIG_GATEWAY)"
    [ "$CONFIG_HOSTNAME_ENABLED" = true ] && echo -e "  ${cyan}Hostname:${nc} $CONFIG_HOSTNAME"
    echo -e "  ${cyan}Dashboard-Domain:${nc} $CONFIG_DASHBOARD_DOMAIN"
    [ -n "$CONFIG_ACME_EMAIL" ] && echo -e "  ${cyan}Let's Encrypt E-Mail:${nc} $CONFIG_ACME_EMAIL"
    echo -e "  ${cyan}Dashboard-Benutzer:${nc} $CONFIG_DASHBOARD_USER"
    [ ${#CONFIG_BACKEND_IPS[@]} -gt 0 ] && echo -e "  ${cyan}Backend-VMs:${nc} ${CONFIG_BACKEND_IPS[*]}"

    echo
    if confirm "Mit der Installation fortfahren?" "y"; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Docker Installation
# =============================================================================

check_and_install_docker() {
    show_step 1 10 "Überprüfe Docker Installation"

    if command -v docker &> /dev/null; then
        step_done "Docker ist bereits installiert ($(docker --version))"
        return 0
    fi

    echo -e "${yellow}Docker ist nicht installiert${nc}"

    if confirm "Möchten Sie Docker jetzt installieren?" "y"; then
        echo -e "${cyan}Installiere Docker...${nc}"

        # Docker Installation
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        rm get-docker.sh

        # Docker Compose Plugin prüfen
        if ! docker compose version &> /dev/null; then
            echo -e "${yellow}Docker Compose Plugin wird installiert...${nc}"
            sudo apt-get update
            sudo apt-get install -y docker-compose-plugin
        fi

        # Aktuellen Benutzer zur Docker-Gruppe hinzufügen
        sudo usermod -aG docker $USER

        step_done "Docker erfolgreich installiert"
        echo -e "${yellow}Hinweis: Möglicherweise müssen Sie sich neu anmelden, damit die Docker-Gruppenzugehörigkeit wirksam wird${nc}"
    else
        error_exit "Docker wird benötigt. Bitte installieren Sie Docker manuell: https://docs.docker.com/engine/install/"
    fi
}

# =============================================================================
# Let's Encrypt Zertifikat Wartefunktion
# =============================================================================

wait_for_letsencrypt_certificate() {
    local domain=$1
    local max_wait=90  # Maximum 90 Sekunden warten
    local waited=0

    echo -e "\n${cyan}${bold}Let's Encrypt Zertifikat Setup${nc}"
    echo -e "${yellow}Das Zertifikat wird beim ersten Request erstellt...${nc}\n"

    # 1. DNS-Check
    echo -e "${cyan}[1/4] Prüfe DNS-Konfiguration...${nc}"
    local resolved_ip=$(dig +short "$domain" A | head -n1)
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null)

    if [ -z "$resolved_ip" ]; then
        echo -e "${red}✗ Domain kann nicht aufgelöst werden${nc}"
        echo -e "${yellow}⚠ Bitte konfigurieren Sie DNS für $domain${nc}"
        echo -e "${yellow}⚠ Das Zertifikat wird erstellt sobald DNS konfiguriert ist${nc}"
        return 1
    fi

    echo -e "${green}✓ DNS aufgelöst: $domain → $resolved_ip${nc}"

    if [ -n "$server_ip" ] && [ "$resolved_ip" != "$server_ip" ]; then
        echo -e "${yellow}⚠ Warnung: Domain zeigt auf $resolved_ip, Server-IP ist $server_ip${nc}"
        echo -e "${yellow}⚠ Let's Encrypt benötigt korrekte DNS-Konfiguration${nc}"
    fi

    # 2. Kurz warten damit Traefik vollständig gestartet ist
    echo -e "\n${cyan}[2/4] Warte auf Traefik-Start...${nc}"
    sleep 5
    echo -e "${green}✓ Traefik sollte bereit sein${nc}"

    # 3. Initialen Request machen (triggert ACME Challenge)
    echo -e "\n${cyan}[3/4] Triggere ACME Challenge...${nc}"
    # -k erlaubt ungültiges Zertifikat, -L folgt Redirects, -s silent, -o /dev/null
    if curl -kLs -o /dev/null -w "%{http_code}" --connect-timeout 10 "https://${domain}" > /dev/null 2>&1; then
        echo -e "${green}✓ Initialer Request erfolgreich - ACME Challenge gestartet${nc}"
    else
        echo -e "${yellow}⚠ Request fehlgeschlagen - Domain evtl. nicht erreichbar${nc}"
    fi

    # 4. Warte auf Zertifikatserstellung
    echo -e "\n${cyan}[4/4] Warte auf Let's Encrypt Zertifikat...${nc}"
    echo -e "${yellow}Dies kann 30-60 Sekunden dauern${nc}\n"

    sleep 10  # Initiale Wartezeit für ACME

    while [ $waited -lt $max_wait ]; do
        # Prüfe ob Zertifikat vorhanden und gültig ist
        cert_issuer=$(echo | timeout 5 openssl s_client -servername "${domain}" -connect "localhost:443" 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null)

        # Prüfe je nach Modus auf den richtigen Issuer
        if [ "$CONFIG_ACME_STAGING" = true ]; then
            # Staging-Modus: Prüfe auf "Fake LE" (Staging-Issuer)
            if echo "$cert_issuer" | grep -qE "(Fake LE|Staging|STAGING)"; then
                echo -e "\n${green}${bold}✓ Let's Encrypt Staging-Zertifikat erfolgreich erstellt!${nc}"
                echo -e "${yellow}⚠ Dies ist ein Test-Zertifikat (nicht vertrauenswürdig)${nc}"
                echo -e "${green}✓ ACME-Konfiguration funktioniert korrekt${nc}"
                return 0
            fi
        else
            # Production-Modus: Prüfe auf "Let's Encrypt"
            if echo "$cert_issuer" | grep -q "Let's Encrypt"; then
                echo -e "\n${green}${bold}✓ Let's Encrypt Zertifikat erfolgreich erstellt!${nc}"
                echo -e "${green}✓ Die Domain ist nun sicher erreichbar unter https://${domain}${nc}"
                return 0
            fi
        fi

        # Fortschrittsanzeige
        printf "\r${yellow}Warte... [%2d/%d Sekunden]${nc}" "$waited" "$max_wait"
        sleep 5
        waited=$((waited + 5))
    done

    # Timeout erreicht
    echo -e "\n\n${yellow}⚠ Zeitüberschreitung beim Warten auf das Zertifikat${nc}"
    echo -e "${yellow}Mögliche Ursachen:${nc}"
    echo -e "  • DNS zeigt nicht auf den richtigen Server"
    echo -e "  • Port 80 ist nicht von außen erreichbar (für HTTP-Challenge)"
    if [ "$CONFIG_ACME_STAGING" != true ]; then
        echo -e "  • Let's Encrypt Rate Limits erreicht (5/Woche)"
        echo -e "    ${cyan}→ Verwenden Sie den Staging-Modus zum Testen${nc}"
    fi
    echo -e "\n${cyan}Das Zertifikat wird im Hintergrund erstellt.${nc}"
    echo -e "${cyan}Versuchen Sie die Seite in 2-3 Minuten erneut aufzurufen.${nc}"
    return 1
}

# =============================================================================
# Frontend Traefik Installation
# =============================================================================

install_frontend_traefik() {
    echo -e "\n${bold}${cyan}Installation: Frontend Traefik${nc}\n"

    total_steps=8
    current_step=2

    # Arbeitsverzeichnis prüfen
    show_step $current_step $total_steps "Prüfe Arbeitsverzeichnis"
    echo -e "${cyan}Arbeitsverzeichnis: $(pwd)${nc}"
    step_done "Arbeitsverzeichnis geprüft"
    ((current_step++))

    # Konfigurationsdateien kopieren/aktualisieren
    show_step $current_step $total_steps "Bereite Konfigurationsdateien vor"

    # Verzeichnisse erstellen falls nicht vorhanden
    mkdir -p data/traefik-frontend/certs /var/log/traefik

    # Dateien kopieren falls nicht vorhanden
    [ ! -f ".env" ] && cp .env.sample .env
    [ ! -f "compose/traefik.yml" ] && cp compose/traefik.yml.sample compose/traefik.yml
    [ ! -f "data/traefik-frontend/traefik.yml" ] && cp data/traefik-frontend/traefik.yml.sample data/traefik-frontend/traefik.yml
    [ ! -f "data/traefik-frontend/certs/acme.json" ] && cp data/traefik-frontend/certs/acme.json.sample data/traefik-frontend/certs/acme.json
    chmod 600 data/traefik-frontend/certs/acme.json

    step_done "Konfigurationsdateien vorbereitet"
    ((current_step++))

    # Konfigurationswerte aus Menü anwenden
    show_step $current_step $total_steps "Wende Konfiguration an"

    # ABSOLUTE_PATH setzen
    sed -i "s|ABSOLUTE_PATH=.*|ABSOLUTE_PATH=$(pwd)|g" .env

    # E-Mail für Let's Encrypt
    sed -i "s/ACME_EMAIL=.*/ACME_EMAIL=$CONFIG_ACME_EMAIL/g" .env
    sed -i "s/email: \".*\"/email: \"$CONFIG_ACME_EMAIL\"/g" data/traefik-frontend/traefik.yml

    # Let's Encrypt Staging-Modus
    if [ "$CONFIG_ACME_STAGING" = true ]; then
        # Staging caServer hinzufügen
        sed -i '/email: /a\      caServer: "https://acme-staging-v02.api.letsencrypt.org/directory"' data/traefik-frontend/traefik.yml
        echo -e "${yellow}Staging-Modus aktiviert - Test-Zertifikate werden verwendet${nc}"
    else
        # Production (caServer-Zeile entfernen falls vorhanden)
        sed -i '/caServer: /d' data/traefik-frontend/traefik.yml
        echo -e "${green}Production-Modus - Echte Zertifikate werden verwendet${nc}"
    fi

    # Dashboard-Domain
    sed -i "s|SERVICES_TRAEFIK_LABELS_TRAEFIK_HOST=.*|SERVICES_TRAEFIK_LABELS_TRAEFIK_HOST=HOST(\`$CONFIG_DASHBOARD_DOMAIN\`)|g" .env

    # Dashboard-Authentifizierung
    if [ -n "$CONFIG_DASHBOARD_PASS" ]; then
        sed -i "s|traefik.http.middlewares.dashboard-auth.basicauth.users:.*|traefik.http.middlewares.dashboard-auth.basicauth.users: \"$CONFIG_DASHBOARD_PASS\"|g" compose/traefik.yml
    elif [ -n "$CONFIG_DASHBOARD_PASS_PLAIN" ]; then
        # Falls htpasswd vorher nicht verfügbar war, jetzt Hash generieren
        DASHBOARD_PASS=$(htpasswd -nb "$CONFIG_DASHBOARD_USER" "$CONFIG_DASHBOARD_PASS_PLAIN" | sed 's/\$/\$\$/g')
        sed -i "s|traefik.http.middlewares.dashboard-auth.basicauth.users:.*|traefik.http.middlewares.dashboard-auth.basicauth.users: \"$DASHBOARD_PASS\"|g" compose/traefik.yml
    fi

    step_done "Konfiguration angewendet"
    ((current_step++))

    # Backend-VMs konfigurieren
    show_step $current_step $total_steps "Konfiguriere Backend-VMs"

    # HTTP Provider Endpoints generieren
    if [ ${#CONFIG_BACKEND_IPS[@]} -gt 0 ]; then
        ENDPOINTS=""
        for ip in "${CONFIG_BACKEND_IPS[@]}"; do
            ENDPOINTS="$ENDPOINTS\n    - \"http://$ip/api\""
        done

        # HTTP Provider aktivieren und Endpoints setzen
        sed -i '/# http:/,/# *pollInterval:/c\  http:\n    endpoints:'"$ENDPOINTS"'\n    pollInterval: "10s"' data/traefik-frontend/traefik.yml

        echo -e "${green}${#CONFIG_BACKEND_IPS[@]} Backend-VM(s) konfiguriert${nc}"
    else
        echo -e "${yellow}Keine Backend-VMs konfiguriert${nc}"
        echo -e "${yellow}HTTP Provider bleibt deaktiviert${nc}"
    fi

    step_done "Backend-VMs konfiguriert"
    ((current_step++))

    # Firewall konfigurieren
    show_step $current_step $total_steps "Konfiguriere Firewall"
    if command -v ufw &> /dev/null; then
        if confirm "Möchten Sie die Firewall-Ports (80, 443) automatisch öffnen?" "y"; then
            sudo ufw allow 80/tcp
            sudo ufw allow 443/tcp
            step_done "Firewall-Ports geöffnet"
        else
            echo -e "${yellow}Bitte öffnen Sie manuell die Ports 80 und 443${nc}"
            step_done "Firewall-Konfiguration übersprungen"
        fi
    else
        echo -e "${yellow}UFW nicht gefunden. Bitte öffnen Sie manuell die Ports 80 und 443${nc}"
        step_done "Firewall-Konfiguration übersprungen"
    fi
    ((current_step++))

    # Docker Compose Datei umbenennen für einfachere Nutzung
    show_step $current_step $total_steps "Finalisiere Installation"
    if [ -f "docker-compose.frontend.yml" ]; then
        mv docker-compose.frontend.yml docker-compose.yml
        echo -e "${green}✓ docker-compose.yml erstellt${nc}"
    fi
    step_done "Installation finalisiert"
    ((current_step++))

    # Stack starten
    show_step $current_step $total_steps "Starte Frontend Traefik"

    # Prüfen, ob Container bereits läuft
    if [ "$(docker ps -q -f name=traefik-frontend)" ]; then
        echo -e "${yellow}Container 'traefik-frontend' läuft bereits${nc}"
        if ! confirm "Container läuft bereits. Neu starten?" "n"; then
            echo -e "${yellow}Start übersprungen${nc}"
            save_installation_config
            return 0
        fi
        echo -e "${cyan}Stoppe laufende Container...${nc}"
        docker compose down
    fi

    if confirm "Möchten Sie den Frontend Traefik jetzt starten?" "y"; then
        docker compose up -d
        step_done "Frontend Traefik gestartet"

        # Warte auf Let's Encrypt Zertifikat
        wait_for_letsencrypt_certificate "$CONFIG_DASHBOARD_DOMAIN"

        # Konfiguration speichern
        save_installation_config

        echo -e "\n${green}${bold}Installation abgeschlossen!${nc}\n"
        echo -e "${cyan}Dashboard erreichbar unter:${nc} https://$CONFIG_DASHBOARD_DOMAIN"
        echo -e "${cyan}Benutzername:${nc} $CONFIG_DASHBOARD_USER"
        echo -e "\n${cyan}Zum Verwalten des Stacks:${nc}"
        echo -e "  Start:   docker compose up -d"
        echo -e "  Stop:    docker compose down"
        echo -e "  Logs:    docker compose logs -f traefik-frontend"
        echo -e "\n${cyan}Installationsverzeichnis:${nc} $(pwd)"
    else
        step_done "Start übersprungen"

        # Konfiguration trotzdem speichern
        save_installation_config

        echo -e "\n${yellow}Sie können den Stack später mit diesem Befehl starten:${nc}"
        echo -e "  cd $(pwd) && docker compose up -d"
    fi
}

# =============================================================================
# Backend Stack Installation (bestehende Logik aus first_install.sh)
# =============================================================================

install_backend_stack() {
    local use_proxy_mode=$1

    echo -e "\n${bold}${cyan}Installation: Backend Stack${nc}"
    if [ "$use_proxy_mode" = true ]; then
        echo -e "${cyan}Modus: Mit vorgeschaltetem Traefik (Proxy-Modus)${nc}\n"
    else
        echo -e "${cyan}Modus: Standard (mit SSL/TLS)${nc}\n"
    fi

    # Hier kommt die bestehende Logik aus first_install.sh
    # Ich werde die relevanten Teile hier einfügen

    total_steps=18
    current_step=2

    # Arbeitsverzeichnis prüfen
    show_step $current_step $total_steps "Prüfe Arbeitsverzeichnis"
    echo -e "${cyan}Arbeitsverzeichnis: $(pwd)${nc}"
    step_done "Arbeitsverzeichnis geprüft"
    ((current_step++))

    # Installiere apache2-utils
    show_step $current_step $total_steps "Installiere apache2-utils, falls erforderlich"
    command -v htpasswd >/dev/null 2>&1 || { sudo apt update && sudo apt install -y apache2-utils; }
    step_done "apache2-utils installiert"
    ((current_step++))

    # Bestehende Konfiguration prüfen
    show_step $current_step $total_steps "Prüfe bestehende Konfiguration"
    EXISTING_CONFIG=false
    EXISTING_EMAIL=""
    EXISTING_DASHBOARD_DOMAIN=""

    if [ -f "data/traefik/traefik.yml" ]; then
        EXISTING_CONFIG=true
        EXISTING_EMAIL=$(grep -oP 'email:\s*"\K[^"]+' data/traefik/traefik.yml 2>/dev/null | head -n1)
        echo -e "${yellow}Bestehende Traefik-Konfiguration gefunden!${nc}"
        [ -n "$EXISTING_EMAIL" ] && echo -e "${cyan}E-Mail: $EXISTING_EMAIL${nc}"
    fi

    if [ -f "data/traefik/dynamic_conf/http.middlewares.traefik-dashboard-auth.yml" ]; then
        EXISTING_DASHBOARD_DOMAIN=$(grep -oP 'Host\(`\K[^`]+' data/traefik/dynamic_conf/http.middlewares.traefik-dashboard-auth.yml 2>/dev/null | head -n1)
        [ -n "$EXISTING_DASHBOARD_DOMAIN" ] && echo -e "${cyan}Dashboard-Domain: $EXISTING_DASHBOARD_DOMAIN${nc}"
    fi

    step_done "Konfiguration geprüft"
    ((current_step++))

    # Überprüfen, ob Container laufen
    show_step $current_step $total_steps "Überprüfen von laufenden Containern"
    containers=("crowdsec" "socket-proxy" "traefik" "traefik_crowdsec_bouncer")
    running_containers=false
    for container in "${containers[@]}"; do
        if [ "$(docker ps -q -f name=$container)" ]; then
            running_containers=true
            echo -e "${yellow}Container '$container' läuft bereits${nc}"
        fi
    done

    if [ "$running_containers" = true ]; then
        if ! confirm "Container laufen bereits. Möchten Sie trotzdem fortfahren? (Bestehende Container werden gestoppt)" "n"; then
            error_exit "Installation abgebrochen"
        fi
        echo -e "${cyan}Stoppe laufende Container...${nc}"
        docker compose down 2>/dev/null || true
    fi

    step_done "Container-Status überprüft"
    ((current_step++))

    # Netzwerke überprüfen (nur Warnung, kein Abbruch mehr)
    show_step $current_step $total_steps "Überprüfen von Netzwerken"
    networks=("proxy" "socket_proxy" "crowdsec")
    for network in "${networks[@]}"; do
        if [ "$(docker network ls -q -f name=^${network}$)" ]; then
            echo -e "${yellow}Netzwerk '$network' existiert bereits${nc}"
        fi
    done
    step_done "Netzwerk-Status überprüft"
    ((current_step++))

    # Dateien kopieren
    show_step $current_step $total_steps "Kopiere erforderliche Dateien"

    # Basis-Dateien
    files_to_copy=(
        ".env.sample .env"
        "data/crowdsec/.env.sample data/crowdsec/.env"
        "data/socket-proxy/.env.sample data/socket-proxy/.env"
        "data/traefik/.env.sample data/traefik/.env"
        "data/traefik/certs/acme_letsencrypt.json.sample data/traefik/certs/acme_letsencrypt.json"
        "data/traefik/certs/tls_letsencrypt.json.sample data/traefik/certs/tls_letsencrypt.json"
        "data/traefik/dynamic_conf/http.middlewares.default.yml.sample data/traefik/dynamic_conf/http.middlewares.default.yml"
        "data/traefik/dynamic_conf/http.middlewares.default-security-headers.yml.sample data/traefik/dynamic_conf/http.middlewares.default-security-headers.yml"
        "data/traefik/dynamic_conf/http.middlewares.gzip.yml.sample data/traefik/dynamic_conf/http.middlewares.gzip.yml"
        "data/traefik/dynamic_conf/http.middlewares.traefik-bouncer.yml.sample data/traefik/dynamic_conf/http.middlewares.traefik-bouncer.yml"
        "data/traefik/dynamic_conf/http.middlewares.traefik-dashboard-auth.yml.sample data/traefik/dynamic_conf/http.middlewares.traefik-dashboard-auth.yml"
        "data/traefik/dynamic_conf/tls.yml.sample data/traefik/dynamic_conf/tls.yml"
        "data/traefik-crowdsec-bouncer/.env.sample data/traefik-crowdsec-bouncer/.env"
    )

    # Je nach Modus die entsprechende Traefik-Konfiguration hinzufügen
    if [ "$use_proxy_mode" = true ]; then
        files_to_copy+=("data/traefik/traefik.yml.proxy.sample data/traefik/traefik.yml")
        files_to_copy+=("docker-compose.yml.proxy.sample docker-compose.yml")
    else
        files_to_copy+=("data/traefik/traefik.yml.sample data/traefik/traefik.yml")
    fi

    # Dateien kopieren (nur wenn nicht vorhanden)
    for file_pair in "${files_to_copy[@]}"; do
        src=$(echo $file_pair | awk '{print $1}')
        dst=$(echo $file_pair | awk '{print $2}')

        src_path="${src}"
        dst_path="${dst}"

        if [ -f "$dst_path" ]; then
            echo -e "${yellow}Behalte bestehende Datei: ${dst}${nc}"
        elif [ -f "$src_path" ]; then
            cp "$src_path" "$dst_path"
            echo -e "${green}Kopiere neue Datei: ${dst}${nc}"
        else
            error_exit "Die Datei ${src_path} existiert nicht."
        fi
    done

    sudo chmod 600 data/traefik/certs/acme_letsencrypt.json
    sudo chmod 600 data/traefik/certs/tls_letsencrypt.json

    step_done "Dateien kopiert und Rechte gesetzt"
    ((current_step++))

    # CrowdSec-Repository
    show_step $current_step $total_steps "Überprüfung: CrowdSec-Repository"
    if confirm "Ist das CrowdSec-Repository bereits in deinen Paketquellen vorhanden?" "n"; then
        echo "Das CrowdSec-Repository ist bereits vorhanden. Installation wird übersprungen."
    else
        echo "Das CrowdSec-Repository wird installiert..."
        curl -s https://install.crowdsec.net | sudo sh
        echo "CrowdSec-Repository erfolgreich installiert."
    fi
    step_done "CrowdSec-Repository überprüft und ggf. installiert"
    ((current_step++))

    # OpenSSL installieren
    show_step $current_step $total_steps "Überprüfen von OpenSSL"
    command -v openssl >/dev/null 2>&1 || { sudo apt update && sudo apt install -y openssl; }
    step_done "OpenSSL überprüft"
    ((current_step++))

    # Bouncer-Passwörter generieren
    show_step $current_step $total_steps "Generiere Bouncer-Passwörter"
    BOUNCER_KEY_TRAEFIK_PASSWORD=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9!@#$%^&*()-_=+[]{}<>?|')
    echo -e "\nBOUNCER_KEY_TRAEFIK=$BOUNCER_KEY_TRAEFIK_PASSWORD" >> .env
    sleep 1
    BOUNCER_KEY_FIREWALL_PASSWORD=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9!@#$%^&*()-_=+[]{}<>?|')
    echo "BOUNCER_KEY_FIREWALL=$BOUNCER_KEY_FIREWALL_PASSWORD" >> .env
    step_done "Bouncer-Passwörter generiert"
    ((current_step++))

    # E-Mail-Adresse für SSL-Zertifikate (nur im Standard-Modus)
    if [ "$use_proxy_mode" = false ]; then
        show_step $current_step $total_steps "Konfiguriere E-Mail-Adresse für SSL-Zertifikate"

        # Funktion zur E-Mail-Validierung
        validate_email() {
            local email_regex="^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"
            [[ $1 =~ $email_regex ]]
        }

        # Benutzer nach E-Mail-Adresse fragen (mit Default wenn vorhanden)
        ssl_email=""
        while true; do
            if [ -n "$EXISTING_EMAIL" ] && [ "$EXISTING_EMAIL" != "your@email.com" ]; then
                read -p "E-Mail-Adresse für SSL-Zertifikate [$EXISTING_EMAIL]: " input_email
                ssl_email=${input_email:-$EXISTING_EMAIL}
            else
                read -p "Bitte gib deine E-Mail-Adresse für die SSL-Zertifikate ein: " ssl_email
            fi

            if validate_email "$ssl_email"; then
                echo -e "${green}Gültige E-Mail-Adresse: $ssl_email${nc}"
                break
            else
                echo -e "${red}Ungültige E-Mail-Adresse. Bitte versuche es erneut.${nc}"
                EXISTING_EMAIL=""  # Bei ungültiger Eingabe kein Default mehr anbieten
            fi
        done

        # E-Mail-Adresse in traefik.yml setzen
        traefik_config_file="data/traefik/traefik.yml"
        if [ ! -f "$traefik_config_file" ]; then
            error_exit "Die Datei $traefik_config_file existiert nicht."
        fi
        sed -i "s/email: \".*\"/email: \"$ssl_email\"/g" "$traefik_config_file"

        # Let's Encrypt Staging-Modus
        if [ "$CONFIG_ACME_STAGING" = true ]; then
            # Staging caServer hinzufügen
            sed -i '/email: /a\      caServer: "https://acme-staging-v02.api.letsencrypt.org/directory"' "$traefik_config_file"
            echo -e "${yellow}Staging-Modus aktiviert - Test-Zertifikate werden verwendet${nc}"
        else
            # Production (caServer-Zeile entfernen falls vorhanden)
            sed -i '/caServer: /d' "$traefik_config_file"
            echo -e "${green}Production-Modus - Echte Zertifikate werden verwendet${nc}"
        fi

        step_done "SSL-Zertifikat E-Mail-Adresse gesetzt"
        ((current_step++))
    else
        show_step $current_step $total_steps "Überspringe SSL-Zertifikat E-Mail (Proxy-Modus)"
        echo "Im Proxy-Modus übernimmt der vorgeschaltete Traefik das Zertifikats-Handling."
        step_done "SSL-Zertifikat E-Mail übersprungen (Proxy-Modus)"
        ((current_step++))
    fi

    # Wunsch-Domain für Traefik-Dashboard
    show_step $current_step $total_steps "Konfiguriere Wunsch-Domain für Traefik-Dashboard"

    env_file=".env"
    if [ ! -f "$env_file" ]; then
        error_exit "Die Datei $env_file existiert nicht."
    fi

    # Funktion zur Domain-Validierung
    validate_domain() {
        local domain_regex="^([a-zA-Z0-9][-a-zA-Z0-9]*\.)+[a-zA-Z]{2,}$"
        [[ $1 =~ $domain_regex ]]
    }

    # Benutzer nach Domain fragen (mit Default wenn vorhanden)
    dashboard_domain=""
    while true; do
        if [ -n "$EXISTING_DASHBOARD_DOMAIN" ]; then
            read -p "Dashboard-Domain (ohne http/https und ohne '/') [$EXISTING_DASHBOARD_DOMAIN]: " input_domain
            dashboard_domain=${input_domain:-$EXISTING_DASHBOARD_DOMAIN}
        else
            read -p "Bitte gib die Wunsch-Domain für dein Traefik-Dashboard ein (ohne http/https und ohne '/'): " dashboard_domain
        fi

        dashboard_domain=$(echo "$dashboard_domain" | sed -e 's|^http[s]\?://||' -e 's|/$||')

        if validate_domain "$dashboard_domain"; then
            echo -e "${green}Domain wird verwendet: $dashboard_domain${nc}"
            break
        else
            echo -e "${red}Ungültiges Domain-Format. Bitte versuche es erneut.${nc}"
            EXISTING_DASHBOARD_DOMAIN=""  # Bei ungültiger Eingabe kein Default mehr anbieten
        fi
    done

    sed -i "s/SERVICES_TRAEFIK_LABELS_TRAEFIK_HOST=.*/SERVICES_TRAEFIK_LABELS_TRAEFIK_HOST=HOST(\`$dashboard_domain\`)/" "$env_file"
    step_done "Traefik-Domain gesetzt"
    ((current_step++))

    # CrowdSec einmalig starten
    show_step $current_step $total_steps "CrowdSec einmalig starten und herunterfahren"
    docker compose up crowdsec -d && docker compose down
    step_done "CrowdSec gestartet und heruntergefahren"
    ((current_step++))

    # CrowdSec Konfiguration
    show_step $current_step $total_steps "CrowdSec Konfiguration anpassen"
    acquis_file="data/crowdsec/config/acquis.yaml"
    if [ ! -f "$acquis_file" ]; then
        error_exit "Die Datei $acquis_file existiert nicht."
    fi

    cat <<EOL > "$acquis_file"
filenames:
  - /var/log/auth.log
  - /var/log/syslog
labels:
  type: syslog
---
filenames:
  - /var/log/traefik/access.log
labels:
  type: traefik
---
EOL

    step_done "acquis.yaml bearbeitet"
    ((current_step++))

    # Firewall-Auswahl
    show_step $current_step $total_steps "Firewall-Bouncer installieren"
    echo -e "${cyan}Welche Firewall verwendest du?${nc}"
    echo "1) UFW"
    echo "2) iptables"
    echo "3) nftables"
    read -p "Bitte wähle die Nummer deiner Firewall (1-3): " firewall_choice

    case $firewall_choice in
        1|2)
            echo "Installiere crowdsec-firewall-bouncer-iptables..."
            sudo apt install -y crowdsec-firewall-bouncer-iptables
            ;;
        3)
            echo "Installiere crowdsec-firewall-bouncer-nftables..."
            sudo apt install -y crowdsec-firewall-bouncer-nftables
            ;;
        *)
            error_exit "Ungültige Auswahl."
            ;;
    esac
    step_done "Firewall-Bouncer installiert"
    ((current_step++))

    # Firewall-Bouncer konfigurieren
    show_step $current_step $total_steps "Firewall-Bouncer Konfiguration anpassen"
    firewall_bouncer_config="/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml"
    if [ ! -f "$firewall_bouncer_config" ]; then
        error_exit "Die Datei $firewall_bouncer_config existiert nicht."
    fi

    sudo sed -i "s#api_url: .*#api_url: http://172.31.127.254:8080/#g" "$firewall_bouncer_config"
    sudo sed -i "s#api_key: .*#api_key: $BOUNCER_KEY_FIREWALL_PASSWORD#g" "$firewall_bouncer_config"
    sudo systemctl enable crowdsec-firewall-bouncer
    sudo systemctl restart crowdsec-firewall-bouncer
    step_done "Firewall-Bouncer angepasst"
    ((current_step++))

    # Dashboard-Benutzer erstellen
    show_step $current_step $total_steps "Erstelle Benutzer für Traefik-Dashboard"
    read -p "Bitte gib den gewünschten Benutzernamen für das Dashboard ein: " dashboard_user
    htpasswd_file="data/traefik/.htpasswd"
    sudo htpasswd -c "$htpasswd_file" "$dashboard_user"
    step_done "Dashboard-Benutzer erstellt"
    ((current_step++))

    # Stack starten
    show_step $current_step $total_steps "Finale Überprüfung und Stack starten"
    if confirm "Hast du die Ports und die Domain überprüft und sind sie korrekt?" "n"; then
        echo "Starte den Stack..."
        docker compose up -d
        step_done "Stack gestartet"

        echo -e "\n${green}${bold}Installation abgeschlossen!${nc}\n"
        echo -e "${cyan}Dashboard erreichbar unter:${nc} https://$dashboard_domain"
        echo -e "${cyan}Benutzername:${nc} $dashboard_user"
        echo -e "\n${yellow}Wichtige nächste Schritte:${nc}"
        echo -e "1. Stelle sicher, dass die Domain auf die Server-IP zeigt"
        echo -e "2. Öffne die Firewall-Ports:"
        if [ "$use_proxy_mode" = true ]; then
            echo -e "   - Port 80 (HTTP für vorgeschalteten Traefik)"
        else
            echo -e "   - Port 80 (HTTP)"
            echo -e "   - Port 443 (HTTPS)"
        fi
        echo -e "3. Warte ca. 1-2 Minuten bis alle Services bereit sind"
    else
        step_done "Start übersprungen"
        echo -e "\n${yellow}Bitte überprüfe die Firewall und die Domain-Einstellungen.${nc}"
        echo -e "${cyan}Du kannst den Stack später mit 'docker compose up -d' starten${nc}"
    fi
}

# =============================================================================
# Hauptprogramm
# =============================================================================

main() {
    # Root-Rechte prüfen
    if [ "$EUID" -ne 0 ]; then
        echo -e "${red}${bold}✗ Fehler: Dieses Script muss mit Root-Rechten ausgeführt werden.${nc}"
        echo -e "${yellow}Bitte starte das Script mit:${nc} sudo ./install.sh"
        exit 1
    fi

    # Prüfe ob .install.conf existiert und INSTALL_TYPE gesetzt ist (Auto-Installation)
    if [ -f ".install.conf" ]; then
        source ".install.conf"
        if [ -n "$INSTALL_TYPE" ]; then
            echo -e "${green}✓ Auto-Installation: $INSTALL_TYPE${nc}"
            # Konfiguration initialisieren und laden
            init_config_vars
            load_installation_config
            # Direkt zur Installation springen (Menü überspringen)
        else
            # Zeige Banner und Menü
            show_main_menu
            # Konfigurationsmenü anzeigen
            show_configuration_menu "$INSTALL_TYPE"
        fi
    else
        # Zeige Banner und Menü
        show_main_menu
        # Konfigurationsmenü anzeigen
        show_configuration_menu "$INSTALL_TYPE"
    fi

    # Installationsverzeichnis einrichten (verwendet CONFIG_INSTALL_DIR aus Konfigurationsmenü)
    setup_installation_directory "$INSTALL_TYPE"

    # Docker prüfen und installieren
    check_and_install_docker

    # IP-Konfiguration anwenden falls gewünscht
    if [ "$CONFIG_IP_ENABLED" = true ]; then
        echo -e "\n${cyan}Wende IP-Konfiguration an...${nc}"
        if apply_network_config "$INTERFACE" "$CONFIG_IP/$CONFIG_CIDR" "$CONFIG_GATEWAY" "$CONFIG_DNS"; then
            echo -e "${green}✓ IP-Konfiguration erfolgreich angewendet${nc}"
            echo -e "${yellow}Hinweis: Möglicherweise wurde die SSH-Verbindung getrennt.${nc}"
            echo -e "${yellow}Neue IP-Adresse: $CONFIG_IP${nc}\n"
        else
            echo -e "${red}✗ Fehler bei der IP-Konfiguration${nc}"
            if ! confirm "Trotzdem fortfahren?" "n"; then
                exit 1
            fi
        fi
    fi

    # Hostname ändern falls gewünscht
    if [ "$CONFIG_HOSTNAME_ENABLED" = true ]; then
        echo -e "\n${cyan}Setze Hostnamen auf: $CONFIG_HOSTNAME${nc}"
        sudo hostnamectl set-hostname "$CONFIG_HOSTNAME"
        echo "127.0.1.1 $CONFIG_HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
        echo -e "${green}✓ Hostname geändert${nc}\n"
    fi

    # Installation basierend auf Auswahl
    case $INSTALL_TYPE in
        "frontend")
            install_frontend_traefik
            ;;
        "backend-standard")
            install_backend_stack false
            ;;
        "backend-proxy")
            install_backend_stack true
            ;;
    esac

    echo -e "\n${green}${bold}Vielen Dank für die Nutzung des Traefik-CrowdSec-Stack Installers!${nc}\n"
}

# Script starten
main
