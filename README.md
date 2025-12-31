# SysAdmin Toolkit

**Version:** 1.0.0
**License:** MIT

---

## 📖 Overview
The **SysAdmin Toolkit** is a centralized repository of standardized scripts, configuration baselines, operational runbooks, and documentation templates. It is designed to establish a consistent, rigorous engineering discipline across IT infrastructure operations.

This toolkit serves as a portable "Swiss Army Knife" for Systems Administrators, Site Reliability Engineers (SREs), and Network Engineers, providing immediate access to validated tools for diagnostics, security hardening, and crisis management.

---

## 📂 Repository Structure

### 1. 🛠 `tools/`
Automated scripts for diagnostics, auditing, and maintenance tasks.
* **`system_health_check.sh`**: (Linux) Generates an instant snapshot of CPU, RAM, Disk, and Failed Services.
* **`system-info-collector.bat`**: (Windows) "Drop-and-run" health report for Windows Servers.
* **`network-reset.bat`**: (Windows) Automated utility to reset Winsock, TCP/IP stack, and flush DNS.
* **`log-parser.ps1`**: (PowerShell) Regex-based log analysis tool for identifying error patterns and frequencies.
* **`bulk-rename.ps1`**: (PowerShell) Mass file sanitization utility for data migrations and standardization.

### 2. 📚 `documentation/`
The knowledge base for Standard Operating Procedures (SOPs) and Policies.
* **`/troubleshooting`**: SOPs for high-volume operational issues (VoIP, Active Directory, Printers, Network).
* **`/best-practices`**: Definitive policy documents (Password Policy, Backup Strategy, Security Hardening Standards).
* **`/servers`**: Repository for detailed, per-host documentation.

### 3. 🚨 `runbooks/`
Playbooks for high-stress scenarios and routine maintenance.
* **`critical-incident-response.md`**: SEV-1 Incident Command structure and workflow.
* **`disaster-recovery.md`**: Protocols for catastrophic site failure, ransomware response, and "Clean Room" recovery.
* **`server-maintenance.md`**: Checklist for routine patching ("Patch Tuesday") and system hygiene.

### 4. ⚙️ `configs/`
Reference configurations for security and infrastructure baselines.
* **`sshd_config_hardened`**: Secure baseline configuration for Linux SSH access.
* **`switch-baseline-config.txt`**: Cisco IOS security template (SSH-only, banner, logging).
* **`basic-firewall-rules.txt`**: Platform-agnostic port strategy and "Default Deny" architecture.
* **`vlan-configuration-example.txt`**: Standard network segmentation schema for securing Management, Voice, and Guest traffic.

### 5. 📝 `templates/`
Standardized forms to ensure consistency in documentation.
* **`change-request-template.md`**: Evaluation form for infrastructure changes, risk assessment, and rollback planning.
* **`system-documentation-template.md`**: The standard format for documenting new server builds.

---

## 🚀 Usage Guide

### Linux Health Check
```bash
chmod +x tools/system_health_check.sh
./tools/system_health_check.sh
Windows Network Stack Reset
Navigate to the tools/ directory.

Right-Click network-reset.bat.

Select Run as Administrator.

Follow the prompts to reset networking components and reboot.

Log Analysis (PowerShell)
PowerShell

.\tools\log-parser.ps1 -FilePath "C:\inetpub\logs\LogFiles\u_ex231201.log" -Pattern " 500 "
🛡️ Security & Best Practices
Review before Execution: Always review scripts before executing them in a production environment to ensure compatibility.

Credentials: Never commit passwords, API Keys, or Webhook URLs to this repository. Use Environment Variables or external secret management.

Safety Switches: PowerShell tools in this repo support the -WhatIf switch to preview changes safely without modifying data.
