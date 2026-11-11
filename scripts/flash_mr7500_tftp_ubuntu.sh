#!/usr/bin/env bash
# ==============================================================================
# Linksys MR7500 (Hydra Pro 6E) — User-Friendly Ubuntu 24.04 / 26.04 TFTP Flasher
# Supports both:
#   - router     : Default Router Mode (10.143.1.1/24, WAN DHCP, LAN DHCP/NAT)
#   - switch-ap  : Current Switch + AP Mode (192.168.1.91/24, all 5 ports bridged)
#
# Uses a self-contained RFC 1350 + RFC 2347 (blksize/tsize) Python 3 TFTP server
# plus HTTP sysupgrade server — works out of the box on Ubuntu 26.04 LTS without
# clobbering system /etc/default/tftpd-hpa or requiring extra packages.
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VARIANT=""
MODE=""
IFACE=""
SERVER_IP=""
ROUTER_IP=""
HTTP_PORT="18980"
TFTP_PORT="69"
BIN_DIR=""
SERIAL_DEV=""
KEEP_SETTINGS="0"
ADDED_ALIAS=""
HTTP_PID=""
TFTP_PID=""
WORK_TMP=""

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

cleanup() {
    [ -n "$TFTP_PID" ] && { kill "$TFTP_PID" 2>/dev/null || true; wait "$TFTP_PID" 2>/dev/null || true; }
    [ -n "$HTTP_PID" ] && { kill "$HTTP_PID" 2>/dev/null || true; wait "$HTTP_PID" 2>/dev/null || true; }
    if [ -n "$ADDED_ALIAS" ] && [ -n "$IFACE" ]; then
        sudo ip addr del "$ADDED_ALIAS" dev "$IFACE" 2>/dev/null || true
    fi
    [ -n "$WORK_TMP" ] && rm -rf "$WORK_TMP" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

usage() {
    cat << 'EOF'
Linksys MR7500 Ubuntu 26.04 TFTP Flash & RAM-Boot Utility

Usage:
  sudo ./flash_mr7500_tftp_ubuntu.sh [options]

Options:
  -v, --variant <router|switch-ap>  Firmware configuration profile to flash
  -m, --mode <flash|ramboot|uboot-factory>
                                    flash:         TFTP boot initramfs -> sysupgrade NAND (Recommended)
                                    ramboot:       TFTP boot initramfs in RAM only (zero flash writes)
                                    uboot-factory: Print U-Boot commands to flash factory.bin directly
  -i, --iface <ifname>              Wired Ethernet interface connected to MR7500
  -s, --server-ip <ip>              Local Ubuntu TFTP/HTTP IP (default: auto-detect or 192.168.1.10 / 10.143.1.10)
  -r, --router-ip <ip>              Temporary U-Boot IP for MR7500 (default: 192.168.1.91 / 10.143.1.1)
  -p, --http-port <port>            HTTP port for sysupgrade.bin transfer (default: 18980)
      --tftp-port <port>            UDP TFTP port (default: 69)
      --bin-dir <path>              Explicit folder containing MR7500 firmware images
      --serial <tty>                Optional USB-UART device (e.g. /dev/ttyUSB0) for hands-free automation
      --keep-settings               Omit '-n' during sysupgrade (preserves existing overlay)
      --self-test                   Run offline TFTP RFC 1350/2347 loopback verification and exit
  -h, --help                        Show this help message
EOF
}

run_embedded_tftp_server() {
    local serve_dir="$1"
    local port="$2"
    local bind_ip="${3:-0.0.0.0}"
    local log_file="$4"
    exec python3 - "$serve_dir" "$port" "$bind_ip" "$log_file" << 'PY_TFTP'
import os, socket, struct, sys, threading

ROOT = os.path.abspath(sys.argv[1])
PORT = int(sys.argv[2])
BIND = sys.argv[3]
LOG = sys.argv[4]

def log(msg):
    line = f"[TFTP] {msg}\n"
    sys.stdout.write(line)
    sys.stdout.flush()
    if LOG:
        with open(LOG, "a", encoding="utf-8") as lf:
            lf.write(line)

def send_error(sock, addr, code, msg):
    pkt = struct.pack("!HH", 5, code) + msg.encode("ascii", "replace") + b"\x00"
    sock.sendto(pkt, addr)

def handle_rrq(initial_data, client_addr):
    parts = initial_data[2:].split(b"\x00")
    if len(parts) < 2:
        return
    fname = os.path.basename(parts[0].decode("ascii", "replace").lstrip("/"))
    mode = parts[1].decode("ascii", "replace").lower()
    if mode != "octet":
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        send_error(s, client_addr, 0, "Only octet mode supported")
        s.close()
        return

    fpath = os.path.join(ROOT, fname)
    if not os.path.isfile(fpath):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        log(f"404 Not Found requested by {client_addr[0]}:{client_addr[1]} -> {fname}")
        send_error(s, client_addr, 1, "File not found")
        s.close()
        return

    opts = {}
    raw_opts = parts[2:]
    for i in range(0, len(raw_opts) - 1, 2):
        k = raw_opts[i].decode("ascii", "replace").lower()
        v = raw_opts[i + 1].decode("ascii", "replace")
        if k:
            opts[k] = v

    fsize = os.path.getsize(fpath)
    blksize = 512
    oack_opts = []
    if "blksize" in opts:
        try:
            req_blk = int(opts["blksize"])
            if 8 <= req_blk <= 65464:
                blksize = req_blk
                oack_opts.append(("blksize", str(blksize)))
        except ValueError:
            pass
    if "tsize" in opts:
        oack_opts.append(("tsize", str(fsize)))
    timeout_sec = 5
    if "timeout" in opts:
        try:
            t = int(opts["timeout"])
            if 1 <= t <= 60:
                timeout_sec = t
                oack_opts.append(("timeout", str(timeout_sec)))
        except ValueError:
            pass

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind((BIND, 0))
    s.settimeout(float(timeout_sec))

    total_blocks = (fsize // blksize) + 1
    log(f"Serving '{fname}' ({fsize} bytes, blksize={blksize}) to {client_addr[0]}:{client_addr[1]}")

    try:
        # RFC 2347 option negotiation requires OACK -> wait for ACK(0)
        if oack_opts:
            oack = struct.pack("!H", 6)
            for k, v in oack_opts:
                oack += k.encode() + b"\x00" + v.encode() + b"\x00"
            acked_zero = False
            for _retry in range(6):
                s.sendto(oack, client_addr)
                try:
                    resp, raddr = s.recvfrom(1024)
                    if raddr == client_addr and len(resp) >= 4:
                        op, blk = struct.unpack("!HH", resp[:4])
                        if op == 4 and blk == 0:
                            acked_zero = True
                            break
                        if op == 5:
                            log(f"Client sent ERROR during OACK: {resp[4:]}")
                            return
                except socket.timeout:
                    continue
            if not acked_zero:
                log("Timed out waiting for ACK(0) after OACK")
                return

        with open(fpath, "rb") as f:
            block_num = 1
            last_pct = -1
            while True:
                chunk = f.read(blksize)
                pkt = struct.pack("!HH", 3, block_num & 0xFFFF) + chunk
                acked = False
                for _retry in range(8):
                    s.sendto(pkt, client_addr)
                    try:
                        resp, raddr = s.recvfrom(1024)
                        if raddr == client_addr and len(resp) >= 4:
                            op, rblk = struct.unpack("!HH", resp[:4])
                            if op == 4 and rblk == (block_num & 0xFFFF):
                                acked = True
                                break
                            if op == 5:
                                log(f"Client sent ERROR at block {block_num}: {resp[4:]}")
                                return
                    except socket.timeout:
                        continue
                if not acked:
                    log(f"Transfer aborted: timeout at block {block_num}")
                    return

                pct = min(100, (block_num * 100) // max(1, total_blocks))
                if pct >= last_pct + 20 or len(chunk) < blksize:
                    log(f"Progress '{fname}': block {block_num}/{total_blocks} ({pct}%)")
                    last_pct = pct

                if len(chunk) < blksize:
                    log(f"Transfer COMPLETE: '{fname}' ({fsize} bytes)")
                    break
                block_num += 1
    finally:
        s.close()

srv = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind((BIND, PORT))
log(f"Listening on UDP {BIND}:{PORT} serving {ROOT}")
while True:
    data, addr = srv.recvfrom(2048)
    if len(data) >= 4 and struct.unpack("!H", data[:2])[0] == 1:
        threading.Thread(target=handle_rrq, args=(data, addr), daemon=True).start()
PY_TFTP
}

run_self_test() {
    WORK_TMP="$(mktemp -d /tmp/mr7500_tftp_test_XXXXXX)"
    local test_port=16969
    local payload="$WORK_TMP/test_payload.bin"
    dd if=/dev/urandom of="$payload" bs=1468 count=5 2>/dev/null
    dd if=/dev/urandom bs=100 count=1 >> "$payload" 2>/dev/null
    local expected_sha
    expected_sha="$(sha256sum "$payload" | awk '{print $1}')"

    run_embedded_tftp_server "$WORK_TMP" "$test_port" "127.0.0.1" "$WORK_TMP/tftp.log" >/dev/null 2>&1 &
    TFTP_PID=$!

    python3 - "$test_port" "$expected_sha" "$WORK_TMP/tftp.log" << 'PY_CLI'
import hashlib, os, socket, struct, sys, time

PORT = int(sys.argv[1])
EXP_SHA = sys.argv[2]
LOG = sys.argv[3]

for _ in range(30):
    if os.path.exists(LOG) and "Listening" in open(LOG).read():
        break
    time.sleep(0.1)

def fetch(with_opts):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(3.0)
    rrq = struct.pack("!H", 1) + b"test_payload.bin\x00octet\x00"
    blksize = 512
    if with_opts:
        rrq += b"blksize\x001468\x00tsize\x000\x00"
    s.sendto(rrq, ("127.0.0.1", PORT))

    buf = bytearray()
    while True:
        data, srv_addr = s.recvfrom(4096)
        op = struct.unpack("!H", data[:2])[0]
        if op == 6:  # OACK
            parts = data[2:].split(b"\x00")
            for i in range(0, len(parts) - 1, 2):
                if parts[i] == b"blksize":
                    blksize = int(parts[i + 1])
            s.sendto(struct.pack("!HH", 4, 0), srv_addr)
        elif op == 3:  # DATA
            blk = struct.unpack("!H", data[2:4])[0]
            payload = data[4:]
            buf.extend(payload)
            s.sendto(struct.pack("!HH", 4, blk), srv_addr)
            if len(payload) < blksize:
                break
        elif op == 5:
            raise RuntimeError(f"TFTP Error: {data[4:]}")
    s.close()
    got_sha = hashlib.sha256(bytes(buf)).hexdigest()
    assert got_sha == EXP_SHA, f"SHA mismatch: {got_sha} != {EXP_SHA}"

fetch(False)
fetch(True)
print("[PASS] TFTP RFC 1350 + RFC 2347 (blksize=1468, tsize) loopback transfer verified!")
PY_CLI
    return 0
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -v|--variant) VARIANT="$2"; shift 2 ;;
        -m|--mode) MODE="$2"; shift 2 ;;
        -i|--iface) IFACE="$2"; shift 2 ;;
        -s|--server-ip) SERVER_IP="$2"; shift 2 ;;
        -r|--router-ip) ROUTER_IP="$2"; shift 2 ;;
        -p|--http-port) HTTP_PORT="$2"; shift 2 ;;
        --tftp-port) TFTP_PORT="$2"; shift 2 ;;
        --bin-dir) BIN_DIR="$2"; shift 2 ;;
        --serial) SERIAL_DEV="$2"; shift 2 ;;
        --keep-settings) KEEP_SETTINGS="1"; shift ;;
        --self-test) run_self_test; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

