# Docker Scout
docker scout version

# Used 
# version: v1.6.3 (go1.22.1 - darwin/arm64)
# git commit: 918810e3d1f572e5d8e29b5acafa269592587dda

docker scout cves --format packages --output docker-scout-20240419.txt python:3.9.18-bullseye
docker scout cves --format spdx --output docker-scout-20240419.spdx.json python:3.9.18-bullseye
docker scout cves --format sarif --output docker-scout-20240419.sarif.json python:3.9.18-bullseye
docker scout cves --format sbom --output docker-scout-20240419.sbom.json python:3.9.18-bullseye

# Grype
grype version

# Used
# Application:         grype
# Version:             0.77.0
# BuildDate:           2024-04-18T18:40:52Z
# GitCommit:           brew
# GitDescription:      [not provided]
# Platform:            darwin/arm64
# GoVersion:           go1.22.2
# Compiler:            gc
# Syft Version:        v1.2.0
# Supported DB Schema: 5

grype python:3.9.18-bullseye --output table --file grype-squashed-20240419.txt
grype python:3.9.18-bullseye --output table --file grype-all-layers-20240419.txt --scope all-layers
grype python:3.9.18-bullseye --output json --file grype-squashed-20240419.json
grype python:3.9.18-bullseye --output json --file grype-all-layers-20240419.json --scope all-layers
grype python:3.9.18-bullseye --output sarif --file grype-squashed-20240419.sarif.json
grype python:3.9.18-bullseye --output sarif --file grype-all-layers-20240419.sarif.json --scope all-layers
grype python:3.9.18-bullseye --output cyclonedx-json --file grype-squashed-20240419.cyclonedx.json
grype python:3.9.18-bullseye --output cyclonedx-json --file grype-all-layers-20240419.cyclonedx.json --scope all-layers

# Trivy
trivy version

# Used
# Version: 0.50.1
# Vulnerability DB:
#   Version: 2
#   UpdatedAt: 2024-04-18 18:12:18.120482471 +0000 UTC
#   NextUpdate: 2024-04-19 00:12:18.12048208 +0000 UTC
#   DownloadedAt: 2024-04-18 23:40:33.695763 +0000 UTC
# Java DB:
#   Version: 1
#   UpdatedAt: 2024-04-18 00:44:23.816697157 +0000 UTC
#   NextUpdate: 2024-04-21 00:44:23.816696977 +0000 UTC
#   DownloadedAt: 2024-04-18 23:44:15.293785 +0000 UTC

trivy image --format table --output trivy-20240419.txt python:3.9.18-bullseye
trivy image --format json --output trivy-20240419.json python:3.9.18-bullseye
trivy image --format sarif --output trivy-20240419.sarif.json python:3.9.18-bullseye
trivy image --format cyclonedx --output trivy-20240419.cyclonedx.json --scanners vuln python:3.9.18-bullseye
trivy image --format spdx-json --output trivy-20240419.spdx.json python:3.9.18-bullseye
# Latter doesn't include vulnerabilities due to the lack of SPDX support before 3.0