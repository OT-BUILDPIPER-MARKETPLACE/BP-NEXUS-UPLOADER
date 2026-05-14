#!/bin/bash
set -euo pipefail
source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/functions.sh

# ==============================
# 🔹 CONFIGURATION
# ==============================
NEXUS_URL="${NEXUS_URL:-http://your-nexus-url}"
REPO_NAME="${REPO_NAME:-your-repo-name}"
USERNAME="${USERNAME:-admin}"
PASSWORD="${PASSWORD:-admin123}"

CODEBASE_LOCATION="${WORKSPACE}/${CODEBASE_DIR}"
logInfoMessage " Processing at [$CODEBASE_LOCATION]"
cd "$CODEBASE_LOCATION"
# ==============================
# 🔹 CHECK xmllint
# ==============================
command -v xmllint >/dev/null 2>&1 || {
  logInfoMessage " xmllint is required but not installed"
  exit 1
}

# ==============================
# 🔹 UPLOAD FUNCTION
# ==============================
upload_file() {
  local FILE_PATH=$1
  local DEST_URL=$2

  logInfoMessage " Uploading $(basename "$FILE_PATH") → $DEST_URL"
  TMP_FILE=$(mktemp)

  HTTP_STATUS=$(curl -k \
    -u "${USERNAME}:${PASSWORD}" \
    --upload-file "$FILE_PATH" \
    "$DEST_URL" \
    -sS -o "$TMP_FILE" \
    -w "%{http_code}") || {
      logInfoMessage " Curl failed for $(basename "$FILE_PATH")"
      rm -f "$TMP_FILE"
      return 1
    }

  BODY=$(cat "$TMP_FILE")
  rm -f "$TMP_FILE"

  if [[ "$HTTP_STATUS" -lt 200 || "$HTTP_STATUS" -ge 300 ]]; then
    logInfoMessage " Upload failed for $(basename "$FILE_PATH") (HTTP $HTTP_STATUS)"
    logInfoMessage "$BODY"
    return 1
  fi

  logInfoMessage " ✅ Uploaded $(basename "$FILE_PATH") successfully (HTTP $HTTP_STATUS)"
}

# ==============================
# 🔹 PROCESS EACH SUBMODULE
# ==============================
FAILED_MODULES=()

