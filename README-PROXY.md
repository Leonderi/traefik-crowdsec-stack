# Konfiguration mit vorgeschaltetem Traefik-Proxy

Diese Anleitung beschreibt, wie Sie den Traefik-CrowdSec-Stack mit einem vorgeschalteten Traefik-Proxy einrichten. In diesem Setup übernimmt der vorgeschaltete Traefik das SSL/TLS-Zertifikats-Handling, während die Backend-Traefik-Instanzen die Anfragen über HTTP empfangen.

## Architektur

```
Internet → Vorgeschalteter Traefik (VM, SSL/TLS, Port 443)
              ↓ HTTP
Backend-Traefik VMs (172.16.16.140+, Port 80) → Docker Services
```

**Wichtig**: Die Kommunikation zwischen vorgeschaltetem und Backend-Traefik erfolgt über **HTTP** (Port 80) im VM-Netzwerk.

## Vorteile

- Zentrale Verwaltung von SSL/TLS-Zertifikaten auf dem vorgeschalteten Traefik
- Mehrere Backend-Traefik-Instanzen (verschiedene VMs) können von einem vorgeschalteten Traefik verwaltet werden
- CrowdSec-Schutz bleibt auf Backend-Ebene erhalten
- Saubere Trennung zwischen Frontend- und Backend-Routing
- Automatische Service-Discovery durch Traefik HTTP Provider

## Netzwerk-Setup

### Backend-VMs (mit diesem Stack)

- **IP-Adressen**: 172.16.16.140, 172.16.16.141, 172.16.16.142, etc.
- **Exponierter Port**: 80 (HTTP)
- **Kommunikation**: HTTP zwischen vorgeschaltetem Traefik und Backend-Traefik
- **Traefik-Version**: 3.6+

### Vorgeschalteter Traefik (separate VM)

- Exponiert Ports 80 und 443
- Übernimmt SSL/TLS-Zertifikats-Handling
- Kommuniziert mit Backend-Traefiks über HTTP (Port 80)

## Installation

### 1. Backend-Traefik installieren

Führen Sie das Installationsskript aus und wählen Sie Option 2 (Installation mit vorgeschaltetem Traefik-Proxy):

```bash
cd /opt/containers/traefik-crowdsec-stack
sudo chmod +x first_install.sh
sudo ./first_install.sh
```

Bei der Abfrage des Installationsmodus wählen Sie:
```
Welchen Installationsmodus möchtest du verwenden?
1) Standard-Installation (Traefik übernimmt SSL/TLS-Zertifikate)
2) Installation mit vorgeschaltetem Traefik-Proxy (vorgeschalteter Traefik übernimmt SSL/TLS)
Bitte wähle den Installationsmodus (1-2, Standard: 1): 2
```

### 2. Vorgeschalteten Traefik konfigurieren

#### Option A: HTTP Provider für automatische Service-Discovery (Empfohlen)

Der vorgeschaltete Traefik kann die Services automatisch von den Backend-Traefiks über die HTTP API abrufen.

**Vorgeschalteter Traefik - traefik.yml:**

```yaml
api:
  dashboard: true

entryPoints:
  web:
    address: ':80'
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ':443'

certificatesResolvers:
  letsencrypt:
    acme:
      email: "your@email.com"
      storage: "/letsencrypt/acme.json"
      tlsChallenge: {}

providers:
  # HTTP Provider für Backend-Traefiks
  http:
    endpoints:
      - "http://172.16.16.140/api"  # Backend VM 1
      - "http://172.16.16.141/api"  # Backend VM 2
      - "http://172.16.16.142/api"  # Backend VM 3
    pollInterval: "10s"

log:
  level: INFO
```

**Vorteile dieser Methode:**
- Automatische Service-Discovery
- Services auf Backend-VMs definieren ihre eigenen Domains/Subdomains
- Keine manuelle Konfiguration für jeden Service erforderlich
- Traefik-Labels der Docker-Services werden automatisch erkannt

#### Option B: Manuelle Service-Konfiguration

Alternativ können Sie Services manuell konfigurieren.

**Vorgeschalteter Traefik - config/backend-services.yml:**

