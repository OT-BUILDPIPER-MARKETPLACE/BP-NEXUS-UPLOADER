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
logInfoMessage "Processing at [$CODEBASE_LOCATION]"
cd "$CODEBASE_LOCATION"

# ==============================
# 🔹 CHECK xmllint
# ==============================
command -v xmllint >/dev/null 2>&1 || {
  logInfoMessage "xmllint is required but not installed"
  exit 1
}

# ==============================
# 🔹 UPLOAD FUNCTION
# ==============================
upload_file() {
  local FILE_PATH=$1
  local DEST_URL=$2

  logInfoMessage "Uploading $(basename "$FILE_PATH") → $DEST_URL"
  TMP_FILE=$(mktemp)

  HTTP_STATUS=$(curl -k \
    -u "${USERNAME}:${PASSWORD}" \
    --upload-file "$FILE_PATH" \
    "$DEST_URL" \
    -sS -o "$TMP_FILE" \
    -w "%{http_code}") || {
      logInfoMessage "Curl failed for $(basename "$FILE_PATH")"
      rm -f "$TMP_FILE"
      return 1
    }

  BODY=$(cat "$TMP_FILE")
  rm -f "$TMP_FILE"

  if [[ "$HTTP_STATUS" -lt 200 || "$HTTP_STATUS" -ge 300 ]]; then
    logInfoMessage "Upload failed for $(basename "$FILE_PATH") (HTTP $HTTP_STATUS)"
    logInfoMessage "$BODY"
    return 1
  fi

  logInfoMessage "✅ Uploaded $(basename "$FILE_PATH") successfully (HTTP $HTTP_STATUS)"
}

