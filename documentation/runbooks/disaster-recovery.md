# Disaster Recovery (DR) Plan & Protocol

**Severity:** Critical (SEV-1)
**Activation Authority:** CTO / Lead Systems Architect
**Objective:** Restore Minimum Viable Product (MVP) functionality within 4 Hours.

---

## 1. Activation Criteria
This plan is **ONLY** activated under the following conditions:
1.  **Physical Destruction:** Primary facility is offline (Fire, Power Grid Failure, Flood).
2.  **Cyber Catastrophe:** Entire network is compromised by Ransomware.
3.  **Extended Outage:** Primary ISP/Service failure expected to exceed 24 hours.

## 2. The Chain of Command (Command & Control)
* **Incident Commander (IC):** [Name/Role] - Makes the decision to failover.
* **Ops Lead:** [Name/Role] - Executes the technical recovery.
* **Comms Lead:** [Name/Role] - Handles internal/external messaging.

> **Note:** Once DR is activated, the "Primary" site is considered dead. Do not attempt to fix it until DR is stable.

---

## 3. Recovery Workflows

### Scenario A: Total Server Loss (Cloud Failover)
*Context: Servers are deleted or hardware has failed catastrophically.*

1.  **Infrastructure Provisioning:**
    * Log into Standby Cloud Provider (AWS/Azure/DigitalOcean).
    * Execute Terraform/Ansible scripts to provision base infrastructure (VPCs, Subnets, VM instances).
    * *Manual Fallback:* If scripts fail, manually create 1 Domain Controller, 1 App Server, 1 DB Server.

2.  **Data Restoration:**
    * **Source:** Off-site Immutable Object Storage (e.g., S3/Wasabi).
    * **Method:** Use the Backup Server Agent or CLI tools to pull the latest "Synthetic Full" backup.
    * **Priority Order:**
        1.  Directory Services (AD/LDAP) - *Users need to log in.*
        2.  Database Servers (SQL) - *Apps need data.*
        3.  File Servers / Application Servers.

3.  **Network Re-Mapping:**
    * Update Public DNS (Cloudflare/GoDaddy) A-Records to point to the **New DR IP Addresses**.
    * Lower TTL (Time to Live) to 60 seconds to propagate changes fast.

### Scenario B: Ransomware Recovery (The "Clean Room")
*Context: Network is infected. Restoring to the same network will just re-infect the backups.*

1.  **Isolation:**
    * **PHYSICALLY DISCONNECT** the uplink cable to the internet.
    * Power down all infected switches and hosts.

2.  **The "Clean Room" Build:**
    * Configure a new, isolated VLAN (e.g., VLAN 999) that cannot route to the old network.
    * Install a clean, fresh OS on a spare server/VM.

3.  **Sanitized Restore:**
    * Restore the backup to the Clean Room VLAN.
    * **Scan Immediately:** Run a full offline virus scan on the restored VM *before* booting the OS if possible, or immediately upon boot with network disconnected.
    * Only once confirmed clean, bridge to the internet.

---

## 4. Verification & Testing
Before announcing "We are back":
1.  **Data Integrity:** Randomly sample 5 recent files/records. Are they there?
2.  **Application Logic:** Can a user log in? Can they save a record?
3.  **External Access:** Is the site loading over 4G/5G (outside corporate network)?

## 5. Failback (Return to Normal)
*Warning: Failback is often harder than Failover.*
1.  **Sync Data:** You must replicate the *new* data created during the outage back to the Primary site.
2.  **Maintenance Window:** Schedule a planned outage.
3.  **Reverse DNS:** Point DNS back to Primary IPs.
4.  **Decommission:** Destroy DR resources to stop the billing clock.

---

## 6. Emergency Contacts
| Role | Name | Phone | Alternate Contact |
| :--- | :--- | :--- | :--- |
| **Hosting Provider** | AWS Support | 1-800-XXX-XXXX | Ticket Portal |
| **ISP Support** | [ISP Name] | 1-888-XXX-XXXX | Account Rep |
| **Cyber Insurance** | [Provider] | 1-800-XXX-XXXX | Policy #12345 |
Risk vs. Reward
Risk: Split-Brain DNS. If you failover to DR but some users are still pointed to the old site (due to long DNS TTL), data will be written in two places. Mitigation: The guide emphasizes lowering TTL before the disaster if possible, or accepting the lag.

Reward: Business Continuity. This document transforms a "Company Ending Event" into a "really bad Tuesday."
