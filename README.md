# Container Failover Watchdog

A Docker-based failover/watchdog service that monitors the health of a primary service URL and automatically starts a backup container when the primary service fails.

## Overview

This watchdog monitors a primary service's health endpoint (URL) and manages automatic failover to a backup container when the primary service becomes unavailable. The primary service can be remote and is NOT managed by this script - external logic should handle primary service recovery. This script only manages the local backup container.

## Features

- **Health Monitoring**: Continuously checks the primary service health endpoint (can be remote)
- **Automatic Failover**: Starts backup container after consecutive failures
- **Automatic Recovery**: Stops backup when primary service is available again
- **Remote Primary Support**: Primary service can be on any host accessible via HTTP
- **Configurable Thresholds**: Customize check intervals, failure thresholds, and recovery times
- **Docker-based**: Lightweight container based on `docker:cli` image
- **Docker Hub**: Available as `omar10594/container-watchdog`

## Configuration

The watchdog is configured using environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `PRIMARY_HEALTH_URL` | URL to check for primary service health (can be remote) | `http://localhost:8080/health` |
| `CHECK_EVERY` | Health check interval in seconds | `10` |
| `FAIL_THRESHOLD` | Number of consecutive failures before failover | `3` |
| `RECOVER_SECONDS` | Time to wait before checking for primary recovery | `60` |
| `BACKUP_CONTAINER_NAME` | Name of the backup container to start on failover | `backup-container` |
| `HEALTH_CHECK_TIMEOUT` | Timeout for health check requests in seconds | `5` |

## Usage

### Using Docker Hub Image

```bash
docker run -d \
  --name watchdog \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e PRIMARY_HEALTH_URL=http://your-service:8080/health \
  -e CHECK_EVERY=10 \
  -e FAIL_THRESHOLD=3 \
  -e RECOVER_SECONDS=60 \
  -e BACKUP_CONTAINER_NAME=backup-container \
  omar10594/container-watchdog:latest
```

### Building from Source

```bash
docker build -t container-watchdog .

docker run -d \
  --name watchdog \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e PRIMARY_HEALTH_URL=http://your-service:8080/health \
  -e CHECK_EVERY=10 \
  -e FAIL_THRESHOLD=3 \
  -e RECOVER_SECONDS=60 \
  -e BACKUP_CONTAINER_NAME=backup-container \
  container-watchdog
```

### Using Docker Compose

The watchdog can be deployed alongside your services or independently. The primary service **does not need to be in the same docker-compose file or even on the same host** - it can be any remote service accessible via HTTP.

#### Option 1: All services in the same docker-compose file

1. Update the `docker-compose.yml` with your service configuration
2. Start the services:

```bash
# Start backup service and watchdog (primary is remote)
docker-compose up -d

# Create the backup container (initially stopped)
docker-compose --profile backup up -d --no-start backup-container
```

#### Option 2: Watchdog in your own docker-compose file (Recommended)

Most users will want to copy just the watchdog service block and add it to their existing docker-compose files:

```yaml
services:
  # Your existing services here...
  
  # Add the watchdog service
  watchdog:
    image: omar10594/container-watchdog:latest
    container_name: watchdog
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - PRIMARY_HEALTH_URL=http://your-primary-service:8080/health
      - CHECK_EVERY=10
      - FAIL_THRESHOLD=3
      - RECOVER_SECONDS=60
      - BACKUP_CONTAINER_NAME=your-backup-container
    restart: unless-stopped
```

To build the image locally:
```bash
git clone https://github.com/omar10594/container-watchdog.git
cd container-watchdog
docker build -t container-watchdog:latest .
```

**Note**: 
- The primary service is monitored via its health URL only - this script does NOT manage the primary container
- External logic (outside this repo) should handle restarting the primary service
- This script only manages starting/stopping the backup container

## How It Works

1. **Normal Operation**: The watchdog continuously checks the primary service health endpoint (URL)
2. **Failure Detection**: When health checks fail, a failure counter increments
3. **Failover**: After reaching `FAIL_THRESHOLD` consecutive failures:
   - Backup container is started
   - Failure counter resets
4. **Recovery Detection**: After `RECOVER_SECONDS` since failover:
   - If primary health check passes, backup is stopped
   - If primary health check fails, backup remains active and check repeats after `RECOVER_SECONDS`