echo -e "${BOLD}${CYAN}================================================================================"
echo " Linksys MR7500 (Hydra Pro 6E) — Ubuntu 24.04 / 26.04 TFTP Flash Utility"
echo -e "================================================================================${NC}"

if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${RED}[-] python3 is required.${NC} Run: sudo apt-get update && sudo apt-get install -y python3"
    exit 1
fi

if [ "$TFTP_PORT" -lt 1024 ] && [ "$(id -u)" -ne 0 ]; then
    echo -e "${YELLOW}[!] Port $TFTP_PORT requires root privileges; re-run with sudo or pass --tftp-port 16969.${NC}"
    exec sudo -E bash "$0" \
        ${VARIANT:+--variant "$VARIANT"} \
        ${MODE:+--mode "$MODE"} \
        ${IFACE:+--iface "$IFACE"} \
        ${SERVER_IP:+--server-ip "$SERVER_IP"} \
        ${ROUTER_IP:+--router-ip "$ROUTER_IP"} \
        --http-port "$HTTP_PORT" \
        --tftp-port "$TFTP_PORT" \
        ${BIN_DIR:+--bin-dir "$BIN_DIR"} \
        ${SERIAL_DEV:+--serial "$SERIAL_DEV"} \
        $( [ "$KEEP_SETTINGS" = "1" ] && echo "--keep-settings" )
