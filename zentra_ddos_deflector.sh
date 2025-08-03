#!/bin/bash

# Zentra Host Advanced DDoS Deflector v1.0
HOST_NAME="Zentra Host"
DISCORD_WEBHOOK="https://discord.com/api/webhooks/XXXX/XXXX"  # Replace with your webhook
THRESHOLD=100                  # Connections per IP threshold
SYN_THRESHOLD=50               # SYN packets threshold
UDP_THRESHOLD=200              # UDP packets threshold
HTTP_REQ_THRESHOLD=300         # HTTP requests threshold
CHECK_INTERVAL=5               # Monitoring interval in seconds
AUTO_UNBLOCK_AFTER=360        # Auto-unblock after 1 hour (in seconds)
MAX_MEMORY_USAGE=80            % Memory usage threshold
MAX_CPU_USAGE=80               % CPU usage threshold
MAX_CONNECTIONS=5000           # Total connections threshold

# File paths
CONFIG_DIR="/etc/zentra"
LOG_FILE="$CONFIG_DIR/zentra_ddos_log.txt"
BLOCKED_IPS_FILE="$CONFIG_DIR/zentra_blocked_ips.txt"
WHITELIST_FILE="$CONFIG_DIR/zentra_whitelist.txt"
GEOIP_BLOCK_LIST="$CONFIG_DIR/geoip_blocked.txt"
TEMP_BLOCK_FILE="$CONFIG_DIR/temp_blocks.txt"
IP_RATE_LIMITS="$CONFIG_DIR/ip_rate_limits.txt"
ADVANCED_RULES="$CONFIG_DIR/advanced_rules.conf"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Initialize required files and directories
init_files() {
  mkdir -p "$CONFIG_DIR"
  touch "$BLOCKED_IPS_FILE" "$WHITELIST_FILE" "$GEOIP_BLOCK_LIST" "$TEMP_BLOCK_FILE" "$IP_RATE_LIMITS"
  
  # Create default advanced rules if not exists
  if [ ! -f "$ADVANCED_RULES" ]; then
    cat > "$ADVANCED_RULES" <<EOF
# Advanced DDoS Protection Rules
# Format: rule_type,pattern,action,rate_limit
http,User-Agent: (wget|curl|python),block,10/60
http,GET /wp-admin,block,5/60
http,POST /xmlrpc.php,block,2/60
tcp,flags=SYN,check_syn,50/10
udp,,check_udp,200/10
EOF
  fi
}

# -------------------- UI & UTILITIES --------------------
header() {
  clear
  echo -e "${CYAN}╔════════════════════════════════════════════╗"
  echo -e "║    Zentra Host Advanced DDoS Deflector    ║"
  echo -e "╚════════════════════════════════════════════╝${NC}"
  echo -e "${BLUE}Version 1.0 | Adaptive Protection Engine${NC}"
  echo
}

log_event() {
  local event="$1"
  local severity="${2:-INFO}"
  echo "$(date '+%F %T') - [$severity] $event" >> "$LOG_FILE"
  
  # Rotate log if over 10MB
  if [ $(stat -c%s "$LOG_FILE") -gt 10000000 ]; then
    mv "$LOG_FILE" "$LOG_FILE.old"
    touch "$LOG_FILE"
  fi
}

send_discord_alert() {
  local message="$1"
  local severity="${2:-WARNING}"
  local color=""
  
  case "$severity" in
    "CRITICAL") color="16711680" ;; # Red
    "HIGH") color="15105570" ;;     # Orange
    *) color="3066993" ;;          # Green
  esac
  
  local payload=$(cat <<EOF
{
    "embeds": [{
      "title": "Zentra DDoS Alert",
      "description": "$message",
      "color": $color,
      "fields": [
        {"name": "Severity", "value": "$severity", "inline": true},
        {"name": "Host", "value": "$HOST_NAME", "inline": true},
        {"name": "Time", "value": "$(date '+%F %T')", "inline": true}
      ]
    }]
}
EOF
  )
  
  curl -s -H "Content-Type: application/json" -X POST -d "$payload" "$DISCORD_WEBHOOK" > /dev/null
}

