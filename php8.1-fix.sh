#!/usr/bin/env bash
# Ubuntu PHP 8.1 remediation for:
#   CVE-2026-109618 / CVE-2026-109619 (PHP2Shell)
#   CVE-2026-115560 (session serializer mismatch; mitigation for PHP 8.1)
set -Eeuo pipefail

readonly JAMMY_FIXED_VERSION='8.1.2-1ubuntu2.28'
readonly MARKER='Managed by patch-php81-php2shell-ubuntu.sh'

log() { printf '[php-security] %s\n' "$*"; }
die() { printf '[php-security] ERROR: %s\n' "$*" >&2; exit 1; }
backup_file() {
  local path="$1"
  local backup="${path}.bak-php-security-$(date +%Y%m%d%H%M%S)-$$"
  cp -a -- "$path" "$backup"
  log "Backup created: $backup"
}

if (( EUID != 0 )); then
  die "Run as root, for example: sudo bash $0"
fi
[[ -r /etc/os-release ]] || die 'Cannot identify the operating system.'
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == 'ubuntu' ]] || die "This script is for Ubuntu; detected ID=${ID:-unknown}."
command -v apt-get >/dev/null || die 'apt-get was not found.'
command -v dpkg-query >/dev/null || die 'dpkg-query was not found.'
command -v python3 >/dev/null || die 'python3 is required to safely update PHP-FPM pool settings.'

