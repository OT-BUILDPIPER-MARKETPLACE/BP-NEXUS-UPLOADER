#!/bin/bash
source /opt/buildpiper/shell-functions/functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh

TASK_STATUS=0
CODEBASE_LOCATION="${WORKSPACE}"/"${CODEBASE_DIR}"
logInfoMessage "I'll do processing at [$CODEBASE_LOCATION]"
sleep  $SLEEP_DURATION

# Change directory to the codebase location
cd "$CODEBASE_LOCATION"

# Set BUILD_COMPONENT_NAME and BUILD_NUMBER with fallback values
BUILD_COMPONENT_NAME="${BUILD_COMPONENT_NAME:-$CODEBASE_DIR}"
BUILD_NUMBER="${BUILD_NUMBER:-$JOB_NUMBER}"


# List all required variables
REQUIRED_VARS=(NEXUS_URL REPO_NAME USERNAME PASSWORD ARTIFACT BUILD_COMPONENT_NAME BUILD_NUMBER)
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var}" ]]; then
    MISSING_VARS+=("$var")
  fi
done

if (( ${#MISSING_VARS[@]} )); then
  echo "❌ Error: Required variables are not set: ${MISSING_VARS[*]}"
  exit 1
fi

ls -ltr

# Check if artifact(s) exist before zipping
if compgen -G "$ARTIFACT" > /dev/null; then
    logInfoMessage "Executing zip command to create zip -qjr ${BUILD_COMPONENT_NAME}-${BUILD_NUMBER}.zip $ARTIFACT"
    zip -qjr "${BUILD_COMPONENT_NAME}-${BUILD_NUMBER}.zip" $ARTIFACT
    ZIP_STATUS=$?
else
    logErrorMessage "No files found matching artifact pattern: $ARTIFACT"
    exit 1
fi

# Check if artifact Zip creation was successful
if [ $ZIP_STATUS -eq 0 ]; then
    TASK_STATUS=0
    logInfoMessage "Created ${BUILD_COMPONENT_NAME}-${BUILD_NUMBER}.zip containing $ARTIFACT"
else
    TASK_STATUS=1
    logErrorMessage "Failed to create the Zip"
    exit 1
fi

# Check if artifact Zip creation was successful
if [ $? -eq 0 ]; then
    TASK_STATUS=0
    logInfoMessage "Created ${BUILD_COMPONENT_NAME}-${BUILD_NUMBER}.zip containing $ARTIFACT"
else
    TASK_STATUS=1
    logErrorMessage "Failed to create the Zip"
    exit 1
fi

# Upload the artifact to Nexus
curl -v -u "${USERNAME}:${PASSWORD}" --upload-file "${BUILD_COMPONENT_NAME}-${BUILD_NUMBER}.zip" "${NEXUS_URL}/repository/${REPO_NAME}/${BUILD_COMPONENT_NAME}-${BUILD_NUMBER}.zip" 2> /dev/null

# Check if artifact upload was successful
if [ $? -eq 0 ]; then
    TASK_STATUS=0
    logInfoMessage "${BUILD_COMPONENT_NAME}-${BUILD_NUMBER}.zip pushed successfully to ${NEXUS_URL}/repository/${REPO_NAME}/${BUILD_COMPONENT_NAME}-${BUILD_NUMBER}.zip "
else
    TASK_STATUS=1
    logErrorMessage "Failed to push the artifact"
    exit 1
fi

# Remove the generated zip file
rm -f "${BUILD_COMPONENT_NAME}-${BUILD_NUMBER}.zip"

# Check the status of zip on local
if [ $? -eq 0 ]; then
    TASK_STATUS=0
    logInfoMessage "${BUILD_COMPONENT_NAME}-${BUILD_NUMBER}.zip removed from local successfully"
else
    TASK_STATUS=1
    logErrorMessage "Failed to remove ${BUILD_COMPONENT_NAME}-${BUILD_NUMBER}.zip from local"
    exit 1
fi

# Save task status
saveTaskStatus "$TASK_STATUS" "$ACTIVITY_SUB_TASK_CODE"