# -------------------- IPTABLES MANAGEMENT --------------------
init_firewall() {
  # Basic rate limiting
  iptables -N ZENTRA_DDOS
  iptables -A INPUT -j ZENTRA_DDOS
  
  # SYN flood protection
  iptables -N ZENTRA_SYN
  iptables -A INPUT -p tcp --syn -j ZENTRA_SYN
  
  # HTTP flood protection
  iptables -N ZENTRA_HTTP
  iptables -A INPUT -p tcp --dport 80 -j ZENTRA_HTTP
  iptables -A INPUT -p tcp --dport 443 -j ZENTRA_HTTP
  
  # UDP flood protection
  iptables -N ZENTRA_UDP
  iptables -A INPUT -p udp -j ZENTRA_UDP
  
  # Default policies
  iptables -P INPUT DROP
  iptables -P FORWARD DROP
  iptables -P OUTPUT ACCEPT
  
  # Allow established connections
  iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
  iptables -A INPUT -i lo -j ACCEPT
  
  log_event "Firewall initialized" "INFO"
}

cleanup_firewall() {
  iptables -D INPUT -j ZENTRA_DDOS 2>/dev/null
  iptables -F ZENTRA_DDOS
  iptables -X ZENTRA_DDOS
  
  iptables -D INPUT -p tcp --syn -j ZENTRA_SYN 2>/dev/null
  iptables -F ZENTRA_SYN
  iptables -X ZENTRA_SYN
  
  iptables -D INPUT -p tcp --dport 80 -j ZENTRA_HTTP 2>/dev/null
  iptables -D INPUT -p tcp --dport 443 -j ZENTRA_HTTP 2>/dev/null
  iptables -F ZENTRA_HTTP
  iptables -X ZENTRA_HTTP
  
  iptables -D INPUT -p udp -j ZENTRA_UDP 2>/dev/null
  iptables -F ZENTRA_UDP
  iptables -X ZENTRA_UDP
  
  iptables -P INPUT ACCEPT
}

# -------------------- BLOCKING FUNCTIONS --------------------
is_whitelisted() {
  grep -qxF "$1" "$WHITELIST_FILE"
}

is_blocked() {
  iptables -C ZENTRA_DDOS -s "$1" -j DROP &>/dev/null || \
  iptables -C INPUT -s "$1" -j DROP &>/dev/null
}

block_ip() {
  local ip="$1"
  local reason="${2:-Excessive connections}"
  local duration="${3:-$AUTO_UNBLOCK_AFTER}"
  
  if is_whitelisted "$ip"; then
    echo -e "${YELLOW}[!] $ip is whitelisted. Not blocking.${NC}"
    log_event "Attempted to block whitelisted IP: $ip" "NOTICE"
    return
  fi
  
  if is_blocked "$ip"; then
    echo -e "${YELLOW}[!] $ip already blocked.${NC}"
    return
  fi
  
  # Add to both temporary and permanent block lists
  iptables -A ZENTRA_DDOS -s "$ip" -j DROP
  echo "$ip $(date +%s) $reason" >> "$TEMP_BLOCK_FILE"
  echo "$ip" >> "$BLOCKED_IPS_FILE"
  
  log_event "Blocked $ip - Reason: $reason" "WARNING"
  send_discord_alert "**IP Blocked:** $ip\n**Reason:** $reason" "HIGH"
  
  # Schedule automatic unblock
  (
    sleep "$duration"
    if is_blocked "$ip"; then
      unblock_ip "$ip" "Automatic unblock after $duration seconds"
    fi
  ) &
  
  echo -e "${RED}[!] Blocked $ip - Reason: $reason${NC}"
}

unblock_ip() {
  local ip="$1"
  local reason="${2:-Manual unblock}"
  
  iptables -D ZENTRA_DDOS -s "$ip" -j DROP 2>/dev/null
  iptables -D INPUT -s "$ip" -j DROP 2>/dev/null
  sed -i "/^$ip/d" "$TEMP_BLOCK_FILE"
  sed -i "/^$ip$/d" "$BLOCKED_IPS_FILE"
  
  log_event "Unblocked $ip - Reason: $reason" "INFO"
  echo -e "${GREEN}[+] Unblocked $ip - Reason: $reason${NC}"
}

