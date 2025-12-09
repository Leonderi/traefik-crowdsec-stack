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
║  Automatische Installation von:                                     ║
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

configure_network() {
    echo -e "\n${bold}Netzwerk-Konfiguration${nc}\n"

    if confirm "Möchten Sie die IP-Adresse dieser Maschine konfigurieren?" "n"; then
        echo -e "${yellow}Hinweis: Für die IP-Konfiguration werden Root-Rechte benötigt${nc}"
        read -p "Bitte geben Sie die gewünschte IP-Adresse ein (z.B. 172.16.16.140): " NEW_IP
        read -p "Bitte geben Sie das Subnetz ein (z.B. 255.255.255.0 oder /24): " SUBNET
        read -p "Bitte geben Sie das Gateway ein: " GATEWAY

        # IP-Konfiguration wird später durchgeführt
        CONFIGURE_IP=true
    else
        CONFIGURE_IP=false
    fi

    if confirm "Möchten Sie den Hostnamen dieser Maschine ändern?" "n"; then
        read -p "Bitte geben Sie den gewünschten Hostnamen ein: " NEW_HOSTNAME
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

    # Weitere Schritte aus first_install.sh folgen...
    # (CrowdSec, Bouncer-Keys, E-Mail, Domain, Firewall, etc.)

    echo -e "\n${yellow}Hinweis: Dies ist eine gekürzte Version. Die vollständige Backend-Installation wird in der finalen Version implementiert.${nc}"
    echo -e "${cyan}Für jetzt verweisen wir auf das bestehende first_install.sh${nc}\n"
}

# =============================================================================
# Hauptprogramm
# =============================================================================

main() {
    # Zeige Banner und Menü
    show_main_menu

    # Netzwerk-Konfiguration (optional)
    configure_network

    # Docker prüfen und installieren
    check_and_install_docker

    # IP/Hostname konfigurieren falls gewünscht
    if [ "$CONFIGURE_IP" = true ]; then
        echo -e "\n${yellow}IP-Konfiguration wird noch nicht vollständig unterstützt.${nc}"
        echo -e "${yellow}Bitte konfigurieren Sie die IP manuell oder verwenden Sie netplan/nmcli.${nc}\n"
    fi

    if [ "$CONFIGURE_HOSTNAME" = true ]; then
        echo -e "\n${cyan}Setze Hostnamen auf: $NEW_HOSTNAME${nc}"
        sudo hostnamectl set-hostname "$NEW_HOSTNAME"
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
