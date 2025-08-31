#!/usr/bin/env bash

set -Eeuo pipefail

if [ -t 1 ]; then
  BOLD="$(printf '\033[1m')"
  DIM="$(printf '\033[2m')"
  RESET="$(printf '\033[0m')"
  RED="$(printf '\033[31m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  BLUE="$(printf '\033[34m')"
  CYAN="$(printf '\033[36m')"
else
  BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN="";
fi

print_header() {
  echo -e "${BLUE}============================================${RESET}"
  echo -e "${BLUE}    UFUKDEGEN TARAFINDAN HAZIRLANMIŞTIR    ${RESET}"
  echo -e "${BLUE}============================================${RESET}"
  echo ""
}

print_header

section() { echo -e "\n${BOLD}${BLUE}========== $* ==========${RESET}\n"; }
info()    { echo -e "${CYAN}[bilgi]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[uyarı]${RESET} $*"; }
ok()      { echo -e "${GREEN}[tamam]${RESET} $*"; }
err()     { echo -e "${RED}[hata]${RESET} $*"; }

abort() {
  err "$*"
  exit 1
}

confirm() {
  local prompt="${1:-Devam edilsin mi?}"
  local default="${2:-Y}"
  local reply
  if [[ "${NON_INTERACTIVE}" == "1" ]]; then
    [[ "${default}" =~ ^[Yy]$ ]] && return 0 || return 1
  fi
  read -rp "${prompt} [Y/n]: " reply || true
  if [[ -z "$reply" ]]; then reply="${default}"; fi
  [[ "$reply" =~ ^[Yy]$ ]]
}

##############################
# ARGÜMANLAR ve VARSAYILANLAR
##############################
NETWORK="mainnet"          # mainnet | sepolia
EXPOSE_RPC="no"            # yes | no
RPC_PORT="8545"
WS_PORT="8546"
ALLOWED_IP=""
NON_INTERACTIVE="0"
UNINSTALL_ONLY="0"
UPDATE_BESU=""
BESU_VERSION_DEFAULT="25.4.1"
BESU_VERSION="${BESU_VERSION_DEFAULT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --network) NETWORK="${2:-mainnet}"; shift 2;;
    --expose-rpc) EXPOSE_RPC="${2:-no}"; shift 2;;
    --rpc-port) RPC_PORT="${2:-8545}"; shift 2;;
    --ws-port) WS_PORT="${2:-8546}"; shift 2;;
    --allowed-ip) ALLOWED_IP="${2:-}"; shift 2;;
    --non-interactive) NON_INTERACTIVE="1"; shift;;
    --uninstall) UNINSTALL_ONLY="1"; shift;;
    --update-besu) UPDATE_BESU="${2:-}"; shift 2;;
    *) abort "Bilinmeyen argüman: $1";;
  esac
done

##############################
# KULLANICI/ORTAM BİLGİSİ
##############################
SUDO_USER_NAME="${SUDO_USER:-${USER}}"
RUN_USER="${SUDO_USER_NAME}"
HOME_DIR="$(eval echo "~${RUN_USER}")"

if [[ "$EUID" -ne 0 ]]; then
  abort "Lütfen scripti sudo ile çalıştırın: sudo bash $(basename "$0")"
fi

if ! id "$RUN_USER" &>/dev/null; then
  abort "Kullanıcı tespit edilemedi: ${RUN_USER}"
fi

# Dizinler
BASE_DIR="${HOME_DIR}/linea-node"
CONF_DIR="${BASE_DIR}/${NETWORK}"
DATA_DIR="${BASE_DIR}/data"

# URL'ler (gerekirse güncelleyebilirsiniz)
BESU_VERSION="${UPDATE_BESU:-${BESU_VERSION_DEFAULT}}"
BESU_TGZ="besu-${BESU_VERSION}.tar.gz"
BESU_URL="https://github.com/hyperledger/besu/releases/download/${BESU_VERSION}/${BESU_TGZ}"

LINEA_MAINNET_GENESIS_URL="https://docs.linea.build/files/besu/genesis-mainnet.json"
LINEA_MAINNET_CONFIG_URL="https://docs.linea.build/files/besu/config-mainnet.toml"
LINEA_MAINNET_ZIP_URL="https://docs.linea.build/files/besu/besu-mainnet.zip"