# -------------------- GEOIP PROTECTION --------------------
block_country() {
  local country="$1"
  if grep -qx "$country" "$GEOIP_BLOCK_LIST"; then
    echo -e "${YELLOW}[!] $country already blocked${NC}"
    return
  fi
  
  if ! iptables -C INPUT -m geoip --src-cc "$country" -j DROP &>/dev/null; then
    iptables -A INPUT -m geoip --src-cc "$country" -j DROP
    echo "$country" >> "$GEOIP_BLOCK_LIST"
    log_event "GeoIP Blocked country: $country" "WARNING"
    send_discord_alert "**GeoIP Block:** Country $country" "HIGH"
    echo -e "${GREEN}[+] Country $country blocked via GeoIP${NC}"
  else
    echo -e "${YELLOW}[!] $country already blocked in iptables${NC}"
  fi
}

unblock_country() {
  local country="$1"
  iptables -D INPUT -m geoip --src-cc "$country" -j DROP 2>/dev/null
  sed -i "/^$country$/d" "$GEOIP_BLOCK_LIST"
  log_event "Removed GeoIP block for country: $country" "INFO"
  echo -e "${GREEN}[+] Removed block for $country${NC}"
}

# -------------------- RATE LIMITING --------------------
apply_rate_limits() {
  # Clear existing rate limits
  iptables -F ZENTRA_SYN
  iptables -F ZENTRA_HTTP
  iptables -F ZENTRA_UDP
  
  # Apply SYN flood protection
  iptables -A ZENTRA_SYN -m limit --limit 50/sec --limit-burst 100 -j RETURN
  iptables -A ZENTRA_SYN -j LOG --log-prefix "[ZENTRA SYN FLOOD] "
  iptables -A ZENTRA_SYN -j DROP
  
  # HTTP flood protection
  iptables -A ZENTRA_HTTP -m limit --limit 300/minute --limit-burst 500 -j RETURN
  iptables -A ZENTRA_HTTP -j LOG --log-prefix "[ZENTRA HTTP FLOOD] "
  iptables -A ZENTRA_HTTP -j DROP
  
  # UDP flood protection
  iptables -A ZENTRA_UDP -m limit --limit 200/minute --limit-burst 400 -j RETURN
  iptables -A ZENTRA_UDP -j LOG --log-prefix "[ZENTRA UDP FLOOD] "
  iptables -A ZENTRA_UDP -j DROP
  
  log_event "Applied rate limiting rules" "INFO"
}

# -------------------- WHITELIST MANAGEMENT --------------------
add_whitelist() {
  local ip="$1"
  if grep -qxF "$ip" "$WHITELIST_FILE"; then
    echo -e "${YELLOW}[!] $ip already whitelisted${NC}"
  else
    echo "$ip" >> "$WHITELIST_FILE"
    log_event "Added $ip to whitelist" "INFO"
    echo -e "${GREEN}[+] $ip added to whitelist${NC}"
    
    # Unblock if currently blocked
    if is_blocked "$ip"; then
      unblock_ip "$ip" "IP was whitelisted"
    fi
  fi
}

remove_whitelist() {
  local ip="$1"
  if sed -i "/^$ip$/d" "$WHITELIST_FILE"; then
    log_event "Removed $ip from whitelist" "INFO"
    echo -e "${GREEN}[+] $ip removed from whitelist${NC}"
  else
    echo -e "${YELLOW}[!] $ip not found in whitelist${NC}"
  fi
}

# -------------------- SYSTEM MONITORING --------------------
check_system_health() {
  local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
  local mem_usage=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
  local conn_count=$(netstat -ntu | grep -vE '^Active|^Proto' | wc -l)
  
  if (( $(echo "$cpu_usage > $MAX_CPU_USAGE" | bc -l) )); then
    log_event "High CPU usage detected: ${cpu_usage}%" "WARNING"
    send_discord_alert "**High CPU Usage:** ${cpu_usage}%\nPossible resource exhaustion attack" "HIGH"
  fi
  
  if (( $(echo "$mem_usage > $MAX_MEMORY_USAGE" | bc -l) )); then
    log_event "High memory usage detected: ${mem_usage}%" "WARNING"
    send_discord_alert "**High Memory Usage:** ${mem_usage}%\nPossible memory exhaustion attack" "HIGH"
  fi
  
  if [ "$conn_count" -gt "$MAX_CONNECTIONS" ]; then
    log_event "High connection count detected: $conn_count" "WARNING"
    send_discord_alert "**High Connection Count:** $conn_count\nPossible connection flood" "HIGH"
    
    # Identify top talkers
    netstat -ntu | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -10 | while read count ip; do
      if [ "$count" -gt "$THRESHOLD" ]; then
        block_ip "$ip" "Connection flood ($count connections)"
      fi
    done
  fi
}

