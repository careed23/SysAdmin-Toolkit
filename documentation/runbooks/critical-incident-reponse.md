# Critical Incident Response Playbook (CIRP)

**Severity Level:** SEV-1 (System Down / Data Loss)
**Trigger:** 50% of users affected or Core Revenue Service offline.

---

## Phase 1: Mobilization (First 15 Minutes)
**Goal:** Acknowledge the issue and assemble the team.

1.  **Declare Incident:**
    * Post in `#incidents` Slack/Teams channel: "SEV-1 Declared: [System Name] is down."
    * **STOP** all non-relevant engineering work.

2.  **Assign Roles (Explicitly Name People):**
    * **Incident Commander (IC):** (Usually the Lead SysAdmin). Makes decisions. Does NOT touch the keyboard.
    * **Ops Lead:** (The most senior tech). Hands on keyboard. Fixes the issue.
    * **Comms Lead:** Updates management/customers. Shield the Ops Lead from questions.

3.  **Open "War Room":**
    * Start a dedicated voice call (Zoom/Teams). All hands join. Mute unless speaking.

---

## Phase 2: Containment
**Goal:** Stop the bleeding. Performance is secondary; availability is primary.

* **Is it an Attack?** -> Isolate the network immediately (Unplug cable / Block port).
* **Is it a Bad Deploy?** -> Rollback to previous version immediately. Do not try to "fix forward."
* **Is it Load?** -> Add capacity (scale up) or shed load (turn off non-essential features).

---

## Phase 3: Eradication & Recovery
**Goal:** Restore service health.

1.  **Apply Fix:** (Ops Lead executes, IC approves).
2.  **Verify:** Check health metrics (CPU, RAM, Error Rates).
3.  **Slow Rollout:** Open traffic to 10% of users. Wait 5 minutes. Then 50%. Then 100%.

---

## Phase 4: Post-Mortem (The "Hot Wash")
**Goal:** Prevent recurrence.

* **Schedule Meeting:** Within 24 hours.
* **The 5 Whys:** Ask "Why" 5 times to find the root cause (not the symptom).
* **Action Items:** Create Jira tickets for the permanent fix.
2. runbooks/server-maintenance.md
Strategic Value: Routine maintenance is the only thing stopping a "Critical Incident." This checklist ensures you don't forget the invisible tasks like log rotation or disk space.

Markdown

# Server Maintenance Standard Operating Procedure

**Frequency:** Monthly (2nd Tuesday, "Patch Tuesday")
**Window:** 02:00 UTC - 04:00 UTC

---

## 1. Pre-Maintenance Checks
* [ ] **Check Backups:** Verify last night's backup was successful. **NO MAINTENANCE WITHOUT BACKUP.**
* [ ] **Check Health:** Review `htop` and disk usage. Do not patch a sick server.
* [ ] **Silence Alerts:** Set monitoring (Nagios/Zabbix) to "Maintenance Mode" for 2 hours.

## 2. The Maintenance Tasks

### A. System Updates
```bash
# Ubuntu/Debian
sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y

# RHEL/CentOS
sudo yum update -y
B. Disk Hygiene
[ ] Log Rotation: Check /var/log sizes. Force rotation if >1GB.

[ ] Docker Prune: Remove unused containers/images.

Bash

docker system prune -f
[ ] Old Kernels: Remove old kernel headers to free /boot space.

C. Security Review
[ ] Audit Users: Check /etc/passwd for unauthorized accounts.

[ ] Failed Logins: Review /var/log/auth.log for brute force spikes.

3. Post-Maintenance (The Reboot)
Reboot: sudo reboot (Required for Kernel updates).

Verification:

Can you SSH back in?

Are services (Nginx, SQL) running? systemctl status nginx

Is the website reachable from the public internet?

4. Closure
[ ] Re-enable Alerts: Turn off Maintenance Mode.

[ ] Log Work: Record activity in the Change Management Log (CR-ID).


### 3. `runbooks/disaster-recovery.md`
*Strategic Value:* This is the "Nuclear Option." Use this document when the primary datacenter is gone (fire, flood) or the data is totally corrupted (ransomware).

```markdown
# Disaster Recovery (DR) Plan

**Activation Authority:** CTO or Lead Systems Architect.
**Objective:** Restore critical business functions within 4 Hours (RTO).

---

## 1. Activation Criteria
This plan is ONLY activated when:
* Primary facility is physically destroyed.
* Primary infrastructure is irretrievably compromised (Ransomware).
* Service outage is expected to exceed 24 hours.

## 2. Communication Chain
1.  **Call Tree:** CEO -> CTO -> Ops Lead -> Staff.
2.  **Public Statement:** "We are experiencing a major outage. Services have failed over to our disaster recovery site."

---

## 3. Recovery Scenarios

### Scenario A: Total Server Loss (Cloud Restore)
*Context: Servers deleted or hardware failure.*
1.  **Provision New Hosts:** Deploy base OS images (use Terraform/Ansible if avail).
2.  **Install Backup Agent:** Install Veeam/Datto/Rsync agent.
3.  **Restore from Object Storage:** Pull "Immutable" off-site backup.
    * *Order of Restoration:*
        1.  Domain Controllers / DNS (Identity)
        2.  Database Servers (Data)
        3.  Application Servers (Logic)
        4.  Web/Proxy Servers (Access)

### Scenario B: Ransomware (The "Clean Room")
*Context: Network is infected.*
1.  **Disconnect Everything:** Pull the uplink cable. Isolate VLANs.
2.  **Build Clean Network:** Create a new, isolated VLAN (VLAN 999).
3.  **Restore to Clean Network:** Restore backups to VLAN 999.
4.  **Scan:** Run full AV/Rootkit scan on restored VMs *before* reconnecting them to the internet.

---

## 4. Failback (Return to Normal)
Once the primary site is rebuilt:
1.  **Sync Data:** Replicate changes from DR site back to Primary.
2.  **Maintenance Window:** Schedule outage.
3.  **DNS Cutover:** Update DNS records to point back to Primary IP.
4.  **Decommission:** Spin down DR resources to save costs.
Risk vs. Reward
Risk: Outdated Runbooks. A DR plan that references servers that no longer exist is dangerous. Mitigation: The "Server Maintenance" runbook should include a quarterly step to "Review DR Plan."

Reward: Survival. When a crisis hits, adrenaline lowers IQ. These documents provide the "brain" when yours is in fight-or-flight mode.

Final Step: The Updated Build Script