LINEA_SEPOLIA_GENESIS_URL="https://docs.linea.build/files/besu/genesis-sepolia.json"
LINEA_SEPOLIA_CONFIG_URL="https://docs.linea.build/files/besu/config-sepolia.toml"
LINEA_SEPOLIA_ZIP_URL="https://docs.linea.build/files/besu/besu-sepolia.zip"

# Nginx ayarları
NGINX_SITE="/etc/nginx/sites-available/besu-rpc"
NGINX_SITE_LINK="/etc/nginx/sites-enabled/besu-rpc"
NGINX_LIMIT_CONF="/etc/nginx/conf.d/limit_req_besu.conf"

##############################
# İNTERNET/PUBLIC IP TESPİTİ
##############################
detect_public_ip() {
  local ip=""
  ip="$(curl -4 -s --max-time 5 https://api.ipify.org || true)"
  if [[ -z "$ip" ]]; then
    ip="$(curl -4 -s --max-time 5 https://ipv4.icanhazip.com || true)"
  fi
  if [[ -z "$ip" ]]; then
    ip="$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"
  fi
  echo "${ip}"
}

PUBLIC_IP="$(detect_public_ip || true)"
if [[ -z "${PUBLIC_IP}" ]]; then
  warn "Genel IP tespit edilemedi. P2P host boş bırakılacak."
fi

##############################
# KALDIRMA (UNINSTALL)
##############################
uninstall_all() {
  section "KALDIRMA BAŞLIYOR"
  systemctl stop besu 2>/dev/null || true
  systemctl disable besu 2>/dev/null || true
  rm -f /etc/systemd/system/besu.service
  systemctl daemon-reload || true

  rm -f "${NGINX_SITE}" "${NGINX_SITE_LINK}" "${NGINX_LIMIT_CONF}"
  systemctl restart nginx 2>/dev/null || true

  rm -f /usr/local/bin/besu
  rm -rf /opt/besu

  rm -rf "${BASE_DIR}"

  ok "Kaldırma işlemi tamamlandı."
}
if [[ "${UNINSTALL_ONLY}" == "1" ]]; then
  uninstall_all
  exit 0
fi

##############################
# GEREKSİNİM KONTROLLERİ
##############################
section "GÜNCELLEME VE KURULUM BAŞLIYOR"
info "Kullanıcı: ${RUN_USER} | Ev dizini: ${HOME_DIR} | Ağ: ${NETWORK}"
sleep 0.5

section "SİSTEM GÜNCELLEME"
apt-get update -y
apt-get upgrade -y

##############################
# JAVA 21 KURULUMU VE YAPILANDIRMASI
##############################
section "JAVA 21 KURULUMU"

# Eski Java sürümlerini kaldır
info "Eski Java sürümleri kaldırılıyor..."
apt-get remove --purge -y openjdk-8-jdk openjdk-11-jdk openjdk-17-jdk 2>/dev/null || true
apt-get autoremove -y

# Java 21 kur
info "Java 21 kuruluyor..."
apt-get install -y openjdk-21-jdk

# Varsayılan Java'yı 21 yap
info "Java 21 varsayılan olarak ayarlanıyor..."
if [[ -f /usr/lib/jvm/java-21-openjdk-amd64/bin/java ]]; then
  update-alternatives --install /usr/bin/java java /usr/lib/jvm/java-21-openjdk-amd64/bin/java 1
  update-alternatives --set java /usr/lib/jvm/java-21-openjdk-amd64/bin/java
  
  # JAVA_HOME ayarla
  export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
  echo "export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64" >> /etc/environment
  
  ok "Java 21 kuruldu ve varsayılan olarak ayarlandı"
  info "Java sürümü: $(java -version 2>&1 | head -n1)"
else
  abort "Java 21 kurulumu başarısız oldu"
fi

section "GEREKLİ PAKETLER"
apt-get install -y wget curl unzip ufw

