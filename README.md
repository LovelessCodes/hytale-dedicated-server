# Hytale Docker Server

A containerized environment for running a Hytale dedicated server with automatic updates and integrated OAuth2 device authentication support.

## Features

- **Automated Updates**: Uses `hytale-downloader` to fetch the latest server binaries on startup.
- **Web-Based Auth**: Built-in status page (port 8080) to handle OAuth2 device verification codes.
- **Graceful Shutdown**: Properly handles `SIGTERM`/`SIGINT` to trigger the `/stop` command.
- **Persistence Support**: Hardware ID persistence and session token management.
- **Configurable**: Deep integration with Java and Hytale-specific CLI arguments via environment variables.

## Quick Start

### Docker Compose
```yaml
services:
  hytale-server:
    container_name: hytale-server
    image: ghcr.io/lovelesscodes/hytale-dedicated-server:main
    ports:
      - "5520:5520/udp"
      - "8080:8080"
    environment:
      - JAVA_XMS=4G
      - JAVA_XMX=4G
      - AUTO_UPDATE=true
      - USE_AOT_CACHE=true
    volumes:
      - ./data:/app
      # Allows to persist server authorization with /auth persistence Encrypted
      # - /etc/machine-id:/etc/machine-id:ro
```

## Configuration

### Environment Variables

| Variable | Default | Description |
| :--- | :--- | :--- |
| `HYTALE_PORT` | `5520` | Server port (UDP). |
| `BIND_ADDR` | `0.0.0.0` | IP to bind the server. |
| `AUTO_UPDATE` | `true` | Check for newer `HytaleServer.jar` on boot. |
| `JAVA_XMS` / `JAVA_XMX` | `4G` | Initial and Maximum Java heap size. |
| `AUTH_MODE` | `authenticated` | `authenticated` or `offline`. |
| `ASSETS_PATH` | `Assets.zip` | Path to server assets. |
| `USE_AOT_CACHE` | `false` | Enable AOT optimization if `.aot` file exists. |

### Hytale Specifics
- `SESSION_TOKEN`: Pre-defined session token.
- `IDENTITY_TOKEN`: Pre-defined identity token.
- `OWNER_UUID`: The UUID of the server owner.
- `BACKUP_ENABLED`: Set to `true` to enable automatic backups.
- `JAVA_CMD_ADDITIONAL_OPTS`: Pass extra flags to the JVM.
- `HYTALE_ADDITIONAL_OPTS`: Pass extra flags to the Hytale JAR.

## Authentication Flow

If the server requires authentication:
1.  Start the container.
2.  Navigate to `http://<host-ip>:8080` in your browser.
3.  Follow the OAuth2 link provided on the status page to verify your account.
4.  Once verified, the server will automatically proceed with the download or boot process.

## Architecture

- **Port 8080**: Serves a Python-based status page providing real-time feedback on hardware ID status and authentication URLs.
- **Named Pipe**: Stdin is managed via `/tmp/hytale_stdin` to allow the entrypoint script to inject commands (like `/auth` and `/stop`) into the Java process.
- **Signal Handling**: A trap captures container termination signals to ensure the world is saved correctly before the process exits.