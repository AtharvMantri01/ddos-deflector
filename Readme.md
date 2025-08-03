# 🛡️ Zentra Host Advanced DDoS Deflector

![Zentra Logo](https://zentrahost.studio/static/img/small-logo.png)

**Version:** `v1.0`  
**License:** MIT  
**Supported OS:** Linux (Ubuntu, Debian, CentOS)

---

## 🚀 What is This?

The **Zentra Host Advanced DDoS Deflector** is a battle-tested, lightweight, and production-ready DDoS protection script built to secure your servers from common Layer 4 and Layer 7 attacks. Designed for hosting providers, gamers, and developers — Zentra deflects attacks in real-time with blazing-fast response and zero bloat.

Whether you're a solo developer or managing a fleet of VPS instances — **this is your server's first line of defense**.

---

## ✨ Features at a Glance

| Feature                        | Description                                                                 |
|-------------------------------|-----------------------------------------------------------------------------|
| 🔰 **Multi-Layer Shield**     | Protects against SYN floods, UDP abuse, HTTP GET/POST floods, and more     |
| 📡 **Real-Time Monitoring**   | Keeps an eye on traffic spikes, connection floods, and suspicious activity |
| 🌐 **GeoIP Blocking**         | Block traffic from specific countries instantly                            |
| 🧠 **Smart Detection Engine** | Automated rules to detect and mitigate evolving threats                    |
| 📬 **Discord Alerts**         | Get live alerts on your Discord channel for real-time monitoring           |
| ⚙️ **Rule Customization**     | Create your own rules for ports, IPs, thresholds, and triggers             |
| 🖥️ **System Insights**        | Lightweight system resource reporting & traffic stats                       |
| ⚡ **Low Resource Usage**     | Optimized for minimal CPU and memory overhead                              |

---

## 🧰 Components Used

- `iptables` / `ipset` for fast connection filtering
- `netstat`, `ss`, and `tcpdump` for traffic analytics
- Bash scripting for speed and control
- Optional integration with external APIs (GeoIP)

---

## 📦 Quick Installation

Paste the following command into your terminal:

```bash
curl -sSL https://raw.githubusercontent.com/zentrahost/ddos-deflector/main/install.sh | sudo bash
```

> ⚠️ Make sure you're running this as root or with `sudo` privileges.

---

## 🔧 Post-Install Notes

- Configuration files will be located in `/etc/zentra-deflector/`
- Logs are stored in `/var/log/zentra/`
- Use `zentra status` or `zentra monitor` to see real-time data
- Default thresholds:
  - Connections per IP: `100`
  - SYN packets/sec: `50`
  - UDP packets/sec: `200`
- Customize Discord Webhook inside the config file

---

## 🌍 GeoIP Blocking (Optional)

To enable country-based blocking:

1. Download GeoIP databases (install script will prompt)
2. Add countries to block list (e.g., `CN`, `RU`, `KP`)
3. Restart the deflector

---

## 📡 Sample Discord Alert

```
⚠️ DDoS Alert from Zentra Host
Suspicious IP: 203.0.113.5
Reason: Exceeded 150 connections in 10 seconds
Action: Temporarily blocked via iptables
```

---

## 🧪 Tested On

- ✅ Ubuntu 20.04 / 22.04
- ✅ Debian 11 / 12
- ✅ CentOS 7 / 8 (Stream)
- ✅ AlmaLinux 8+

---

## 📝 License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT). Feel free to fork, modify, and deploy it.

---

## 👨‍💻 Developed By

**Zentra Host Security Division**  
🔗 [https://zentrahost.studio](https://zentrahost.studio)  

---
