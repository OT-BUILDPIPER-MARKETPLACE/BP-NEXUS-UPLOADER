FROM alpine:3.20

# ------------------------------
# Install required packages
# ------------------------------
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    libxml2-utils \
    coreutils \
    ca-certificates && \
    update-ca-certificates

# ------------------------------
# Create non-root user (65522)
# ------------------------------
RUN addgroup -g 65522 buildpiper && \
    adduser -D -u 65522 -G buildpiper buildpiper
RUN mkdir /bp && \
    chown -R buildpiper:buildpiper /bp
# ------------------------------
# Set working directory
# ------------------------------
WORKDIR /home/buildpiper

# ------------------------------
# Copy files with ownership
# ------------------------------
COPY --chown=65522:65522 build.sh /home/buildpiper/build.sh
COPY --chown=65522:65522 BP-BASE-SHELL-STEPS /opt/buildpiper/shell-functions/

# ------------------------------
# Permissions
# ------------------------------
RUN chmod +x /home/buildpiper/build.sh

# ------------------------------
# Environment variables
# ------------------------------
ENV SLEEP_DURATION=5
ENV ACTIVITY_SUB_TASK_CODE=NEXUS_UPLOAD_ARTIFACT
ENV VALIDATION_FAILURE_ACTION=WARNING

# ------------------------------
# Switch to non-root user
# ------------------------------
USER 65522:65522

# ------------------------------
# Entry point
# ------------------------------
ENTRYPOINT ["/home/buildpiper/build.sh"]