##############################
# BESU KURULUMU
##############################
section "BESU KURULUMU"
if [[ ! -x /usr/local/bin/besu ]]; then
  info "Besu indiriliyor: ${BESU_URL}"
  cd /tmp
  rm -f "${BESU_TGZ}" || true
  wget -q --show-progress "${BESU_URL}" || abort "Besu indirme başarısız: ${BESU_URL}"
  tar -xzf "${BESU_TGZ}"
  BESU_DIR="/opt/besu"
  rm -rf "${BESU_DIR}"
  mv "besu-${BESU_VERSION}" "${BESU_DIR}"
  ln -sf "${BESU_DIR}/bin/besu" /usr/local/bin/besu
  ok "Besu kuruldu: $(besu --version)"
else
  ok "Besu zaten kurulu: $(besu --version)"
fi

##############################
# LİNEA DOSYALARI
##############################
section "LINEA YAPILANDIRMA DOSYALARI"
mkdir -p "${CONF_DIR}" "${DATA_DIR}"
chown -R "${RUN_USER}:${RUN_USER}" "${BASE_DIR}"

cd "${CONF_DIR}"

# Doğrudan (resmi) genesis ve config indirme + ZIP'e geri düşme mekanizması
if [[ "${NETWORK}" == "sepolia" ]]; then
  GENESIS_URL="${LINEA_SEPOLIA_GENESIS_URL}"
  CONF_URL="${LINEA_SEPOLIA_CONFIG_URL}"
  ZIP_URL="${LINEA_SEPOLIA_ZIP_URL}"
else
  GENESIS_URL="${LINEA_MAINNET_GENESIS_URL}"
  CONF_URL="${LINEA_MAINNET_CONFIG_URL}"
  ZIP_URL="${LINEA_MAINNET_ZIP_URL}"
fi

FINAL_GENESIS="${CONF_DIR}/genesis-${NETWORK}.json"
UPSTREAM_CONFIG="${CONF_DIR}/upstream-config-${NETWORK}.toml"
CONFIG_FILE="${CONF_DIR}/config-${NETWORK}.toml"

download_ok=0
info "Genesis indiriliyor: ${GENESIS_URL}"
if curl -fsSL "${GENESIS_URL}" -o "${FINAL_GENESIS}"; then
  download_ok=1
  ok "Genesis indirildi: ${FINAL_GENESIS}"
else
  warn "Genesis indirme başarısız. ZIP'e geri düşülecek."
fi

conf_ok=0
info "Config indiriliyor: ${CONF_URL}"
if curl -fsSL "${CONF_URL}" -o "${UPSTREAM_CONFIG}"; then
  conf_ok=1
  ok "Upstream config indirildi: ${UPSTREAM_CONFIG}"
else
  warn "Config indirme başarısız. ZIP'e geri düşülecek."
fi

if [[ "${download_ok}" -ne 1 || "${conf_ok}" -ne 1 ]]; then
  info "ZIP paketi indiriliyor (geri düşme): ${ZIP_URL}"
  ZIP_NAME="besu-${NETWORK}.zip"
  rm -f "${ZIP_NAME}" || true
  if wget -q --show-progress -O "${ZIP_NAME}" "${ZIP_URL}"; then
    rm -rf "${CONF_DIR}/extracted" || true
    mkdir -p "${CONF_DIR}/extracted"
    if unzip -o "${ZIP_NAME}" -d "${CONF_DIR}/extracted" >/dev/null 2>&1; then
      # Olası dosya isim varyasyonlarını ara
      FOUND_GENESIS="$(find "${CONF_DIR}/extracted" -maxdepth 3 -type f -name 'genesis*json' | head -n1 || true)"
      FOUND_CONF="$(find "${CONF_DIR}/extracted" -maxdepth 3 -type f -name 'config*mainnet*.toml' -o -name 'config*sepolia*.toml' | head -n1 || true)"
      if [[ -n "${FOUND_GENESIS}" ]]; then
        cp -f "${FOUND_GENESIS}" "${FINAL_GENESIS}"
        download_ok=1
      fi
      if [[ -n "${FOUND_CONF}" ]]; then
        cp -f "${FOUND_CONF}" "${UPSTREAM_CONFIG}"
        conf_ok=1
      fi
    else
      warn "ZIP çıkarılamadı."
    fi
  else
    warn "ZIP indirilemedi."
  fi
fi

[[ "${download_ok}" -eq 1 ]] || abort "Genesis dosyası bulunamadı. Resmi bağlantılar/ZIP erişilebilir değil."
[[ "${conf_ok}" -eq 1 ]] || warn "Upstream config bulunamadı. Bootnodes olmadan devam edilecek."