fi

# 1. Pick Firmware Variant
if [ -z "$VARIANT" ] && [ -z "$BIN_DIR" ]; then
    echo ""
    echo "Select firmware configuration variant to install:"
    echo "  1) Switch + AP Mode (IP: 192.168.1.91/24, all 5 ports bridged, DHCP disabled)"
    echo "  2) Router Mode      (IP: 10.143.1.1/24, NAT on 5GbE WAN, LAN DHCPv4 + SLAAC)"
    read -rp "Enter choice [1-2] (default 1): " vchoice
    case "${vchoice:-1}" in
        2) VARIANT="router" ;;
        *) VARIANT="switch-ap" ;;
    esac
fi

if [ -z "$BIN_DIR" ]; then
    if [ "$VARIANT" = "switch-ap" ]; then
        for cand in "$SCRIPT_DIR/switch-ap-mode" "$SCRIPT_DIR/../bin/switch-ap-mode" "$SCRIPT_DIR/../switch-ap-mode"; do
            [ -d "$cand" ] && BIN_DIR="$(cd "$cand" && pwd)" && break
        done
    else
        VARIANT="router"
        for cand in "$SCRIPT_DIR/router-mode" "$SCRIPT_DIR/../bin/router-mode" "$SCRIPT_DIR/../router-mode" "$SCRIPT_DIR/../bin" "$SCRIPT_DIR"; do
            if [ -f "$cand/openwrt-qualcommax-ipq60xx-linksys_mr7500-initramfs-uImage.itb" ]; then
                BIN_DIR="$(cd "$cand" && pwd)"
                break
            fi
        done
    fi
