# Container Failover Watchdog

A Docker-based failover/watchdog service that monitors the health of a primary service and automatically switches to a backup container when the primary service fails.

## Overview

This watchdog monitors a primary service's health endpoint and manages automatic failover to a backup container when the primary service becomes unavailable. After a configurable recovery period, it attempts to restore the primary service.

## Features

- **Health Monitoring**: Continuously checks the primary service health endpoint
- **Automatic Failover**: Switches to backup container after consecutive failures
- **Automatic Recovery**: Attempts to restore primary service after a recovery period
- **Configurable Thresholds**: Customize check intervals, failure thresholds, and recovery times
- **Docker-based**: Lightweight container based on `docker:cli` image

## Configuration

The watchdog is configured using environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `PRIMARY_HEALTH_URL` | URL to check for primary service health | `http://localhost:8080/health` |
| `CHECK_EVERY` | Health check interval in seconds | `10` |
| `FAIL_THRESHOLD` | Number of consecutive failures before failover | `3` |
| `RECOVER_SECONDS` | Time to wait before attempting recovery | `60` |
| `CONTAINER_NAME` | Name of the primary container to manage | `primary-container` |
| `BACKUP_CONTAINER_NAME` | Name of the backup container to start on failover | `backup-container` |
| `HEALTH_CHECK_TIMEOUT` | Timeout for health check requests in seconds | `5` |
| `CONTAINER_START_WAIT` | Time to wait for container to start before health check | `5` |

## Usage

### Using Docker Run

```bash
docker build -t container-failover .

docker run -d \
  --name watchdog \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e PRIMARY_HEALTH_URL=http://your-service:8080/health \
  -e CHECK_EVERY=10 \
  -e FAIL_THRESHOLD=3 \
  -e RECOVER_SECONDS=60 \
  -e CONTAINER_NAME=primary-container \
  -e BACKUP_CONTAINER_NAME=backup-container \
  container-failover
```

### Using Docker Compose

The watchdog can be deployed alongside your services or independently. The primary and backup containers **do not need to be in the same docker-compose file** - they can be remote services running on different hosts.

#### Option 1: All services in the same docker-compose file

1. Update the `docker-compose.yml` with your service configuration
2. Start the services:

```bash
# Start primary service and watchdog
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
    build: ./path/to/container-failover  # Build from cloned repo
    # OR use a pre-built image:
    # image: container-failover:latest
    container_name: watchdog
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - PRIMARY_HEALTH_URL=http://your-primary-service:8080/health
      - CHECK_EVERY=10
      - FAIL_THRESHOLD=3
      - RECOVER_SECONDS=60
      - CONTAINER_NAME=your-primary-container
      - BACKUP_CONTAINER_NAME=your-backup-container
    restart: unless-stopped
```

To build the image locally:
```bash
git clone https://github.com/omar10594/container-failover.git
cd container-failover
docker build -t container-failover:latest .
```

**Note**: The primary and backup containers can be:
- In the same docker-compose file
- In different docker-compose files on the same host
- On completely different remote hosts (as long as they're accessible via Docker socket or remote Docker API)

## How It Works

1. **Normal Operation**: The watchdog continuously checks the primary service health endpoint
2. **Failure Detection**: When health checks fail, a failure counter increments
3. **Failover**: After reaching `FAIL_THRESHOLD` consecutive failures:
   - Primary container is stopped
   - Backup container is started
   - Failure counter resets
4. **Recovery Attempt**: After `RECOVER_SECONDS` since failover:
   - Primary container is started
   - If health check passes, backup is stopped and primary takes over
   - If health check fails, primary is stopped and backup remains active
5. **Cycle**: The process repeats, continuously monitoring and managing containers

## Example Scenario

Consider a setup where you have a primary service and a backup service. These services can be:
- On the same Docker host
- On different Docker hosts (remote services)
- In different data centers or availability zones

**Scenario**:
1. Both containers exist: `primary-container` and `backup-container` (can be on same or different hosts)
2. Primary is running, backup is stopped
3. Primary service becomes unhealthy (e.g., database connection lost)
4. After 3 failed checks (taking up to 30 seconds with default settings), watchdog:
   - Stops `primary-container`
   - Starts `backup-container`
5. After 60 seconds, watchdog attempts to start primary
6. If primary is healthy again, it switches back; otherwise, backup remains active

**Note**: During failover transitions, there may be brief periods (a few seconds) where both containers are running or both are stopped.

## Testing

To test the failover mechanism:

```bash
# Start the services
docker-compose up -d

# Watch the watchdog logs
docker logs -f watchdog

# In another terminal, simulate a failure by stopping the primary container
docker stop primary-container

# Watch the logs to see the failover happen
# After RECOVER_SECONDS, you'll see recovery attempts
```

## Requirements

- Docker Engine with access to Docker socket (`/var/run/docker.sock`)
- Primary and backup containers must exist (can be stopped)
- Health endpoint must be accessible from the watchdog container

### Working with Remote Containers

The watchdog can manage containers on remote Docker hosts by configuring the Docker client to connect to a remote Docker daemon. You have several options:

1. **Local containers**: Default behavior, manages containers on the same host via `/var/run/docker.sock`
2. **Remote Docker API**: Set `DOCKER_HOST` environment variable to connect to a remote Docker daemon
3. **Docker Context**: Use Docker contexts to switch between different Docker environments

Example for remote containers:
```bash
docker run -d \
  --name watchdog \
  -e DOCKER_HOST=tcp://remote-host:2376 \
  -e PRIMARY_HEALTH_URL=http://remote-primary:8080/health \
  -e CONTAINER_NAME=remote-primary-container \
  -e BACKUP_CONTAINER_NAME=remote-backup-container \
  container-failover
```

## Security Considerations

- The watchdog container requires access to the Docker socket to manage containers
- Ensure proper network isolation between services
- Use Docker secrets for sensitive configuration in production
- Consider running the watchdog with appropriate Docker socket permissions

## Logs

The watchdog provides detailed logging:

```
[2024-01-07 12:00:00] === Container Failover Watchdog Started ===
[2024-01-07 12:00:00] Configuration:
[2024-01-07 12:00:00]   PRIMARY_HEALTH_URL: http://primary-container:80
[2024-01-07 12:00:00]   CHECK_EVERY: 10s
[2024-01-07 12:00:00]   FAIL_THRESHOLD: 3
[2024-01-07 12:00:00]   RECOVER_SECONDS: 60s
[2024-01-07 12:00:00]   CONTAINER_NAME: primary-container
[2024-01-07 12:00:00]   BACKUP_CONTAINER_NAME: backup-container
[2024-01-07 12:00:00] ===========================================
[2024-01-07 12:00:10] Primary service check failed (1/3)
[2024-01-07 12:00:20] Primary service check failed (2/3)
[2024-01-07 12:00:30] Primary service check failed (3/3)
[2024-01-07 12:00:30] FAILOVER: Primary service has failed 3 times
[2024-01-07 12:00:30] FAILOVER: Stopping primary container and starting backup
```

## License

This project is open source and available for use and modification.