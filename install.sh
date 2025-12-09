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
# Hauptmenü
# =============================================================================

show_main_menu() {
    show_banner
    echo -e "${bold}Bitte wählen Sie den Installationsmodus:${nc}\n"
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

    read -p "Ihre Auswahl [0-3]: " INSTALL_MODE

    case $INSTALL_MODE in
        1)
            INSTALL_TYPE="frontend"
            echo -e "\n${green}Frontend Traefik gewählt${nc}\n"
            ;;
        2)
            INSTALL_TYPE="backend-standard"
            echo -e "\n${green}Backend Stack - Standard gewählt${nc}\n"
            ;;
        3)
            INSTALL_TYPE="backend-proxy"
            echo -e "\n${green}Backend Stack - Proxy-Modus gewählt${nc}\n"
            ;;
        0)
            echo -e "\n${yellow}Installation abgebrochen.${nc}"
            exit 0
            ;;
        *)
            echo -e "\n${red}Ungültige Auswahl!${nc}"
            sleep 2
            show_main_menu
            ;;
    esac
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
# Frontend Traefik Installation
# =============================================================================

install_frontend_traefik() {
    echo -e "\n${bold}${cyan}Installation: Frontend Traefik${nc}\n"

    total_steps=10
    current_step=2

    # Arbeitsverzeichnis setzen
    show_step $current_step $total_steps "Setze Arbeitsverzeichnis"
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
    FRONTEND_DIR="${SCRIPT_DIR}/frontend"
    cd "$FRONTEND_DIR" || error_exit "Frontend-Verzeichnis nicht gefunden"
    step_done "Arbeitsverzeichnis gesetzt"
    ((current_step++))

    # Apache2-utils installieren
    show_step $current_step $total_steps "Installiere apache2-utils"
    command -v htpasswd >/dev/null 2>&1 || { sudo apt update && sudo apt install -y apache2-utils; }
    step_done "apache2-utils installiert"
    ((current_step++))

    # Konfigurationsdateien kopieren
    show_step $current_step $total_steps "Kopiere Konfigurationsdateien"
    cp .env.sample .env
    cp traefik.yml.sample traefik.yml
    cp docker-compose.yml.sample docker-compose.yml
    cp letsencrypt/acme.json.sample letsencrypt/acme.json
    chmod 600 letsencrypt/acme.json
    step_done "Konfigurationsdateien kopiert"
    ((current_step++))

    # E-Mail für Let's Encrypt
    show_step $current_step $total_steps "Konfiguriere Let's Encrypt"
    read -p "Bitte geben Sie Ihre E-Mail-Adresse für Let's Encrypt ein: " ACME_EMAIL
    sed -i "s/email: \".*\"/email: \"$ACME_EMAIL\"/g" traefik.yml
    sed -i "s/ACME_EMAIL=.*/ACME_EMAIL=$ACME_EMAIL/g" .env
    step_done "Let's Encrypt konfiguriert"
    ((current_step++))

    # Dashboard-Domain
    show_step $current_step $total_steps "Konfiguriere Dashboard-Domain"
    read -p "Bitte geben Sie die Domain für das Traefik-Dashboard ein: " DASHBOARD_HOST
    sed -i "s/TRAEFIK_DASHBOARD_HOST=.*/TRAEFIK_DASHBOARD_HOST=$DASHBOARD_HOST/g" .env
    step_done "Dashboard-Domain konfiguriert"
    ((current_step++))

    # Backend-VMs konfigurieren
    show_step $current_step $total_steps "Konfiguriere Backend-VMs"
    echo -e "${cyan}Geben Sie die IP-Adressen Ihrer Backend-VMs ein (eine pro Zeile, leere Zeile zum Beenden):${nc}"
    BACKEND_IPS=()
    while true; do
        read -p "Backend-VM IP $(( ${#BACKEND_IPS[@]} + 1 )) (Enter zum Beenden): " BACKEND_IP
        [ -z "$BACKEND_IP" ] && break
        BACKEND_IPS+=("$BACKEND_IP")
    done

    # HTTP Provider Endpoints generieren
    if [ ${#BACKEND_IPS[@]} -gt 0 ]; then
        ENDPOINTS=""
        for ip in "${BACKEND_IPS[@]}"; do
            if [ -z "$ENDPOINTS" ]; then
                ENDPOINTS="      - \"http://$ip/api\""
            else
                ENDPOINTS="$ENDPOINTS\n      - \"http://$ip/api\""
            fi
        done
        sed -i "/endpoints: \[\]/c\    endpoints:\n$ENDPOINTS" traefik.yml
        echo -e "${green}${#BACKEND_IPS[@]} Backend-VM(s) konfiguriert${nc}"
    else
        echo -e "${yellow}Keine Backend-VMs konfiguriert. Sie können diese später in traefik.yml hinzufügen.${nc}"
    fi
    step_done "Backend-VMs konfiguriert"
    ((current_step++))

    # Dashboard-Authentifizierung
    show_step $current_step $total_steps "Erstelle Dashboard-Authentifizierung"
    read -p "Bitte geben Sie den Benutzernamen für das Dashboard ein: " DASHBOARD_USER
    DASHBOARD_PASS=$(htpasswd -nb "$DASHBOARD_USER" "$(read -sp 'Passwort: ' pwd; echo $pwd)" | sed 's/\$/\$\$/g')
    echo
    sed -i "s|traefik.http.middlewares.dashboard-auth.basicauth.users:.*|traefik.http.middlewares.dashboard-auth.basicauth.users: \"$DASHBOARD_PASS\"|g" docker-compose.yml
    step_done "Dashboard-Authentifizierung erstellt"
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

    # Stack starten
    show_step $current_step $total_steps "Starte Frontend Traefik"
    if confirm "Möchten Sie den Frontend Traefik jetzt starten?" "y"; then
        docker compose up -d
        step_done "Frontend Traefik gestartet"

        echo -e "\n${green}${bold}Installation abgeschlossen!${nc}\n"
        echo -e "${cyan}Dashboard erreichbar unter:${nc} https://$DASHBOARD_HOST"
        echo -e "${cyan}Benutzername:${nc} $DASHBOARD_USER"
    else
        step_done "Start übersprungen"
        echo -e "\n${yellow}Sie können den Stack später mit 'docker compose up -d' starten${nc}"
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

    # Setze das Arbeitsverzeichnis
    show_step $current_step $total_steps "Setze Arbeitsverzeichnis"
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
    cd "$SCRIPT_DIR" || exit
    step_done "Arbeitsverzeichnis gesetzt"
    ((current_step++))

    # Root-Rechte prüfen
    show_step $current_step $total_steps "Überprüfen von Root-Rechten"
    if [ "$EUID" -ne 0 ]; then
        error_exit "Bitte führe das Skript mit Root-Rechten aus."
    fi
    step_done "Root-Rechte überprüft"
    ((current_step++))

    # Installiere apache2-utils
    show_step $current_step $total_steps "Installiere apache2-utils, falls erforderlich"
    command -v htpasswd >/dev/null 2>&1 || { sudo apt update && sudo apt install -y apache2-utils; }
    step_done "apache2-utils installiert"
    ((current_step++))

    # Überprüfen, ob Container laufen
    show_step $current_step $total_steps "Überprüfen von laufenden Containern"
    containers=("crowdsec" "socket-proxy" "traefik" "traefik_crowdsec_bouncer")
    for container in "${containers[@]}"; do
        if [ "$(docker ps -q -f name=$container)" ]; then
            error_exit "Der Docker-Container '$container' läuft bereits. Das Skript wird abgebrochen."
        fi
    done
    step_done "Keine laufenden Container gefunden"
    ((current_step++))

    # Netzwerke überprüfen
    show_step $current_step $total_steps "Überprüfen von Netzwerken"
    networks=("proxy" "socket_proxy" "crowdsec")
    for network in "${networks[@]}"; do
        if [ "$(docker network ls -q -f name=^${network}$)" ]; then
            error_exit "Das Docker-Netzwerk '$network' existiert bereits. Das Skript wird abgebrochen."
        fi
    done
    step_done "Keine bestehenden Netzwerke gefunden"
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

    # Dateien kopieren
    for file_pair in "${files_to_copy[@]}"; do
        src=$(echo $file_pair | awk '{print $1}')
        dst=$(echo $file_pair | awk '{print $2}')

        src_path="${SCRIPT_DIR}/${src}"
        dst_path="${SCRIPT_DIR}/${dst}"

        if [ -f "$src_path" ]; then
            cp "$src_path" "$dst_path"
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
    echo -e "\nBOUNCER_KEY_TRAEFIK=$BOUNCER_KEY_TRAEFIK_PASSWORD" >> ${SCRIPT_DIR}/.env
    sleep 1
    BOUNCER_KEY_FIREWALL_PASSWORD=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9!@#$%^&*()-_=+[]{}<>?|')
    echo "BOUNCER_KEY_FIREWALL=$BOUNCER_KEY_FIREWALL_PASSWORD" >> ${SCRIPT_DIR}/.env
    step_done "Bouncer-Passwörter generiert"
    ((current_step++))

    # E-Mail-Adresse für SSL-Zertifikate (nur im Standard-Modus)
    if [ "$use_proxy_mode" = false ]; then
        show_step $current_step $total_steps "Frage nach E-Mail-Adresse für SSL-Zertifikate"

        # Funktion zur E-Mail-Validierung
        validate_email() {
            local email_regex="^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"
            [[ $1 =~ $email_regex ]]
        }

        # Benutzer nach E-Mail-Adresse fragen
        while true; do
            read -p "Bitte gib deine E-Mail-Adresse für die SSL-Zertifikate ein: " ssl_email
            if validate_email "$ssl_email"; then
                echo -e "${green}Gültige E-Mail-Adresse: $ssl_email${nc}"
                if confirm "Möchtest du diese E-Mail-Adresse verwenden? ($ssl_email)" "y"; then
                    break
                fi
            else
                echo -e "${red}Ungültige E-Mail-Adresse. Bitte versuche es erneut.${nc}"
            fi
        done

        # E-Mail-Adresse in traefik.yml setzen
        traefik_config_file="data/traefik/traefik.yml"
        if [ ! -f "$traefik_config_file" ]; then
            error_exit "Die Datei $traefik_config_file existiert nicht."
        fi
        sed -i "s/email: \".*\"/email: \"$ssl_email\"/g" "$traefik_config_file"

        step_done "SSL-Zertifikat E-Mail-Adresse gesetzt"
        ((current_step++))
    else
        show_step $current_step $total_steps "Überspringe SSL-Zertifikat E-Mail (Proxy-Modus)"
        echo "Im Proxy-Modus übernimmt der vorgeschaltete Traefik das Zertifikats-Handling."
        step_done "SSL-Zertifikat E-Mail übersprungen (Proxy-Modus)"
        ((current_step++))
    fi

    # Wunsch-Domain für Traefik-Dashboard
    show_step $current_step $total_steps "Frage nach Wunsch-Domain für Traefik-Dashboard"

    env_file="${SCRIPT_DIR}/.env"
    if [ ! -f "$env_file" ]; then
        error_exit "Die Datei $env_file existiert nicht."
    fi

    # Funktion zur Domain-Validierung
    validate_domain() {
        local domain_regex="^([a-zA-Z0-9][-a-zA-Z0-9]*\.)+[a-zA-Z]{2,}$"
        [[ $1 =~ $domain_regex ]]
    }

    # Benutzer nach Domain fragen
    while true; do
        read -p "Bitte gib die Wunsch-Domain für dein Traefik-Dashboard ein (ohne http/https und ohne '/'): " dashboard_domain
        dashboard_domain=$(echo "$dashboard_domain" | sed -e 's|^http[s]\?://||' -e 's|/$||')

        if validate_domain "$dashboard_domain"; then
            if confirm "Möchtest du diese Domain verwenden? ($dashboard_domain)" "y"; then
                break
            fi
        else
            echo -e "${red}Ungültiges Domain-Format. Bitte versuche es erneut.${nc}"
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
    acquis_file="${SCRIPT_DIR}/data/crowdsec/config/acquis.yaml"
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
    htpasswd_file="${SCRIPT_DIR}/data/traefik/.htpasswd"
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

    # Zeige Banner und Menü
    show_main_menu

    # Netzwerk-Konfiguration (optional)
    configure_network

    # Docker prüfen und installieren
    check_and_install_docker

    # IP-Konfiguration anwenden falls gewünscht
    if [ "$CONFIGURE_IP" = true ]; then
        echo -e "\n${cyan}Wende IP-Konfiguration an...${nc}"
        if apply_network_config "$INTERFACE" "$NEW_IP/$NEW_CIDR" "$NEW_GATEWAY" "$NEW_DNS"; then
            echo -e "${green}✓ IP-Konfiguration erfolgreich angewendet${nc}"
            echo -e "${yellow}Hinweis: Möglicherweise wurde die SSH-Verbindung getrennt.${nc}"
            echo -e "${yellow}Neue IP-Adresse: $NEW_IP${nc}\n"
        else
            echo -e "${red}✗ Fehler bei der IP-Konfiguration${nc}"
            if ! confirm "Trotzdem fortfahren?" "n"; then
                exit 1
            fi
        fi
    fi

    # Hostname ändern falls gewünscht
    if [ "$CONFIGURE_HOSTNAME" = true ]; then
        echo -e "\n${cyan}Setze Hostnamen auf: $NEW_HOSTNAME${nc}"
        sudo hostnamectl set-hostname "$NEW_HOSTNAME"
        echo "127.0.1.1 $NEW_HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
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
