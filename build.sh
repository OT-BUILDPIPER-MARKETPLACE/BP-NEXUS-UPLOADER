#!/bin/bash
source /opt/buildpiper/shell-functions/functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/str-functions.sh
source /opt/buildpiper/shell-functions/file-functions.sh
source /opt/buildpiper/shell-functions/aws-functions.sh

TASK_STATUS=0
CODEBASE_LOCATION="${WORKSPACE}"/"${CODEBASE_DIR}"
logInfoMessage "I'll do processing at [$CODEBASE_LOCATION]"
sleep  $SLEEP_DURATION

# Change directory to the codebase location
cd "$CODEBASE_LOCATION"

# Zip the artifact
zip -qr "${BUILD_COMPONENT_NAME}-${BUILD_NUMBER}.zip" "$ARTIFACT" 

# Upload the artifact to Nexus
curl -v -u "${USERNAME}:${PASSWORD}" --upload-file "${BUILD_COMPONENT_NAME}-${BUILD_NUMBER}.zip" "${NEXUS_URL}/${REPO_NAME}/${BUILD_COMPONENT_NAME}-${BUILD_NUMBER}" 2> /dev/null

# Check if artifact upload was successful
if [ $? -eq 0 ]; then
    TASK_STATUS=0
    logInfoMessage "Artifact pushed successfully"
else
    TASK_STATUS=1
    logErrorMessage "Failed to push the artifact"
    exit 1
fi

# Remove the generated zip file
rm -f "${BUILD_COMPONENT_NAME}-${BUILD_NUMBER}.zip"


# Save task status
saveTaskStatus "$TASK_STATUS" "$ACTIVITY_SUB_TASK_CODE"