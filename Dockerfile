FROM alpine:3.20

RUN apk add --no-cache \
    bash \
    curl \
    ca-certificates \
    python3 \
    py3-pip \
    libxml2-utils \
    jq && \
    update-ca-certificates

RUN python3 -m pip install \
    --no-cache-dir \
    --break-system-packages \
    --upgrade pip twine

RUN python3 --version && \
    python3 -m pip --version && \
    xmllint --version && \
    twine --version && \
    jq --version

# -------------------------------------------------------
# Create non-root user (UID/GID 65522)
# -------------------------------------------------------
RUN addgroup -g 65522 buildpiper && \
    adduser -D -u 65522 -G buildpiper -h /home/buildpiper buildpiper

# -------------------------------------------------------
# Create BuildPiper directory
# -------------------------------------------------------
RUN mkdir -p /bp && \
    chown -R buildpiper:buildpiper /bp

# -------------------------------------------------------
# Working directory
# -------------------------------------------------------
WORKDIR /home/buildpiper

# -------------------------------------------------------
# Copy files
# -------------------------------------------------------
COPY --chown=65522:65522 build-jfrog.sh /home/buildpiper/build-jfrog.sh
COPY --chown=65522:65522 BP-BASE-SHELL-STEPS /opt/buildpiper/shell-functions/

# -------------------------------------------------------
# Permissions
# -------------------------------------------------------
RUN chmod +x /home/buildpiper/build-jfrog.sh

# -------------------------------------------------------
# Default environment variables
# -------------------------------------------------------
ENV SLEEP_DURATION=5
ENV ACTIVITY_SUB_TASK_CODE=NEXUS_UPLOAD_ARTIFACT
ENV VALIDATION_FAILURE_ACTION=WARNING

# -------------------------------------------------------
# Run as non-root
# -------------------------------------------------------
USER 65522:65522

# -------------------------------------------------------
# Entry point
# -------------------------------------------------------
ENTRYPOINT ["/home/buildpiper/build-jfrog.sh"]