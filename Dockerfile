FROM ubuntu:22.04

# ============================================================
# INSTALL REQUIRED PACKAGES
# ============================================================

RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    libxml2-utils \
    coreutils \
    jq \
    python3 \
    python3-cryptography \
    && rm -rf /var/lib/apt/lists/*


# VALIDATION_FAILURE_ACTION is kept for compatibility with other
# functions in functions.sh that may reference it. Not used by
# the nexus upload logic directly.
ENV VALIDATION_FAILURE_ACTION WARNING

# Do NOT hardcode ACTIVITY_SUB_TASK_CODE here. The platform injects
# the real step name at container runtime. Hardcoding a value would
# cause generateOutput to write the wrong key to summary.json and
# the platform would not find its expected step entry.


# ============================================================
# CREATE BUILDPIPER USER
# ============================================================

RUN groupadd -g 65522 buildpiper && \
    useradd -u 65522 \
    -g buildpiper \
    -m \
    -s /bin/bash \
    buildpiper


# ============================================================
# CREATE DIRECTORIES
# ============================================================

RUN mkdir -p /opt/buildpiper/shell-functions

# generateOutput() in functions.sh writes to
# /bp/execution_dir/<EXECUTION_TASK_ID>/summary.json.
# Pre-create the base directory and give ownership to the
# buildpiper user so the runtime mkdir -p always succeeds.
RUN mkdir -p /bp/execution_dir


# ============================================================
# COPY BUILDPIPER SHELL FUNCTIONS
# ============================================================

COPY BP-BASE-SHELL-STEPS /opt/buildpiper/shell-functions/


# ============================================================
# COPY BUILD SCRIPT
# ============================================================

COPY build.sh /opt/buildpiper/build.sh


# ============================================================
# SET PERMISSIONS
# ============================================================

RUN chown -R buildpiper:buildpiper /opt/buildpiper /bp && \
    chmod +x /opt/buildpiper/build.sh


# ============================================================
# SWITCH TO BUILDPIPER USER
# ============================================================

USER buildpiper

WORKDIR /opt/buildpiper


# ============================================================
# ENTRYPOINT
# ============================================================

ENTRYPOINT ["./build.sh"]
