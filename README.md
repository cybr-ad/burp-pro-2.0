# ⚡ Burp Suite Pro — Universal Linux Setup

<div align="center">

[![Linux Support](https://img.shields.io/badge/Linux-Kali%20%7C%20Ubuntu%20%7C%20Debian%20%7C%20Fedora%20%7C%20Arch-blue?style=for-the-badge&logo=linux&logoColor=white)](#-compatibility)
[![Java Runtime](https://img.shields.io/badge/Java-Oracle%20JDK%2017--25-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white)](#-java-runtime)
[![Bash Script](https://img.shields.io/badge/Script-Bash%205.0+-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)](burp-pro-setup.sh)
[![License](https://img.shields.io/badge/License-MIT-purple?style=for-the-badge)](LICENSE)

**A clean, automated 1-click setup script that installs, configures, and integrates Burp Suite Professional on any modern Linux system.**

[🚀 Quick Start](#-quick-start) • [✨ Features](#-features) • [🔑 Activation Guide](#-activation-steps) • [🖥️ How to Launch](#-how-to-launch) • [❓ Troubleshooting](#-troubleshooting)

</div>

---

## ✨ Features

- ⚡ **1-Click Automated Setup** — Automatically sets up dependencies, downloads necessary files, and configures shortcuts.
- ☕ **Smart Java Runtime Management** — Installs and configures Oracle JDK (17–25, defaults to proven JDK 23 / 21 LTS).
- 🌐 **Dual Download Modes** — Supports high-speed Direct downloads or Tor / Proxychains routing.
- 📦 **PortSwigger Archive Support** — Select popular releases (`2025.12.3`, `2023.3.3`, `2026.x`) or browse releases from the last 10 years (2016–2026).
- 🖥️ **System-Wide Integration** — Installs desktop launcher (`Burp-pro.desktop`), high-res app icon, and global terminal command (`burp-pro`).
- 🛡️ **Clean System State** — Automatically checks and fixes stale `/etc/hosts` overrides and firewall rules.

---

## 📋 Compatibility

| Component | Supported Environments |
| :--- | :--- |
| **Operating Systems** | Kali Linux, Ubuntu, Debian, Fedora, Arch Linux, Parrot OS |
| **Architecture** | `x86_64` / `amd64` |
| **Java Runtimes** | Oracle JDK 17 (LTS), JDK 21 (LTS), JDK 23 *(Recommended)* to JDK 25 |
| **Desktop Environments** | XFCE, GNOME, KDE Plasma, Cinnamon, MATE |

---

## 🚀 Quick Start

Run these commands in your terminal:

```bash
# 1. Clone this repository
git clone https://github.com/your-username/burp-pro-2.0.git
cd burp-pro-2.0

# 2. Grant execution permission
chmod +x burp-pro-setup.sh

# 3. Run the installer
sudo ./burp-pro-setup.sh
```

> [!TIP]
> Always run the script with `sudo` so it can install necessary packages and configure system shortcuts. The script automatically detects and drops privileges to your real desktop user for GUI and file ownership.

---

## ⚙️ Interactive Installer Flow

When you run `burp-pro-setup.sh`, it guides you through a few simple choices:

```text
1. Network Mode      ─ Choose (1) Direct Connection (recommended) or (2) Proxychains / Tor
2. JDK Selection     ─ Select JDK 17 to 25 (Press Enter for default JDK 23)
3. Burp Version      ─ Pick v2025.12.3, v2023.3.3, v2026.9.2, or custom release
4. Offline Activate  ─ Keygen GUI opens in background; activate Burp Suite
5. Finish & Integrate─ Script creates desktop icon and 'burp-pro' command
```

---

## 🔑 Activation Steps

During installation, the script launches the **burploader** GUI. Follow these steps:

```
┌────────────────────────────────────────────────────────────────────────┐
│  1. In Keygen GUI  ──> Copy the "License" string                       │
│  2. In Burp Suite  ──> Paste the License and click [ Next ]            │
│  3. In Burp Suite  ──> Choose [ Manual Activation ]                    │
│  4. In Burp Suite  ──> Click [ Copy Request ]                          │
│  5. In Keygen GUI  ──> Paste into "Activation Request" box             │
│  6. In Keygen GUI  ──> Copy the generated "Activation Response"        │
│  7. In Burp Suite  ──> Paste into "Activation Response" & click Next   │
│  8. In Keygen GUI  ──> Copy the "Loader Command" to your terminal      │
└────────────────────────────────────────────────────────────────────────┘
```

> [!NOTE]
> If you don't copy a custom loader command from Keygen, just press **Enter** in the terminal — the script will automatically generate the optimal launch command for you.

---

## 🖥️ How to Launch

Once setup is complete, you can start Burp Suite Pro in any of these convenient ways:

### 1. From Terminal (Anywhere)
```bash
burp-pro
```

### 2. From Desktop Application Menu
Open your Application menu and search for **Burp-pro**, or double-click the **Burp-pro** shortcut on your Desktop.

### 3. Background Script
```bash
~/Documents/burp/burp.sh
```

---

## 📁 Installed Directory Structure

The setup script organizes all files inside your user directory:

```
~/Documents/burp/
├── burploader.jar             # Loader & keygen tool
├── burpsuite_pro_v*.jar       # PortSwigger Burp Suite JAR
├── burp.sh                    # Optimized background startup script
└── burpsuite.png              # High-resolution application icon

/usr/local/bin/burp-pro        # Global terminal symlink -> ~/Documents/burp/burp.sh
~/Desktop/Burp-pro.desktop     # Desktop launcher shortcut
~/.local/share/applications/   # App menu launcher
```

---

## ❓ Troubleshooting

<details>
<summary><b>Keygen GUI fails to open ("Cannot open display")</b></summary>

Allow local GUI permissions for X11 by running:
```bash
xhost +local:
```
Then re-run the script.
</details>

<details>
<summary><b>Switch or verify active Java version</b></summary>

Check your active Java version:
```bash
java -version
```
To switch between installed versions manually:
```bash
sudo update-alternatives --config java
```
</details>

<details>
<summary><b>Tor / Proxychains connection timeout</b></summary>

Ensure Tor service is up and active:
```bash
sudo systemctl restart tor
sudo systemctl status tor
```
Or simply choose **Option 1 (Direct Connection)** when prompted by the script.
</details>

<details>
<summary><b>Burp desktop icon shows "Untrusted Desktop File" (XFCE)</b></summary>

Right-click the **Burp-pro.desktop** file on your Desktop and click **"Mark as Executable"** or **"Allow Launching"**. The script also attempts to auto-trust it via `gio`.
</details>

---

## 📜 Disclaimer & License

- **Disclaimer**: This script and project are intended solely for **educational and research purposes**. Burp Suite is a registered trademark of PortSwigger Ltd. Please support the creators by purchasing an official commercial license from [PortSwigger](https://portswigger.net/).
- **License**: Released under the [MIT License](LICENSE).
