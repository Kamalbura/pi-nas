#!/bin/bash
# Generate status.json with current Pi NAS live data

set -e

# Export ALL variables for Python to use
export SYS_HOSTNAME=$(hostname)
export SYS_UPTIME=$(uptime -p | sed 's/up //')
export SYS_UPTIME_SECONDS=$(cat /proc/uptime | awk '{print int($1)}')
export SYS_LOAD=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
export SYS_TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.1f", $1/1000}')
THROTTLED=$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)
[ "$THROTTLED" = "0x0" ] && export SYS_THROTTLED="No" || export SYS_THROTTLED="Yes"
export SYS_VOLT=$(vcgencmd measure_volts core 2>/dev/null | cut -d= -f2 | tr -d 'V')
export SYS_CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | sed 's/^ *//')
export SYS_CPU_CORES=$(nproc)
export SYS_CPU_FREQ=$(lscpu | grep "CPU max MHz" | awk '{print $4}')
export SYS_CPU_ARCH=$(uname -m)
export SYS_KERNEL=$(uname -r)

export MEM_TOTAL=$(free -h | awk '/^Mem:/{print $2}')
export MEM_USED=$(free -h | awk '/^Mem:/{print $3}')
export MEM_PERC=$(free | awk '/^Mem:/{printf "%.0f", $3/$2 * 100}')
export SWAP_TOTAL=$(free -h | awk '/^Swap:/{print $2}')
export SWAP_USED=$(free -h | awk '/^Swap:/{print $3}')
export SWAP_PERC=$(free | awk '/^Swap:/{if($2>0) printf "%.0f", $3/$2 * 100; else print "0"}')

export SSD_MODEL=$(sudo smartctl -i -d sat /dev/sda 2>/dev/null | grep "Device Model" | cut -d: -f2- | sed 's/^ *//')
export SSD_TOTAL=$(lsblk /dev/sda -n -o SIZE 2>/dev/null | head -1)
export SSD_USED=$(df -h / | awk 'NR==2{print $3}')
export SSD_AVAIL=$(df -h / | awk 'NR==2{print $4}')
export SSD_PERC=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')
export SSD_HEALTH=$(sudo smartctl -H -d sat /dev/sda 2>/dev/null | grep "SMART overall-health" | grep -oP '(PASSED|FAILED)')
export SSD_TEMP=$(sudo smartctl -A -d sat /dev/sda 2>/dev/null | grep Temperature_Celsius | awk '{print $10}' | head -1)
export SSD_POH=$(sudo smartctl -A -d sat /dev/sda 2>/dev/null | grep Power_On_Hours | awk '{print $10}')
export SSD_REALLOC=$(sudo smartctl -A -d sat /dev/sda 2>/dev/null | grep "^  5 " | awk '{print $10}')
export SSD_WEAR=$(sudo smartctl -A -d sat /dev/sda 2>/dev/null | grep Media_Wearout_Indicator | awk '{print $10}')

