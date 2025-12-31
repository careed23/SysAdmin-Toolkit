# Troubleshooting Guide: Common Printer Issues

## 1. Initial Triage Checklist
* [ ] **Physical Check:** Is the printer powered on and are paper trays full?
* [ ] **Error Codes:** Record the exact error code on the printer display.
* [ ] **Connectivity:** Can you ping the printer IP?
* [ ] **Spooler:** Has the Print Spooler service been restarted on the server/client?

## 2. Network Connectivity Issues
**Symptom:** User cannot find printer or job sits in queue indefinitely.

**Steps:**
1.  **Verify IP Address:** Ensure the printer has a Static IP. Dynamic IPs cause disconnection upon lease renewal.
2.  **Ping Test:** `ping <printer_ip>`
3.  **Web Interface:** Attempt to access the printer's Web UI via a browser.
4.  **Firewall:** Ensure port 9100 (RAW) or 515 (LPR) is open between the subnet and printer VLAN.

## 3. Print Spooler Reset (Windows)
**Symptom:** Jobs are stuck in "Deleting" or "Spooling" status.

**Command Line Fix (Run as Admin):**
```powershell
net stop spooler
del /Q /F /S "%systemroot%\System32\Spool\Printers\*.*"
net start spooler