##############################
# RPC ve GÜVENLİK SEÇENEKLERİ
##############################
if [[ "${NON_INTERACTIVE}" != "1" ]]; then
  info "RPC varsayılanı: yalnızca localhost (127.0.0.1)"
  if confirm "RPC'yi internete açmak ister misiniz? (Nginx önerilir)"; then
    EXPOSE_RPC="yes"
  fi
fi

# Nginx kullanımı önerilir: 127.0.0.1'e bağla ve reverse proxy ile yayınla
RPC_HOST="127.0.0.1"
WS_HOST="127.0.0.1"
if [[ "${EXPOSE_RPC}" == "yes" ]]; then
  RPC_HOST="0.0.0.0"
  WS_HOST="0.0.0.0"
fi

##############################
# CONFIG TOML OLUŞTURMA
##############################
section "CONFIG DOSYASI OLUŞTURMA"
# Varsayılan RPC bağlama (reverse proxy önerilir)
RPC_HOST="127.0.0.1"
WS_HOST="127.0.0.1"
if [[ "${EXPOSE_RPC}" == "yes" ]]; then
  RPC_HOST="0.0.0.0"
  WS_HOST="0.0.0.0"
fi

# Önce upstream config'i (bootnodes dahil) baz al, ardından bizim seçeneklerle override et
: > "${CONFIG_FILE}"
if [[ -f "${UPSTREAM_CONFIG}" ]]; then
  cat "${UPSTREAM_CONFIG}" > "${CONFIG_FILE}"
  echo "" >> "${CONFIG_FILE}"
else
  warn "Upstream config yok; sıfırdan oluşturulacak."
fi


# Upstream config içinde aşağıdaki anahtarlar varsa temizle (TOML duplicate key hatasını önlemek için)
PURGE_KEYS=(
  "data-path"
  "genesis-file"
  "sync-mode"
  "data-storage-format"
  "max-peers"
  "rpc-http-enabled"
  "rpc-http-host"
  "rpc-http-port"
  "rpc-http-cors-origins"
  "rpc-http-api"
  "rpc-ws-enabled"
  "rpc-ws-host"
  "rpc-ws-port"
  "p2p-port"
  "p2p-host"
)

if [[ -f "${CONFIG_FILE}" ]]; then
  for K in "${PURGE_KEYS[@]}"; do
    sed -i -E "/^[[:space:]]*${K}[[:space:]]*=.*/d" "${CONFIG_FILE}"
  done
  # Fazla boş satırları sadeleştir
  awk 'BEGIN{blank=0} { if (NF==0) { if(blank==0){print; blank=1} } else {print; blank=0} }' "${CONFIG_FILE}" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "${CONFIG_FILE}"
fi

cat >> "${CONFIG_FILE}" <<EOF
# --- Aşağıdaki blok otomatik eklendi: $(date -Iseconds) ---
data-path="${DATA_DIR}"
genesis-file="${FINAL_GENESIS}"

# Performans ve disk
sync-mode="SNAP"
data-storage-format="BONSAI"
max-peers=50

# RPC (MetaMask)
rpc-http-enabled=true
rpc-http-host="${RPC_HOST}"
rpc-http-port=${RPC_PORT}
rpc-http-cors-origins=["*"]
rpc-http-api=["ETH","NET","WEB3"]

# WebSocket
rpc-ws-enabled=true
rpc-ws-host="${WS_HOST}"
rpc-ws-port=${WS_PORT}

# P2P
p2p-port=30303
EOF

# Public IP biliniyorsa p2p-host ekle
if [[ -n "${PUBLIC_IP}" ]]; then
  echo "p2p-host=\"${PUBLIC_IP}\"" >> "${CONFIG_FILE}"
fi

chown "${RUN_USER}:${RUN_USER}" "${CONFIG_FILE}" "${FINAL_GENESIS}"
ok "Config yazıldı: ${CONFIG_FILE}"
##############################
# UFW AYARLARI
##############################
section "UFW GÜVENLİK DUVARI AYARLARI"
if ! ufw status | grep -q "Status: active"; then
  warn "UFW etkin değil, etkinleştirilecektir."
  ufw allow 22/tcp || true
  ufw --force enable
