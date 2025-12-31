# Apex SysAdmin Toolkit

**Version:** 1.0.0
**Maintainer:** [Your Name/Organization]
**License:** MIT (Open Source)

---

## 📖 Overview
The **Apex SysAdmin Toolkit** is a battle-tested collection of scripts, configuration baselines, operational runbooks, and documentation templates. It is designed to standardize the "Chaos" of IT operations into a structured, repeatable, and secure engineering discipline.

This toolkit focuses on **Zero-Cost** implementation—leveraging native tools (Bash, PowerShell, Python) and open-source standards to achieve enterprise-grade reliability without enterprise-grade licensing fees.

---

## 📂 Repository Structure

### 1. 🛠 `tools/` (The Automation Engine)
Scripts for diagnostics, auditing, and maintenance.
* **`system_health_check.sh`**: (Linux) Instant snapshot of CPU, RAM, Disk, and Failed Services.
* **`system-info-collector.bat`**: (Windows) "Drop-and-run" health report for Windows Servers.
* **`network-reset.bat`**: (Windows) The "Big Red Button" that resets the entire TCP/IP stack.
* **`log-parser.ps1`**: (PowerShell) Regex-based log analysis tool (Poor man's Splunk).
* **`bulk-rename.ps1`**: (PowerShell) Mass file sanitizer for data migrations.

### 2. 📚 `documentation/` (The Knowledge Base)
Standard Operating Procedures (SOPs) and Policies.
* **`/troubleshooting`**: Guides for "High Volume" tickets (VoIP, Active Directory, Printers, Network).
* **`/best-practices`**: Policy documents (Password Policy, Backup Strategy, Security Hardening).
* **`/servers`**: Detailed documentation for specific production hosts.

### 3. 🚨 `runbooks/` (Crisis Management)
Playbooks for high-stress scenarios.
* **`critical-incident-response.md`**: SEV-1 Incident Command structure.
* **`disaster-recovery.md`**: Protocols for total site failure or ransomware.
* **`server-maintenance.md`**: Checklist for "Patch Tuesday" and routine maintenance.

### 4. ⚙️ `configs/` (The Baseline)
Reference configurations for security and infrastructure.
* **`sshd_config_hardened`**: Secure baseline for Linux SSH access.
* **`switch-baseline-config.txt`**: Cisco IOS security template.
* **`basic-firewall-rules.txt`**: Platform-agnostic port strategy.
* **`vlan-configuration-example.txt`**: Standard network segmentation schema.

### 5. 📝 `templates/` (Standardization)
Blank forms to ensure consistency.
* **`change-request-template.md`**: Evaluation form for infrastructure changes.
* **`system-documentation-template.md`**: The standard format for documenting a new server.

---

## 🚀 Quick Start Guide

### Linux Health Check
```bash
chmod +x tools/system_health_check.sh
./tools/system_health_check.sh
Windows Network Reset
Right-Click tools/network-reset.bat.

Select Run as Administrator.

Follow the prompts to reset Winsock/TCP stacks.

Deployment
To initialize this directory structure on a new workstation, run the master build script (if available) or clone this repo:

Bash

git clone [https://github.com/careed23/SysAdmin-Toolkit.git](https://github.com/careed23/SysAdmin-Toolkit.git)
🛡️ Security & Liability
Review before Run: Always review scripts before executing them in a production environment.

Credentials: Never commit passwords, API Keys, or Webhook URLs to this repository. Use Environment Variables.

"WhatIf": PowerShell tools in this repo support the -WhatIf switch to preview changes safely.

🤝 Contributing
Create a branch (git checkout -b feature/new-tool).

Commit your changes.

Open a Pull Request.

Strict Rule: No hardcoded credentials allowed.

Built with the Apex Methodology.


### How to Apply This
Since you are currently in the process of rebuilding/cleaning the repo:

1.  **Create the file:**
    ```bash
    cat << 'EOF' > README.md
    # Paste the content above here...
    EOF
    ```
    *(Or just copy-paste it into your editor).*

2.  **Add and Commit:**
    ```bash
    git add README.md
    git commit -m "Docs: Add root README"
    git push -u origin main
    ```