# -------------------- ADVANCED RULES ENGINE --------------------
load_advanced_rules() {
  while IFS=, read -r rule_type pattern action rate_limit; do
    # Skip comments and empty lines
    [[ "$rule_type" =~ ^# ]] && continue
    [ -z "$rule_type" ] && continue
    
    case "$rule_type" in
      "http")
        apply_http_rule "$pattern" "$action" "$rate_limit"
        ;;
      "tcp")
        apply_tcp_rule "$pattern" "$action" "$rate_limit"
        ;;
      "udp")
        apply_udp_rule "$pattern" "$action" "$rate_limit"
        ;;
      *)
        log_event "Unknown rule type in advanced rules: $rule_type" "WARNING"
        ;;
    esac
  done < "$ADVANCED_RULES"
}

apply_http_rule() {
  local pattern="$1"
  local action="$2"
  local rate_limit="$3"
  
  # Add iptables rule to match HTTP traffic with the pattern
  # This is a simplified example - in practice you'd need something like nginx+lua or similar
  log_event "Applying HTTP rule: $pattern -> $action (Rate: $rate_limit)" "INFO"
}

apply_tcp_rule() {
  local pattern="$1"
  local action="$2"
  local rate_limit="$3"
  
  # Add iptables rule for TCP patterns
  log_event "Applying TCP rule: $pattern -> $action (Rate: $rate_limit)" "INFO"
}

apply_udp_rule() {
  local pattern="$1"
  local action="$2"
  local rate_limit="$3"
  
  # Add iptables rule for UDP patterns
  log_event "Applying UDP rule: $pattern -> $action (Rate: $rate_limit)" "INFO"
}

# -------------------- MONITORING & ANALYSIS --------------------
monitor_ddos() {
  header
  echo -e "${CYAN}[~] Starting advanced DDoS monitoring...${NC}"
  echo -e "${YELLOW}[*] Protection thresholds:"
  echo -e "  - Connections/IP: $THRESHOLD"
  echo -e "  - SYN packets: $SYN_THRESHOLD/sec"
  echo -e "  - UDP packets: $UDP_THRESHOLD/min"
  echo -e "  - HTTP requests: $HTTP_REQ_THRESHOLD/min${NC}"
  echo -e "${MAGENTA}[*] Press Ctrl+C to stop monitoring${NC}"
  
  # Load advanced rules
  load_advanced_rules
  
  while true; do
    # Check system health first
    check_system_health
    
    # Monitor connection floods
    analyze_connection_floods
    
    # Monitor HTTP floods
    analyze_http_floods
    
    # Monitor SYN floods
    analyze_syn_floods
    
    # Monitor UDP floods
    analyze_udp_floods
    
    # Check for temporary blocks that can be removed
    check_temp_blocks
    
    sleep "$CHECK_INTERVAL"
  done
}

analyze_connection_floods() {
  # Analyze TCP connection floods
  ss -ntu state established | awk 'NR>1 {split($5,a,":"); ip=a[1]; print ip}' | 
    sort | uniq -c | sort -nr |
    while read count ip; do
      if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ && "$count" -gt "$THRESHOLD" ]]; then
        block_ip "$ip" "Connection flood ($count connections)"
      fi
    done
}

analyze_http_floods() {
  # This would require access to HTTP logs - simplified example
  if [ -f "/var/log/nginx/access.log" ]; then
    tail -1000 /var/log/nginx/access.log | awk '{print $1}' | 
      sort | uniq -c | sort -nr |
      while read count ip; do
        if [ "$count" -gt "$HTTP_REQ_THRESHOLD" ]; then
          block_ip "$ip" "HTTP flood ($count requests)"
        fi
      done
  fi
}

