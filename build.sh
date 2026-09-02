#!/bin/bash

source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/functions.sh

: "${ACTIVITY_SUB_TASK_CODE:?ERROR: ACTIVITY_SUB_TASK_CODE is not set}"

echo "===== START NEXUS UPLOAD ====="
# --------------------------------------------------
for VAR in FERNET_KEY ARTIFACTORY_REPOSITORY REPO_NAME; do
    if [[ -z "${!VAR:-}" ]]; then
        echo "ERROR: $VAR is not set"
        exit 1
    fi
done

# --------------------------------------------------
# Decrypt credentials and extract Nexus URL
# --------------------------------------------------
python3 - <<'PY' > /tmp/nexus_creds
import os
import json
from cryptography.fernet import Fernet

repo = json.loads(os.environ["ARTIFACTORY_REPOSITORY"])["integration_1"]
fernet = Fernet(os.environ["FERNET_KEY"].encode())

username = fernet.decrypt(
    repo["ARTIFACTORY_USERNAME"].encode()
).decode()

password = fernet.decrypt(
    repo["ARTIFACTORY_PASSWORD"].encode()
).decode()

# ARTIFACTORY_URL is the Nexus base URL stored inside the integration blob.
# Fall back to the standalone NEXUS_URL env var if present.
nexus_url = repo.get("ARTIFACTORY_URL") or os.environ.get("NEXUS_URL", "")

print(username)
print(password)
print(nexus_url)
PY

if [[ $? -ne 0 ]]; then
    echo "ERROR: Credential decryption failed"
    exit 1
fi

NEXUS_USERNAME=$(sed -n '1p' /tmp/nexus_creds)
NEXUS_PASSWORD=$(sed -n '2p' /tmp/nexus_creds)
# Use URL from integration blob; fall back to standalone NEXUS_URL env var.
_url_from_creds=$(sed -n '3p' /tmp/nexus_creds)
NEXUS_URL="${_url_from_creds:-${NEXUS_URL:-}}"

rm -f /tmp/nexus_creds

if [[ -z "$NEXUS_USERNAME" || -z "$NEXUS_PASSWORD" ]]; then
    echo "ERROR: Nexus username/password is empty after decryption"
    exit 1
fi

if [[ -z "$NEXUS_URL" ]]; then
    echo "ERROR: Nexus URL could not be determined (not in ARTIFACTORY_URL field or NEXUS_URL env var)"
    exit 1
fi

logInfoMessage "Nexus credentials decrypted successfully"
logInfoMessage "Nexus URL          : $NEXUS_URL"
logInfoMessage "Repository         : $REPO_NAME"

# --------------------------------------------------
# Codebase
# --------------------------------------------------
CODEBASE="${WORKSPACE}/${CODEBASE_DIR}"

if [[ ! -d "$CODEBASE" ]]; then
    echo "ERROR: Codebase not found: $CODEBASE"
    exit 1
fi

cd "${CODEBASE}" || { logErrorMessage "Failed to change directory to $CODEBASE"; exit 1; }

# --------------------------------------------------
# Upload function
# --------------------------------------------------
upload() {
    local FILE="$1"
    local URL="$2"
    local CURL_STATUS
    local HTTP_STATUS

    echo "----------------------------------------"
    echo "Uploading : $(basename "$FILE")"
    echo "URL       : $URL"

    curl -k -sS \
        -u "$NEXUS_USERNAME:$NEXUS_PASSWORD" \
        --upload-file "$FILE" \
        -o /tmp/nexus_response \
        -w "HTTP_STATUS=%{http_code}\n" \
        "$URL" > /tmp/nexus_curl_meta

    CURL_STATUS=$?

    HTTP_STATUS=$(grep -o 'HTTP_STATUS=[0-9]*' /tmp/nexus_curl_meta | cut -d= -f2)

    echo "Curl exit code : $CURL_STATUS"
    echo "HTTP status    : ${HTTP_STATUS:-unknown}"

    if [[ -s /tmp/nexus_response ]]; then
        echo "Nexus response:"
        cat /tmp/nexus_response
    fi

    rm -f /tmp/nexus_curl_meta /tmp/nexus_response

    # Fail on transport-level errors (curl itself failed)
    if [[ $CURL_STATUS -ne 0 ]]; then
        echo "ERROR: Curl failed (transport error)"
        return 1
    fi

    # Fail on non-2xx HTTP responses
    if [[ -z "$HTTP_STATUS" || "$HTTP_STATUS" -lt 200 || "$HTTP_STATUS" -ge 300 ]]; then
        echo "ERROR: Nexus rejected upload (HTTP $HTTP_STATUS)"
        return 1
    fi

    return 0
}

