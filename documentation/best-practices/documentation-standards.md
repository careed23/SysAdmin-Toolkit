# Documentation Standards & Style Guide

**Version:** 1.0
**Philosophy:** "Documentation is Code." It lives in Git, it is versioned, and it is written in Markdown.

---

## 1. File Format & Storage
* **Format:** All documentation must be written in **Markdown (.md)**.
* **Storage:** Stored in the `SysAdmin-Toolkit/documentation/` Git repository.
* **Naming Convention:** Kebab-case (lowercase with hyphens).
    * *Good:* `server-setup-guide.md`
    * *Bad:* `Server Setup Guide.docx`, `Server_Setup.txt`

## 2. Structure of a Document
Every technical document must contain these four sections:

### A. Front Matter (Metadata)
```markdown
# Title of Document
**Author:** [Name]
**Last Updated:** [YYYY-MM-DD]
**Scope:** [What this covers]
B. The "Why" (Context)Before listing commands, explain why we are doing this.Example: "This guide details the setup of the Nginx Reverse Proxy to handle SSL termination for our internal apps."C. The "How" (Steps)Use numbered lists for sequential steps.Use code blocks for commands.NEVER use screenshots for text/code. Screenshots are not searchable.D. Verification (The "Proof")How does the user know they finished successfully?Example: "Run nginx -t. If the output says 'syntax is ok', the procedure is complete."3. Code Block StandardsAlways specify the language for syntax highlighting.Bash/Shell:Bashsudo apt update
sudo apt install nginx -y
PowerShell:PowerShellGet-Service -Name Spooler | Restart-Service
Config Files:Ini, TOML[server]
port = 8080
4. Tone and StyleActive Voice: "Restart the server" (Not "The server should be restarted").Concise: Avoid fluff. "Run the script" is better than "Please kindly go ahead and execute the script."No "Magic Numbers": Do not write "Set value to 10" without explaining why it is 10.Better: "Set MaxClients 10 (Matches our CPU core count)."5. MaintenanceReview Cycle: All documentation is marked "Stale" after 6 months.Deprecation: Do not delete old documentation immediately. Move it to an _archive/ folder and mark the header as [DEPRECATED].
---

### **Final Execution: The Master Build Script**

I have compiled **every single file** we have discussed into one master bash script. This is the zero-cost implementation tool.

**Instructions:**
1.  Copy the code block below.
2.  Save it as `init_toolkit.sh` on your machine.
3.  Run it: `bash init_toolkit.sh`.

It will create the `SysAdmin-Toolkit` directory, all subdirectories, all documentation files, all config files, all scripts, make the scripts executable, and initialize it as a Git repository.

```bash
#!/bin/bash

# Apex SysAdmin Toolkit - Master Build Script
# Usage: bash init_toolkit.sh

echo ">>> Initializing Apex SysAdmin Toolkit..."
BASE_DIR="SysAdmin-Toolkit"

# 1. Create Directory Structure
echo ">>> Creating directories..."
mkdir -p "$BASE_DIR/templates/documentation"
mkdir -p "$BASE_DIR/configs"
mkdir -p "$BASE_DIR/tools"
mkdir -p "$BASE_DIR/reports"
mkdir -p "$BASE_DIR/documentation/troubleshooting"
mkdir -p "$BASE_DIR/documentation/best-practices"
mkdir -p "$BASE_DIR/documentation/servers"

# ------------------------------------------------------------------------------
# 2. POPULATE TEMPLATES
# ------------------------------------------------------------------------------

echo ">>> Generating Templates..."

# Change Request Template
cat << 'EOF' > "$BASE_DIR/templates/documentation/change-request-template.md"
# IT Infrastructure Change Request (CR)

| CR ID | Requestor | Date Submitted | Priority |
| :--- | :--- | :--- | :--- |
| CR-YYYY-MM-DD-001 | [Name] | YYYY-MM-DD | [Low/Med/High/Critical] |

