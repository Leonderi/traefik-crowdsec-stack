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
    local mode_name=""
    local target_dir=""

    # Modus-spezifischen Namen festlegen
    case "$mode" in
        "frontend")
            mode_name="traefik-frontend"
            ;;
        "backend-standard")
            mode_name="traefik-backend"
            ;;
        "backend-proxy")
            mode_name="traefik-backend-proxy"
            ;;
    esac

    echo -e "\n${bold}${cyan}Installationsverzeichnis konfigurieren${nc}\n"

    # Nach Basis-Verzeichnis fragen
    read -p "Basis-Verzeichnis [/opt/containers]: " BASE_DIR
    BASE_DIR=${BASE_DIR:-/opt/containers}

    # Vollständigen Pfad erstellen
    INSTALL_DIR="${BASE_DIR}/${mode_name}"

    echo -e "\n${yellow}Zielverzeichnis:${nc} $INSTALL_DIR"

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

# Globale Konfigurationsvariablen initialisieren
init_config_vars() {
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

    # Dashboard-Benutzer
    CONFIG_DASHBOARD_USER=""
    CONFIG_DASHBOARD_PASS=""

    # Backend-VMs (nur für Frontend-Modus)
    CONFIG_BACKEND_IPS=()
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
        if [ -n "$CONFIG_DASHBOARD_USER" ]; then
            echo -e "${cyan}5)${nc} Dashboard-Benutzer      ${green}[$CONFIG_DASHBOARD_USER]${nc}"
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
                    configure_backend_vms
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

    if [ ${#errors[@]} -gt 0 ]; then
        echo -e "\n${red}${bold}Folgende Konfigurationen fehlen:${nc}"
        for error in "${errors[@]}"; do
            echo -e "${red}  ✗ $error${nc}"
        done
        echo
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
    if confirm "Möchten Sie den Frontend Traefik jetzt starten?" "y"; then
        docker compose up -d
        step_done "Frontend Traefik gestartet"

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

    # Zeige Banner und Menü
    show_main_menu

    # Installationsverzeichnis einrichten
    setup_installation_directory "$INSTALL_TYPE"

    # Konfigurationsmenü anzeigen
    show_configuration_menu "$INSTALL_TYPE"

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
