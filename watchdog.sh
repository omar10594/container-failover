#!/bin/sh

# Container Failover Watchdog Script
# Monitors a primary service health URL and manages backup container failover
# NOTE: This script does NOT manage the primary container as it may be remote.
#       External logic should handle primary container recovery.

# Configuration from environment variables with defaults
PRIMARY_HEALTH_URL="${PRIMARY_HEALTH_URL:-http://localhost:8080/health}"
CHECK_EVERY="${CHECK_EVERY:-10}"
FAIL_THRESHOLD="${FAIL_THRESHOLD:-3}"
RECOVER_SECONDS="${RECOVER_SECONDS:-60}"
BACKUP_CONTAINER_NAME="${BACKUP_CONTAINER_NAME:-backup-container}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-5}"

# Internal state variables
fail_count=0
backup_active=false
last_failover_time=0

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_health() {
    local url=$1
    if wget --spider --timeout="$HEALTH_CHECK_TIMEOUT" --tries=1 "$url" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

start_container() {
    local container=$1
    log "Starting container: $container"
    if docker ps -a -q -f name="^${container}$" | grep -q .; then
        if ! docker start "$container" 2>/dev/null; then
            log "Warning: Failed to start $container"
        fi
    else
        log "Container $container does not exist"
    fi
}

stop_container() {
    local container=$1
    log "Stopping container: $container"
    if docker ps -q -f name="^${container}$" | grep -q .; then
        if ! docker stop "$container" 2>/dev/null; then
            log "Warning: Failed to stop $container"
        fi
    else
        log "Container $container is not running"
    fi
}

perform_failover() {
    log "FAILOVER: Primary service has failed $FAIL_THRESHOLD times"
    log "FAILOVER: Starting backup container"
    
    start_container "$BACKUP_CONTAINER_NAME"
    
    backup_active=true
    last_failover_time=$(date +%s)
    fail_count=0
    
    log "FAILOVER: Completed. Backup container is now active"
}

attempt_recovery() {
    local current_time=$(date +%s)
    local time_since_failover=$((current_time - last_failover_time))
    
    if [ "$time_since_failover" -ge "$RECOVER_SECONDS" ]; then
        log "RECOVERY: Checking if primary service is available again"
        
        if check_health "$PRIMARY_HEALTH_URL"; then
            log "RECOVERY: Primary service is healthy, stopping backup"
            stop_container "$BACKUP_CONTAINER_NAME"
            backup_active=false
            fail_count=0
            log "RECOVERY: Completed. Primary service is active, backup stopped"
        else
            log "RECOVERY: Primary service still unhealthy, keeping backup active"
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
log "  BACKUP_CONTAINER_NAME: $BACKUP_CONTAINER_NAME"
log "==========================================="

while true; do
    if [ "$backup_active" = false ]; then
        # Backup is not active, check primary health
        if check_health "$PRIMARY_HEALTH_URL"; then
            if [ "$fail_count" -gt 0 ]; then
                log "Primary service recovered (was failing $fail_count times)"
            fi
            fail_count=0
        else
            fail_count=$((fail_count + 1))
            log "Primary service check failed ($fail_count/$FAIL_THRESHOLD)"
            
            if [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
                perform_failover
            fi
        fi
    else
        # Backup is active, check if primary is available again
        attempt_recovery
    fi
    
    sleep "$CHECK_EVERY"
done