## 1. Summary of Change
**Description:**
> Briefly describe the change being implemented.

**Justification:**
> Why is this change necessary? (e.g., Security patch, Feature request, Bug fix)

## 2. Implementation Plan
**Affected Systems:**
* [Server Name/IP]
* [Service Name]

**Detailed Steps:**
1.  [Step 1]
2.  [Step 2]
3.  [Step 3]

**Time Window:**
* Start: [YYYY-MM-DD HH:MM]
* End: [YYYY-MM-DD HH:MM]

## 3. Risk and Impact Analysis
* **Risk Level:** [Low/Medium/High]
* **Potential Impact:** (e.g., Service downtime, latency)
* **Rollback Plan:**
    > Describe the exact steps to revert the changes if failure occurs.

## 4. Approval
| Name | Role | Status | Date |
| :--- | :--- | :--- | :--- |
| [Approver Name] | SysAdmin Lead | [Pending/Approved] | |
EOF

# System Documentation Template
cat << 'EOF' > "$BASE_DIR/templates/documentation/system-documentation-template.md"
# System Documentation: [Hostname]

## 1. Overview
* **Hostname:** `server-01`
* **IP Address:** `192.168.x.x`
* **OS/Version:** (e.g., Ubuntu 22.04 LTS)
* **Primary Function:** (e.g., Web Server, Database, Load Balancer)

## 2. Network Configuration
| Interface | IP Address | Gateway | DNS |
| :--- | :--- | :--- | :--- |
| eth0 | 10.0.0.5 | 10.0.0.1 | 8.8.8.8 |

## 3. Installed Services & Ports
| Service Name | Port | Config Location | Status |
| :--- | :--- | :--- | :--- |
| Nginx | 80/443 | `/etc/nginx/` | Active |
| SSH | 22 | `/etc/ssh/sshd_config` | Active |

## 4. User Access & Permissions
* **Sudoers:** `admin`, `deploy`
* **SSH Key Auth Only:** [Yes/No]

## 5. Maintenance Schedule
* **Backup Schedule:** Daily at 02:00 UTC
* **Patching Schedule:** Monthly (2nd Tuesday)
EOF

# ------------------------------------------------------------------------------
# 3. POPULATE CONFIGS
# ------------------------------------------------------------------------------

echo ">>> Generating Configurations..."

# SSH Hardened Config
cat << 'EOF' > "$BASE_DIR/configs/sshd_config_hardened"
# Secure SSH Configuration Baseline
# Copy to /etc/ssh/sshd_config

Port 22
Protocol 2

# Authentication
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no

# Timeout (Disconnect idle sessions after 5 mins)
ClientAliveInterval 300
ClientAliveCountMax 0

# Banner
Banner /etc/issue.net
EOF

# Bash Aliases
cat << 'EOF' > "$BASE_DIR/configs/.bash_aliases_admin"
# SysAdmin Shortcuts
alias ll='ls -alF'
alias update='sudo apt update && sudo apt upgrade -y'
alias ports='netstat -tulanp'
alias logs='tail -f /var/log/syslog'
alias weblogs='tail -f /var/log/nginx/access.log'
alias myip='curl ifconfig.me'
EOF

# ------------------------------------------------------------------------------
# 4. POPULATE TOOLS
# ------------------------------------------------------------------------------

echo ">>> Generating Tools..."

# System Health Check Script
cat << 'EOF' > "$BASE_DIR/tools/system_health_check.sh"
#!/bin/bash
# Description: Quick system health check
# Usage: ./system_health_check.sh

echo "--- System Health Report: $(date) ---"

# 1. Disk Usage
echo "[DISK USAGE]"
df -h | grep '^/dev/'
echo ""

# 2. Memory Usage
echo "[MEMORY USAGE]"
free -h
echo ""

# 3. CPU Load
echo "[CPU LOAD]"
uptime
echo ""

