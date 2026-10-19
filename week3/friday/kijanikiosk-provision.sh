#!/usr/bin/env bash
# =============================================================================
# kijanikiosk-provision.sh
# KijaniKiosk production server foundation (Week 3, Friday)
#
# One idempotent script that converges a DIRTY Ubuntu 24.04 VM to the intended
# state for the three KijaniKiosk services: kk-api, kk-payments and kk-logs.
#
# Usage:   sudo ./kijanikiosk-provision.sh
# Options (environment variables, pass them through sudo):
#   KK_ADMIN_CIDR="192.168.56.1/32"  extra source allowed to SSH (lockout guard)
#   KK_OPERATOR_USER=amina           human account that may read health + logs
#                                    (default: the user who ran sudo)
#   KK_PIN_NGINX / KK_PIN_CURL       override the pinned package versions
#
# Exit codes: 0 = converged and every verification check passed
#             1 = one or more verification checks failed (listed at the end)
#             2 = pre-flight failure (not root, wrong OS, already running)
#             3 = pinned package version mismatch (manual decision required)
#
# -----------------------------------------------------------------------------
# Expected dirty conditions found in pre-provisioning audit
# (the six conditions from the brief; each one has a named handling block)
#
# D1 Service accounts created by hand on Tuesday, possibly with a login shell,
#    a home directory or the wrong groups
#      -> Phase 3: "Already exists" detected by `id`; shell, home, primary
#         group, supplementary groups and password lock are each compared and
#         converged with usermod. UIDs are kept (files on disk use them).
# D2 Permissions and ACLs set by hand on Tuesday and partly changed since
#    (e.g. config/ left at 777, shared/logs missing the kk-payments entry)
#      -> Phase 4: owner, group and mode compared per directory; the full
#         access + default ACL is compared as text and, on any drift, cleared
#         and re-applied from the access model.
# D3 Logrotate config fixed by hand on Thursday but never committed
#      -> Phase 7: the existing file is compared with the intended one; if it
#         differs it is backed up and replaced, then validated with --debug.
# D4 ufw rules edited by hand twice (Wednesday setup, Thursday deny 3001)
#      -> Phase 5: the live ruleset is fingerprinted; if it is not exactly the
#         ruleset this script last applied, ufw is RESET and rebuilt from
#         intent (rules in a deliberate order, every rule commented).
# D5 Package holds set earlier and possibly overridden by `apt upgrade`
#      -> Phase 2: installed version compared with the pin BEFORE any install.
#         Match: skip. Mismatch: stop with exit 3 (no silent downgrade).
#         Missing holds re-applied; unexpected holds reported.
# D6 systemd units left over from Wednesday with a different hardening level
#    (and possibly drop-in overrides that silently weaken them)
#      -> Phase 6: each unit file is compared with the inline definition;
#         differences are backed up and replaced; drop-in override
#         directories are moved to the backup folder; daemon-reload only
#         when something changed.
# Also handled: config files under /etc/kijanikiosk from earlier labs
#    (Integration Challenge A) -> Phase 4 backs them up and removes the
#    legacy directory so the only config source is /opt/kijanikiosk/config.
# -----------------------------------------------------------------------------

set -Eeuo pipefail
umask 027

# ============================== Configuration ================================
readonly KK_BASE=/opt/kijanikiosk
readonly KK_CONFIG="${KK_BASE}/config"
readonly KK_SHARED="${KK_BASE}/shared"
readonly KK_LOGS="${KK_SHARED}/logs"
readonly KK_HEALTH="${KK_BASE}/health"
readonly KK_GROUP=kijanikiosk
readonly KK_SERVICES=(kk-api kk-payments kk-logs)
readonly NOLOGIN=/usr/sbin/nologin
readonly MONITORING_CIDR=10.0.1.0/24
readonly LOGROTATE_CONF=/etc/logrotate.d/kijanikiosk
readonly JOURNALD_DROPIN=/etc/systemd/journald.conf.d/kijanikiosk.conf
readonly NGINX_SITE=/etc/nginx/sites-available/kijanikiosk
readonly STATE_DIR=/var/lib/kijanikiosk
RUN_ID="$(date +%Y%m%dT%H%M%S)"; readonly RUN_ID
readonly BACKUP_DIR="/var/backups/kijanikiosk/${RUN_ID}"

# Ports. kk-payments listens on all interfaces (the firewall and its own
# IP allow-list decide who may connect); the other two are loopback-only.
declare -A SVC_PORT=([kk-api]=3000 [kk-payments]=3001 [kk-logs]=3002)
declare -A SVC_BIND=([kk-api]=127.0.0.1 [kk-payments]=0.0.0.0 [kk-logs]=127.0.0.1)
declare -A SVC_SHORT=([kk-api]=api [kk-payments]=payments [kk-logs]=logs)
declare -A SVC_ENVFILE=([kk-api]=api.env [kk-payments]=payments-api.env [kk-logs]=logs.env)

# Pinned packages (Challenge D). Override per environment, never edit in place
# on a server: the pin is part of the reviewed spec.
declare -A PINS=(
  [nginx]="${KK_PIN_NGINX:-1.24.0-2ubuntu7.7}"
  [curl]="${KK_PIN_CURL:-8.5.0-2ubuntu10.16}"
)
readonly BASE_PACKAGES=(acl ufw logrotate python3)

KK_OPERATOR_USER="${KK_OPERATOR_USER:-${SUDO_USER:-}}"
KK_ADMIN_CIDR="${KK_ADMIN_CIDR:-}"

