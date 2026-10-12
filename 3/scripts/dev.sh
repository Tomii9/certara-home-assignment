#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# dev.sh - run the hello-rest service on a local minikube cluster.
#
# Works on Linux, macOS, WSL and Git-Bash. Windows PowerShell users: dev.ps1.
#
#   ./scripts/dev.sh all       # check + up + deploy + test + open
#   ./scripts/dev.sh help      # list all commands
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

load_config() {
  local key value
  while IFS='=' read -r key value || [[ -n "${key}" ]]; do
    key="${key//[[:space:]]/}"
    [[ -z "${key}" || "${key}" == \#* ]] && continue
    value="${value%%$'\r'}"
    if [[ -z "${!key:-}" ]]; then
      export "${key}=${value}"
    fi
  done < "${ROOT_DIR}/config.env"
}
load_config

IMAGE="localhost:${REGISTRY_PORT}/${APP_NAME}:${APP_VERSION}"
URL="http://localhost:${LOCAL_PORT}/hello-world"

if [[ -t 1 ]]; then
  C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'; C_OFF=$'\033[0m'
else
  C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_OFF=""
fi
step() { echo "${C_BLUE}==>${C_OFF} $*"; }
ok()   { echo "  ${C_GREEN}[ok]${C_OFF} $*"; }
warn() { echo "  ${C_YELLOW}[warn]${C_OFF} $*"; }
fail() { echo "  ${C_RED}[fail]${C_OFF} $*" >&2; }
die()  { fail "$*"; exit 1; }

candidate_dirs=(/usr/local/bin /opt/homebrew/bin "${HOME}/.minikube/bin")
if command -v cygpath >/dev/null 2>&1; then
  [[ -n "${LOCALAPPDATA:-}" ]] && candidate_dirs+=("$(cygpath -u "${LOCALAPPDATA}/Programs/minikube")")
  [[ -n "${ProgramFiles:-}" ]] && candidate_dirs+=("$(cygpath -u "${ProgramFiles}/Kubernetes/Minikube")")
fi
for p in "${candidate_dirs[@]}"; do
  if [[ -d "${p}" && ":${PATH}:" != *":${p}:"* ]]; then
    PATH="${p}:${PATH}"
  fi
done

have() { command -v "$1" >/dev/null 2>&1; }

# kubectl, falling back to the version bundled with minikube.
kc() {
  if have kubectl; then
    kubectl --context "${MINIKUBE_PROFILE}" "$@"
  else
    minikube -p "${MINIKUBE_PROFILE}" kubectl -- "$@"
  fi
}

mk() { minikube -p "${MINIKUBE_PROFILE}" "$@"; }

cluster_running() {
  [[ "$(mk status --format '{{.Host}}/{{.APIServer}}' 2>/dev/null || true)" == "Running/Running" ]]
}

require_cluster() {
  cluster_running || die "Minikube profile '${MINIKUBE_PROFILE}' is not running. Run: $0 up"
}

cmd_check() {
  step "Checking required tooling"
  local errors=0

  if have docker; then
    ok "docker CLI    $(docker version --format '{{.Client.Version}}' 2>/dev/null || true)"
    if [[ "${MINIKUBE_DRIVER}" == "docker" ]]; then
      if docker info >/dev/null 2>&1; then
        ok "docker daemon running"
      else
        fail "docker daemon is not running (start Docker Desktop / 'sudo systemctl start docker')"
        errors=$((errors + 1))
      fi
    fi
  else
    fail "docker not found  -> https://docs.docker.com/get-docker/"
    errors=$((errors + 1))
  fi

  if have minikube; then
    ok "minikube      $(minikube version --short 2>/dev/null || echo '?')"
  else
    fail "minikube not found -> https://minikube.sigs.k8s.io/docs/start/"
    errors=$((errors + 1))
  fi

  if have kubectl; then
    ok "kubectl       $(kubectl version --client -o yaml 2>/dev/null | awk '/gitVersion/{print $2; exit}')"
  else
    warn "kubectl not found - falling back to 'minikube kubectl --' (https://kubernetes.io/docs/tasks/tools/)"
  fi

  if have curl; then
    ok "curl          $(curl --version | head -n1 | awk '{print $2}')"
  else
    fail "curl not found (needed by 'test')"
    errors=$((errors + 1))
  fi

  if (( errors > 0 )); then
    die "${errors} required tool(s) missing or not running."
  fi
  ok "All required tooling present"
}

cmd_up() {
  cmd_check
  step "Starting minikube profile '${MINIKUBE_PROFILE}'"
  if cluster_running; then
    ok "Already running"
  else
    mk start \
      --driver="${MINIKUBE_DRIVER}" \
      --container-runtime=docker \
      --cpus="${MINIKUBE_CPUS}" \
      --memory="${MINIKUBE_MEMORY}" \
      --kubernetes-version="${KUBERNETES_VERSION}"
  fi

  step "Enabling local image registry addon"
  mk addons enable registry >/dev/null
  kc -n kube-system wait --for=condition=Ready pod \
    -l kubernetes.io/minikube-addons=registry --timeout=180s >/dev/null
  ok "Registry ready at localhost:${REGISTRY_PORT} (inside the cluster)"
}

cmd_build() {
  require_cluster
  step "Building and pushing ${IMAGE} to the in-cluster registry"
  # Use minikube's own Docker daemon: the build runs inside the node, and from
  # there localhost:5000 is the registry addon (the same path the kubelet uses
  # to pull). No remote registry, no port-forward, no insecure-registry config.
  (
    eval "$(mk docker-env --shell bash)"
    docker build \
      --build-arg "APP_VERSION=${APP_VERSION}" \
      --build-arg "APP_ZIP_URL=${APP_ZIP_URL}" \
      --build-arg "APP_ZIP_SHA256=${APP_ZIP_SHA256}" \
      -t "${IMAGE}" "${ROOT_DIR}"
    docker push "${IMAGE}"
  )
  ok "Pushed ${IMAGE}"
}

cmd_deploy() {
  cmd_build
  step "Applying Kubernetes manifests (k8s/)"
  kc apply -k "${ROOT_DIR}/k8s"
  # Keep the image in sync with APP_VERSION and force a fresh pull of the tag.
  kc -n "${APP_NAMESPACE}" set image "deployment/${APP_NAME}" "${APP_NAME}=${IMAGE}" >/dev/null
  kc -n "${APP_NAMESPACE}" rollout restart "deployment/${APP_NAME}" >/dev/null
  kc -n "${APP_NAMESPACE}" rollout status "deployment/${APP_NAME}" --timeout=180s
  ok "Deployed"
}

cmd_test() {
  require_cluster
  step "Smoke-testing the service"
  local port=18080 pf_pid body
  kc -n "${APP_NAMESPACE}" port-forward "svc/${APP_NAME}" "${port}:80" >/dev/null 2>&1 &
  pf_pid=$!
  # shellcheck disable=SC2064  # expand pf_pid now
  trap "kill ${pf_pid} 2>/dev/null || true" RETURN EXIT

  for _ in $(seq 1 20); do
    if body="$(curl -fsS "http://localhost:${port}/hello-world" 2>/dev/null)"; then
      break
    fi
    sleep 0.5
  done
  [[ -n "${body:-}" ]] || die "No response from the service"

  echo "  response: ${body}"
  if [[ "${body}" =~ \"message\"[[:space:]]*:[[:space:]]*\"Hello\ World ]]; then
    ok "Service returns the expected JSON"
  else
    die "Unexpected response"
  fi
}

cmd_open() {
  require_cluster
  step "Forwarding ${URL}  ->  svc/${APP_NAME}"
  echo "  Try:  curl ${URL}"
  echo "  Press Ctrl+C to stop."
  kc -n "${APP_NAMESPACE}" port-forward "svc/${APP_NAME}" "${LOCAL_PORT}:80"
}

cmd_status() {
  require_cluster
  step "Cluster"
  mk status || true
  step "Resources in namespace ${APP_NAMESPACE}"
  kc -n "${APP_NAMESPACE}" get deploy,rs,pods,svc -o wide || true
  step "Recent events"
  kc -n "${APP_NAMESPACE}" get events --sort-by=.lastTimestamp 2>/dev/null | tail -n 10 || true
}

cmd_logs() {
  require_cluster
  kc -n "${APP_NAMESPACE}" logs -f "deployment/${APP_NAME}" --all-containers
}

cmd_undeploy() {
  require_cluster
  step "Removing the application"
  kc delete -k "${ROOT_DIR}/k8s" --ignore-not-found
}

cmd_down() {
  step "Stopping minikube profile '${MINIKUBE_PROFILE}' (state is kept)"
  mk stop
}

cmd_destroy() {
  step "Deleting minikube profile '${MINIKUBE_PROFILE}'"
  mk delete
}

cmd_all() {
  cmd_up
  cmd_deploy
  cmd_test
  cmd_open
}

cmd_help() {
  cat <<EOF
Usage: $0 <command>

  all        check + up + deploy + test + open   (start here)
  check      verify required tooling is installed / running
  up         start minikube (profile '${MINIKUBE_PROFILE}') and the local registry
  build      build the image and push it to the in-cluster registry
  deploy     build + push + kubectl apply -k k8s/ + wait for rollout
  test       call /hello-world through a temporary port-forward
  open       expose ${URL} (blocks, Ctrl+C to stop)
  status     show cluster and application state
  logs       follow application logs
  undeploy   remove the application, keep the cluster
  down       stop the cluster (fast restart with 'up')
  destroy    delete the cluster completely

Settings live in config.env and can be overridden by environment variables,
e.g.  LOCAL_PORT=9090 $0 open
EOF
}

case "${1:-help}" in
  all|check|up|build|deploy|test|open|status|logs|undeploy|down|destroy|help)
    "cmd_${1:-help}" ;;
  -h|--help) cmd_help ;;
  *) cmd_help; exit 1 ;;
esac