fi

if [ -z "$BIN_DIR" ] || [ ! -d "$BIN_DIR" ]; then
    echo -e "${RED}[-] Could not locate firmware directory for variant '${VARIANT}'. Pass --bin-dir <path>.${NC}"
    exit 1
fi

ITB_FILE="$BIN_DIR/openwrt-qualcommax-ipq60xx-linksys_mr7500-initramfs-uImage.itb"
SYS_FILE="$BIN_DIR/openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-sysupgrade.bin"
FAC_FILE="$BIN_DIR/openwrt-qualcommax-ipq60xx-linksys_mr7500-squashfs-factory.bin"

for req in "$ITB_FILE" "$SYS_FILE"; do
    if [ ! -f "$req" ]; then
        echo -e "${RED}[-] Missing required firmware file: $req${NC}"
        exit 1
    fi
done

# Verify SHA-256 checksums if sha256sums* present
if [ -f "$BIN_DIR/sha256sums.txt" ]; then
    echo "[*] Verifying firmware SHA-256 checksums in $BIN_DIR..."
    (cd "$BIN_DIR" && sha256sum -c sha256sums.txt --ignore-missing)
elif [ -f "$BIN_DIR/sha256sums" ]; then
    echo "[*] Verifying MR7500 firmware SHA-256 checksums in $BIN_DIR..."
    (cd "$BIN_DIR" && grep linksys_mr7500 sha256sums | sha256sum -c)