5. **Cycle**: The process repeats, continuously monitoring and managing containers

## Example Scenario

Consider a setup where you have a primary service (possibly remote) and a local backup service:

**Scenario**:
1. Primary service is running on any host (local or remote) and accessible via health URL
2. Local backup container exists but is stopped
3. Primary service becomes unhealthy (e.g., database connection lost, network issue)
4. After 3 failed checks (taking up to 30 seconds with default settings), watchdog:
   - Starts local `backup-container`
5. After 60 seconds, watchdog checks if primary is available again
6. If primary is healthy, backup is stopped; otherwise, backup remains active

**Important Notes**: 
- The watchdog does NOT manage the primary container/service
- External logic must handle restarting/recovering the primary service
- The watchdog only starts/stops the local backup container

## Testing

To test the failover mechanism:

```bash
# Start the watchdog (assuming backup container exists)
docker run -d \
  --name watchdog \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e PRIMARY_HEALTH_URL=http://your-primary:8080/health \
  -e BACKUP_CONTAINER_NAME=backup-container \
  omar10594/container-watchdog:latest

# Watch the watchdog logs
docker logs -f watchdog

# In another terminal, simulate a failure by making the primary unavailable
# (stop the primary service, block network, etc.)

# Watch the logs to see the failover happen
# After RECOVER_SECONDS, you'll see recovery checks
```

## Requirements

- Docker Engine with access to Docker socket (`/var/run/docker.sock`)
- Backup container must exist (can be stopped)
- Primary service health endpoint must be accessible from the watchdog container

### Working with Remote Primary Services

The watchdog monitors any HTTP-accessible health endpoint. The primary service can be:

1. **Local service**: On the same Docker host
2. **Remote service**: On a different host, in a different data center, or in the cloud
3. **Any HTTP endpoint**: As long as it's accessible from the watchdog container

The watchdog does NOT require Docker access to the primary service - it only needs HTTP access to the health endpoint.

Example for remote primary service:
```bash
docker run -d \
  --name watchdog \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e PRIMARY_HEALTH_URL=http://remote-primary:8080/health \
  -e BACKUP_CONTAINER_NAME=local-backup-container \
  omar10594/container-watchdog:latest
```

## Docker Hub

The image is automatically published to Docker Hub on commits to the main branch:
- **Image**: `omar10594/container-watchdog`
- **Tags**: `latest`, branch names, version tags (e.g., `v1.0.0`)

### Setting up Docker Hub Publishing

To enable automatic publishing, add these secrets to your GitHub repository:
1. `DOCKER_USERNAME`: Your Docker Hub username
2. `DOCKER_PASSWORD`: Your Docker Hub password or access token

## Security Considerations

- The watchdog container requires access to the Docker socket to manage the backup container
- Ensure proper network isolation between services
- Use Docker secrets for sensitive configuration in production
- Consider running the watchdog with appropriate Docker socket permissions

## Logs

The watchdog provides detailed logging:

```
[2024-01-07 12:00:00] === Container Failover Watchdog Started ===
[2024-01-07 12:00:00] Configuration:
[2024-01-07 12:00:00]   PRIMARY_HEALTH_URL: http://primary-service:80
[2024-01-07 12:00:00]   CHECK_EVERY: 10s
[2024-01-07 12:00:00]   FAIL_THRESHOLD: 3
[2024-01-07 12:00:00]   RECOVER_SECONDS: 60s
[2024-01-07 12:00:00]   BACKUP_CONTAINER_NAME: backup-container
[2024-01-07 12:00:00] ===========================================
[2024-01-07 12:00:10] Primary service check failed (1/3)
[2024-01-07 12:00:20] Primary service check failed (2/3)
[2024-01-07 12:00:30] Primary service check failed (3/3)
[2024-01-07 12:00:30] FAILOVER: Primary service has failed 3 times
[2024-01-07 12:00:30] FAILOVER: Starting backup container
[2024-01-07 12:00:30] Starting container: backup-container
[2024-01-07 12:00:30] FAILOVER: Completed. Backup container is now active
[2024-01-07 12:01:30] RECOVERY: Checking if primary service is available again
[2024-01-07 12:01:30] RECOVERY: Primary service is healthy, stopping backup
[2024-01-07 12:01:30] RECOVERY: Completed. Primary service is active, backup stopped
```

## License

This project is open source and available for use and modification.