```yaml
http:
  services:
    backend-vm-140:
      loadBalancer:
        servers:
          - url: "http://172.16.16.140:80"
    backend-vm-141:
      loadBalancer:
        servers:
          - url: "http://172.16.16.141:80"
    backend-vm-142:
      loadBalancer:
        servers:
          - url: "http://172.16.16.142:80"

  routers:
    # Beispiel: Service auf Backend VM 140
    app-on-vm-140:
      rule: "Host(`app.yourdomain.com`)"
      entryPoints:
        - websecure
      service: backend-vm-140
      tls:
        certResolver: letsencrypt

    # Beispiel: Service auf Backend VM 141
    api-on-vm-141:
      rule: "Host(`api.yourdomain.com`)"
      entryPoints:
        - websecure
      service: backend-vm-141
      tls:
        certResolver: letsencrypt
```

## Service-Definition auf Backend-VMs

### Docker Compose mit Traefik-Labels

Auf den Backend-VMs definieren Sie Ihre Services mit Traefik-Labels in Ihren Docker Compose Files:

**Beispiel: docker-compose.yml auf Backend VM (172.16.16.140)**

```yaml
version: '3.8'

services:
  my-app:
    image: nginx:latest
    labels:
      traefik.enable: "true"
      # Router für HTTP (wird vom Backend-Traefik empfangen)
      traefik.http.routers.my-app.rule: "Host(`app.yourdomain.com`)"
      traefik.http.routers.my-app.entrypoints: "web"
      traefik.http.services.my-app.loadbalancer.server.port: "80"
    networks:
      - proxy

networks:
  proxy:
    external: true
```

**Wichtig**:
- Verwenden Sie `entrypoints: "web"` (Port 80), nicht `websecure`
- Der vorgeschaltete Traefik übernimmt automatisch das HTTPS-Handling
- Services müssen im `proxy`-Netzwerk sein

### Service mit mehreren Subdomains

```yaml
services:
  webapp:
    image: myapp:latest
    labels:
      traefik.enable: "true"

      # Frontend
      traefik.http.routers.webapp-frontend.rule: "Host(`app.yourdomain.com`)"
      traefik.http.routers.webapp-frontend.entrypoints: "web"
      traefik.http.routers.webapp-frontend.service: "webapp-frontend"
      traefik.http.services.webapp-frontend.loadbalancer.server.port: "3000"

      # API
      traefik.http.routers.webapp-api.rule: "Host(`api.yourdomain.com`)"
      traefik.http.routers.webapp-api.entrypoints: "web"
      traefik.http.routers.webapp-api.service: "webapp-api"
      traefik.http.services.webapp-api.loadbalancer.server.port: "8080"
    networks:
      - proxy
```

## Traefik-Dashboard-Zugriff

Das Traefik-Dashboard der Backend-VMs ist ebenfalls über den vorgeschalteten Traefik erreichbar, wenn Sie den HTTP Provider verwenden.

**Backend-Traefik** (bereits in backend/traefik-proxy.yml konfiguriert):
```yaml
labels:
  traefik.enable: "true"
  traefik.http.routers.traefik-dashboard.rule: "Host(`traefik-backend-140.yourdomain.com`)"
  traefik.http.routers.traefik-dashboard.entrypoints: "web"
  traefik.http.routers.traefik-dashboard.service: "api@internal"
```

Der vorgeschaltete Traefik erkennt diese Konfiguration automatisch und macht das Dashboard über HTTPS verfügbar.

## Vorgeschalteter Traefik - Vollständiges Beispiel

### docker-compose.yml

```yaml
version: '3.8'

services:
  traefik:
    image: traefik:3.6
    container_name: traefik-frontend
    command:
      - "--api.dashboard=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      - "--certificatesresolvers.letsencrypt.acme.email=your@email.com"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.tlschallenge=true"
      - "--providers.http.endpoints=http://172.16.16.140/api,http://172.16.16.141/api,http://172.16.16.142/api"
      - "--providers.http.pollInterval=10s"
      - "--log.level=INFO"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./letsencrypt:/letsencrypt
      - ./config:/etc/traefik/dynamic:ro
    labels:
      # Dashboard des vorgeschalteten Traefik
      traefik.enable: "true"
      traefik.http.routers.dashboard.rule: "Host(`traefik.yourdomain.com`)"
      traefik.http.routers.dashboard.entrypoints: "websecure"
      traefik.http.routers.dashboard.service: "api@internal"
      traefik.http.routers.dashboard.tls.certresolver: "letsencrypt"
      traefik.http.routers.dashboard.middlewares: "dashboard-auth"
      # Basic Auth für Dashboard
      traefik.http.middlewares.dashboard-auth.basicauth.users: "admin:$$apr1$$..."
    restart: unless-stopped
```