fi

SYS_SHA="$(sha256sum "$SYS_FILE" | awk '{print $1}')"

# 2. Pick Mode
if [ -z "$MODE" ]; then
    echo ""
    echo "Select deployment mode:"
    echo "  1) Safe RAM-boot -> Verify -> Flash to NAND via sysupgrade (Recommended)"
    echo "  2) Test in RAM Only (TFTP initramfs boot, zero flash writes)"
    echo "  3) Direct U-Boot NAND Factory Flash (Recovery when SSH/shell unavailable)"
    read -rp "Enter choice [1-3] (default 1): " mchoice
    case "${mchoice:-1}" in
        2) MODE="ramboot" ;;
        3) MODE="uboot-factory" ;;
        *) MODE="flash" ;;
    esac
fi

# 3. Network Interface & IP Selection
if [ -z "$IFACE" ]; then
    echo ""
    echo "[*] Available non-loopback network interfaces:"
    ip -o link show | awk -F': ' '$2 != "lo" {print "   - " $2 " (" $0 ")"}' | sed 's/state \([^ ]*\).*/[\1]/'
    DEFAULT_IFACE="$(ip -o link show up | awk -F': ' '$2 ~ /^(en|eth)/ {print $2; exit}')"
    read -rp "Ethernet interface wired to MR7500 [${DEFAULT_IFACE:-enp1s0}]: " iface_in
    IFACE="${iface_in:-${DEFAULT_IFACE:-enp1s0}}"
fi

CURRENT_IP="$(ip -4 -o addr show dev "$IFACE" | awk '{print $4}' | cut -d/ -f1 | head -n1)"
if [ -z "$SERVER_IP" ]; then
    if [ -n "$CURRENT_IP" ]; then
        SERVER_IP="$CURRENT_IP"
    elif [ "$VARIANT" = "switch-ap" ]; then
        SERVER_IP="192.168.1.10"
    else
        SERVER_IP="10.143.1.10"
    fi
fi

if [ -z "$ROUTER_IP" ]; then
    if [[ "$SERVER_IP" == 10.143.1.* ]]; then
        ROUTER_IP="10.143.1.1"
    else
        ROUTER_IP="192.168.1.91"
    fi
fi

if ! ip -4 addr show dev "$IFACE" | grep -q "inet ${SERVER_IP}/"; then
    echo "[*] Temporarily assigning ${SERVER_IP}/24 to ${IFACE} (will clean up on exit)..."
    ip addr add "${SERVER_IP}/24" dev "$IFACE"
    ip link set dev "$IFACE" up
    ADDED_ALIAS="${SERVER_IP}/24"
fi

# Check if port 69 is already bound (e.g. tftpd-hpa / dnsmasq)
if ss -uln 2>/dev/null | grep -qE "[:.]${TFTP_PORT}[[:space:]]"; then
    echo -e "${YELLOW}[!] UDP port ${TFTP_PORT} is already in use on this Ubuntu host:${NC}"
    ss -ulnp 2>/dev/null | grep -E "[:.]${TFTP_PORT}[[:space:]]" || true
    echo -e "${YELLOW}    Stop existing TFTP service (e.g. 'sudo systemctl stop tftpd-hpa') or pass --tftp-port.${NC}"
    exit 1
