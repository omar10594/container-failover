#!/bin/sh

# Container Failover Watchdog Script
# Monitors a primary service and manages container failover

set -e

# Configuration from environment variables with defaults
PRIMARY_HEALTH_URL="${PRIMARY_HEALTH_URL:-http://localhost:8080/health}"
CHECK_EVERY="${CHECK_EVERY:-10}"
FAIL_THRESHOLD="${FAIL_THRESHOLD:-3}"
RECOVER_SECONDS="${RECOVER_SECONDS:-60}"
CONTAINER_NAME="${CONTAINER_NAME:-primary-container}"
BACKUP_CONTAINER_NAME="${BACKUP_CONTAINER_NAME:-backup-container}"

# Internal state variables
fail_count=0
primary_down=false
last_failover_time=0

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_health() {
    local url=$1
    if wget --spider --timeout=5 --tries=1 "$url" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

stop_container() {
    local container=$1
    log "Stopping container: $container"
    if docker ps -q -f name="^${container}$" | grep -q .; then
        docker stop "$container" || log "Warning: Failed to stop $container"
    else
        log "Container $container is not running"
    fi
}

start_container() {
    local container=$1
    log "Starting container: $container"
    if docker ps -a -q -f name="^${container}$" | grep -q .; then
        docker start "$container" || log "Warning: Failed to start $container"
    else
        log "Container $container does not exist"
    fi
}

is_container_running() {
    local container=$1
    docker ps -q -f name="^${container}$" | grep -q .
}

perform_failover() {
    log "FAILOVER: Primary service has failed $FAIL_THRESHOLD times"
    log "FAILOVER: Stopping primary container and starting backup"
    
    stop_container "$CONTAINER_NAME"
    start_container "$BACKUP_CONTAINER_NAME"
    
    primary_down=true
    last_failover_time=$(date +%s)
    fail_count=0
    
    log "FAILOVER: Completed. Backup container is now active"
}

attempt_recovery() {
    local current_time=$(date +%s)
    local time_since_failover=$((current_time - last_failover_time))
    
    if [ "$time_since_failover" -ge "$RECOVER_SECONDS" ]; then
        log "RECOVERY: Attempting to recover primary service"
        
        start_container "$CONTAINER_NAME"
        sleep 5
        
        if check_health "$PRIMARY_HEALTH_URL"; then
            log "RECOVERY: Primary service is healthy, switching back"
            stop_container "$BACKUP_CONTAINER_NAME"
            primary_down=false
            fail_count=0
            log "RECOVERY: Completed. Primary container is now active"
        else
            log "RECOVERY: Primary service still unhealthy, keeping backup active"
            stop_container "$CONTAINER_NAME"
            last_failover_time=$current_time
        fi
    fi
}

# Main watchdog loop
log "=== Container Failover Watchdog Started ==="
log "Configuration:"
log "  PRIMARY_HEALTH_URL: $PRIMARY_HEALTH_URL"
log "  CHECK_EVERY: ${CHECK_EVERY}s"
log "  FAIL_THRESHOLD: $FAIL_THRESHOLD"
log "  RECOVER_SECONDS: ${RECOVER_SECONDS}s"
log "  CONTAINER_NAME: $CONTAINER_NAME"
log "  BACKUP_CONTAINER_NAME: $BACKUP_CONTAINER_NAME"
log "==========================================="

while true; do
    if [ "$primary_down" = false ]; then
        # Primary is supposed to be active, check its health
        if check_health "$PRIMARY_HEALTH_URL"; then
            if [ "$fail_count" -gt 0 ]; then
                log "Primary service recovered (was failing $fail_count times)"
            fi
            fail_count=0
            log "Primary service is healthy"
        else
            fail_count=$((fail_count + 1))
            log "Primary service check failed ($fail_count/$FAIL_THRESHOLD)"
            
            if [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
                perform_failover
            fi
        fi
    else
        # Primary is down, check if it's time to attempt recovery
        attempt_recovery
    fi
    
    sleep "$CHECK_EVERY"
done