# ==============================
# 🔹 PROCESS ONE MODULE
# ==============================
process_module() {
  local POM_FILE=$1
  local MODULE_DIR
  MODULE_DIR=$(dirname "$POM_FILE")
  local MODULE_NAME
  MODULE_NAME=$(basename "$MODULE_DIR")

  logInfoMessage "================================================"
  logInfoMessage "🔹 Processing module: $MODULE_NAME"
  logInfoMessage "================================================"

  # --- Read artifactId ---
  ARTIFACT=$(xmllint --xpath "string(/*[local-name()='project']/*[local-name()='artifactId'])" "$POM_FILE" 2>/dev/null)

  # --- Read version (own → parent fallback) ---
  VERSION=$(xmllint --xpath "string(/*[local-name()='project']/*[local-name()='version'])" "$POM_FILE" 2>/dev/null)
  [[ -z "$VERSION" ]] && VERSION=$(xmllint --xpath "string(/*[local-name()='project']/*[local-name()='parent']/*[local-name()='version'])" "$POM_FILE" 2>/dev/null)

  # --- Read groupId (own first, then parent fallback) ---
  GROUP_ID=$(xmllint --xpath "string(/*[local-name()='project']/*[local-name()='groupId'])" "$POM_FILE" 2>/dev/null)
  [[ -z "$GROUP_ID" ]] && GROUP_ID=$(xmllint --xpath "string(/*[local-name()='project']/*[local-name()='parent']/*[local-name()='groupId'])" "$POM_FILE" 2>/dev/null)

  # --- Validation ---
  if [[ -z "$ARTIFACT" || -z "$VERSION" || -z "$GROUP_ID" ]]; then
    logInfoMessage "Skipping $MODULE_NAME — could not read artifact/version/groupId from pom.xml"
    return 0
  fi

  GROUP_ID_PATH=$(echo "$GROUP_ID" | tr '.' '/')
  UPLOAD_VERSION="${VERSION}"
  POM_NAME="${ARTIFACT}-${UPLOAD_VERSION}.pom"
  BASE_URL="${NEXUS_URL}/repository/${REPO_NAME}/${GROUP_ID_PATH}/${ARTIFACT}/${UPLOAD_VERSION}"

  logInfoMessage "Artifact  : $ARTIFACT"
  logInfoMessage "GroupId   : $GROUP_ID"
  logInfoMessage "Version   : $UPLOAD_VERSION"
  logInfoMessage "Base URL  : $BASE_URL"

  # --- Try to find JAR in target/ ---
  JAR_FILE_SOURCE="${MODULE_DIR}/target/${ARTIFACT}-${VERSION}.jar"

  # --- Generate POM checksums ---
  logInfoMessage "Generating POM checksums..."
  md5sum  "$POM_FILE" | awk '{print $1}' > "${POM_FILE}.md5"
  sha1sum "$POM_FILE" | awk '{print $1}' > "${POM_FILE}.sha1"

  # --- Always upload POM (needed for dependency resolution) ---
  upload_file "$POM_FILE"        "$BASE_URL/${POM_NAME}"      || return 1
  upload_file "${POM_FILE}.md5"  "$BASE_URL/${POM_NAME}.md5"  || return 1
  upload_file "${POM_FILE}.sha1" "$BASE_URL/${POM_NAME}.sha1" || return 1

  # --- Upload JAR only if it exists (submodules with packaging=jar) ---
  if [[ -f "$JAR_FILE_SOURCE" ]]; then
    JAR_NAME="${ARTIFACT}-${UPLOAD_VERSION}.jar"

    logInfoMessage "JAR source: $JAR_FILE_SOURCE"
    logInfoMessage "Generating JAR checksums..."
    md5sum  "$JAR_FILE_SOURCE" | awk '{print $1}' > "${JAR_FILE_SOURCE}.md5"
    sha1sum "$JAR_FILE_SOURCE" | awk '{print $1}' > "${JAR_FILE_SOURCE}.sha1"

    upload_file "$JAR_FILE_SOURCE"        "$BASE_URL/${JAR_NAME}"      || return 1
    upload_file "${JAR_FILE_SOURCE}.md5"  "$BASE_URL/${JAR_NAME}.md5"  || return 1
    upload_file "${JAR_FILE_SOURCE}.sha1" "$BASE_URL/${JAR_NAME}.sha1" || return 1

    rm -f "${JAR_FILE_SOURCE}.md5" "${JAR_FILE_SOURCE}.sha1"
  else
    logInfoMessage "ℹ️  No JAR found at $JAR_FILE_SOURCE — uploading POM only (parent/aggregator module)"
  fi

  # --- Cleanup POM checksums ---
  rm -f "${POM_FILE}.md5" "${POM_FILE}.sha1"

  logInfoMessage "✅ Module $MODULE_NAME pushed successfully"
}

# ==============================
# 🔹 COLLECT ALL POM FILES
# ==============================
FAILED_MODULES=()

# FIX: mindepth 1 so root pom.xml (depth 1) is included
# Root pom.xml is at $CODEBASE_LOCATION/pom.xml → depth 1
# Submodule pom.xml files are at depth 2-3
ALL_POMS=()
while IFS= read -r f; do ALL_POMS+=("$f"); done < <(
  find "$CODEBASE_LOCATION" -mindepth 1 -maxdepth 3 -name "pom.xml" | sort
)

logInfoMessage "Found ${#ALL_POMS[@]} pom.xml files to process"

for POM_FILE in "${ALL_POMS[@]}"; do
  MODULE_NAME=$(basename "$(dirname "$POM_FILE")")
  process_module "$POM_FILE" || FAILED_MODULES+=("$MODULE_NAME")
done

# ==============================
# 🔹 FINAL SUMMARY
# ==============================
logInfoMessage ""
logInfoMessage "================================================"
if [[ ${#FAILED_MODULES[@]} -gt 0 ]]; then
  logInfoMessage "❌ Failed modules: ${FAILED_MODULES[*]}"
  saveTaskStatus "1" "$ACTIVITY_SUB_TASK_CODE"
  exit 1
else
  logInfoMessage "🎉 All modules uploaded successfully!"
  saveTaskStatus "0" "$ACTIVITY_SUB_TASK_CODE"
fi