# Find all pom.xml except root
find "$CODEBASE_LOCATION" -mindepth 3 -maxdepth 3 -name "pom.xml" | sort | while read -r POM_FILE; do

  MODULE_DIR=$(dirname "$POM_FILE")
  MODULE_NAME=$(basename "$MODULE_DIR")
  MODULE_PATH=${MODULE_DIR}/${CODEBASE_DIR}
  logInfoMessage "================================================"
  logInfoMessage " 🔹 Processing module: $MODULE_NAME"
  logInfoMessage "================================================"

  # --- Read artifactId ---
  ARTIFACT=$(xmllint --xpath "string(/*[local-name()='project']/*[local-name()='artifactId'])" "$POM_FILE" 2>/dev/null)

  # --- Read version (own → parent fallback) ---
  VERSION=$(xmllint --xpath "string(/*[local-name()='project']/*[local-name()='version'])" "$POM_FILE" 2>/dev/null)
  [[ -z "$VERSION" ]] && VERSION=$(xmllint --xpath "string(/*[local-name()='project']/*[local-name()='parent']/*[local-name()='version'])" "$POM_FILE" 2>/dev/null)

  # --- Read groupId (parent preferred) ---
  GROUP_ID=$(xmllint --xpath "string(/*[local-name()='project']/*[local-name()='parent']/*[local-name()='groupId'])" "$POM_FILE" 2>/dev/null)
  [[ -z "$GROUP_ID" ]] && GROUP_ID=$(xmllint --xpath "string(/*[local-name()='project']/*[local-name()='groupId'])" "$POM_FILE" 2>/dev/null)

  # --- Validation ---
  if [[ -z "$ARTIFACT" || -z "$VERSION" || -z "$GROUP_ID" ]]; then
    logInfoMessage " Skipping $MODULE_NAME — could not read artifact/version/groupId from pom.xml"
    continue
  fi

  # --- Find JAR in target/ ---
  JAR_FILE_SOURCE="${MODULE_DIR}/target/${ARTIFACT}-${VERSION}.jar"

  if [[ ! -f "$JAR_FILE_SOURCE" ]]; then
    logInfoMessage " Skipping $MODULE_NAME — JAR not found: $JAR_FILE_SOURCE"
    continue
  fi

  UPLOAD_VERSION="${VERSION}"
  GROUP_ID_PATH=$(echo "$GROUP_ID" | tr '.' '/')

  JAR_NAME="${ARTIFACT}-${UPLOAD_VERSION}.jar"
  POM_NAME="${ARTIFACT}-${UPLOAD_VERSION}.pom"
  BASE_URL="${NEXUS_URL}/repository/${REPO_NAME}/${GROUP_ID_PATH}/${ARTIFACT}/${UPLOAD_VERSION}"

  logInfoMessage " Artifact  : $ARTIFACT"
  logInfoMessage " GroupId   : $GROUP_ID"
  logInfoMessage " Version   : $UPLOAD_VERSION"
  logInfoMessage " JAR source: $JAR_FILE_SOURCE"
  logInfoMessage " Base URL  : $BASE_URL"

  # --- Generate checksums ---
  logInfoMessage " Generating checksums..."
  md5sum  "$JAR_FILE_SOURCE" | awk '{print $1}' > "${JAR_FILE_SOURCE}.md5"
  sha1sum "$JAR_FILE_SOURCE" | awk '{print $1}' > "${JAR_FILE_SOURCE}.sha1"
  md5sum  "$POM_FILE"        | awk '{print $1}' > "${POM_FILE}.md5"
  sha1sum "$POM_FILE"        | awk '{print $1}' > "${POM_FILE}.sha1"

  # --- Upload ---
  upload_file "$JAR_FILE_SOURCE"          "$BASE_URL/${JAR_NAME}"      || { FAILED_MODULES+=("$MODULE_NAME"); continue; }
  upload_file "${JAR_FILE_SOURCE}.md5"    "$BASE_URL/${JAR_NAME}.md5"  || { FAILED_MODULES+=("$MODULE_NAME"); continue; }
  upload_file "${JAR_FILE_SOURCE}.sha1"   "$BASE_URL/${JAR_NAME}.sha1" || { FAILED_MODULES+=("$MODULE_NAME"); continue; }

  upload_file "$POM_FILE"                 "$BASE_URL/${POM_NAME}"      || { FAILED_MODULES+=("$MODULE_NAME"); continue; }
  upload_file "${POM_FILE}.md5"           "$BASE_URL/${POM_NAME}.md5"  || { FAILED_MODULES+=("$MODULE_NAME"); continue; }
  upload_file "${POM_FILE}.sha1"          "$BASE_URL/${POM_NAME}.sha1" || { FAILED_MODULES+=("$MODULE_NAME"); continue; }

  # --- Cleanup temp checksums ---
  rm -f "${JAR_FILE_SOURCE}.md5" "${JAR_FILE_SOURCE}.sha1" "${POM_FILE}.md5" "${POM_FILE}.sha1"

  logInfoMessage " ✅ Module $MODULE_NAME pushed successfully"
done
TASK_STATUS=$?
# ==============================
# 🔹 FINAL SUMMARY
# ==============================
logInfoMessage ""
logInfoMessage "================================================"
if [[ ${#FAILED_MODULES[@]} -gt 0 ]]; then
  logInfoMessage " ❌ Failed modules: ${FAILED_MODULES[*]}"
  exit 1
else
  logInfoMessage " 🎉 All modules uploaded successfully!"
fi
saveTaskStatus "$TASK_STATUS" "$ACTIVITY_SUB_TASK_CODE"