# ================================ Logging ====================================
CURRENT_PHASE="0"
ts()      { date -Is; }
log()     { printf '[%s] [PHASE %s] INFO  %s\n' "$(ts)" "$CURRENT_PHASE" "$*"; }
found()   { printf '[%s] [PHASE %s] FOUND %s\n' "$(ts)" "$CURRENT_PHASE" "$*"; }
changed() { printf '[%s] [PHASE %s] FIX   %s\n' "$(ts)" "$CURRENT_PHASE" "$*"; }
ok()      { printf '[%s] [PHASE %s] OK    %s\n' "$(ts)" "$CURRENT_PHASE" "$*"; }
warn()    { printf '[%s] [PHASE %s] WARN  %s\n' "$(ts)" "$CURRENT_PHASE" "$*" >&2; }
die()     { printf '[%s] [PHASE %s] FATAL %s\n' "$(ts)" "$CURRENT_PHASE" "$*" >&2; exit "${2:-2}"; }
phase()   { CURRENT_PHASE="$1"; printf '\n[%s] ================ PHASE %s: %s ================\n' "$(ts)" "$1" "$2"; }

# shellcheck disable=SC2154
trap 'rc=$?; printf "[%s] [PHASE %s] FATAL unexpected error (exit %s) at line %s: %s\n" "$(ts)" "$CURRENT_PHASE" "$rc" "$LINENO" "$BASH_COMMAND" >&2; exit "$rc"' ERR

# ================================ Helpers ====================================
backup() {          # backup <path>: copy a file or directory into this run's backup folder
  local src="$1" dest
  [[ -e "$src" ]] || return 0
  dest="${BACKUP_DIR}${src}"
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
  log "Backed up ${src} -> ${dest}"
}

# write_file <path> <owner:group> <mode> <description>   (content on stdin)
# Writes only when content differs; returns 0 if changed, 1 if unchanged.
write_file() {
  local path="$1" owner="$2" mode="$3" desc="$4" tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  if [[ -f "$path" ]] && cmp -s "$tmp" "$path"; then
    rm -f "$tmp"
    ensure_owner_mode "$path" "$owner" "$mode"
    ok "Unchanged: ${desc} (${path})"
    return 1
  fi
  if [[ -f "$path" ]]; then
    found "Drift: ${desc} differs from the spec (${path})"
    backup "$path"
  else
    log "Missing: ${desc} (${path})"
  fi
  install -D -o "${owner%%:*}" -g "${owner##*:}" -m "$mode" "$tmp" "$path"
  rm -f "$tmp"
  changed "Wrote ${desc} (${path})"
  return 0
}

