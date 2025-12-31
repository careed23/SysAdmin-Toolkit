# Security Hardening Baseline

**Scope:** All production Linux/Windows servers.
**Philosophy:** Principle of Least Privilege.

## 1. User Access & Authentication
* **Root/Admin Login:** DISABLED via SSH/RDP. Use sudo/runas.
* **SSH Keys:** Mandatory. Password authentication DISABLED.
* **Idle Timeout:** Sessions disconnect after 15 minutes of inactivity.
* **Banners:** Legal warning banner displayed at login (deterrence/liability).

## 2. Network & Firewall
* **Default Policy:** DENY ALL inbound.
* **Allow List:** Only open ports explicitly required (e.g., 80, 443).
* **Management Ports:** SSH (22) and RDP (3389) restricted to VPN or specific Management IP ranges only.
* **ICMP:** Limit rate to prevent Ping floods, but allow for diagnostics.

## 3. Services & Packages
* **Minimal Install:** Install only the OS components required (e.g., "Server Core" for Windows, "Minimal" for Linux).
* **Unused Services:** Disable legacy services (Telnet, FTP, SMBv1).
* **Web Servers:** Hide version headers (e.g., `server_tokens off` in Nginx).

## 4. Logging & Auditing
* **Retention:** Logs retained for minimum 90 days.
* **Off-site:** Critical security logs shipped to central syslog server (prevent tampering).
* **Events Monitored:** Failed sudo attempts, new user creation, service stops.
2. backup-and-recovery-strategy.md
Strategic Value: Backups are useless; Restores are priceless. This document formalizes the "3-2-1" rule to ensure data survivability.

Markdown

# Backup & Recovery Strategy

## 1. The 3-2-1 Rule (Mandatory)
Every critical dataset must adhere to this standard:
* **3** Copies of data (1 Production + 2 Backups).
* **2** Different media types (e.g., Local Disk + Cloud Object Storage).
* **1** Copy off-site (Physically separated from the primary datacenter).

## 2. Backup Schedules
| Data Type | Frequency | Retention | Method |
| :--- | :--- | :--- | :--- |
| **Databases** | Every 1 Hour | 7 Days | Dump/Transaction Logs |
| **File Servers** | Daily (Nightly) | 30 Days | Incremental |
| **System State** | Weekly | 3 Months | Full Image/Snapshot |

## 3. The "Restore Test" Protocol
A backup is considered "Failed" until a restore is successfully verified.
* **Frequency:** Monthly.
* **Method:** Randomly select 1 file and 1 database. Restore to a sandbox environment.
* **Verification:** Check file integrity and application launch.

## 4. Ransomware Protection
* **Immutability:** Primary off-site backups must be "Object Locked" or "Immutable" for 7 days to prevent encryption by ransomware.
* **Air Gap:** If possible, one copy should be offline (tape/detached disk).
3. patch-management-policy.md
Strategic Value: Patching breaks things. This policy protects you from being blamed for downtime caused by a bad update by establishing "Testing Rings."

Markdown

# Patch Management Policy

## 1. Patch Classifications
* **Critical/Security:** Vulnerabilities with CVSS > 7.0. (SLA: 48 Hours)
* **Important:** Stability fixes and non-critical security. (SLA: 14 Days)
* **Optional:** Feature updates. (SLA: As needed)

## 2. Deployment Rings
Never patch all servers at once.
* **Ring 0 (Dev/Test):** Patched immediately upon release. Monitor for 24 hours.
* **Ring 1 (Staging/Non-Critical):** Patched if Ring 0 is stable. Monitor for 48 hours.
* **Ring 2 (Production):** Patched only after Ring 1 is confirmed stable.

## 3. The "Blackout" Windows
* No patching on Fridays (prevents weekend emergencies).
* No patching during Month-End Close (Finance) or Black Friday (Retail).

## 4. Rollback Plan
* **Requirement:** Before applying any Ring 2 patch, a snapshot/backup must be taken.
* **Trigger:** If primary application fails health check post-patch, immediate rollback is initiated.
4. credential-management.md
Strategic Value: Prevents "Key to the Kingdom" attacks. This is often the weakest link in small to mid-sized businesses.

Markdown

# Credential & Secret Management

## 1. Password Complexity Standards
* **Length:** Minimum 14 characters.
* **Complexity:** Not enforced (length is mathematically superior).
* **Rotation:** Only on compromise or staff turnover (NIST guidelines).

## 2. Multi-Factor Authentication (MFA)
* **Mandatory:** For ALL remote access (VPN, RDP Gateway, Cloud Consoles).
* **Type:** App-based (TOTP) or Hardware Key. SMS is deprecated.

## 3. Service Accounts
* **Restriction:** "Logon as Service" only. Deny Interactive Login.
* **Least Privilege:** Do not add Service Accounts to Domain Admins group.
* **Management:** Passwords managed via PAM (Privileged Access Management) tool or Vault, rotated automatically if possible.

## 4. Storage of Secrets
* **Prohibited:** Post-it notes, `passwords.txt` on desktop, unencrypted Excel sheets.
* **Approved:** Enterprise Password Manager (e.g., Bitwarden, 1Password, KeePassXC).
Risk vs. Reward
Risk: Compliance Rigidity. Adhering strictly to "Ring" patching schedules can delay fixes for zero-day exploits. Mitigation: The policy includes an exception for "Critical/Security" (48h SLA) to bypass rings when necessary.

Reward: Liability Shield. When a server is hacked or data is lost, having these signed policies proves you were not negligent. It transforms "IT screwed up" into "We followed the industry-standard protocol."
