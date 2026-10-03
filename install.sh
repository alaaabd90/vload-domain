#!/usr/bin/env bash
###############################################################################
# vload-domain installer  —  Linux / WSL (Debian · Ubuntu · Kali)
#
# One-command install:
#   curl -fsSL https://raw.githubusercontent.com/alaaabd90/vload-domain/main/install.sh | sudo bash
#
# What it does:
#   1. Installs system dependencies via apt (jq, curl, fping, whois, dig, nc …)
#   2. Installs the recon toolchain at the EXACT pinned versions, pulled from
#      THIS repo's release assets first; falls back to the official sources.
#   3. Installs the `vload` command into /usr/local/bin.
# Re-running is safe: tools already at the right version are skipped.
###############################################################################
set -euo pipefail

REPO="alaaabd90/vload-domain"
RAW="https://raw.githubusercontent.com/${REPO}/main"
DL="https://github.com/${REPO}/releases/latest/download"
BIN="/usr/local/bin"

if [ -t 1 ]; then
  CG=$'\033[0;32m'; CY=$'\033[1;33m'; CR=$'\033[0;31m'; CB=$'\033[0;34m'; CN=$'\033[0m'
else CG=; CY=; CR=; CB=; CN=; fi
info(){ echo -e "${CB}[*]${CN} $*"; }
ok(){   echo -e "${CG}[+]${CN} $*"; }
warn(){ echo -e "${CY}[!]${CN} $*"; }
err(){  echo -e "${CR}[-]${CN} $*" >&2; }

SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
need(){ command -v "$1" >/dev/null 2>&1; }

# ── Pinned tool versions (match the reference build) ─────────────────────────
declare -A VER=(
  [subfinder]="v2.14.0" [dnsx]="1.2.3"  [httpx]="v1.9.0"
  [naabu]="2.5.0"       [amass]="v4.2.0" [findomain]="9.0.4"
  [assetfinder]="latest" [tlsx]="v1.4.0"
)
# Go module paths for the official fallback
declare -A GOMOD=(
  [subfinder]="github.com/projectdiscovery/subfinder/v2/cmd/subfinder"
  [dnsx]="github.com/projectdiscovery/dnsx/cmd/dnsx"
  [httpx]="github.com/projectdiscovery/httpx/cmd/httpx"
  [naabu]="github.com/projectdiscovery/naabu/v2/cmd/naabu"
  [amass]="github.com/owasp-amass/amass/v4/..."
  [assetfinder]="github.com/tomnomnom/assetfinder"
  [tlsx]="github.com/projectdiscovery/tlsx/cmd/tlsx"
)

banner(){
  echo -e "${CB}"
  echo "  ┌──────────────────────────────────────────────┐"
  echo "  │   vload-domain — subdomain recon installer     │"
  echo "  └──────────────────────────────────────────────┘"
  echo -e "${CN}"
}

install_system_deps(){
  info "Installing system dependencies..."
  if need apt-get; then
    $SUDO apt-get update -y -q || warn "apt update had warnings (continuing)"
    $SUDO apt-get install -y -q \
      jq curl fping whois dnsutils ncat ca-certificates tar gzip coreutils \
      || warn "some apt packages failed; will verify individually"
  else
    warn "Not an apt system — make sure these exist: jq curl fping whois dig nc tar gzip"
  fi
  # 'nc' may be provided by ncat; make sure one exists
  need nc || need ncat || warn "netcat not found (needed for IP enrichment)"
}

# installed AND version matches the pin?
version_ok(){
  local t="$1" want="${VER[$1]}" have=""
  need "$t" || return 1
  [ "$want" = "latest" ] && return 0
  case "$t" in
    subfinder|dnsx|naabu|tlsx) have=$("$t" -version 2>&1 | grep -oiE '[0-9]+\.[0-9]+\.[0-9]+' | head -1);;
    httpx)                have=$(httpx -version 2>&1 | grep -oiE '[0-9]+\.[0-9]+\.[0-9]+' | head -1);;
    amass)                have=$(amass -version 2>&1 | grep -oiE '[0-9]+\.[0-9]+\.[0-9]+' | head -1);;
    findomain)            have=$(findomain --version 2>&1 | grep -oiE '[0-9]+\.[0-9]+\.[0-9]+' | head -1);;
  esac
  [ -n "$have" ] && [ "${want#v}" = "$have" ]
}

