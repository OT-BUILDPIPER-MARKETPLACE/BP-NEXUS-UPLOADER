#!/bin/bash
set -euo pipefail
source /opt/buildpiper/shell-functions/functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh

TASK_STATUS=0
CODEBASE_LOCATION="${WORKSPACE}/${CODEBASE_DIR}"

logInfoMessage "Processing at [$CODEBASE_LOCATION]"
sleep $SLEEP_DURATION

cd "$CODEBASE_LOCATION" || exit 1

# ==============================
# 🔹 CHECK xmllint
# ==============================
command -v xmllint >/dev/null 2>&1 || {
  logErrorMessage "xmllint is required but not installed"
  exit 1
}

# ==============================
# 🔹 READ FROM POM.XML
# ==============================
ARTIFACT=$(xmllint --xpath "string(/*[local-name()='project']/*[local-name()='artifactId'])" pom.xml)

VERSION=$(xmllint --xpath "string(/*[local-name()='project']/*[local-name()='version'])" pom.xml)
[[ -z "$VERSION" ]] && VERSION=$(xmllint --xpath "string(/*[local-name()='project']/*[local-name()='parent']/*[local-name()='version'])" pom.xml)
JAR_NAME_SOURCE="${ARTIFACT}-${VERSION}.jar"
JAR_FILE_SOURCE="target/${JAR_NAME_SOURCE}"
POM_FILE="pom.xml"

if [[ ! -f "$JAR_FILE_SOURCE" ]]; then
    logErrorMessage "Jar not found: $JAR_FILE_SOURCE"
    exit 1
fi

VERSION=${VERSION/-SNAPSHOT/}
JAR_NAME="${ARTIFACT}-${VERSION}.jar"
POM_NAME="${ARTIFACT}-${VERSION}.pom"

# Prefer parent groupId (your requirement)
GROUP_ID=$(xmllint --xpath "string(/*[local-name()='project']/*[local-name()='parent']/*[local-name()='groupId'])" pom.xml)
[[ -z "$GROUP_ID" ]] && GROUP_ID=$(xmllint --xpath "string(/*[local-name()='project']/*[local-name()='groupId'])" pom.xml)

GROUP_ID_PATH=$(echo "$GROUP_ID" | tr '.' '/')



# ==============================
# 🔹 VALIDATION
# ==============================
if [[ -z "$ARTIFACT" || -z "$GROUP_ID" || -z "$VERSION" ]]; then
    logErrorMessage "Failed to read artifact details from pom.xml"
    exit 1
fi

logInfoMessage "Artifact: $ARTIFACT"
logInfoMessage "Group ID: $GROUP_ID"
logInfoMessage "Group Path: $GROUP_ID_PATH"
logInfoMessage "Version: $VERSION"
logInfoMessage "Jar: $JAR_NAME"
logInfoMessage "Jar File Source: $JAR_FILE_SOURCE"

# ==============================
# 🔹 REQUIRED VARS
# ==============================
REQUIRED_VARS=(NEXUS_URL REPO_NAME USERNAME PASSWORD)

for var in "${REQUIRED_VARS[@]}"; do
  [[ -z "${!var}" ]] && { logErrorMessage "Missing variable: $var"; exit 1; }
done

# ==============================
# 🔹 FILE PATHS
# ==============================


# ==============================
# 🔹 GENERATE CHECKSUMS
# ==============================
logInfoMessage "Generating checksums..."

md5sum "$JAR_FILE_SOURCE" | awk '{print $1}' > "${JAR_FILE_SOURCE}.md5"
sha1sum "$JAR_FILE_SOURCE" | awk '{print $1}' > "${JAR_FILE_SOURCE}.sha1"

md5sum "$POM_FILE" | awk '{print $1}' > "${POM_FILE}.md5"
sha1sum "$POM_FILE" | awk '{print $1}' > "${POM_FILE}.sha1"

# ==============================
# 🔹 UPLOAD FUNCTION
# ==============================

upload_file() {
  local FILE_PATH=$1
  local DEST_URL=$2


  logInfoMessage "Uploading $(basename "$FILE_PATH")"
  TMP_FILE=$(mktemp)

  HTTP_STATUS=$(curl -k \
    -u "${USERNAME}:${PASSWORD}" \
    --upload-file "$FILE_PATH" \
    "$DEST_URL" \
    -sS -o $TMP_FILE \
    -w "%{http_code}") || {
        logErrorMessage "Curl command failed for $(basename "$FILE_PATH")"
        exit 1
    }

  BODY=$(cat $TMP_FILE)
  rm -f "$TMP_FILE"


  #Fail on HTTP error
  if [[ "$HTTP_STATUS" -lt 200 || "$HTTP_STATUS" -ge 300 ]]; then
      logErrorMessage "Upload failed for $(basename "$FILE_PATH") (HTTP $HTTP_STATUS)"
      echo "$BODY"
      exit 1
  fi

  logInfoMessage "Uploaded $(basename "$FILE_PATH") successfully"
}

# ==============================
# 🔹 CONSTRUCT URL
# ==============================
BASE_URL="${NEXUS_URL}/repository/${REPO_NAME}/${GROUP_ID_PATH}/${ARTIFACT}/${VERSION}"

logInfoMessage "Base URL: $BASE_URL"

# ==============================
# 🔹 UPLOAD ARTIFACTS
# ==============================
upload_file "$JAR_FILE_SOURCE" "$BASE_URL/${JAR_NAME}" || exit 1
upload_file "${JAR_FILE_SOURCE}.md5" "$BASE_URL/${JAR_NAME}.md5" || exit 1
upload_file "${JAR_FILE_SOURCE}.sha1" "$BASE_URL/${JAR_NAME}.sha1" || exit 1

upload_file "$POM_FILE" "$BASE_URL/${POM_NAME}" || exit 1
upload_file "${POM_FILE}.md5" "$BASE_URL/${POM_NAME}.md5" || exit 1
upload_file "${POM_FILE}.sha1" "$BASE_URL/${POM_NAME}.sha1" || exit 1

# ==============================
# 🔹 CLEANUP (optional)
# ==============================
rm -f "${JAR_FILE_SOURCE}.md5" "${JAR_FILE_SOURCE}.sha1" "${POM_FILE}.md5" "${POM_FILE}.sha1"

# ==============================
# 🔹 FINAL STATUS
# ==============================

logInfoMessage "All artifacts uploaded successfully"

saveTaskStatus "$TASK_STATUS" "$ACTIVITY_SUB_TASK_CODE"