#!/usr/bin/env bash
# ==============================================================================
# DigiQ Production Serve Script (Linux / WSL / Ubuntu / macOS)
# ==============================================================================
# Script otomasi build release Flutter Web & penyajian via scripts/spa_server.py
# pada port 9000 untuk diintegrasikan dengan Cloudflare Zero Trust Tunnel.
# ==============================================================================

set -euo pipefail

# Pindah ke direktori root proyek
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

# Nilai default
PORT="${PORT:-9000}"
HOST="${HOST:-0.0.0.0}"
SKIP_BUILD=false

# Fungsi bantuan
show_help() {
  cat << EOF
Penggunaan: $(basename "$0") [OPTIONS]

Opsi:
  --skip-build      Lewati langkah 'flutter build web' dan langsung jalankan server
  --port <PORT>     Ganti port listen server (default: 9000)
  --host <HOST>     Ganti host bind server (default: 0.0.0.0, gunakan 127.0.0.1 bila perlu)
  -h, --help        Tampilkan pesan bantuan ini

Contoh:
  ./scripts/serve_prod_9000.sh
  ./scripts/serve_prod_9000.sh --skip-build
  ./scripts/serve_prod_9000.sh --port 9000 --host 127.0.0.1
EOF
  exit 0
}

# Parsing Argumen CLI
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --host)
      HOST="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      ;;
    *)
      echo "[ERROR] Opsi tidak dikenal: $1" >&2
      show_help
      ;;
  esac
done

