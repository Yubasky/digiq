#!/usr/bin/env bash
# ==============================================================================
# DigiQ Development Web Server (Port 9000)
# ==============================================================================
# PERINGATAN PENTING ARSITEKTUR:
# Mode development (dev_9000) ini HANYA untuk pengujian lokal / LAN internal.
# Hot reload dan WebSocket devtools LEWAT DOMAIN PUBLIK CLOUDFLARE
# (https://enikzrad.web.id) TIDAK didukung secara praktis karena restriksi
# Host Header validation dan WebSockets handshake.
#
# Untuk akses publik melalui Cloudflare Zero Trust Tunnel, WAJIB gunakan:
#   ./scripts/serve_prod_9000.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

# Parser .env Aman
parse_env_file() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
      line="${line//$'\r'/}"
      [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
      line="$(echo "${line}" | sed -e 's/^[[:space:]]*//')"
      if [[ "${line}" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)=(.*)$ ]]; then
        local key="${BASH_REMATCH[1]}"
        local val="${BASH_REMATCH[2]}"
        val="$(echo "${val}" | sed -e 's/[[:space:]]*$//')"
        if [[ "${val}" =~ ^\"(.*)\"$ ]]; then
          val="${BASH_REMATCH[1]}"
        elif [[ "${val}" =~ ^\'(.*)\'$ ]]; then
          val="${BASH_REMATCH[1]}"
        fi
        if [[ -z "${!key:-}" ]]; then
          export "${key}=${val}"
        fi
      fi
    done < "${file}"
  fi
}

parse_env_file "${PROJECT_ROOT}/.env"
parse_env_file "${PROJECT_ROOT}/.env.local"

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "[FATAL] SUPABASE_URL atau SUPABASE_ANON_KEY belum dikonfigurasi di .env!" >&2
  exit 1
fi

echo "================================================================="
echo "       Memulai Flutter Dev Server di http://0.0.0.0:9000         "
echo "================================================================="
echo "Akses Lokal: http://localhost:9000 atau http://127.0.0.1:9000"
echo "Catatan    : Hot reload aktif untuk browser lokal."
echo "================================================================="

RUN_ARGS=(
  run
  -d web-server
  --web-port=9000
  --web-hostname=0.0.0.0
  --web-allow-expose-url
  --dart-define="SUPABASE_URL=${SUPABASE_URL}"
  --dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
)

if [[ -n "${PUBLIC_SITE_URL:-}" ]]; then
  RUN_ARGS+=(--dart-define="PUBLIC_SITE_URL=${PUBLIC_SITE_URL}")
fi

exec flutter "${RUN_ARGS[@]}"
