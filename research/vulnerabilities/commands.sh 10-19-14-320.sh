# Step #1 - Show the vulnerabilities in the base image
trivy image python:3.12.2 --severity HIGH,CRITICAL | grep Total

# Step #2 - Build the application image based on the base image
docker build -t flasksample:1.0 --build-arg BASE_IMAGE="python:3.12.2" .

# Step #3 - Show the vulnerabilities in the application image
trivy image --severity HIGH,CRITICAL flasksample:1.0 | grep Total

# Step #4 - We don't use Git in our application
trivy image --severity HIGH,CRITICAL flasksample:1.0 | grep git

# Step #5 - Let's exclude those
# We don't need the SBOM for this
# trivy image --format cyclonedx --output ./research/vulnerabilities/vex/flasksample.1.0.sbom.cdx python:3.12.2

vexctl create --product="pkg:deb/debian/git@2.39.2-1.1?arch=arm64&distro=debian-12.5&epoch=1" \
              --author="ToddySM" \
              --vuln="CVE-2024-32002" \
              --status="not_affected" \
              --justification="vulnerable_code_not_in_execute_path" \
              > ./research/vulnerabilities/vex/flasksample1.0-CVE-2024-32002.vex.json

vexctl create --product="pkg:deb/debian/git@2.39.2-1.1?arch=arm64&distro=debian-12.5&epoch=1" \
              --author="ToddySM" \
              --vuln="CVE-2023-25652" \
              --status="not_affected" \
              --justification="vulnerable_code_not_in_execute_path" \
              > ./research/vulnerabilities/vex/flasksample1.0-CVE-2023-25652.vex.json

vexctl create --product="pkg:deb/debian/git@2.39.2-1.1?arch=arm64&distro=debian-12.5&epoch=1" \
              --author="ToddySM" \
              --vuln="CVE-2023-29007" \
              --status="not_affected" \
              --justification="vulnerable_code_not_in_execute_path" \
              > ./research/vulnerabilities/vex/flasksample1.0-CVE-2023-29007.vex.json

vexctl create --product="pkg:deb/debian/git@2.39.2-1.1?arch=arm64&distro=debian-12.5&epoch=1" \
              --author="ToddySM" \
              --vuln="CVE-2024-32004" \
              --status="not_affected" \
              --justification="vulnerable_code_not_in_execute_path" \
              > ./research/vulnerabilities/vex/flasksample1.0-CVE-2024-32004.vex.json

vexctl create --product="pkg:deb/debian/git@2.39.2-1.1?arch=arm64&distro=debian-12.5&epoch=1" \
              --author="ToddySM" \
              --vuln="CVE-2024-32465" \
              --status="not_affected" \
              --justification="vulnerable_code_not_in_execute_path" \
              > ./research/vulnerabilities/vex/flasksample1.0-CVE-2024-32465.vex.json

vexctl merge ./research/vulnerabilities/vex/flasksample1.0-CVE-2024-32002.vex.json \
              ./research/vulnerabilities/vex/flasksample1.0-CVE-2023-25652.vex.json \
              ./research/vulnerabilities/vex/flasksample1.0-CVE-2023-29007.vex.json \
              ./research/vulnerabilities/vex/flasksample1.0-CVE-2024-32004.vex.json \
              ./research/vulnerabilities/vex/flasksample1.0-CVE-2024-32465.vex.json \
              > ./research/vulnerabilities/vex/flasksample1.0.vex.json

trivy image --severity HIGH,CRITICAL --vex ./research/vulnerabilities/vex/flasksample1.0.vex.json flasksample:1.0 | grep Total
# Compare the results with the previous one
trivy image --severity HIGH,CRITICAL flasksample:1.0 | grep Total

### Copacetic patching
# Step #6 - Let's build a vulnerability report
trivy image --ignore-unfixed --vuln-type os flasksample:1.0 | grep Total
trivy image --ignore-unfixed --vuln-type os --format json --output ./research/vulnerabilities/vex/flasksample1.0.vuln-report.json flasksample:1.0

copa patch -i flasksample:1.0 -r ./research/vulnerabilities/vex/flasksample1.0.vuln-report.json -t 1.0-patched

### Exceptions with Rego
trivy image --policy ./research/vulnerabilities/vex/exception.rego flasksample:1.0 | grep Total

################ Scratchpad ################

# Get the vulnerabilities of the python:3.12.2 image
trivy image --ignore-unfixed --vuln-type os python:3.12.2 | grep HIGH
trivy image python:3.12.2 | grep bsdutils

# Total: 98 (UNKNOWN: 6, LOW: 5, MEDIUM: 63, HIGH: 24, CRITICAL: 0)
# │ bsdutils           │ CVE-2024-28085 │ HIGH     │ fixed  │ 1:2.38.1-5+b1     │ 2.38.1-5+deb12u1 │ util-linux: CVE-2024-28085: wall: escape sequence injection  │
# │ libc-dev-bin       │ CVE-2024-2961  │ HIGH     │        │                   │ 2.36-9+deb12u6   │ glibc: Out of bounds write in iconv may lead to remote       │
# │ libc6              │ CVE-2024-2961  │ HIGH     │        │                   │ 2.36-9+deb12u6   │ glibc: Out of bounds write in iconv may lead to remote       │
# │ libc6-dev          │ CVE-2024-2961  │ HIGH     │        │                   │ 2.36-9+deb12u6   │ glibc: Out of bounds write in iconv may lead to remote       │
# │ libmount-dev       │ CVE-2024-28085 │ HIGH     │        │ 2.38.1-5+b1       │ 2.38.1-5+deb12u1 │ util-linux: CVE-2024-28085: wall: escape sequence injection  │
# │ mount              │ CVE-2024-28085 │ HIGH     │        │ 2.38.1-5+b1       │ 2.38.1-5+deb12u1 │ util-linux: CVE-2024-28085: wall: escape sequence injection  │

# Have the SBOM generated
trivy image --format spdx-json --output python-3.12.2.spdx.json python:3.12.2
trivy image --format cyclonedx --output python-3.12.2.sbom.cdx python:3.12.2

# Generate a VEX statement for bsdutils package
vexctl create --product="pkg:deb/debian/git@2.39.2-1.1?arch=arm64&distro=debian-12.5&epoch=1" \
              --author="ToddySM" \
              --vuln="CVE-2024-32002" \
              --status="not-affected" \
              > ./research/vulnerabilities/vex/flasksample1.0.vex.json

# Scan with a VEX statement
trivy sbom python-3.12.2.spdx.json --vex python-3.12.2.vex.json | grep HIGH
trivy sbom python-3.12.2.spdx.json --vex python-3.12.2.vex.json | grep bsdutils
trivy sbom python-3.12.2.spdx.json | grep bsdutils

trivy sbom python-3.12.2.sbom.cdx | grep bsdutils

trivy image --ignore-unfixed --vuln-type os --vex python-3.12.2.vex.json python:3.12.2 | grep HIGH