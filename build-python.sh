#!/bin/bash
set -euo pipefail

source /opt/buildpiper/shell-functions/functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh

TASK_STATUS=0
CODEBASE_LOCATION="${WORKSPACE}/${CODEBASE_DIR}"

logInfoMessage "Processing at [$CODEBASE_LOCATION]"
sleep "${SLEEP_DURATION}"

cd "$CODEBASE_LOCATION"

logInfoMessage "Repository Format : ${REPOSITORY_FORMAT}"
logInfoMessage "Artifact          : ${ARTIFACT:-N/A}"
logInfoMessage "Artifact Path     : ${ARTIFACT_SOURCE_PATH}"

# ==========================================================
# Validate common variables
# ==========================================================

REQUIRED_VARS=(
    NEXUS_URL
    REPO_NAME
    REPOSITORY_FORMAT
    USERNAME
    PASSWORD
    ARTIFACT_SOURCE_PATH
)

for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        logErrorMessage "Missing variable: $var"
        exit 1
    fi
done

if [[ ! -f "${ARTIFACT_SOURCE_PATH}" ]]; then
    logErrorMessage "Artifact not found: ${ARTIFACT_SOURCE_PATH}"
    exit 1
fi

# ==========================================================
# RAW Repository Upload
# ==========================================================

upload_raw() {

    [[ -z "${ARTIFACT:-}" ]] && {
        logErrorMessage "ARTIFACT variable is required for RAW repository."
        exit 1
    }

    local DEST_URL="${NEXUS_URL}/repository/${REPO_NAME}/${ARTIFACT}"

    logInfoMessage "Uploading RAW artifact..."
    logInfoMessage "Destination: ${DEST_URL}"

    local TMP_FILE
    local HTTP_STATUS
    local BODY

    TMP_FILE=$(mktemp)

    HTTP_STATUS=$(curl -k \
        -u "${USERNAME}:${PASSWORD}" \
        --upload-file "${ARTIFACT_SOURCE_PATH}" \
        "${DEST_URL}" \
        -sS \
        -o "${TMP_FILE}" \
        -w "%{http_code}")

    BODY=$(cat "${TMP_FILE}")
    rm -f "${TMP_FILE}"

    if [[ "${HTTP_STATUS}" -lt 200 || "${HTTP_STATUS}" -ge 300 ]]; then
        logErrorMessage "Upload failed (HTTP ${HTTP_STATUS})"
        echo "${BODY}"
        exit 1
    fi

    logInfoMessage "RAW upload successful."
}

# ==========================================================
# PyPI Upload
# ==========================================================

upload_pypi() {

    command -v twine >/dev/null 2>&1 || {
        logErrorMessage "twine is not installed."
        exit 1
    }

    logInfoMessage "NEXUS_URL=${NEXUS_URL}"
    logInfoMessage "Repository=${REPO_NAME}"

    python3 --version
    python3 -m pip --version
    twine --version

    env | grep -Ei 'http|https|proxy|requests|ssl' || true

    curl -v "${NEXUS_URL}/repository/${REPO_NAME}/" || true

    twine upload \
        --verbose \
        --non-interactive \
        --disable-progress-bar \
        --repository-url "${NEXUS_URL}/repository/${REPO_NAME}/" \
        -u "${USERNAME}" \
        -p "${PASSWORD}" \
        "${ARTIFACT_SOURCE_PATH}"

    logInfoMessage "PyPI upload successful."
}

# ==========================================================
# Maven Upload
# ==========================================================

upload_maven() {

    REQUIRED_MAVEN=(
        GROUP_ID
        ARTIFACT_ID
        VERSION
    )

    for var in "${REQUIRED_MAVEN[@]}"; do
        [[ -z "${!var:-}" ]] && {
            logErrorMessage "Missing variable: $var"
            exit 1
        }
    done

    command -v mvn >/dev/null 2>&1 || {
        logErrorMessage "mvn is not installed."
        exit 1
    }

    logInfoMessage "Uploading Maven artifact..."

    mvn deploy:deploy-file \
        -Durl="${NEXUS_URL}/repository/${REPO_NAME}/" \
        -DrepositoryId=nexus \
        -Dfile="${ARTIFACT_SOURCE_PATH}" \
        -DgroupId="${GROUP_ID}" \
        -DartifactId="${ARTIFACT_ID}" \
        -Dversion="${VERSION}" \
        -Dpackaging="${PACKAGING:-jar}" \
        -DgeneratePom=true

    logInfoMessage "Maven upload successful."
}

# ==========================================================
# npm Upload
# ==========================================================

upload_npm() {

    command -v npm >/dev/null 2>&1 || {
        logErrorMessage "npm is not installed."
        exit 1
    }

    logInfoMessage "Publishing npm package..."

    npm config set registry "${NEXUS_URL}/repository/${REPO_NAME}/"

    npm config set \
        "//$(echo "${NEXUS_URL}" | sed 's#^https\?://##')/repository/${REPO_NAME}/:_auth" \
        "$(printf "%s:%s" "${USERNAME}" "${PASSWORD}" | base64 -w0)"

    npm publish "${ARTIFACT_SOURCE_PATH}"

    logInfoMessage "npm publish successful."
}

# ==========================================================
# NuGet Upload
# ==========================================================

upload_nuget() {

    command -v dotnet >/dev/null 2>&1 || {
        logErrorMessage "dotnet is not installed."
        exit 1
    }

    logInfoMessage "Uploading NuGet package..."

    dotnet nuget push "${ARTIFACT_SOURCE_PATH}" \
        --source "${NEXUS_URL}/repository/${REPO_NAME}/" \
        --api-key "${PASSWORD}"

    logInfoMessage "NuGet upload successful."
}

# ==========================================================
# Select Upload Method
# ==========================================================

case "${REPOSITORY_FORMAT,,}" in

    raw)
        upload_raw
        ;;

    pypi)
        upload_pypi
        ;;

    maven)
        upload_maven
        ;;

    npm)
        upload_npm
        ;;

    nuget)
        upload_nuget
        ;;

    *)
        logErrorMessage "Unsupported repository format: ${REPOSITORY_FORMAT}"
        exit 1
        ;;
esac

TASK_STATUS=0

logInfoMessage "Artifact uploaded successfully."

saveTaskStatus "$TASK_STATUS" "$ACTIVITY_SUB_TASK_CODE"