export HDD_MODEL=$(sudo smartctl -i -d sat /dev/sdb 2>/dev/null | grep "Device Model" | cut -d: -f2- | sed 's/^ *//')
export HDD_TOTAL=$(lsblk /dev/sdb -n -o SIZE 2>/dev/null | head -1)
export HDD_USED=$(df -h /mnt/nas 2>/dev/null | awk 'NR==2{print $3}')
export HDD_AVAIL=$(df -h /mnt/nas 2>/dev/null | awk 'NR==2{print $4}')
export HDD_PERC=$(df -h /mnt/nas 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
export HDD_HEALTH=$(sudo smartctl -H -d sat /dev/sdb 2>/dev/null | grep "SMART overall-health" | grep -oP '(PASSED|FAILED)')
export HDD_TEMP=$(sudo smartctl -A -d sat /dev/sdb 2>/dev/null | grep Temperature_Celsius | awk '{print $10}' | head -1)
export HDD_POH=$(sudo smartctl -A -d sat /dev/sdb 2>/dev/null | grep Power_On_Hours | awk '{print $10}')
export HDD_REALLOC=$(sudo smartctl -A -d sat /dev/sdb 2>/dev/null | grep "^  5 " | awk '{print $10}')
export HDD_LOAD_CYCLE=$(sudo smartctl -A -d sat /dev/sdb 2>/dev/null | grep Load_Cycle_Count | awk '{print $10}')
export HDD_STATE=$(sudo hdparm -C /dev/sdb 2>/dev/null | grep "drive state" | cut -d: -f2 | sed 's/^ *//')

export LAN_IP=$(ip -4 addr show eth0 2>/dev/null | grep inet | awk '{print $2}')
export TAILSCALE_IP=$(ip -4 addr show tailscale0 2>/dev/null | grep inet | awk '{print $2}')
export TAILSCALE_HOSTNAME=$(tailscale status 2>/dev/null | head -1 | awk '{print $2}')
export MAGICDNS="${TAILSCALE_HOSTNAME}.tailcdf1f7.ts.net"
export TAILSCALE_SERVE=$(sudo tailscale serve status 2>/dev/null | grep -v "^$" | paste -sd ' | ')

export CONTAINER_LIST=$(sudo docker ps -a --format '{"name":"{{.Names}}","image":"{{.Image}}","status":"{{.Status}}","ports":"{{.Ports}}"}' 2>/dev/null | paste -sd,)
export CONTAINER_RUNNING=$(sudo docker ps -q 2>/dev/null | wc -l)
export CONTAINER_TOTAL=$(sudo docker ps -aq 2>/dev/null | wc -l)
# Fix empty container list
[ -z "$CONTAINER_LIST" ] && export CONTAINER_LIST="" || export CONTAINER_LIST

export COMPOSE_STACKS=$(find /home/bura /etc -name "docker-compose.yml" -not -path "*/node_modules/*" -not -path "/home/bura/projects/*" 2>/dev/null | paste -sd ','| sed 's/,/, /g')

LATEST_REPORT=$(ls -t /home/bura/smart-reports/smart-report-*.txt 2>/dev/null | head -1)
if [ -n "$LATEST_REPORT" ]; then
    export LAST_SMART_CHECK=$(stat -c '%y' "$LATEST_REPORT" | cut -d. -f1)
else
    export LAST_SMART_CHECK="Never"
fi

export SYS_NOW=$(date '+%Y-%m-%d %H:%M:%S %Z')

# Generate JSON via Python
python3 << 'PYEOF'
import os, json

d = {
    "timestamp": os.environ.get("SYS_NOW", ""),
    "system": {
        "hostname": os.environ.get("SYS_HOSTNAME", ""),
        "os": "Debian 13 (Trixie)",
        "kernel": os.environ.get("SYS_KERNEL", ""),
        "arch": os.environ.get("SYS_CPU_ARCH", ""),
        "uptime": os.environ.get("SYS_UPTIME", ""),
        "uptime_seconds": int(os.environ.get("SYS_UPTIME_SECONDS", "0")),
        "load": os.environ.get("SYS_LOAD", ""),
        "temperature_c": float(os.environ.get("SYS_TEMP", "0")),
        "throttled": os.environ.get("SYS_THROTTLED", ""),
        "voltage_v": float(os.environ.get("SYS_VOLT", "0")),
        "cpu": {
            "model": os.environ.get("SYS_CPU_MODEL", ""),
            "cores": int(os.environ.get("SYS_CPU_CORES", "0")),
            "max_freq_mhz": float(os.environ.get("SYS_CPU_FREQ", "0"))
        },
        "memory": {
            "total": os.environ.get("MEM_TOTAL", ""),
            "used": os.environ.get("MEM_USED", ""),
            "percent": int(os.environ.get("MEM_PERC", "0")),
            "swap_total": os.environ.get("SWAP_TOTAL", ""),
            "swap_used": os.environ.get("SWAP_USED", ""),
            "swap_percent": int(os.environ.get("SWAP_PERC", "0"))
        }
    },
    "storage": {
        "ssd": {
            "model": os.environ.get("SSD_MODEL", ""),
            "device": "/dev/sda",
            "total": os.environ.get("SSD_TOTAL", ""),
            "used": os.environ.get("SSD_USED", ""),
            "available": os.environ.get("SSD_AVAIL", ""),
            "percent_used": int(os.environ.get("SSD_PERC", "0")),
            "mount": "/",
            "smart": {
                "health": os.environ.get("SSD_HEALTH", ""),
                "temperature_c": os.environ.get("SSD_TEMP", ""),
                "power_on_hours": os.environ.get("SSD_POH", ""),
                "reallocated_sectors": os.environ.get("SSD_REALLOC", ""),
                "wearout_indicator": os.environ.get("SSD_WEAR", "")
            }
        },
        "hdd": {
            "model": os.environ.get("HDD_MODEL", ""),
            "device": "/dev/sdb",
            "total": os.environ.get("HDD_TOTAL", ""),
            "used": os.environ.get("HDD_USED", ""),
            "available": os.environ.get("HDD_AVAIL", ""),
            "percent_used": int(os.environ.get("HDD_PERC", "0")),
            "mount": "/mnt/nas (label: OLD MAN)",
            "state": os.environ.get("HDD_STATE", ""),
            "smart": {
                "health": os.environ.get("HDD_HEALTH", ""),
                "temperature_c": os.environ.get("HDD_TEMP", ""),
                "power_on_hours": os.environ.get("HDD_POH", ""),
                "reallocated_sectors": os.environ.get("HDD_REALLOC", ""),
                "load_cycle_count": os.environ.get("HDD_LOAD_CYCLE", "")
            }
        }
    },
    "network": {
        "lan_ip": os.environ.get("LAN_IP", ""),
        "tailscale_ip": os.environ.get("TAILSCALE_IP", ""),
        "magicdns": os.environ.get("MAGICDNS", ""),
        "tailscale_serve": os.environ.get("TAILSCALE_SERVE", "")
    },
    "containers": {
        "running": int(os.environ.get("CONTAINER_RUNNING", "0")),
        "total": int(os.environ.get("CONTAINER_TOTAL", "0")),
        "list": [x for x in [os.environ.get("CONTAINER_LIST", "")] if x]
    },
    "maintenance": {
        "last_smart_report": os.environ.get("LAST_SMART_CHECK", "Never"),
        "hdd_spindown": "10 min idle (APM 127, standby -S 120)",
        "smart_schedule": "Every Sunday 3am",
        "compose_stacks": os.environ.get("COMPOSE_STACKS", "")
    }
}

print(json.dumps(d, indent=2))
PYEOF
