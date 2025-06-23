# check=skip=SecretsUsedInArgOrEnv
FROM alpine:latest

RUN apk add --no-cache --upgrade \
  bash \
  jq \
  openssh \
  curl \
  zip \
  coreutils

ENV TZ=Asia/Kolkata
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

COPY build.sh .
ADD BP-BASE-SHELL-STEPS /opt/buildpiper/shell-functions/

ENV ARTIFACT=""
ENV USERNAME=""
ENV PASSWORD=""
ENV NEXUS_URL=""
ENV REPO_NAME=""

ENV SLEEP_DURATION=5s
ENV ACTIVITY_SUB_TASK_CODE=NEXUS_UPLOADER
ENV VALIDATION_FAILURE_ACTION=WARNING

RUN chmod +x *.sh && chmod -R +x /opt/buildpiper/shell-functions/

ENTRYPOINT [ "./build.sh" ]