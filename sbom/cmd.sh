docker pull alpine:3.20.0
docker pull alpine:3.20.6
copa patch -i alpine:3.20.0 -t 3.20.0-patched

trivy image alpine:3.20.0
trivy image alpine:3.20.6
trivy image alpine:3.20.0-patched

trivy image --format spdx-json --output alpine-3.20.0.spdx.json alpine:3.20.0
trivy image --format spdx-json --output alpine-3.20.6.spdx.json alpine:3.20.6
trivy image --format spdx-json --output alpine-3.20.0-patched.spdx.json alpine:3.20.0-patched

docker inspect 77726ef6b57d | jq -r '.[].RootFS'

docker run -it --rm alpine:3.20.0 sh
docker run -it --rm alpine:3.20.6 sh
docker run -it --rm alpine:3.20.0-patched sh

docker pull mcr.microsoft.com/oss/istio/proxyv2:1.24.3
docker pull mcr.microsoft.com/oss/istio/pilot:1.24.3
docker pull mcr.microsoft.com/azure-application-gateway/kubernetes-ingress:1.8.0
docker pull mcr.microsoft.com/azure-watson/agent/agent_mariner:1.21.13.0

trivy image --format spdx-json --output istio-proxyv2-1.24.3.spdx.json mcr.microsoft.com/oss/istio/proxyv2:1.24.3
trivy image --format spdx-json --output istio-pilot-1.24.3.spdx.json mcr.microsoft.com/oss/istio/pilot:1.24.3
trivy image --format spdx-json --output agic-1.8.0.spdx.json mcr.microsoft.com/azure-application-gateway/kubernetes-ingress:1.8.0
trivy image --format spdx-json --output agent-watson-mariner-1.21.12.0.spdx.json mcr.microsoft.com/azure-watson/agent/agent_mariner:1.21.13.0

trivy image alpine:3.20.0 | grep Total
trivy image alpine:3.20.6 | grep Total
trivy image alpine:3.20.0-patched | grep Total

trivy image mcr.microsoft.com/oss/istio/proxyv2:1.24.3 | grep Total
trivy image mcr.microsoft.com/oss/istio/pilot:1.24.3 | grep Total
trivy image mcr.microsoft.com/azure-application-gateway/kubernetes-ingress:1.8.0 | grep Total
trivy image mcr.microsoft.com/azure-watson/agent/agent_mariner:1.21.13.0 | grep Total

copa patch -i mcr.microsoft.com/oss/istio/proxyv2:1.24.3 -t 1.24.3-patched
copa patch -i mcr.microsoft.com/oss/istio/pilot:1.24.3 -t 1.24.3-patched
copa patch -i mcr.microsoft.com/azure-application-gateway/kubernetes-ingress:1.8.0 -t 1.8.0-patched
copa patch -i mcr.microsoft.com/azure-watson/agent/agent_mariner:1.21.13.0 -t 1.21.13.0-patched

# List the packages from the SBOM
cat alpine-3.20.0.spdx.json| jq '.packages.[].name'

# List the packages and the version from the SBOM
cat alpine-3.20.0.spdx.json| jq '.packages[] | .name + " " + .versionInfo'