## Firewall-Konfiguration

### Backend-VMs (172.16.16.140+)

```bash
# Port 80 für vorgeschalteten Traefik öffnen
ufw allow from <VORGESCHALTETER_TRAEFIK_IP> to any port 80

# ODER für alle IPs im Subnetz:
ufw allow 80/tcp
```

**Wichtig**: Port 443 muss auf den Backend-VMs **nicht** geöffnet werden!

### Vorgeschaltete Traefik-VM

```bash
# Standard-Ports für HTTPS
ufw allow 80/tcp
ufw allow 443/tcp
```

## Debugging und Fehlerbehebung

### 1. Backend-Traefik API testen

Testen Sie, ob die Traefik-API erreichbar ist:

```bash
# Von der vorgeschalteten Traefik-VM aus:
curl http://172.16.16.140/api/http/routers
curl http://172.16.16.140/api/http/services
```

Sie sollten JSON-Ausgaben mit den konfigurierten Routern und Services sehen.

### 2. Logs überprüfen

**Backend-Traefik:**
```bash
docker logs traefik
tail -f /var/log/traefik/access.log
```

**Vorgeschalteter Traefik:**
```bash
docker logs traefik-frontend
```

### 3. Service wird nicht erkannt

**Problem**: Services auf Backend-VMs werden nicht vom vorgeschalteten Traefik erkannt.

**Lösungen**:
- Überprüfen Sie, ob der HTTP Provider korrekt konfiguriert ist
- Testen Sie die API-Endpunkte manuell (siehe oben)
- Stellen Sie sicher, dass `pollInterval` gesetzt ist
- Überprüfen Sie die Traefik-Labels in Ihren Docker Compose Files
- Stellen Sie sicher, dass Services im `proxy`-Netzwerk sind

### 4. Verbindungsprobleme

**Problem**: Vorgeschalteter Traefik kann Backend-Traefik nicht erreichen.

**Lösungen**:
- Überprüfen Sie Firewall-Regeln auf Backend-VMs
- Testen Sie die Verbindung mit `curl` oder `telnet`
- Überprüfen Sie IP-Adressen in der Konfiguration
- Stellen Sie sicher, dass Port 80 auf Backend-VMs exponiert ist

### 5. CrowdSec-Probleme

CrowdSec auf den Backend-VMs schützt weiterhin alle eingehenden Anfragen. Wenn legitime Anfragen vom vorgeschalteten Traefik blockiert werden:

```bash
# Vorgeschaltete Traefik-IP zur Whitelist hinzufügen
docker exec crowdsec cscli decisions add --ip <VORGESCHALTETER_TRAEFIK_IP> --duration 999999h --type ban
```

## Performance-Optimierung

### HTTP/2 zwischen Traefiks aktivieren

Für bessere Performance können Sie HTTP/2 für die Kommunikation zwischen den Traefiks aktivieren:

**Vorgeschalteter Traefik:**
```yaml
http:
  serversTransports:
    backend-transport:
      serverName: "backend.internal"
      insecureSkipVerify: false

  services:
    backend-vm-140:
      loadBalancer:
        servers:
          - url: "h2c://172.16.16.140:80"
        serversTransport: "backend-transport"
```

**Backend-Traefik (traefik.yml.proxy.sample):**
```yaml
entryPoints:
  web:
    address: ':80'
    http2:
      maxConcurrentStreams: 250
```

## Zusammenfassung

1. **Backend-VMs**: Installieren Sie den Stack mit Proxy-Modus, exponieren Sie Port 80
2. **Vorgeschalteter Traefik**: Konfigurieren Sie HTTP Provider mit Backend-VM-IPs
3. **Services**: Definieren Sie Traefik-Labels in Docker Compose auf Backend-VMs
4. **Automatisch**: Services werden vom vorgeschalteten Traefik erkannt und über HTTPS bereitgestellt
5. **Zentral**: SSL/TLS-Zertifikate werden nur auf dem vorgeschalteten Traefik verwaltet

Die Kommunikation erfolgt:
```
Client (HTTPS) → Vorgeschalteter Traefik (HTTPS → HTTP) → Backend-Traefik (HTTP) → Service
```
