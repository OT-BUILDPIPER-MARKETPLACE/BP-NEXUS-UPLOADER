# Changelog for registry.buildpiper.in/nexus-push-artifact

## [0.1.0] - 2025-06-22

### Added
- Initial release of Nexus Push Artifact Docker image.
- Zips the specified artifact as `service_name-build_no.zip`.
- Uploads the zipped artifact to the provided Nexus repository using `curl`.
- Removes the zip file from local after upload.
- Includes logging and status reporting.
- Includes helper shell functions for AWS, file, string, and logging