# --------------------------------------------------
# Process POM
# --------------------------------------------------
process_pom() {
    local POM="$1"
    local DIR
    local ARTIFACT
    local VERSION
    local GROUP
    local BASE
    local JAR

    DIR=$(dirname "$POM")

    echo ""
    echo "========================================"
    echo "Processing: $POM"
    echo "========================================"

    ARTIFACT=$(xmllint \
        --xpath "string(/*[local-name()='project']/*[local-name()='artifactId'])" \
        "$POM" 2>/dev/null)

    VERSION=$(xmllint \
        --xpath "string(/*[local-name()='project']/*[local-name()='version'])" \
        "$POM" 2>/dev/null)

    GROUP=$(xmllint \
        --xpath "string(/*[local-name()='project']/*[local-name()='groupId'])" \
        "$POM" 2>/dev/null)

    [[ -z "$VERSION" ]] && VERSION=$(xmllint \
        --xpath "string(/*[local-name()='project']/*[local-name()='parent']/*[local-name()='version'])" \
        "$POM" 2>/dev/null)

    [[ -z "$GROUP" ]] && GROUP=$(xmllint \
        --xpath "string(/*[local-name()='project']/*[local-name()='parent']/*[local-name()='groupId'])" \
        "$POM" 2>/dev/null)

    echo "Group    : $GROUP"
    echo "Artifact : $ARTIFACT"
    echo "Version  : $VERSION"

    if [[ -z "$ARTIFACT" || -z "$VERSION" || -z "$GROUP" ]]; then
        echo "ERROR: Could not read Maven information"
        return 1
    fi

    BASE="${NEXUS_URL}/repository/${REPO_NAME}/${GROUP//./\/}/$ARTIFACT/$VERSION"

    echo "Base URL : $BASE"

    # -----------------------------
    # Upload POM
    # -----------------------------
    if ! upload "$POM" "$BASE/$ARTIFACT-$VERSION.pom"; then
        echo "ERROR: POM upload failed"
        return 1
    fi

    echo "POM upload successful"

    # -----------------------------
    # Upload JAR
    # -----------------------------
    JAR="$DIR/target/$ARTIFACT-$VERSION.jar"

    if [[ ! -f "$JAR" ]]; then
        echo "WARNING: JAR not found: $JAR"
        echo "Continuing..."
        return 0
    fi

    if ! upload "$JAR" "$BASE/$ARTIFACT-$VERSION.jar"; then
        echo "ERROR: JAR upload failed"
        return 1
    fi

    echo "JAR upload successful"

    # -----------------------------
    # Checksums
    # -----------------------------
    echo "Generating checksums..."

    md5sum "$POM"  | awk '{print $1}' > "$POM.md5"
    sha1sum "$POM" | awk '{print $1}' > "$POM.sha1"
    md5sum "$JAR"  | awk '{print $1}' > "$JAR.md5"
    sha1sum "$JAR" | awk '{print $1}' > "$JAR.sha1"

    echo "Uploading checksums..."

    upload "$POM.md5"  "$BASE/$ARTIFACT-$VERSION.pom.md5"  || echo "WARNING: POM MD5 upload failed"
    upload "$POM.sha1" "$BASE/$ARTIFACT-$VERSION.pom.sha1" || echo "WARNING: POM SHA1 upload failed"
    upload "$JAR.md5"  "$BASE/$ARTIFACT-$VERSION.jar.md5"  || echo "WARNING: JAR MD5 upload failed"
    upload "$JAR.sha1" "$BASE/$ARTIFACT-$VERSION.jar.sha1" || echo "WARNING: JAR SHA1 upload failed"

    rm -f "$POM.md5" "$POM.sha1" "$JAR.md5" "$JAR.sha1"

    echo "========================================"
    echo "SUCCESS: $ARTIFACT:$VERSION"
    echo "========================================"

    return 0
}

# --------------------------------------------------
# Find and process POMs
# --------------------------------------------------
FAILED=0

while IFS= read -r POM; do

    process_pom "$POM"

    if [[ $? -ne 0 ]]; then
        echo "ERROR: Module failed: $POM"
        FAILED=1
    fi

done < <(
    find "$CODEBASE" \
        -mindepth 1 \
        -maxdepth 3 \
        -name "pom.xml" \
        | sort
)

# --------------------------------------------------
# Final result
# --------------------------------------------------
echo ""
echo "========================================"

if [[ $FAILED -eq 0 ]]; then
    echo "ALL MODULES COMPLETED"
    echo "========================================"
    FINAL_STATUS=0
else
    echo "ONE OR MORE MODULES FAILED"
    echo "========================================"
    FINAL_STATUS=1
fi

if [[ "${FINAL_STATUS}" -eq 0 ]]; then
    logInfoMessage "Congratulations ${ACTIVITY_SUB_TASK_CODE} succeeded!!!"
    _status_bool=true
else
    logErrorMessage "Please check ${ACTIVITY_SUB_TASK_CODE} failed!!!"
    _status_bool=false
fi

# Write summary.json with a proper boolean status value.
_exec_dir="/bp/execution_dir"
_out_dir="${_exec_dir}/${EXECUTION_TASK_ID}"
_summary="${_out_dir}/summary.json"

mkdir -p "${_out_dir}"

_existing=""
[[ -f "${_summary}" ]] && _existing=$(<"${_summary}")
[[ "${_existing}" != "["* ]] && _existing="[${_existing}]"

_msg="Congratulations ${ACTIVITY_SUB_TASK_CODE} succeeded!!!"
[[ "${FINAL_STATUS}" -ne 0 ]] && _msg="Please check ${ACTIVITY_SUB_TASK_CODE} failed!!!"

_updated=$(jq -c \
    --arg  key     "${ACTIVITY_SUB_TASK_CODE}" \
    --argjson status "${_status_bool}" \
    --arg  message "${_msg}" \
    '. += [{ ($key): { "status": $status, "message": $message } }]' \
    <<< "${_existing}")

echo "${_updated}" | jq "." > "${_summary}"

jq -n \
    --arg  key     "${ACTIVITY_SUB_TASK_CODE}" \
    --argjson status "${_status_bool}" \
    --arg  message "${_msg}" \
    '{ ($key): { "status": $status, "message": $message } }' \
    > "${_out_dir}/${ACTIVITY_SUB_TASK_CODE}.json"

echo "Job step response updated in: ${_summary}"

exit "${FINAL_STATUS}"
