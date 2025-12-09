# Konfiguration mit vorgeschaltetem Traefik-Proxy

Diese Anleitung beschreibt, wie Sie den Traefik-CrowdSec-Stack mit einem vorgeschalteten Traefik-Proxy einrichten. In diesem Setup übernimmt der vorgeschaltete Traefik das SSL/TLS-Zertifikats-Handling, während der Backend-Traefik die Anfragen über das interne Proxy-Netzwerk empfängt.

## Architektur

```
Internet → Vorgeschalteter Traefik (SSL/TLS) → Backend-Traefik (Proxy-Modus) → Services
```

## Vorteile

- Zentrale Verwaltung von SSL/TLS-Zertifikaten
- Mehrere Backend-Traefik-Instanzen können von einem vorgeschalteten Traefik verwaltet werden
- CrowdSec-Schutz bleibt auf Backend-Ebene erhalten
- Saubere Trennung zwischen Frontend- und Backend-Routing

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

#### Netzwerk-Verbindung

Der vorgeschaltete Traefik muss mit dem Proxy-Netzwerk des Backend-Traefik verbunden werden. Fügen Sie in Ihrer `docker-compose.yml` des vorgeschalteten Traefik folgendes hinzu:

```yaml
networks:
  backend-proxy:
    external: true
    name: proxy
```

Und binden Sie den vorgeschalteten Traefik an dieses Netzwerk:

```yaml
services:
  traefik:
    networks:
      - backend-proxy
      # ... weitere Netzwerke
```

#### Service-Konfiguration

Erstellen Sie eine dynamische Konfigurationsdatei für den Backend-Traefik-Service. Zum Beispiel `config/backend-traefik.yml`:

```yaml
http:
  services:
    backend-traefik:
      loadBalancer:
        servers:
          - url: "http://172.31.191.254:80"
```

**Wichtig**: Die IP-Adresse `172.31.191.254` ist die Standard-IP des Backend-Traefik im Proxy-Netzwerk. Diese kann in der `.env`-Datei über `SERVICES_TRAEFIK_NETWORKS_PROXY_IPV4` angepasst werden.

#### Router-Konfiguration

Erstellen Sie Router für Ihre Services, die den Backend-Traefik verwenden. Beispiel:

```yaml
http:
  routers:
    my-service:
      rule: "Host(`service.yourdomain.com`)"
      entryPoints:
        - websecure
      service: backend-traefik
      tls:
        certResolver: letsencrypt  # Ihr Certificate Resolver
```

### 3. Alternative Konfiguration: Traefik-API-Provider

Wenn Sie möchten, dass der vorgeschaltete Traefik die Services direkt vom Backend-Traefik über die API abruft, können Sie den HTTP-Provider verwenden:

```yaml
providers:
  http:
    endpoint: "http://172.31.191.254:8080/api"
    pollInterval: 10s
```

**Hinweis**: Stellen Sie sicher, dass die Traefik-API des Backend-Traefik im Proxy-Netzwerk erreichbar ist.

## Netzwerk-Details

### Standard-IP-Adressen

Der Backend-Traefik verwendet folgende Standard-IP-Adressen:

- **Proxy-Netzwerk (IPv4)**: 172.31.191.254
- **Proxy-Netzwerk (IPv6)**: fd00:1:be:a:7001:0:3e:7fff
- **CrowdSec-Netzwerk (IPv4)**: 172.31.127.253
- **Socket-Proxy-Netzwerk (IPv4)**: 172.31.255.253

Diese können in der `.env`-Datei angepasst werden:

```bash
SERVICES_TRAEFIK_NETWORKS_PROXY_IPV4=172.31.191.254
SERVICES_TRAEFIK_NETWORKS_PROXY_IPV6=fd00:1:be:a:7001:0:3e:7fff
```

## Beispiel: Vollständige Konfiguration

### Backend-Traefik (.env)

```bash
ABSOLUTE_PATH=/opt/containers/traefik-crowdsec-stack
TZ=Europe/Berlin
SERVICES_TRAEFIK_LABELS_TRAEFIK_HOST=HOST(`traefik-backend.yourdomain.com`)
SERVICES_TRAEFIK_NETWORKS_PROXY_IPV4=172.31.191.254
```

### Vorgeschalteter Traefik (docker-compose.yml)

```yaml
version: '3.8'

services:
  traefik:
    image: traefik:3.3
    command:
      - "--api.dashboard=true"
      - "--providers.docker=true"
      - "--providers.file.directory=/etc/traefik/dynamic"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.email=your@email.com"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.tlschallenge=true"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./config:/etc/traefik/dynamic:ro
      - ./letsencrypt:/letsencrypt
    networks:
      - frontend
      - backend-proxy

networks:
  frontend:
  backend-proxy:
    external: true
    name: proxy
```

### Vorgeschalteter Traefik (config/backend-services.yml)

```yaml
http:
  services:
    backend-traefik:
      loadBalancer:
        servers:
          - url: "http://172.31.191.254:80"

  routers:
    # Beispiel: Weiterleitung des Traefik-Dashboards
    traefik-backend-dashboard:
      rule: "Host(`traefik-backend.yourdomain.com`)"
      entryPoints:
        - websecure
      service: backend-traefik
      tls:
        certResolver: letsencrypt

    # Beispiel: Service im Backend-Traefik
    my-app:
      rule: "Host(`myapp.yourdomain.com`)"
      entryPoints:
        - websecure
      service: backend-traefik
      tls:
        certResolver: letsencrypt
```

## Fehlerbehebung

### Backend-Traefik ist nicht erreichbar

1. Überprüfen Sie, ob der Backend-Traefik läuft:
   ```bash
   docker ps | grep traefik
   ```

2. Überprüfen Sie die Netzwerkverbindung:
   ```bash
   docker network inspect proxy
   ```

3. Testen Sie die Verbindung vom vorgeschalteten Traefik:
   ```bash
   docker exec <vorgeschalteter-traefik-container> curl http://172.31.191.254:80
   ```

### Services werden nicht gefunden

1. Überprüfen Sie die Traefik-Logs des Backend-Traefik:
   ```bash
   docker logs traefik
   ```

2. Stellen Sie sicher, dass die Services im Proxy-Netzwerk sind:
   ```bash
   docker network inspect proxy
   ```

### Zertifikatsfehler

Da der vorgeschaltete Traefik das Zertifikats-Handling übernimmt, sollten keine Zertifikatsfehler am Backend-Traefik auftreten. Überprüfen Sie die Konfiguration des vorgeschalteten Traefik.

## Weitere Hinweise

- Der Backend-Traefik exponiert **keine** Ports nach außen
- CrowdSec schützt weiterhin alle Anfragen auf Backend-Ebene
- Das Traefik-Dashboard des Backend-Traefik ist über den vorgeschalteten Traefik erreichbar
- Sie können mehrere Backend-Traefik-Instanzen betreiben und über einen vorgeschalteten Traefik verwalten