fi

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    echo -e "${YELLOW}[!] UFW firewall is active. Ensure U-Boot/router traffic is permitted:${NC}"
    echo "    sudo ufw allow in on $IFACE to any port $TFTP_PORT proto udp"
    [ "$MODE" = "flash" ] && echo "    sudo ufw allow in on $IFACE to any port $HTTP_PORT proto tcp"
fi

WORK_TMP="$(mktemp -d /tmp/mr7500_tftp_XXXXXX)"
ln -sf "$ITB_FILE" "$WORK_TMP/mr7500-initramfs.itb"
ln -sf "$SYS_FILE" "$WORK_TMP/sysupgrade.bin"
[ -f "$FAC_FILE" ] && ln -sf "$FAC_FILE" "$WORK_TMP/mr7500-factory.bin"
echo "$SYS_SHA  sysupgrade.bin" > "$WORK_TMP/sysupgrade.sha256"

# Start self-contained TFTP server + HTTP server
run_embedded_tftp_server "$WORK_TMP" "$TFTP_PORT" "$SERVER_IP" "$WORK_TMP/tftp.log" &
TFTP_PID=$!

if [ "$MODE" = "flash" ]; then
    python3 -m http.server "$HTTP_PORT" --bind "$SERVER_IP" --directory "$WORK_TMP" >/dev/null 2>&1 &
    HTTP_PID=$!
fi

sleep 0.5
echo ""
echo -e "${GREEN}[+] Ready on ${IFACE}: TFTP ${SERVER_IP}:${TFTP_PORT} (variant=${VARIANT:-custom}, mode=${MODE})${NC}"

if [ -n "$SERIAL_DEV" ]; then
    if [ ! -e "$SERIAL_DEV" ]; then
        echo -e "${RED}[-] Serial device not found: $SERIAL_DEV${NC}"
        exit 1
    fi
    echo -e "${CYAN}[*] Running automated U-Boot serial flow over $SERIAL_DEV...${NC}"
    python3 - "$SERIAL_DEV" "$MODE" "$SERVER_IP" "$ROUTER_IP" "$HTTP_PORT" "$SYS_SHA" "$KEEP_SETTINGS" << 'PY_SERIAL'
import os, sys, termios, time, tty