# ── Parser .env Aman (Tanpa eval/source) ───────────────────────────────────────
# Membaca .env lalu .env.local; env var sistem yang sudah ada memiliki prioritas lebih tinggi.
parse_env_file() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
      # Hapus karakter carriage return (CRLF support)
      line="${line//$'\r'/}"
      # Abaikan baris kosong dan komentar (#)
      [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
      # Tangani spasi di awal
      line="$(echo "${line}" | sed -e 's/^[[:space:]]*//')"
      if [[ "${line}" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)=(.*)$ ]]; then
        local key="${BASH_REMATCH[1]}"
        local val="${BASH_REMATCH[2]}"
        # Bersihkan trailing whitespace
        val="$(echo "${val}" | sed -e 's/[[:space:]]*$//')"
        # Hapus tanda kutip tunggal atau ganda pembungkus jika ada
        if [[ "${val}" =~ ^\"(.*)\"$ ]]; then
          val="${BASH_REMATCH[1]}"
        elif [[ "${val}" =~ ^\'(.*)\'$ ]]; then
          val="${BASH_REMATCH[1]}"
        fi
        # Set hanya jika belum ada di environment sistem
        if [[ -z "${!key:-}" ]]; then
          export "${key}=${val}"
        fi
      fi
    done < "${file}"
  fi
}

parse_env_file "${PROJECT_ROOT}/.env"
parse_env_file "${PROJECT_ROOT}/.env.local"

# Helper untuk menyamarkan (mask) secret string
mask_secret() {
  local str="${1:-}"
  if [[ ${#str} -gt 8 ]]; then
    echo "${str:0:6}****${str: -4}"
  elif [[ -n "${str}" ]]; then
    echo "****"
  else
    echo "(kosong)"
  fi
}

# ── Langkah 1: Build Release Flutter Web (Jika tidak dilewati) ────────────────
if [[ "${SKIP_BUILD}" == false ]]; then
  echo "================================================================="
  echo "         [1/3] Menyiapkan Build Release Flutter Web              "
  echo "================================================================="

  # Validasi ketersediaan binary flutter
  if ! command -v flutter >/dev/null 2>&1; then
    echo "[FATAL] Perintah 'flutter' tidak ditemukan di PATH sistem!" >&2
    exit 1
  fi

  # Validasi variabel wajib Supabase
  if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
    echo "[FATAL] SUPABASE_URL atau SUPABASE_ANON_KEY belum dikonfigurasi!" >&2
    echo "Harap buat file .env atau ekspor environment variable sebelum build." >&2
    exit 1
  fi

  echo "SUPABASE_URL     : ${SUPABASE_URL}"
  echo "SUPABASE_ANON_KEY: $(mask_secret "${SUPABASE_ANON_KEY}")"
  echo "PUBLIC_SITE_URL  : ${PUBLIC_SITE_URL:-https://enikzrad.web.id}"
  echo ""

  echo "Menjalankan flutter pub get..."
  flutter pub get

  echo "Mengompilasi Flutter Web (Release Mode)..."
  # Menggunakan array bash untuk keamanan argumen & --no-web-resources-cdn untuk self-hosted CanvasKit
  BUILD_ARGS=(
    build web
    --release
    --no-web-resources-cdn
    --dart-define="SUPABASE_URL=${SUPABASE_URL}"
    --dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
  )

  if [[ -n "${PUBLIC_SITE_URL:-}" ]]; then
    BUILD_ARGS+=(--dart-define="PUBLIC_SITE_URL=${PUBLIC_SITE_URL}")
  fi

  flutter "${BUILD_ARGS[@]}"

  # Verifikasi hasil build
  if [[ ! -f "${PROJECT_ROOT}/build/web/index.html" ]]; then
    echo "[FATAL] Kompilasi selesai namun 'build/web/index.html' tidak ditemukan!" >&2
    exit 1
  fi

  # Verifikasi keamanan: pastikan tidak ada file .env yang masuk ke folder build
  if compgen -G "${PROJECT_ROOT}/build/web/.env*" >/dev/null; then
    echo "[FATAL] File rahasia .env terdeteksi di build/web/! Menghapus demi keamanan..." >&2
    rm -f "${PROJECT_ROOT}/build/web/.env*"
    exit 1
  fi
  echo "Build Release Flutter Web BERHASIL."
  echo ""
else
  echo "================================================================="
  echo "    [1/3] Melewati Build (--skip-build aktif)                    "
  echo "================================================================="
  if [[ ! -f "${PROJECT_ROOT}/build/web/index.html" ]]; then
    echo "[FATAL] Flag --skip-build diberikan tetapi 'build/web/index.html' belum ada!" >&2
    echo "Jalankan build terlebih dahulu tanpa flag --skip-build." >&2
    exit 1
  fi
  echo "Ditemukan file build valid di: ${PROJECT_ROOT}/build/web/index.html"
  echo ""
fi

# ── Langkah 2: Matikan Proses Lama pada Port 9000 (Secara Aman) ───────────────
echo "================================================================="
echo "         [2/3] Memeriksa Ketersediaan Port ${PORT}               "
echo "================================================================="

TARGET_PID=""
if command -v lsof >/dev/null 2>&1; then
  TARGET_PID="$(lsof -ti tcp:"${PORT}" -sTCP:LISTEN || true)"
elif command -v fuser >/dev/null 2>&1; then
  TARGET_PID="$(fuser "${PORT}/tcp" 2>/dev/null || true)"
elif command -v ss >/dev/null 2>&1; then
  TARGET_PID="$(ss -lptn "sport = :${PORT}" | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u || true)"
fi

if [[ -n "${TARGET_PID}" ]]; then
  for pid in ${TARGET_PID}; do
    if ps -p "${pid}" >/dev/null 2>&1; then
      PROC_NAME="$(ps -p "${pid}" -o comm= 2>/dev/null || echo "Unknown")"
      echo "[PERINGATAN] Port ${PORT} sedang digunakan oleh proses PID ${pid} (${PROC_NAME})."
      echo "Mengirim sinyal SIGTERM ke PID ${pid}..."
      kill -15 "${pid}" 2>/dev/null || true
      sleep 2
      if ps -p "${pid}" >/dev/null 2>&1; then
        echo "Proses masih berjalan, mengirim SIGKILL ke PID ${pid}..."
        kill -9 "${pid}" 2>/dev/null || true
      fi
    fi
  done
  echo "Port ${PORT} telah dibersihkan."
else
  echo "Port ${PORT} bersih (tidak ada proses aktif)."
fi
echo ""

# ── Langkah 3: Menjalankan Server SPA Production ──────────────────────────────
echo "================================================================="
echo "         [3/3] Menjalankan DigiQ SPA Server                      "
echo "================================================================="
echo "Host Binding  : ${HOST}:${PORT}"
echo "Domain Publik : https://enikzrad.web.id"
echo ""
echo "[INFO PENTING CLOUDFLARE]"
echo "  1. Pastikan Cloudflare Tunnel aktif meneruskan ke: http://127.0.0.1:${PORT}"
echo "  2. Jika baru saja deploy update UI, lakukan PURGE CACHE di Cloudflare Dashboard"
echo "     agar browser customer mendapatkan bundle terbaru."
echo "================================================================="
echo ""

export HOST="${HOST}"
export PORT="${PORT}"

# Eksekusi python server dengan exec agar sinyal Unix diteruskan
if command -v python3 >/dev/null 2>&1; then
  exec python3 "${SCRIPT_DIR}/spa_server.py"
elif command -v python >/dev/null 2>&1; then
  exec python "${SCRIPT_DIR}/spa_server.py"
else
  echo "[FATAL] Python 3 tidak ditemukan di sistem! Install python3 terlebih dahulu." >&2
  exit 1
fi