# 4. Check Failed Services
echo "[FAILED SERVICES]"
systemctl list-units --state=failed
echo ""

# 5. Top 5 Memory Consuming Processes
echo "[TOP MEMORY CONSUMERS]"
ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -n 6
echo "-----------------------------------"
EOF

# User Audit Script
cat << 'EOF' > "$BASE_DIR/tools/user_audit.sh"
#!/bin/bash
# Description: Lists all users with sudo access and checks for empty passwords

echo "--- User Security Audit ---"

echo "[USERS WITH SUDO PRIVILEGES]"
grep -Po '^sudo.+:\K.*$' /etc/group
echo ""

echo "[USERS WITH UID 0 (Root Privileges)]"
awk -F: '($3 == 0) {print}' /etc/passwd
echo ""

echo "[CHECKING FOR EMPTY PASSWORDS]"
sudo awk -F: '($2 == "") {print}' /etc/shadow
if [ $? -eq 0 ]; then
    echo "Scan complete."
fi
EOF

# Make scripts executable
chmod +x "$BASE_DIR/tools/"*.sh

# ------------------------------------------------------------------------------
# 5. POPULATE REPORTS
# ------------------------------------------------------------------------------

echo ">>> Generating Reports Placeholder..."

cat << 'EOF' > "$BASE_DIR/reports/README.md"
# Reports Directory

This directory is the output destination for automated scripts located in `../tools/`.

## Report Retention Policy
* Daily Health Checks: Retained for 30 days.
* Security Audits: Retained for 1 year.
* Incident Reports: Indefinite retention.

## Automation
Scripts such as `system_health_check.sh` should be configured via cron to dump logs here:
`*/5 * * * * /path/to/tools/system_health_check.sh >> /path/to/reports/daily_log.txt`
EOF

# ------------------------------------------------------------------------------
# 6. POPULATE DOCUMENTATION (Troubleshooting & Best Practices)
# ------------------------------------------------------------------------------

echo ">>> Generating Documentation..."

# Main README
cat << 'EOF' > "$BASE_DIR/documentation/README.md"
# SysAdmin Toolkit Documentation

## Overview
This directory contains all operational documentation regarding the infrastructure managed by the SysAdmin Toolkit.

## Directory Structure
* **`/templates`**: Standardized forms for Change Requests and System Definitions.
* **`/troubleshooting`**: SOPs for fixing common issues.
* **`/best-practices`**: Policy documents and standards.
* **`/servers`**: Individual documentation for production servers (use template).
EOF

# -- Troubleshooting Guides --

# Printers
cat << 'EOF' > "$BASE_DIR/documentation/troubleshooting/printer-common-issues.md"
# Troubleshooting Guide: Common Printer Issues

## 1. Initial Triage Checklist
* [ ] **Physical Check:** Is the printer powered on and are paper trays full?
* [ ] **Error Codes:** Record the exact error code on the printer display.
* [ ] **Connectivity:** Can you ping the printer IP?
* [ ] **Spooler:** Has the Print Spooler service been restarted on the server/client?