analyze_syn_floods() {
  # Monitor SYN packets
  local syn_count=$(netstat -nt | grep SYN_RECV | wc -l)
  if [ "$syn_count" -gt "$SYN_THRESHOLD" ]; then
    log_event "SYN flood detected: $syn_count SYN_RECV connections" "WARNING"
    send_discord_alert "**SYN Flood Detected:** $syn_count half-open connections" "HIGH"
    
    # Identify SYN flood sources
    netstat -nt | grep SYN_RECV | awk '{print $5}' | cut -d: -f1 | 
      sort | uniq -c | sort -nr | head -10 |
      while read count ip; do
        if [ "$count" -gt "$((SYN_THRESHOLD/2))" ]; then
          block_ip "$ip" "SYN flood ($count half-open connections)"
        fi
      done
  fi
}

analyze_udp_floods() {
  # Monitor UDP packets
  local udp_count=$(netstat -nu | wc -l)
  if [ "$udp_count" -gt "$UDP_THRESHOLD" ]; then
    log_event "UDP flood detected: $udp_count UDP packets" "WARNING"
    send_discord_alert "**UDP Flood Detected:** $udp_count UDP packets" "HIGH"
    
    # Identify UDP flood sources
    netstat -nu | awk '{print $5}' | cut -d: -f1 | 
      sort | uniq -c | sort -nr | head -10 |
      while read count ip; do
        if [ "$count" -gt "$((UDP_THRESHOLD/2))" ]; then
          block_ip "$ip" "UDP flood ($count packets)"
        fi
      done
  fi
}

check_temp_blocks() {
  local now=$(date +%s)
  while read -r line; do
    local ip=$(echo "$line" | awk '{print $1}')
    local timestamp=$(echo "$line" | awk '{print $2}')
    local reason=$(echo "$line" | cut -d' ' -f3-)
    
    if [ -z "$ip" ] || [ -z "$timestamp" ]; then
      continue
    fi
    
    local elapsed=$((now - timestamp))
    if [ "$elapsed" -gt "$AUTO_UNBLOCK_AFTER" ]; then
      unblock_ip "$ip" "Automatic unblock after timeout"
    fi
  done < "$TEMP_BLOCK_FILE"
}

# -------------------- STATISTICS & REPORTING --------------------
show_stats() {
  header
  echo -e "${CYAN}╔════════════════════════════════════╗"
  echo -e "║          Protection Stats          ║"
  echo -e "╚════════════════════════════════════╝${NC}"
  
  # Current connections
  local conn_count=$(netstat -ntu | grep -vE '^Active|^Proto' | wc -l)
  echo -e "${YELLOW}Current Connections:${NC} $conn_count"
  
  # Blocked IPs count
  local blocked_count=$(wc -l < "$BLOCKED_IPS_FILE")
  echo -e "${YELLOW}Blocked IPs:${NC} $blocked_count"
  
  # Top blocked countries
  if [ -s "$GEOIP_BLOCK_LIST" ]; then
    echo -e "\n${YELLOW}Blocked Countries:${NC}"
    cat "$GEOIP_BLOCK_LIST" | tr '\n' ' ' | fold -s
    echo
  fi
  
  # Recent attacks
  echo -e "\n${YELLOW}Recent Attacks Blocked:${NC}"
  tail -5 "$LOG_FILE" | grep "Blocked" | cut -d' ' -f4- | sed 's/^/  /'
  
  # System health
  local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
  local mem_usage=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
  echo -e "\n${YELLOW}System Health:${NC}"
  echo -e "  CPU Usage: $cpu_usage%"
  echo -e "  Memory Usage: $mem_usage%"
  
  echo -e "\n${MAGENTA}Press any key to return to menu...${NC}"
  read -n1 -s
}

