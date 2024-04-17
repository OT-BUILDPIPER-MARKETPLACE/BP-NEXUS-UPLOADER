#!/bin/bash
source /opt/buildpiper/shell-functions/functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/str-functions.sh
source /opt/buildpiper/shell-functions/file-functions.sh
source /opt/buildpiper/shell-functions/aws-functions.sh


CODEBASE_LOCATION="${WORKSPACE}"/"${CODEBASE_DIR}"
logInfoMessage "I'll do processing at [$CODEBASE_LOCATION]"
sleep  $SLEEP_DURATION
cd  "${CODEBASE_LOCATION}"

zip -qr ${BUILD_COMPONENT_NAME}-${BUILD_NUMBER}.zip ${ARTIFACT}
# 
curl -v -u ${USERNAME}:${PASSWORD} --upload-file ${BUILD_COMPONENT_NAME}-${BUILD_NUMBER}.zip ${NEXUS_URL}/${BUILD_COMPONENT_NAME}-${BUILD_NUMBER}


if [ $? -eq 0 ]; then
    TASK_STATUS=0
    logInfoMessage "Artifact pushed successfully"
else
    TASK_STATUS=1
    logErrorMessage "Failed to push the artifact"

fi
saveTaskStatus ${TASK_STATUS} ${ACTIVITY_SUB_TASK_CODE}