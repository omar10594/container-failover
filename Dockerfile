FROM docker:cli

# Install wget for health checks
RUN apk add --no-cache wget

# Copy the watchdog script
COPY watchdog.sh /watchdog.sh

# Make the script executable
RUN chmod +x /watchdog.sh

# Set environment variables with defaults
ENV PRIMARY_HEALTH_URL=http://localhost:8080/health
ENV CHECK_EVERY=10
ENV FAIL_THRESHOLD=3
ENV RECOVER_SECONDS=60
ENV CONTAINER_NAME=primary-container
ENV BACKUP_CONTAINER_NAME=backup-container

# Run the watchdog script
CMD ["/watchdog.sh"]