# ensure_owner_mode <path> <owner:group> <mode>: converge ownership and mode, logging drift
ensure_owner_mode() {
  local path="$1" want_owner="$2" want_mode="$3" have_owner have_mode
  have_owner="$(stat -c '%U:%G' "$path")"
  have_mode="$(stat -c '%a' "$path")"
  if [[ "$have_owner" != "$want_owner" ]]; then
    found "${path} owned by ${have_owner}, expected ${want_owner}"
    chown "$want_owner" "$path"
    changed "chown ${want_owner} ${path}"
  fi
  # compare numerically so 0750 and 750 are equal
  if (( 8#${have_mode} != 8#${want_mode} )); then
    found "${path} has mode ${have_mode}, expected ${want_mode}"
    chmod "$want_mode" "$path"
    changed "chmod ${want_mode} ${path}"
  fi
}

ensure_dir() {      # ensure_dir <path> <owner:group> <mode>
  local path="$1" owner="$2" mode="$3"
  if [[ -d "$path" ]]; then
    ok "Already exists: directory ${path}"
  else
    install -d -o "${owner%%:*}" -g "${owner##*:}" -m "$mode" "$path"
    changed "Created directory ${path}"
  fi
  ensure_owner_mode "$path" "$owner" "$mode"
}

# ensure_acl <dir> <acl-spec>: the spec is the exact access + default ACL
# (setfacl --set syntax, default entries prefixed with d:). Any drift (extra,
# missing or changed entries) clears the ACL and re-applies the full spec.
ensure_acl() {
  local dir="$1" spec="$2" want have tmpdir
  tmpdir="$(mktemp -d)"
  # Render the intended ACL by applying it to a scratch object of the same
  # type and owner, then compare the two as text.
  if [[ -d "$dir" ]]; then mkdir "${tmpdir}/x"; else : > "${tmpdir}/x"; fi
  chown --reference="$dir" "${tmpdir}/x"
  chmod --reference="$dir" "${tmpdir}/x"
  setfacl --set "$spec" "${tmpdir}/x"
  want="$(getfacl --omit-header --absolute-names --numeric "${tmpdir}/x" | sed '/^$/d')"
  have="$(getfacl --omit-header --absolute-names --numeric "$dir" | sed '/^$/d')"
  rm -rf "$tmpdir"
  if [[ "$want" == "$have" ]]; then
    ok "ACL matches access model: ${dir}"
  else
    found "ACL drift on ${dir}:"
    diff <(printf '%s\n' "$have") <(printf '%s\n' "$want") | sed 's/^/        /' || true
    setfacl -b "$dir"
    setfacl --set "$spec" "$dir"
    changed "ACL reset to access model: ${dir}"
  fi
}

port_open() { timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/$1" 2>/dev/null; }

# ============================ Verification registry ==========================
PASSED=(); FAILED=()
check() {           # check "<phase>" "<description>" <command...>
  local ph="$1" desc="$2"; shift 2
  if "$@" >/dev/null 2>&1; then
    PASSED+=("[P${ph}] ${desc}"); printf '  PASS  [P%s] %s\n' "$ph" "$desc"
  else
    FAILED+=("[P${ph}] ${desc}"); printf '  FAIL  [P%s] %s\n' "$ph" "$desc"
  fi
}

# =============================================================================
phase 1 "Pre-flight and dirty-state detection"
# =============================================================================
[[ $EUID -eq 0 ]] || die "Run as root: sudo $0" 2
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID}" == "ubuntu" && "${VERSION_ID}" == "24.04" ]] \
  || die "Built and tested for Ubuntu 24.04, found ${PRETTY_NAME}" 2

mkdir -p "$STATE_DIR" "$BACKUP_DIR"
exec 9> "${STATE_DIR}/provision.lock"
flock -n 9 || die "Another provisioning run holds ${STATE_DIR}/provision.lock" 2
log "Run ID ${RUN_ID}; backups for anything replaced go to ${BACKUP_DIR}"
log "Operator account (read access to health and logs): ${KK_OPERATOR_USER:-<none>}"

# A quick inventory, so the log states up front what this run inherits.
# Each item is handled again (and fixed) in its own phase.
for u in "${KK_SERVICES[@]}"; do
  if id "$u" &>/dev/null; then log "Already exists: ${u} ($(id "$u"); shell $(getent passwd "$u" | cut -d: -f7))"
  else log "Not present yet: account ${u}"; fi
done
[[ -d "$KK_BASE" ]] && log "Already exists: ${KK_BASE}" || log "Not present yet: ${KK_BASE}"
[[ -d /etc/kijanikiosk ]] && found "Legacy config directory present: /etc/kijanikiosk (Challenge A)" || true
[[ -f "$LOGROTATE_CONF" ]] && log "Existing logrotate config: ${LOGROTATE_CONF}" || true
holds="$(apt-mark showhold | tr '\n' ' ')"
[[ -n "$holds" ]] && log "Package holds present: ${holds}" || log "No package holds set"
if ufw status 2>/dev/null | grep -q '^Status: active'; then
  log "ufw is active with $(ufw status numbered | grep -c '^\[' || true) rule(s) inherited"
else
  log "ufw is inactive"
fi
for s in "${KK_SERVICES[@]}"; do
  [[ -f "/etc/systemd/system/${s}.service" ]] && log "Existing unit file: ${s}.service" || true
  [[ -d "/etc/systemd/system/${s}.service.d" ]] && found "Drop-in override directory: ${s}.service.d" || true
done

# =============================================================================
phase 2 "Packages and version pins"
# =============================================================================
# Refresh the index at most once a day, so repeat runs do not hit the mirrors.
if [[ -z "$(find /var/lib/apt/lists -maxdepth 1 -name '*_Packages' -mmin -1440 2>/dev/null | head -1)" ]]; then
  apt-get update -qq
  changed "apt package index refreshed"
else
  ok "apt package index is less than a day old: not refreshed"
fi

missing=()
for p in "${BASE_PACKAGES[@]}"; do
  if dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed'; then
    ok "Already installed: ${p}"
  else
    missing+=("$p")
  fi
done
if ((${#missing[@]})); then
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"
  changed "Installed: ${missing[*]}"
fi

# D5 / Challenge D: compare the installed version with the pin BEFORE touching apt.
mismatch=0
for p in "${!PINS[@]}"; do
  want="${PINS[$p]}"
  have="$(dpkg-query -W -f='${Version}' "$p" 2>/dev/null || true)"
  status="$(dpkg-query -W -f='${Status}' "$p" 2>/dev/null || true)"
  if [[ "$status" != *"install ok installed"* ]]; then
    log "Not installed: ${p}; installing pinned version ${want}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --allow-change-held-packages "${p}=${want}"
    changed "Installed ${p}=${want}"
  elif [[ "$have" == "$want" ]]; then
    ok "Already at pinned version: ${p} ${have} (install skipped)"
  else
    warn "Pinned version mismatch: ${p} is ${have}, spec pins ${want}"
    mismatch=1
  fi
done
if ((mismatch)); then
  die "Refusing to up/downgrade pinned packages automatically. Review the change, then either
        (a) update the pin in this script through a reviewed commit, or
        (b) run: apt-get install --allow-downgrades --allow-change-held-packages <pkg>=<pinned version>
        and re-run this script. See hardening-decisions.md (package policy)." 3
fi

held="$(apt-mark showhold)"
for p in "${!PINS[@]}"; do
  if grep -qx "$p" <<<"$held"; then
    ok "Hold already set: ${p}"
  else
    found "Hold missing on pinned package ${p} (lost or never set)"
    apt-mark hold "$p" >/dev/null
    changed "apt-mark hold ${p}"
  fi
done
while read -r h; do
  [[ -z "$h" || -n "${PINS[$h]+x}" ]] && continue
  warn "Unexpected hold on ${h}: not part of this spec, left in place for a human to review"
done <<<"$held"

# =============================================================================
phase 3 "Service accounts and groups"
# =============================================================================
for g in "$KK_GROUP" "${KK_SERVICES[@]}"; do
  if getent group "$g" >/dev/null; then ok "Already exists: group ${g} (GID $(getent group "$g" | cut -d: -f3))"
  else groupadd --system "$g"; changed "Created system group ${g}"; fi
done

for u in "${KK_SERVICES[@]}"; do
  if ! id "$u" &>/dev/null; then
    useradd --system --gid "$u" --groups "$KK_GROUP" --shell "$NOLOGIN" \
            --home-dir /nonexistent --no-create-home "$u"
    changed "Created service account ${u} (UID $(id -u "$u"))"
  else
    log "Already exists: ${u} (UID $(id -u "$u")); comparing its parameters with the spec (D1)"
    # usermod refuses some changes while the account runs processes (e.g. a
    # unit left over from Wednesday). Stop it first; Phase 6 starts it again.
    if pgrep -u "$u" >/dev/null 2>&1; then
      systemctl stop "${u}.service" 2>/dev/null || true
      pkill -u "$u" 2>/dev/null || true
      found "${u} had running processes: stopped before changing the account"
    fi
    IFS=: read -r _ _ _ gid _ home shell < <(getent passwd "$u")
    want_gid="$(getent group "$u" | cut -d: -f3)"
    if [[ "$shell" != "$NOLOGIN" ]]; then
      found "${u} has login shell ${shell}"; usermod --shell "$NOLOGIN" "$u"; changed "${u} shell -> ${NOLOGIN}"; fi
    if [[ "$home" != /nonexistent ]]; then
      found "${u} has home ${home}"; usermod --home /nonexistent "$u"; changed "${u} home -> /nonexistent (old directory left untouched)"; fi
    if [[ "$gid" != "$want_gid" ]]; then
      found "${u} primary GID ${gid}, expected ${want_gid} (${u})"; usermod --gid "$u" "$u"; changed "${u} primary group -> ${u}"; fi
    groups_now="$(id -nG "$u" | tr ' ' '\n' | grep -vx "$u" | sort | tr '\n' ' ' | sed 's/ $//' || true)"
    if [[ "$groups_now" != "$KK_GROUP" ]]; then
      found "${u} supplementary groups '${groups_now}', expected '${KK_GROUP}'"
      usermod --groups "$KK_GROUP" "$u"; changed "${u} supplementary groups -> ${KK_GROUP}"
    fi
  fi
  if [[ "$(passwd -S "$u" | awk '{print $2}')" != "L" ]]; then
    passwd -l "$u" >/dev/null; changed "${u} password locked"
  else
    ok "${u}: password locked, shell ${NOLOGIN}, groups ${u} + ${KK_GROUP}"
  fi
done

if [[ -n "$KK_OPERATOR_USER" && "$KK_OPERATOR_USER" != root ]] && id "$KK_OPERATOR_USER" &>/dev/null; then
  if id -nG "$KK_OPERATOR_USER" | tr ' ' '\n' | grep -qx "$KK_GROUP"; then
    ok "Operator ${KK_OPERATOR_USER} already in ${KK_GROUP}"
  else
    usermod -aG "$KK_GROUP" "$KK_OPERATOR_USER"
    changed "Added operator ${KK_OPERATOR_USER} to ${KK_GROUP} (read-only access to health and logs)"
  fi
fi

# =============================================================================
phase 4 "Directories, configuration and the access model"
# =============================================================================
ensure_dir "$KK_BASE"   "root:${KK_GROUP}" 0750
ensure_dir "$KK_CONFIG" "root:${KK_GROUP}" 0750
ensure_dir "$KK_SHARED" "root:${KK_GROUP}" 0750
# shared/logs shows 2770 because, once named ACL entries exist, the group
# permission bits display the ACL mask (rwx). The owning group itself is
# held to r-x by its ACL entry.
ensure_dir "$KK_LOGS"   "kk-logs:${KK_GROUP}" 2770
ensure_dir "$KK_HEALTH" "kk-logs:${KK_GROUP}" 2750
for s in "${KK_SERVICES[@]}"; do
  short="${SVC_SHORT[$s]}"
  ensure_dir "${KK_BASE}/${short}"      "root:${s}" 0750
  ensure_dir "${KK_BASE}/${short}/app"  "root:${s}" 0750
  ensure_dir "${KK_BASE}/${short}/data" "${s}:${s}" 0750
done

# Access model (see access-model-final.md). Default ACLs make every file
# created later (including by logrotate) inherit the same rules.
ensure_acl "$KK_LOGS" \
  "u::rwx,u:kk-api:rwx,u:kk-payments:r-x,g::r-x,m::rwx,o::---,d:u::rwx,d:u:kk-api:rwx,d:u:kk-payments:r-x,d:g::r-x,d:m::rwx,d:o::---"
ensure_acl "$KK_HEALTH" \
  "u::rwx,g::r-x,o::---,d:u::rwx,d:g::r-x,d:o::---"
ensure_acl "$KK_CONFIG" "u::rwx,g::r-x,o::---"
ensure_acl "$KK_BASE"   "u::rwx,g::r-x,o::---"

# Challenge A: one config location. Anything left in /etc/kijanikiosk from
# earlier labs is backed up and removed so it cannot be read by mistake.
if [[ -d /etc/kijanikiosk ]]; then
  found "Legacy config in /etc/kijanikiosk: $(find /etc/kijanikiosk -type f | tr '\n' ' ' || true)"
  backup /etc/kijanikiosk
  rm -rf /etc/kijanikiosk
  changed "Removed /etc/kijanikiosk; the single config source is ${KK_CONFIG}"
else
  ok "No legacy config under /etc/kijanikiosk"
fi

# Environment files: root-owned, readable only by the service's own group.
ENV_CHANGED=()
for s in "${KK_SERVICES[@]}"; do
  if write_file "${KK_CONFIG}/${SVC_ENVFILE[$s]}" "root:${s}" 0640 "${s} environment file" <<EOF
# Managed by kijanikiosk-provision.sh. Do not edit on the server.
SERVICE_NAME=${s}
SERVICE_PORT=${SVC_PORT[$s]}
BIND_ADDRESS=${SVC_BIND[$s]}
APP_ENV=production
LOG_DIR=${KK_LOGS}
EOF
  then ENV_CHANGED+=("$s"); fi
done

# Placeholder application content (no application code is deployed yet).
for s in "${KK_SERVICES[@]}"; do
  write_file "${KK_BASE}/${SVC_SHORT[$s]}/app/index.html" "root:${s}" 0640 "${s} placeholder page" <<EOF || true
<!doctype html><title>${s}</title><p>${s} placeholder: application not yet deployed.</p>
EOF
done

# Log files exist before the services start, with the same owner and mode
# that logrotate's create directive will use (0660 kk-logs:kijanikiosk).
for s in "${KK_SERVICES[@]}"; do
  f="${KK_LOGS}/${s}.log"
  if [[ -f "$f" ]]; then ok "Already exists: ${f}"
  else install -o kk-logs -g "$KK_GROUP" -m 0660 /dev/null "$f"; changed "Created ${f}"; fi
  ensure_owner_mode "$f" "kk-logs:${KK_GROUP}" 0660
  # Files created before the default ACL existed (Tuesday's hand setup) do not
  # carry it; give them exactly what a newly created file would inherit.
  ensure_acl "$f" "u::rw-,u:kk-api:rwx,u:kk-payments:r-x,g::r-x,m::rw-,o::---"
done

# =============================================================================
phase 5 "Firewall: express intent, not history"
# =============================================================================
# Intended ruleset, in evaluation order (first match wins).
# The two port-3001 allows MUST come before the port-3001 deny.
UFW_RULES=(
  "allow in on lo to any port 3001 proto tcp comment 'kk-payments: loopback only, for nginx proxying'"
  "allow from ${MONITORING_CIDR} to any port 3001 proto tcp comment 'kk-payments health check from monitoring subnet'"
  "deny 3001/tcp comment 'kk-payments internal port: block every other source'"
  "allow from ${MONITORING_CIDR} to any port 22 proto tcp comment 'SSH from monitoring/admin subnet only'"
  "allow from ${MONITORING_CIDR} to any port 80 proto tcp comment 'HTTP (nginx) from monitoring subnet only'"
)
# Lockout guard: keep the operator's current SSH session reachable.
guard_sources=()
[[ -n "$KK_ADMIN_CIDR" ]] && guard_sources+=("$KK_ADMIN_CIDR")
while read -r peer; do
  [[ -n "$peer" ]] && guard_sources+=("${peer}/32")
done < <(ss -Htn state established '( sport = :22 )' 2>/dev/null | awk '{print $4}' | sed -E 's/^\[?(::ffff:)?//; s/\]?:[0-9]+$//' | grep -E '^[0-9.]+$' | sort -u)
for src in $(printf '%s\n' "${guard_sources[@]}" | sort -u); do
  UFW_RULES+=("allow from ${src} to any port 22 proto tcp comment 'operator SSH session (lockout guard)'")
done

intent_hash="$(printf '%s\n' "${UFW_RULES[@]}" | sha256sum | cut -d' ' -f1)"
live_hash="$( { ufw status verbose 2>/dev/null; ufw show added 2>/dev/null; } | sha256sum | cut -d' ' -f1)"
recorded="$(cat "${STATE_DIR}/ufw.intent" 2>/dev/null || true)"

if [[ "$recorded" == "${intent_hash} ${live_hash}" ]]; then
  ok "Live ufw ruleset is exactly the ruleset this script last applied: no reset needed"
else
  if [[ -z "$recorded" ]]; then
    found "ufw ruleset has no record of being applied by this script (hand-edited history, D4)"
  else
    found "ufw ruleset drifted from the last applied intent (D4)"
  fi
  ufw status numbered 2>/dev/null | sed 's/^/        inherited: /' || true
  ufw --force reset >/dev/null
  # ufw reset leaves timestamped copies of the old rules; move them into this run's backup.
  mkdir -p "${BACKUP_DIR}/ufw"
  if [[ -d /etc/ufw ]]; then
    find /etc/ufw -maxdepth 1 -name '*.rules.[0-9]*' -exec mv {} "${BACKUP_DIR}/ufw/" \;
  fi
  changed "ufw reset to a clean baseline (old rules saved under ${BACKUP_DIR}/ufw)"
  ufw default deny incoming  >/dev/null
  ufw default allow outgoing >/dev/null
  for r in "${UFW_RULES[@]}"; do
    eval "ufw ${r}" >/dev/null
    changed "ufw ${r}"
  done
  ufw --force enable >/dev/null
  live_hash="$( { ufw status verbose; ufw show added; } | sha256sum | cut -d' ' -f1)"
  printf '%s %s\n' "$intent_hash" "$live_hash" > "${STATE_DIR}/ufw.intent"
  changed "ufw enabled; intent fingerprint recorded in ${STATE_DIR}/ufw.intent"
fi

# =============================================================================
phase 6 "systemd units (written inline) and nginx"
# =============================================================================
# Hardening shared by all three services. kk-payments adds a tighter
# network allow-list and gets no write access to the shared logs.
# Measured scores: see kk-payments-hardening.md.
COMMON_HARDENING='# ---- Filesystem ----
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
UMask=0027
# ---- Privilege ----
NoNewPrivileges=yes
CapabilityBoundingSet=
AmbientCapabilities=
RestrictSUIDSGID=yes
RemoveIPC=yes
KeyringMode=private
# ---- Kernel, devices, processes ----
PrivateDevices=yes
DevicePolicy=closed
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
ProtectProc=invisible
ProcSubset=pid
LockPersonality=yes
MemoryDenyWriteExecute=yes
RestrictRealtime=yes
RestrictNamespaces=yes
# ---- System calls and network ----
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
SystemCallErrorNumber=EPERM
RestrictAddressFamilies=AF_INET AF_INET6'

unit_body() {       # unit_body <service> <description> <extra [Unit] lines> <extra [Service] lines>
  local s="$1" desc="$2" unit_extra="$3" svc_extra="$4" short="${SVC_SHORT[$1]}"
  cat <<EOF
# Managed by kijanikiosk-provision.sh (written inline). Do not edit on the server.
[Unit]
Description=${desc}
After=network-online.target
Wants=network-online.target
${unit_extra}
[Service]
Type=simple
User=${s}
Group=${s}
SupplementaryGroups=${KK_GROUP}
EnvironmentFile=${KK_CONFIG}/${SVC_ENVFILE[$s]}
WorkingDirectory=${KK_BASE}/${short}/app
# Placeholder process until the application is deployed: serves app/ on the port.
ExecStart=/usr/bin/python3 -m http.server \${SERVICE_PORT} --bind \${BIND_ADDRESS} --directory ${KK_BASE}/${short}/app
Restart=on-failure
RestartSec=5
# systemd (PID 1) opens the log before the sandbox applies; logrotate's
# postrotate try-restart makes it reopen the new file after rotation.
StandardOutput=append:${KK_LOGS}/${s}.log
StandardError=inherit

${COMMON_HARDENING}
${svc_extra}

[Install]
WantedBy=multi-user.target
EOF
}

UNITS_CHANGED=()
write_unit() {      # write_unit <service> (body on stdin)
  local s="$1" dropin="/etc/systemd/system/$1.service.d"
  if [[ -d "$dropin" ]]; then
    found "Drop-in overrides for ${s} would change its hardening: $(find "$dropin" -type f | tr '\n' ' ') (D6)"
    backup "$dropin"; rm -rf "$dropin"
    changed "Removed ${dropin}"
    UNITS_CHANGED+=("$s")
  fi
  if write_file "/etc/systemd/system/${s}.service" root:root 0644 "${s} unit file"; then
    UNITS_CHANGED+=("$s")
  fi
}

write_unit kk-api < <(unit_body kk-api "KijaniKiosk API (customer-facing, behind nginx)" "" \
"ReadWritePaths=${KK_LOGS} ${KK_BASE}/api/data
IPAddressDeny=any
IPAddressAllow=localhost")

write_unit kk-payments < <(unit_body kk-payments "KijaniKiosk payments service (financial transactions)" \
"After=kk-api.service
Wants=kk-api.service" \
"# Payments may write only its own data directory: shared logs are read-only to it.
ReadWritePaths=${KK_BASE}/payments/data
# Only loopback (nginx) and the monitoring subnet may connect.
IPAddressDeny=any
IPAddressAllow=localhost ${MONITORING_CIDR}")

write_unit kk-logs < <(unit_body kk-logs "KijaniKiosk log collector and health reporter" "" \
"ReadWritePaths=${KK_LOGS} ${KK_HEALTH} ${KK_BASE}/logs/data
IPAddressDeny=any
IPAddressAllow=localhost
# No ExecReload: this process cannot reopen files on a signal. logrotate
# uses 'systemctl try-restart' instead (integration-notes.md, Challenge C).")

if ((${#UNITS_CHANGED[@]})); then
  systemctl daemon-reload
  changed "systemd daemon-reload (changed: ${UNITS_CHANGED[*]})"
else
  ok "All three unit files match the spec: no daemon-reload needed"
fi

for s in "${KK_SERVICES[@]}"; do
  if [[ "$(systemctl is-enabled "$s" 2>/dev/null || true)" == enabled ]]; then ok "Already enabled: ${s}"
  else systemctl enable "$s" >/dev/null 2>&1; changed "Enabled ${s}"; fi
  if printf '%s\n' "${UNITS_CHANGED[@]}" "${ENV_CHANGED[@]}" | grep -qx "$s"; then
    if systemctl restart "$s"; then changed "Restarted ${s} (unit or environment changed)"
    else warn "${s} failed to restart: see journalctl -u ${s} (verification will report it)"; fi
  elif systemctl is-active --quiet "$s"; then ok "Already running: ${s}"
  elif systemctl start "$s"; then changed "Started ${s}"
  else warn "${s} failed to start: see journalctl -u ${s} (verification will report it)"; fi
done

# nginx: proxy to the loopback-only services.
write_file "$NGINX_SITE" root:root 0644 "nginx site" <<'EOF' && NGINX_CHANGED=1 || NGINX_CHANGED=0
# Managed by kijanikiosk-provision.sh
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    location = /healthz          { return 200 "ok\n"; }
    location /api/               { proxy_pass http://127.0.0.1:3000/; }
    location /payments/health    { proxy_pass http://127.0.0.1:3001/; }
}
EOF
if [[ -L /etc/nginx/sites-enabled/default ]]; then
  found "nginx default site enabled (claims default_server)"
  rm -f /etc/nginx/sites-enabled/default; changed "Disabled nginx default site"; NGINX_CHANGED=1
fi
if [[ "$(readlink -f /etc/nginx/sites-enabled/kijanikiosk 2>/dev/null)" != "$NGINX_SITE" ]]; then
  ln -sfn "$NGINX_SITE" /etc/nginx/sites-enabled/kijanikiosk; changed "Enabled nginx site"; NGINX_CHANGED=1
fi
nginx -t -q || die "nginx configuration test failed" 1
if ((NGINX_CHANGED)); then systemctl reload-or-restart nginx; changed "nginx reloaded"
else systemctl is-active --quiet nginx || systemctl start nginx; ok "nginx config unchanged"; fi

# =============================================================================
phase 7 "Journal persistence and log rotation"
# =============================================================================
if write_file "$JOURNALD_DROPIN" root:root 0644 "journald drop-in" <<'EOF'
# Managed by kijanikiosk-provision.sh
[Journal]
Storage=persistent
SystemMaxUse=500M
EOF
then JOURNAL_CHANGED=1; else JOURNAL_CHANGED=0; fi
if [[ ! -d /var/log/journal ]]; then
  mkdir -p /var/log/journal; changed "Created /var/log/journal"; JOURNAL_CHANGED=1
fi
systemd-tmpfiles --create --prefix /var/log/journal >/dev/null 2>&1 || true
if ((JOURNAL_CHANGED)); then
  systemctl restart systemd-journald; journalctl --flush
  changed "journald restarted: persistent storage, capped at 500M"
else
  ok "Journal already persistent and capped at 500M"
fi

# D3: Thursday's hand fix is replaced by the committed definition.
# - su: the directory has an ACL granting write to non-root accounts, so
#   logrotate refuses it unless told which account to act as.
# - create 0660: the group bits become the ACL mask. 0640 would cap kk-api's
#   rwx entry at r-- and it could no longer write after rotation.
write_file "$LOGROTATE_CONF" root:root 0644 "logrotate config" <<EOF || true
# Managed by kijanikiosk-provision.sh. See access-model-final.md.
${KK_LOGS}/kk-api.log
${KK_LOGS}/kk-payments.log
${KK_LOGS}/kk-logs.log {
    su kk-logs ${KK_GROUP}
    daily
    rotate 14
    maxsize 50M
    missingok
    notifempty
    compress
    delaycompress
    create 0660 kk-logs ${KK_GROUP}
    sharedscripts
    postrotate
        # None of the units implement ExecReload, so 'reload' would fail.
        # try-restart reopens the log and does nothing if a service is stopped.
        systemctl try-restart kk-api.service kk-payments.service kk-logs.service >/dev/null 2>&1 || true
    endscript
}
EOF

if logrotate --debug "$LOGROTATE_CONF" > "${STATE_DIR}/logrotate-debug.txt" 2>&1 \
   && ! grep -qiE '^error' "${STATE_DIR}/logrotate-debug.txt"; then
  ok "logrotate --debug passed (output in ${STATE_DIR}/logrotate-debug.txt)"
else
  sed 's/^/        /' "${STATE_DIR}/logrotate-debug.txt" >&2
  die "logrotate --debug reported errors" 1
fi

# Requirement 3: simulate a rotation and check the access model survives it.
for s in "${KK_SERVICES[@]}"; do
  printf '%s provisioning run %s: rotation test marker\n' "$(ts)" "$RUN_ID" >> "${KK_LOGS}/${s}.log"
done
logrotate --force "$LOGROTATE_CONF"
changed "Forced a rotation of the three service logs (services try-restarted by postrotate)"
for s in "${KK_SERVICES[@]}"; do
  f="${KK_LOGS}/${s}.log"
  log "After rotation: $(stat -c '%A %U:%G' "$f") ${f}; ACL: $(getfacl --omit-header --absolute-names "$f" 2>/dev/null | grep -E '^user:kk-' | tr '\n' ' ' || true)"
done

# =============================================================================
phase 8 "Health checks and final verification"
# =============================================================================
# Give services restarted by postrotate a moment to bind their ports.
for _ in $(seq 1 20); do
  port_open 3000 && port_open 3001 && port_open 3002 && break
  sleep 0.5
done
status_of() { port_open "$1" && echo '"ok"' || echo '"down"'; }
api_status="$(status_of 3000)"; payments_status="$(status_of 3001)"; logs_status="$(status_of 3002)"
printf '{"timestamp":"%s","run_id":"%s","kk-api":%s,"kk-payments":%s,"kk-logs":%s}\n' \
  "$(ts)" "$RUN_ID" "$api_status" "$payments_status" "$logs_status" > "${KK_HEALTH}/last-provision.json"
chown "kk-logs:${KK_GROUP}" "${KK_HEALTH}/last-provision.json"
chmod 0640 "${KK_HEALTH}/last-provision.json"
log "Health check written: $(cat "${KK_HEALTH}/last-provision.json")"

echo
log "Running every verification check (PASS/FAIL per check)"

# -- Phase 2 checks
for p in "${!PINS[@]}"; do
  check 2 "${p} installed at pinned version ${PINS[$p]}" test "$(dpkg-query -W -f='${Version}' "$p")" = "${PINS[$p]}"
  check 2 "${p} is on hold" bash -c "apt-mark showhold | grep -qx '$p'"
done
for p in "${BASE_PACKAGES[@]}"; do
  check 2 "${p} installed" bash -c "dpkg-query -W -f='\${Status}' '$p' | grep -q 'install ok installed'"
done

# -- Phase 3 checks
for u in "${KK_SERVICES[@]}"; do
  check 3 "${u} exists with shell ${NOLOGIN}" test "$(getent passwd "$u" | cut -d: -f7)" = "$NOLOGIN"
  check 3 "${u} primary group is ${u}" test "$(id -gn "$u")" = "$u"
  check 3 "${u} supplementary groups are exactly ${KK_GROUP}" test "$(id -nG "$u" | tr ' ' '\n' | grep -vx "$u" | sort | xargs)" = "$KK_GROUP"
  check 3 "${u} password is locked" test "$(passwd -S "$u" | awk '{print $2}')" = L
done

# -- Phase 4 checks
check 4 "${KK_BASE} is root:${KK_GROUP} 750" test "$(stat -c '%U:%G %a' "$KK_BASE")" = "root:${KK_GROUP} 750"
check 4 "${KK_CONFIG} is root:${KK_GROUP} 750" test "$(stat -c '%U:%G %a' "$KK_CONFIG")" = "root:${KK_GROUP} 750"
check 4 "${KK_LOGS} owned kk-logs:${KK_GROUP}, setgid" bash -c "[[ \$(stat -c '%U:%G' '$KK_LOGS') == kk-logs:${KK_GROUP} && -g '$KK_LOGS' ]]"
check 4 "${KK_LOGS} ACL grants kk-api rwx"            bash -c "getfacl -p '$KK_LOGS' | grep -qx 'user:kk-api:rwx'"
check 4 "${KK_LOGS} ACL grants kk-payments read only"  bash -c "getfacl -p '$KK_LOGS' | grep -qx 'user:kk-payments:r-x'"
check 4 "${KK_LOGS} default ACL present for new files" bash -c "getfacl -p '$KK_LOGS' | grep -qx 'default:user:kk-api:rwx'"
check 4 "${KK_HEALTH} default ACL gives the group read" bash -c "getfacl -p '$KK_HEALTH' | grep -qx 'default:group::r-x'"
check 4 "No legacy config under /etc/kijanikiosk" test ! -e /etc/kijanikiosk
for s in "${KK_SERVICES[@]}"; do
  ef="${KK_CONFIG}/${SVC_ENVFILE[$s]}"
  check 4 "${s} can read its EnvironmentFile ${ef}" sudo -u "$s" cat "$ef"
done
check 4 "kk-api cannot read the payments EnvironmentFile" bash -c "! sudo -u kk-api cat '${KK_CONFIG}/payments-api.env'"

# -- Phase 5 checks (one assertion per rule, plus ordering)
ufw_num="$(ufw status numbered)"
ufw_verbose="$(ufw status verbose)"
check 5 "ufw is active"                              grep -q '^Status: active' <<<"$ufw_verbose"
check 5 "default policy: deny incoming"              grep -q 'deny (incoming)' <<<"$ufw_verbose"
check 5 "3001/tcp allowed on loopback (nginx proxy)"  grep -Eq '3001/tcp on lo +ALLOW IN +Anywhere +# kk-payments: loopback' <<<"$ufw_num"
check 5 "3001/tcp allowed from ${MONITORING_CIDR}"   grep -Eq '3001/tcp +ALLOW IN +10\.0\.1\.0/24 +# kk-payments health' <<<"$ufw_num"
check 5 "3001/tcp denied from everywhere else"       grep -Eq '3001/tcp +DENY IN +Anywhere +# kk-payments internal' <<<"$ufw_num"
check 5 "22/tcp allowed from ${MONITORING_CIDR} only" grep -Eq '22/tcp +ALLOW IN +10\.0\.1\.0/24 +# SSH from' <<<"$ufw_num"
check 5 "80/tcp allowed from ${MONITORING_CIDR} only" grep -Eq '80/tcp +ALLOW IN +10\.0\.1\.0/24 +# HTTP' <<<"$ufw_num"
no_open_ssh_http()  { ! grep -Eq '^\[ *[0-9]+\] +(22|80)/tcp( \(v6\))? +ALLOW IN +Anywhere' <<<"$ufw_num"; }
all_rules_commented() { ! grep -E '^\[ *[0-9]+\]' <<<"$ufw_num" | grep -vq '#'; }
check 5 "no SSH or HTTP rule open to Anywhere"       no_open_ssh_http
check 5 "every ufw rule carries a comment"           all_rules_commented
idx() { grep -nE "$1" <<<"$ufw_num" | head -1 | cut -d: -f1 || true; }
lo_i="$(idx '3001/tcp on lo')"; mon_i="$(idx '3001/tcp +ALLOW IN +10\.0\.1')"; deny_i="$(idx '3001/tcp +DENY')"
check 5 "loopback allow is evaluated before the 3001 deny"   test "${lo_i:-99}"  -lt "${deny_i:-0}"
check 5 "monitoring allow is evaluated before the 3001 deny" test "${mon_i:-99}" -lt "${deny_i:-0}"

# -- Phase 6 checks
for s in "${KK_SERVICES[@]}"; do
  check 6 "${s} is enabled" systemctl is-enabled --quiet "$s"
  check 6 "${s} is active"  systemctl is-active  --quiet "$s"
  check 6 "${s} has no drop-in overrides" test ! -d "/etc/systemd/system/${s}.service.d"
done
check 6 "kk-payments: After=kk-api.service" bash -c "systemctl show -p After kk-payments | grep -qw kk-api.service"
check 6 "kk-payments: Wants=kk-api.service" bash -c "systemctl show -p Wants kk-payments | grep -qw kk-api.service"
score() { systemd-analyze security --no-pager "$1" 2>/dev/null | sed -nE 's/.*exposure level for [^:]+: ([0-9.]+).*/\1/p'; }
declare -A SCORE_MAX=([kk-api]=3.5 [kk-payments]=2.5 [kk-logs]=3.5)
for s in "${KK_SERVICES[@]}"; do
  sc="$(score "${s}.service")"
  check 6 "${s} exposure ${sc:-n/a} is below ${SCORE_MAX[$s]}" awk -v a="${sc:-99}" -v b="${SCORE_MAX[$s]}" 'BEGIN{exit !(a+0 < b+0)}'
done
check 6 "nginx configuration is valid" nginx -t -q
check 6 "nginx is active"              systemctl is-active --quiet nginx
check 6 "nginx proxies to kk-payments over loopback" curl -fsS -m 3 http://127.0.0.1/payments/health

# -- Phase 7 checks
check 7 "journal storage is persistent"   test -d /var/log/journal
check 7 "journal capped at 500M"          bash -c "systemd-analyze cat-config systemd/journald.conf | grep -qx 'SystemMaxUse=500M'"
check 7 "logrotate --debug passes"        bash -c "logrotate --debug '$LOGROTATE_CONF' 2>&1 | grep -qi '^error' && exit 1 || exit 0"
for s in "${KK_SERVICES[@]}"; do
  f="${KK_LOGS}/${s}.log"
  check 7 "${s}.log after rotation is kk-logs:${KK_GROUP} 660" test "$(stat -c '%U:%G %a' "$f")" = "kk-logs:${KK_GROUP} 660"
  check 7 "${s}.log after rotation: kk-api effective rw" bash -c "getfacl -p '$f' | grep -E '^user:kk-api:rw' | grep -vq 'effective:r--'"
done
check 7 "kk-api can write in shared/logs after rotation" \
  bash -c "sudo -u kk-api touch '${KK_LOGS}/test-write.tmp' && rm -f '${KK_LOGS}/test-write.tmp'"
check 7 "kk-payments can read kk-api.log after rotation" sudo -u kk-payments cat "${KK_LOGS}/kk-api.log"

# -- Phase 8 checks
hj="${KK_HEALTH}/last-provision.json"
check 8 "health file exists"                       test -s "$hj"
check 8 "health file is valid JSON"                python3 -m json.tool "$hj"
check 8 "health file is kk-logs:${KK_GROUP} 640"   test "$(stat -c '%U:%G %a' "$hj")" = "kk-logs:${KK_GROUP} 640"
if [[ -n "$KK_OPERATOR_USER" && "$KK_OPERATOR_USER" != root ]] && id "$KK_OPERATOR_USER" &>/dev/null; then
  check 8 "operator ${KK_OPERATOR_USER} can read the health file without sudo" sudo -u "$KK_OPERATOR_USER" cat "$hj"
fi
check 8 "kk-api port 3000 listening"      port_open 3000
check 8 "kk-payments port 3001 listening" port_open 3001
check 8 "kk-logs port 3002 listening"     port_open 3002

echo
printf '[%s] ================ VERIFICATION SUMMARY ================\n' "$(ts)"
printf 'Passed: %d   Failed: %d\n' "${#PASSED[@]}" "${#FAILED[@]}"
if ((${#FAILED[@]})); then
  printf 'Failed checks:\n'; printf '  - %s\n' "${FAILED[@]}"
  exit 1
fi
printf 'All checks passed. Server converged to the KijaniKiosk production foundation.\n'
exit 0
