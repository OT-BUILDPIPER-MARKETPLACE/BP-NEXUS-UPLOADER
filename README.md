# BP-NEXUS-UPLOADER

This tool creates a zip of the specified artifact as `service_name-build_no.zip`, pushes it to the provided Nexus repository using the `curl` command, and then deletes the created zip from local storage.

## Setup

* Clone the code available at [BP-NEXUS-UPLOADER](https://github.com/OT-BUILDPIPER-MARKETPLACE/BP-NEXUS-UPLOADER)

* Build the docker image:
    ```
    git submodule init
    git submodule update
    docker build -t registry.buildpiper.in/nexus-push-artifact:0.1.0 .
    ```

* Do local testing:
    ```
    docker run -it --rm \
      -v $PWD:/src \
      -e WORKSPACE=/src \
      -e BUILD_NUMBER="<build_number>" \
      -e BUILD_COMPONENT_NAME="<component_name>" \
      -e ARTIFACT="<artifact_path>" \
      -e USERNAME="<nexus_username>" \
      -e PASSWORD="<nexus_password>" \
      -e NEXUS_URL="<nexus_url>" \
      -e REPO_NAME="<repo_name>" \
      registry.buildpiper.in/nexus-push-artifact:0.1.0
    ```

* Debug:
    ```
    docker run -it --rm \
      -v $PWD:/src \
      -e WORKSPACE=/src \
      -e BUILD_NUMBER="<build_number>" \
      -e BUILD_COMPONENT_NAME="<component_name>" \
      -e ARTIFACT="<artifact_path>" \
      -e USERNAME="<nexus_username>" \
      -e PASSWORD="<nexus_password>" \
      -e NEXUS_URL="<nexus_url>" \
      -e REPO_NAME="<repo_name>" \
      --entrypoint sh \
      registry.buildpiper.in/nexus-push-artifact:0.1.0
    ```

## Environment Variables

- `WORKSPACE`: Path to the workspace directory (usually `/src`).
- `CODEBASE_DIR`: Directory name inside workspace containing the codebase.
- `BUILD_NUMBER`: Build number for the artifact.
- `BUILD_COMPONENT_NAME`: Name of the component/service.
- `ARTIFACT`: Path to the artifact or directory to be zipped and uploaded.
- `USERNAME`: Nexus repository username.
- `PASSWORD`: Nexus repository password.
- `NEXUS_URL`: Nexus base URL (e.g., `https://nexus.example.com`).
- `REPO_NAME`: Nexus repository name.

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for release notes.

## Image

- Docker image: `registry.buildpiper.in/nexus-push-artifact:0.1.0`