# Changelog

## [0.1.2] - 2025-06-23

### Changed
- Improved artifact existence check before zipping using `compgen -G "$ARTIFACT"` to prevent zip errors when no files match the artifact pattern.
- Enhanced error logging for missing artifacts and zip failures.
- Ensured script exits gracefully with clear error messages if required variables are missing or artifact files are not found.
- **Added fallback handling:** `BUILD_COMPONENT_NAME` now defaults to `CODEBASE_DIR` and `BUILD_NUMBER` defaults to `JOB_NUMBER` if not set as environment variables in case of V3 Job-Step.

## [0.1.1] - 2025-06-22

### Added
- Initial release of Nexus Push Artifact Docker image.
- Zips the specified artifact as `service_name-build_no.zip`.
- Uploads the zipped artifact to the provided Nexus repository using `curl`.
- Removes the zip file from local after upload.
- Includes logging and status reporting.
- Includes helper shell functions for AWS, file, string, and logging operations.