# -------------------- MAIN MENU --------------------
main_menu() {
  init_files
  init_firewall
  
  while true; do
    header
    echo -e "${CYAN}╔════════════════════════════════════╗"
    echo -e "║          Main Menu               ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}1.${NC} Start Advanced DDoS Monitor"
    echo -e "${YELLOW}2.${NC} Manual IP Block"
    echo -e "${YELLOW}3.${NC} Manual IP Unblock"
    echo -e "${YELLOW}4.${NC} Whitelist Management"
    echo -e "${YELLOW}5.${NC} GeoIP Country Blocking"
    echo -e "${YELLOW}6.${NC} View Protection Stats"
    echo -e "${YELLOW}7.${NC} Configure Advanced Rules"
    echo -e "${YELLOW}8.${NC} Exit"
    echo -ne "${CYAN}Select: ${NC}"
    
    read -n1 opt
    echo
    
    case "$opt" in
      1) monitor_ddos ;;
      2) 
        read -p "Enter IP to block: " ip
        read -p "Reason (optional): " reason
        block_ip "$ip" "${reason:-Manual block}"
        ;;
      3) 
        read -p "Enter IP to unblock: " ip
        unblock_ip "$ip" "Manual unblock"
        ;;
      4) whitelist_menu ;;
      5) geoip_menu ;;
      6) show_stats ;;
      7) configure_rules ;;
      8) 
        cleanup_firewall
        exit 0
        ;;
      *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
    esac
  done
}

whitelist_menu() {
  while true; do
    header
    echo -e "${CYAN}╔════════════════════════════════════╗"
    echo -e "║          Whitelist Management     ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}1.${NC} Add IP to Whitelist"
    echo -e "${YELLOW}2.${NC} Remove IP from Whitelist"
    echo -e "${YELLOW}3.${NC} View Whitelisted IPs"
    echo -e "${YELLOW}4.${NC} Back to Main Menu"
    echo -ne "${CYAN}Select: ${NC}"
    
    read -n1 opt
    echo
    
    case "$opt" in
      1) 
        read -p "Enter IP to whitelist: " ip
        add_whitelist "$ip"
        ;;
      2) 
        read -p "Enter IP to remove from whitelist: " ip
        remove_whitelist "$ip"
        ;;
      3)
        echo -e "\n${YELLOW}Whitelisted IPs:${NC}"
        cat "$WHITELIST_FILE" | sed 's/^/  /'
        echo -e "\n${MAGENTA}Press any key to continue...${NC}"
        read -n1 -s
        ;;
      4) return ;;
      *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
    esac
  done
}

geoip_menu() {
  while true; do
    header
    echo -e "${CYAN}╔════════════════════════════════════╗"
    echo -e "║          GeoIP Blocking          ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}1.${NC} Block Country"
    echo -e "${YELLOW}2.${NC} Unblock Country"
    echo -e "${YELLOW}3.${NC} View Blocked Countries"
    echo -e "${YELLOW}4.${NC} Back to Main Menu"
    echo -ne "${CYAN}Select: ${NC}"
    
    read -n1 opt
    echo
    
    case "$opt" in
      1) 
        read -p "Enter country code (e.g., CN, RU, US): " cc
        block_country "$cc"
        ;;
      2) 
        read -p "Enter country code to unblock: " cc
        unblock_country "$cc"
        ;;
      3)
        echo -e "\n${YELLOW}Blocked Countries:${NC}"
        cat "$GEOIP_BLOCK_LIST" | sed 's/^/  /'
        echo -e "\n${MAGENTA}Press any key to continue...${NC}"
        read -n1 -s
        ;;
      4) return ;;
      *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
    esac
  done
}

configure_rules() {
  header
  echo -e "${CYAN}╔════════════════════════════════════╗"
  echo -e "║          Advanced Rules           ║"
  echo -e "╚════════════════════════════════════╝${NC}"
  echo -e "${YELLOW}Current Rules:${NC}"
  cat "$ADVANCED_RULES" | sed 's/^/  /'
  
  echo -e "\n${YELLOW}Options:${NC}"
  echo -e "1. Edit rules (nano)"
  echo -e "2. Reload rules"
  echo -e "3. Back to menu"
  echo -ne "${CYAN}Select: ${NC}"
  
  read -n1 opt
  echo
  
  case "$opt" in
    1) 
      if command -v nano >/dev/null; then
        nano "$ADVANCED_RULES"
        load_advanced_rules
      else
        echo -e "${RED}Nano editor not found. Please install it or edit $ADVANCED_RULES manually.${NC}"
        sleep 2
      fi
      ;;
    2) 
      load_advanced_rules
      echo -e "${GREEN}Rules reloaded${NC}"
      sleep 1
      ;;
    3) return ;;
    *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
  esac
}

# -------------------- MAIN EXECUTION --------------------
trap 'cleanup_firewall; exit 0' INT TERM EXIT
main_menu