mapfile -t php_packages < <(
  dpkg-query -W -f='${Package}\t${db:Status-Abbrev}\n' 2>/dev/null |
    awk '$2 ~ /^ii/ && ($1 ~ /^php8\.1($|-)/ || $1 == "libapache2-mod-php8.1" || $1 ~ /^libphp8\.1($|-)/) { print $1 }' |
    sort -u
)
((${#php_packages[@]} > 0)) || die 'No Ubuntu APT-managed PHP 8.1 packages are installed. This script cannot patch a manual, containerized, or hosting-panel PHP runtime.'

log "Ubuntu release: ${VERSION_ID:-unknown} (${VERSION_CODENAME:-unknown})"
log "Installed PHP 8.1 packages: ${php_packages[*]}"
log 'Updating APT indexes and upgrading installed PHP 8.1 packages.'
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y --only-upgrade install "${php_packages[@]}"

if ! dpkg-query -W -f='${db:Status-Abbrev}' php8.1-common 2>/dev/null | grep -q '^ii'; then
  die 'php8.1-common is not installed after the package update; unable to verify the PHP2Shell fix.'
fi
installed_common_version=$(dpkg-query -W -f='${Version}' php8.1-common)

if [[ "${VERSION_CODENAME:-}" == 'jammy' ]]; then
  if ! dpkg --compare-versions "$installed_common_version" ge "$JAMMY_FIXED_VERSION"; then
    die "php8.1-common is $installed_common_version; Ubuntu 22.04 requires $JAMMY_FIXED_VERSION or later. Check APT security repositories and try again."
  fi
else
  changelog_gz='/usr/share/doc/php8.1-common/changelog.Debian.gz'
  changelog='/usr/share/doc/php8.1-common/changelog.Debian'
  [[ -r "$changelog_gz" || -r "$changelog" ]] || die 'No readable php8.1-common changelog is available to verify the PHP2Shell fix.'
  for cve in CVE-2026-109618 CVE-2026-109619; do
    if [[ -r "$changelog_gz" ]]; then
      zgrep -q "$cve" "$changelog_gz" || die "The installed PHP 8.1 changelog does not confirm $cve."
    else
      grep -q "$cve" "$changelog" || die "The installed PHP 8.1 changelog does not confirm $cve."
    fi
  done
fi
log "Verified PHP2Shell fix in php8.1-common $installed_common_version."

# PHP 8.1 has no upstream binary release for CVE-2026-115560. Disable the
# session upload-progress feature at startup, and enforce it for FPM pools
# and Apache mod_php so per-directory/application settings cannot re-enable it.
install_managed_ini() {
  local path="$1" tmp
  tmp=$(mktemp)
  cat > "$tmp"
  if [[ -e "$path" ]]; then
    if ! grep -Fq "$MARKER" "$path"; then
      rm -f -- "$tmp"
      die "Refusing to overwrite an existing unmanaged config: $path"
    fi
    if cmp -s -- "$tmp" "$path"; then
      rm -f -- "$tmp"
      return
    fi
    backup_file "$path"
  fi
  install -D -m 0644 -- "$tmp" "$path"
  rm -f -- "$tmp"
  log "Installed mitigation config: $path"
}

for sapi in cli cgi fpm apache2; do
  conf_dir="/etc/php/8.1/$sapi/conf.d"
  if [[ -d "$conf_dir" ]]; then
    install_managed_ini "$conf_dir/99-session-upload-progress-off.ini" <<EOF_INI
; $MARKER
; Mitigation for CVE-2026-115560. File uploads still work; progress reporting is disabled.
session.upload_progress.enabled = Off
EOF_INI
  fi
done

fpm_pool_originals=()
fpm_pool_backups=()
shopt -s nullglob
fpm_pool_files=(/etc/php/8.1/fpm/pool.d/*.conf)
shopt -u nullglob
for pool_file in "${fpm_pool_files[@]}"; do
  if ! grep -Eq '^\s*\[[^]]+\]' "$pool_file"; then
    continue
  fi
  pool_backup="${pool_file}.bak-php-security-$(date +%Y%m%d%H%M%S)-$$"
  cp -a -- "$pool_file" "$pool_backup"
  log "Backup created: $pool_backup"
  fpm_pool_originals+=("$pool_file")
  fpm_pool_backups+=("$pool_backup")
  python3 - "$pool_file" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
lines = text.splitlines(keepends=True)
section_re = re.compile(r'^\s*\[[^\]]+\]')
setting_re = re.compile(r'^\s*php_admin_value\s*\[\s*session\.upload_progress\.enabled\s*\]\s*=')
chunks = []
preamble = []
current = None
for line in lines:
    if section_re.match(line):
        if current is not None:
            chunks.append(current)
        elif preamble:
            chunks.append(preamble)
            preamble = []
        current = [line]
    elif current is None:
        preamble.append(line)
    else:
        current.append(line)
if current is not None:
    chunks.append(current)
if preamble:
    chunks.insert(0, preamble)

out = []
for chunk in chunks:
    if not chunk or not section_re.match(chunk[0]):
        out.extend(chunk)
        continue
    found = False
    updated = []
    for line in chunk:
        if setting_re.match(line):
            if not found:
                updated.append('php_admin_value[session.upload_progress.enabled] = 0\n')
                found = True
        else:
            updated.append(line)
    if not found:
        header = updated[0]
        if not header.endswith(('\n', '\r')):
            updated[0] = header + '\n'
        updated.insert(1, 'php_admin_value[session.upload_progress.enabled] = 0\n')
    out.extend(updated)
path.write_text(''.join(out))
PY
done

if ((${#fpm_pool_originals[@]} > 0)); then
  fpm_tester=$(command -v php-fpm8.1 || true)
  [[ -n "$fpm_tester" ]] || [[ ! -x /usr/sbin/php-fpm8.1 ]] || fpm_tester='/usr/sbin/php-fpm8.1'
  if [[ -z "$fpm_tester" ]]; then
    for i in "${!fpm_pool_originals[@]}"; do
      cp -a -- "${fpm_pool_backups[$i]}" "${fpm_pool_originals[$i]}"
    done
    die 'PHP-FPM pool files were restored because php-fpm8.1 -t is unavailable to validate them.'
  fi
  if ! "$fpm_tester" -t; then
    for i in "${!fpm_pool_originals[@]}"; do
      cp -a -- "${fpm_pool_backups[$i]}" "${fpm_pool_originals[$i]}"
    done
    die 'PHP-FPM configuration check failed; pool files were restored from their backups.'
  fi
fi

# Enforce the mitigation for Apache mod_php if that SAPI is installed.
if dpkg-query -W -f='${db:Status-Abbrev}' libapache2-mod-php8.1 2>/dev/null | grep -q '^ii'; then
  apache_conf='/etc/apache2/conf-available/php81-session-upload-progress-hardening.conf'
  if [[ ! -d /etc/apache2/conf-available ]]; then
    die 'mod_php8.1 is installed, but Apache conf-available is missing; cannot enforce the mitigation.'
  fi
  install_managed_ini "$apache_conf" <<EOF_APACHE
# $MARKER
<IfModule php_module>
    php_admin_value session.upload_progress.enabled 0
</IfModule>
EOF_APACHE
  command -v a2enconf >/dev/null || die 'a2enconf is unavailable; cannot enable the Apache mitigation.'
  a2enconf php81-session-upload-progress-hardening >/dev/null
  if command -v apache2ctl >/dev/null; then
    apache2ctl configtest
  else
    die 'Apache mod_php8.1 is installed, but apache2ctl is unavailable for config validation.'
  fi
fi
clear
log 'PHP2Shell package fixes are verified; session upload progress is administratively disabled for PHP 8.1.'
if command -v systemctl >/dev/null && [[ -d /run/systemd/system ]]; then
  restart_if_active() {
    local unit="$1"
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
      log "Restarting $unit."
      systemctl restart "$unit"
    fi
  }
  restart_if_active 'php8.1-fpm.service'
  restart_if_active 'apache2.service'
else
  log 'systemd is unavailable; restart PHP-FPM/Apache through the system init process.'
fi

if command -v php8.1 >/dev/null 2>&1; then
  log "CLI reports PHP $(php8.1 -r 'echo PHP_VERSION;')"
fi
log 'Restart custom PHP queue workers or long-running application services separately.'
log 'The CVE-2026-115560 mitigation disables upload-progress reporting; normal file uploads remain enabled.'
