# Server Maintenance Standard Operating Procedure (SOP)

**Frequency:** Monthly (Recommended: 2nd Tuesday/Wednesday, aligning with "Patch Tuesday")
**Time Window:** 02:00 UTC - 04:00 UTC (Or lowest traffic window)
**Owner:** SysAdmin Lead

---

## 1. Pre-Maintenance Checklist (The "No-Go" Checks)
*Do not proceed if any of these fail.*

* [ ] **Verify Backups:** Check the backup dashboard. Ensure the last backup ( < 24 hours old) was **Successful**.
* [ ] **Check System Health:** Run `htop` or the `system_health_check.sh` tool. If CPU/RAM is currently spiking, investigate before patching.
* [ ] **Silence Monitoring:** Set Nagios/Zabbix/PagerDuty to "Maintenance Mode" for 2 hours to prevent false alarms.
* [ ] **Notify Stakeholders:** Send a reminder email/Slack message: "Scheduled maintenance beginning in 10 minutes."

---

## 2. Maintenance Execution Tasks

### A. System Updates (Patching)
Apply security patches and stable updates.

**Debian/Ubuntu:**
```bash
sudo apt update
sudo apt upgrade -y
# Remove obsolete packages to free space
sudo apt autoremove -y
RHEL/CentOS/AlmaLinux:

Bash

sudo yum update -y
# Or if using dnf
sudo dnf update -y
B. Disk & Log Hygiene
Prevent "Disk Full" outages by cleaning up.

[ ] Check Disk Space: df -h (Ensure root / and /var are < 80%).

[ ] Log Rotation: Check /var/log. If huge logs exist (e.g., syslog.1 > 2GB), force rotation or compression.

[ ] Docker Cleanup (If applicable):

Bash

# Removes stopped containers and unused images
docker system prune -f
[ ] Journal Control: Vacuum old systemd logs if > 500MB.

Bash

journalctl --vacuum-size=500M
C. Security Review
[ ] Audit Sudoers: cat /etc/group | grep sudo - Verify no unauthorized users were added.

[ ] Check Failed Logins: Briefly review auth logs for spikes in brute force attacks.

Bash

grep "Failed password" /var/log/auth.log | tail -n 20
3. Post-Maintenance (The Reboot & Verify)
A. Reboot
If the kernel or libc was updated, a reboot is mandatory.

Bash

sudo reboot
B. Verification Steps (After Reboot)
Connectivity: Can you SSH back in?

Services: Are critical services running?

Bash

systemctl status nginx
systemctl status mysql
# etc...
Public Access: Load the website/application from a browser/external network.

Internal Communication: Can the web server talk to the database?

4. Closure
[ ] Re-enable Alerts: Turn off Maintenance Mode in monitoring tools.

[ ] Close Ticket: Update the Change Request (CR) with "Completed Successfully."

[ ] Notify: Post in Slack/Teams: "Maintenance complete. All systems green."