dev, mode, srv_ip, rtr_ip, http_port, sys_sha, keep_set = sys.argv[1:8]
fd = os.open(dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
attrs = termios.tcgetattr(fd)
attrs[0] = 0
attrs[1] = 0
attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
attrs[3] = 0
attrs[4] = attrs[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, attrs)

def read_all(wait=0.2):
    time.sleep(wait)
    out = bytearray()
    while True:
        try:
            d = os.read(fd, 4096)
            if not d:
                break
            out.extend(d)
        except BlockingIOError:
            break
    s = out.decode("utf-8", "replace")
    if s:
        sys.stdout.write(s)
        sys.stdout.flush()
    return s

def wait_for(patterns, timeout=60):
    buf = ""
    t0 = time.time()
    while time.time() - t0 < timeout:
        c = read_all(0.15)
        if c:
            buf += c
            for p in patterns:
                if p in buf:
                    return buf
    raise TimeoutError(f"Timed out waiting for {patterns}")

print("[*] Reboot/power-cycle MR7500 now (catching U-Boot autoboot on serial)...")
os.write(fd, b"\r")
buf = ""
t0 = time.time()
caught = False
while time.time() - t0 < 90:
    c = read_all(0.08)
    buf = (buf + c)[-600:]
    if any(k in buf for k in ("Hit any key", "autoboot", "CBT U-Boot")):
        os.write(fd, b" \r\n")
    if "IPQ6018#" in buf or "(IPQ6018) #" in buf:
        caught = True
        break
assert caught, "Failed to interrupt U-Boot"

for cmd in (
    f"setenv ipaddr {rtr_ip}",
    f"setenv serverip {srv_ip}",
    f"ping {srv_ip}",
):
    os.write(fd, (cmd + "\r\n").encode())
    wait_for(["IPQ6018#", "(IPQ6018) #"], timeout=15)

img_name = "mr7500-factory.bin" if mode == "uboot-factory" else "mr7500-initramfs.itb"
os.write(fd, f"tftp 0x44000000 {img_name}\r\n".encode())
res = wait_for(["IPQ6018#", "(IPQ6018) #"], timeout=60)
assert "Bytes transferred =" in res, "TFTP transfer failed!"

if mode == "uboot-factory":
    print("\n[+] Image loaded at 0x44000000! Flashing via U-Boot requires manual confirmation for NAND safety.")
    sys.exit(0)

os.write(fd, b"bootm 0x44000000\r\n")
wait_for(["init complete", "Please press Enter to activate this console"], timeout=140)
time.sleep(20)
os.write(fd, b"\r\n")
read_all(0.5)

if mode == "flash":
    flag = "" if keep_set == "1" else "-n "
    cmd = (
        f"wget -O /tmp/sysupgrade.bin http://{srv_ip}:{http_port}/sysupgrade.bin && "
        f"[ \"$(sha256sum /tmp/sysupgrade.bin | awk '{{print $1}}')\" = \"{sys_sha}\" ] && "
        f"sysupgrade {flag}-v /tmp/sysupgrade.bin\r\n"
    )
    os.write(fd, cmd.encode())
    wait_for(["Reboot", "Booting Linux on physical CPU"], timeout=180)
    print("\n[+] Sysupgrade flash complete and reboot started!")
os.close(fd)
PY_SERIAL
else
    echo ""
    echo -e "${BOLD}==================== STEP 1: U-BOOT SERIAL CONSOLE (115200 8N1) ====================${NC}"
    echo "Power on the MR7500 and press any key at 'Hit any key to stop autoboot', then run:"
    echo -e "${CYAN}"
    echo "  setenv ipaddr ${ROUTER_IP}"
    echo "  setenv serverip ${SERVER_IP}"
    echo "  ping ${SERVER_IP}"
    if [ "$MODE" = "uboot-factory" ]; then
        echo "  tftpboot 0x44000000 mr7500-factory.bin"
        echo "  # Verify active boot_part (1=kernel/rootfs, 2=alt_kernel/alt_rootfs) before nand write!"
        echo "  printenv boot_part"
    else
        echo "  tftpboot 0x44000000 mr7500-initramfs.itb"
        echo "  bootm 0x44000000"
    fi
    echo -e "${NC}"
    if [ "$MODE" = "flash" ]; then
        FLAG_STR="$( [ "$KEEP_SETTINGS" = "1" ] && echo "" || echo "-n " )"
        echo -e "${BOLD}==================== STEP 2: INSIDE OPENWRT RAM SHELL ====================${NC}"
        echo "Once OpenWrt boots from RAM (~35s), run this command on the MR7500 console:"
        echo -e "${CYAN}"
        echo "  wget -O /tmp/sysupgrade.bin http://${SERVER_IP}:${HTTP_PORT}/sysupgrade.bin && \\"
        echo "  echo \"${SYS_SHA}  /tmp/sysupgrade.bin\" | sha256sum -c - && \\"
        echo "  sysupgrade ${FLAG_STR}-v /tmp/sysupgrade.bin"
        echo -e "${NC}"
    fi
    echo -e "${YELLOW}[*] Servers running. Press Ctrl+C once flashing/booting is complete.${NC}"
    wait "$TFTP_PID"
fi