fi
# P2P
ufw allow 30303/tcp || true
ufw allow 30303/udp || true

# RPC: varsayılan olarak 8545'i dışa açmıyoruz
if [[ "${EXPOSE_RPC}" == "yes" ]]; then
  if [[ -n "${ALLOWED_IP}" ]]; then
    ufw allow from "${ALLOWED_IP}" to any port "${RPC_PORT}" proto tcp || true
    info "RPC için izinli IP: ${ALLOWED_IP}"
  else
    warn "RPC genel erişime açık olacaktır: port ${RPC_PORT} (dikkatli kullanın)"
    ufw allow "${RPC_PORT}"/tcp || true
  fi
fi

ok "UFW ayarları uygulandı."
ufw status || true

##############################
# SYSTEMD SERVİS
##############################
section "SYSTEMD SERVİS OLUŞTURMA"
SERVICE_FILE="/etc/systemd/system/besu.service"
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Besu Ethereum Client (Linea ${NETWORK})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_USER}
Restart=on-failure
RestartSec=5
LimitNOFILE=200000
Environment=JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ExecStart=/usr/local/bin/besu --config-file=${CONFIG_FILE}
WorkingDirectory=${CONF_DIR}
StandardOutput=journal
StandardError=journal
SyslogIdentifier=besu

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now besu

sleep 2
systemctl --no-pager --full status besu || true

##############################
# NGINX REVERSE PROXY (OPSİYONEL)
##############################
if [[ "${EXPOSE_RPC}" == "yes" ]]; then
  section "NGINX REVERSE PROXY (OPSİYONEL)"
  apt-get install -y nginx
  # Limit conf (global http context)
  cat > "${NGINX_LIMIT_CONF}" <<'NGX'
# Basit rate limiting
limit_req_zone $binary_remote_addr zone=api:10m rate=5r/s;
NGX

  # Basit site
  SERVER_NAME="${PUBLIC_IP:-_}"
  if [[ "${NON_INTERACTIVE}" != "1" ]]; then
    read -rp "Nginx server_name (domain veya IP) [${SERVER_NAME}]: " input || true
    if [[ -n "${input}" ]]; then SERVER_NAME="${input}"; fi
  fi

  cat > "${NGINX_SITE}" <<EOF
server {
    listen 80;
    server_name ${SERVER_NAME};

    location / {
        proxy_pass http://127.0.0.1:${RPC_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Connection "";
        limit_req zone=api burst=10 nodelay;
    }
}
EOF
  ln -sf "${NGINX_SITE}" "${NGINX_SITE_LINK}"
  nginx -t
  systemctl restart nginx
  ok "Nginx reverse proxy hazır. Gerekirse certbot ile TLS ekleyin."
fi

##############################
# SON KONTROLLER ve BİLGİ
##############################
section "SENKRONİZASYON KONTROLLERİ"
sleep 1
set +e
SYNC_OUT="$(curl -s -X POST -H "Content-Type: application/json" \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_syncing\",\"params\":[],\"id\":1}" \
  http://127.0.0.1:${RPC_PORT} || true)"
echo "${SYNC_OUT}"

BLOCK_OUT="$(curl -s -X POST -H "Content-Type: application/json" \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}" \
  http://127.0.0.1:${RPC_PORT} || true)"
echo "${BLOCK_OUT}"
set -e

CHAIN_ID="59144"
EXPLORER_URL="https://lineascan.build"
if [[ "${NETWORK}" == "sepolia" ]]; then
  CHAIN_ID="59141"
  EXPLORER_URL="https://sepolia.lineascan.build"
fi

section "METAMASK AĞ BİLGİLERİ"
cat <<MM
Network Name : Linea ${NETWORK^} (Local Node)
New RPC URL  : $( [[ "${EXPOSE_RPC}" == "yes" ]] && echo "http://${PUBLIC_IP}:${RPC_PORT}" || echo "http://127.0.0.1:${RPC_PORT}" )
Chain ID     : ${CHAIN_ID}
Currency     : ETH
Explorer     : ${EXPLORER_URL}
MM

ok "Kurulum tamamlandı. Logları izlemek için: sudo journalctl -f -u besu"
ok "Servis durumunu görmek için: sudo systemctl status besu"

exit 0
