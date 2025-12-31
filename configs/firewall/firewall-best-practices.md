# Firewall Best Practices & Security Architecture

**Version:** 1.0
**Scope:** Perimeter Firewalls, Cloud Security Groups (AWS/Azure), and Host-Based Firewalls (UFW/Windows Firewall).
**Philosophy:** "Default Deny" (Zero Trust).

---

## 1. The Core Philosophy: Default Deny
The most critical rule in any firewall is the implicit cleanup rule at the bottom.
* **Inbound:** DROP ALL. (Nothing enters unless explicitly invited).
* **Outbound:** RESTRICT. (Servers should not be browsing the internet).
* **Forwarding:** DROP. (Your server is not a router unless configured to be one).

## 2. Rule Ordering Strategy
Firewalls process rules sequentially (Top-Down). The order impacts performance and security.
1.  **Anti-Spoofing/Bogons:** Drop packets from invalid ranges (e.g., 127.0.0.0/8 coming from WAN).
2.  **Established/Related:** Allow traffic for connections already approved. (High volume, needs to be top).
3.  **Specific Blocks:** "Deny IP X" (Blacklists).
4.  **Specific Allows:** "Allow IP Y to Port 22".
5.  **General Allows:** "Allow Any to Port 80".
6.  **Logging:** Log the packet before dropping it.
7.  **Implicit Drop:** The final "cleanup" rule.

## 3. Egress (Outbound) Filtering
**90% of admins ignore this.** If a server is compromised, it will try to "phone home" to a Command & Control (C2) server.
* **Block:** All outbound traffic by default.
* **Allow:** Only necessary services (DNS, NTP, OS Updates, API endpoints).
* **Why:** This neutralizes reverse shells and prevents your server from becoming part of a botnet.

## 4. Management Access (SSH/RDP)
* **Never expose Management Ports (22, 3389) to `0.0.0.0/0`.**
* **Option A (Best):** Require VPN connection; Management Ports only accept traffic from the VPN subnet.
* **Option B:** Allow List only specific static IPs (Office, Home).
* **Option C:** Port Knocking or Geo-Blocking (if static IPs are impossible).

## 5. Documentation & Justification
Every rule must have a comment or description.
* *Bad:* `Allow TCP 8080`
* *Good:* `Allow TCP 8080 - Jenkins Web UI - Req by DevTeam (Ticket #1234)`

## 6. The "Any/Any" Sin
**NEVER** create a rule that allows `Any Source` to `Any Destination` on `Any Port`.
* *Risk:* This effectively turns off the firewall. It is often created for "troubleshooting" and forgotten.

## 7. Review Schedule
* **Frequency:** Quarterly (Every 3 months).
* **Task:** Remove rules for decommissioned servers. Remove temporary access rules.
Action: Update Your Build Script
Since you already have the Master Build Script (init_repo.sh), you don't need to regenerate the whole thing. You can simply append this file to the structure using the command below.

Run this in your terminal (where SysAdmin-Toolkit is located):

Bash

cat << 'EOF' > SysAdmin-Toolkit/documentation/best-practices/firewall-best-practices.md
# Firewall Best Practices & Security Architecture

## 1. The Core Philosophy: Default Deny
* **Inbound:** DROP ALL.
* **Outbound:** RESTRICT.

## 2. Rule Ordering Strategy
1. Anti-Spoofing
2. Established/Related
3. Specific Blocks
4. Specific Allows
5. General Allows
6. Logging
7. Implicit Drop

## 3. Egress (Outbound) Filtering
Block all outbound traffic by default. Only allow DNS, NTP, and Updates. This prevents Reverse Shells.

## 4. Management Access
Never expose SSH/RDP to the open internet. Use VPN or Allow Lists.

## 5. Documentation
Every rule must have a comment referencing a ticket number or owner.
EOF