## 2. Print Spooler Reset (Windows)
**Command Line Fix (Run as Admin):**
```powershell
net stop spooler
del /Q /F /S "%systemroot%\System32\Spool\Printers\*.*"
net start spooler
EOFVoIPcat << 'EOF' > "$BASE_DIR/documentation/troubleshooting/voip-troubleshooting.md"VoIP & SIP Troubleshooting Standard Operating Procedure (SOP)1. Quick Diagnostic MatrixSymptomMost Likely CauseOne-Way AudioSIP ALG enabled on firewall.Choppy / Robot VoicePacket Loss (>1%) or High Jitter (>30ms).Dropped CallsUDP Timeout misconfiguration.2. The Golden Rule: SIP ALGSIP ALG (Application Layer Gateway) must be DISABLED on the edge router/firewall immediately.3. Network Performance RequirementsLatency (Ping): < 150msJitter: < 30msPacket Loss: < 1%EOFActive Directorycat << 'EOF' > "$BASE_DIR/documentation/troubleshooting/active-directory-issues.md"Troubleshooting Guide: Active Directory (AD)1. Top Issue: Account LockoutsFind Locked Accounts:PowerShellSearch-ADAccount -LockedOut | Select-Object Name, SamAccountName
2. Replication FailuresCheck Replication Status:DOSrepadmin /showrepl /csv > c:\temp\replreport.csv
Force Replication:DOSrepadmin /syncall /A /e /P
EOFNetwork Connectivitycat << 'EOF' > "$BASE_DIR/documentation/troubleshooting/network-connectivity-issues.md"Troubleshooting Guide: General Network ConnectivityMethodology: Bottom-Up (OSI Model)Layer 1 (Physical): Check link lights and cables.Layer 2 (Data Link): Check ARP table (arp -a).Layer 3 (Network): Ping Loopback -> Local IP -> Gateway -> WAN IP (8.8.8.8).Layer 4+ (Transport/DNS): Check DNS (nslookup google.com) and Ports (telnet or nc).EOF-- Best Practices --Security Hardeningcat << 'EOF' > "$BASE_DIR/documentation/best-practices/security-hardening-baseline.md"Security Hardening Baseline1. User AccessRoot/Admin Login: DISABLED via SSH/RDP.SSH Keys: Mandatory.Idle Timeout: 15 minutes.2. NetworkDefault Policy: DENY ALL inbound.Allow List: Only open ports explicitly required.EOFBackup Strategycat << 'EOF' > "$BASE_DIR/documentation/best-practices/backup-strategies.md"Backup Strategies & ArchitecturesThe 3-2-1 Rule3 Copies of data.2 Different media types.1 Copy off-site.Rotation: GFS (Grandfather-Father-Son)Son (Daily): Retain 14 days.Father (Weekly): Retain 5 weeks.Grandfather (Monthly): Retain 1 year.EOFPassword Policycat << 'EOF' > "$BASE_DIR/documentation/best-practices/password-policies.md"Corporate Password PolicyGeneral UsersMinimum Length: 12 characters.Complexity: Not enforced if length > 14.Expiration: None (unless compromised).AdminsMinimum Length: 16 characters.MFA: Mandatory.EOFPatching Policycat << 'EOF' > "$BASE_DIR/documentation/best-practices/patch-management-policy.md"Patch Management PolicyDeployment RingsRing 0 (Dev): Immediate.Ring 1 (Staging): +24 Hours.Ring 2 (Production): +48 Hours (if stable).Critical ExceptionsSecurity patches with CVSS > 7.0 are applied within 48 hours regardless of ring status.EOFCredential Managementcat << 'EOF' > "$BASE_DIR/documentation/best-practices/credential-management.md"Credential ManagementStorageProhibited: Sticky notes, text files, Excel.Mandatory: Enterprise Password Manager (Bitwarden, KeepassXC).Service AccountsRestriction: "Logon as Service" only.Rotation: Annually or upon staff departure.EOFDocumentation Standardscat << 'EOF' > "$BASE_DIR/documentation/best-practices/documentation-standards.md"Documentation StandardsPhilosophyDocumentation is Code. It lives in Git and uses Markdown.StructureFront Matter: Author, Date, Scope.Context: The "Why".Steps: The "How" (Commands).Verification: The "Proof".EOF------------------------------------------------------------------------------7. INITIALIZE GIT------------------------------------------------------------------------------echo ">>> Initializing Git Repository..."cd "$BASE_DIR" || exitgit initcat << 'EOF' > .gitignore.DS_Storereports/.logreports/.txttmp/EOFgit add .git commit -m "Initial commit: Apex SysAdmin Toolkit structure and baseline documentation."echo ">>> Build Complete. Your toolkit is ready in directory: $BASE_DIR"