# Pull a single binary from THIS repo's release assets (gzip'd)
fetch_from_repo(){
  local t="$1" tmp; tmp=$(mktemp)
  if curl -fsSL "${DL}/${t}.gz" -o "${tmp}.gz" 2>/dev/null \
     && gunzip -f "${tmp}.gz" 2>/dev/null; then
    $SUDO install -m 0755 "$tmp" "${BIN}/${t}" && { rm -f "$tmp"; return 0; }
  fi
  rm -f "$tmp" "${tmp}.gz" 2>/dev/null || true
  return 1
}

# Official-source fallback (Go toolchain, or findomain release binary)
install_official(){
  local t="$1"
  case "$t" in
    findomain)
      local arch; arch=$(uname -m); [ "$arch" = "arm64" ] && arch="aarch64"
      curl -fsSL "https://github.com/Findomain/Findomain/releases/download/${VER[findomain]}/findomain-linux-${arch}.zip" -o /tmp/fd.zip 2>/dev/null \
        && (need unzip || $SUDO apt-get install -y -q unzip) \
        && unzip -o /tmp/fd.zip -d /tmp >/dev/null 2>&1 \
        && $SUDO install -m0755 /tmp/findomain "${BIN}/findomain" \
        && { rm -f /tmp/fd.zip /tmp/findomain; return 0; }
      return 1 ;;
    *)
      need go || { err "Go not installed — cannot build $t from source"; return 1; }
      local ver="@latest"; [ "${VER[$t]}" != "latest" ] && ver="@${VER[$t]}"
      # try pinned, then @latest
      GOBIN="$BIN" $SUDO env "PATH=$PATH" go install "${GOMOD[$t]}${ver}" 2>/dev/null \
        || GOBIN="$BIN" $SUDO env "PATH=$PATH" go install "${GOMOD[$t]}@latest" 2>/dev/null
      need "$t" ;;
  esac
}

ensure_tool(){
  local t="$1"
  if version_ok "$t"; then ok "$t ${VER[$t]} — already installed"; return 0; fi
  need "$t" && warn "$t present but version differs from pin ${VER[$t]} — updating"
  info "Installing $t ${VER[$t]} ..."
  if fetch_from_repo "$t"; then ok "$t ${VER[$t]} installed (from repo release)"; return 0; fi
  warn "repo release not available for $t — trying official source"
  if install_official "$t"; then ok "$t installed (official source)"; return 0; fi
  err "could not install $t"; return 1
}

install_vload(){
  info "Installing the vload command..."
  if [ -f "./vload" ]; then
    $SUDO install -m 0755 ./vload "${BIN}/vload"
  else
    curl -fsSL "${RAW}/vload" -o /tmp/vload && $SUDO install -m 0755 /tmp/vload "${BIN}/vload" && rm -f /tmp/vload
  fi
  ok "vload installed → ${BIN}/vload"
}

main(){
  banner
  install_system_deps
  local failed=0 t
  for t in subfinder dnsx httpx naabu amass assetfinder findomain; do
    ensure_tool "$t" || failed=1
  done
  # Optional: tlsx enables the TLS certificate SAN expansion stage. vload
  # skips that stage cleanly if it's missing, so a failure here is never
  # fatal to the install — just report it separately from the required set.
  if ensure_tool tlsx; then :; else warn "tlsx not installed — vload will skip TLS SAN expansion (all other stages still run)"; fi
  install_vload
  echo
  if [ "$failed" -eq 0 ]; then
    ok "All tools ready."
  else
    warn "Some tools failed to install — vload will report any that are still missing."
  fi
  echo
  ok "Done. Usage:"
  echo "    vload example.com                 # single domain"
  echo "    vload a.com b.com c.com           # multiple (space separated)"
  echo "    vload                             # prompts for domain(s)"
  echo
  echo "  Results are saved to ~/recon/<domain>_<timestamp>/subdomains.txt"
  echo "  and auto-copied to your Windows Documents when run under WSL."
}
main "$@"
