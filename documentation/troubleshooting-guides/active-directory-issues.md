# Troubleshooting Guide: Active Directory (AD) & Domain Services

**Version:** 1.0
**Scope:** Diagnosis of Account Lockouts, Replication Failures, and Trust Relationship issues.
**Prerequisites:** All commands must be run as a Domain Administrator via PowerShell (Admin).

---

## 1. Top Issue: Account Lockouts
**Symptom:** User accounts repeatedly lock out immediately after unlocking.
**Root Cause:** Usually a mobile device with old credentials, a mapped drive, or a service account.

### Diagnostic Steps
1.  **Find Locked Accounts:**
    ```powershell
    Search-ADAccount -LockedOut | Select-Object Name, SamAccountName
    ```

2.  **Identify the Source (PDC Emulator):**
    Query the Security Event Log on the PDC Emulator for Event ID **4740**.
    ```powershell
    # Get the PDC Emulator
    $PDC = (Get-ADDomainController -Service PrimaryDC).Name
    
    # Search logs for the specific user (Replace 'jdoe')
    Get-WinEvent -ComputerName $PDC -FilterHashtable @{LogName='Security';ID=4740} | 
    Where-Object {$_.Properties[0].Value -match 'jdoe'} | 
    Select-Object TimeCreated, @{n='SourceWorkstation';e={$_.Properties[1].Value}}
    ```
    * **Action:** Go to the `SourceWorkstation` identified and clear cached credentials (Credential Manager) or update the service password.

---

## 2. Replication Failures
**Symptom:** Changes made on one Domain Controller (DC) do not appear on others. Group Policy fails to update.

### Diagnostic Steps
1.  **Check Replication Status:**
    ```cmd
    repadmin /showrepl /csv > c:\temp\replreport.csv
    ```
    *Review the CSV for any status other than "0" (Success).*

2.  **Force Replication (Sync All):**
    If a specific DC is out of sync, force a push.
    ```cmd
    repadmin /syncall /A /e /P
    ```

3.  **Check for "Tombstoned" Objects:**
    If a DC has been offline longer than the Tombstone Lifetime (usually 180 days), **DO NOT** reconnect it. It must be demoted and re-promoted to avoid lingering object corruption.

---

## 3. Domain Controller Health (DCDIAG)
**Symptom:** Slow logins, weird DNS errors, or Group Policy processing failures.

### Diagnostic Steps
Run the master diagnostic tool.
```cmd
dcdiag /v /c /d /e /s:%computername% > c:\temp\dcdiag.log
Search the log for "FAIL".

Common Fail: Advertising (DC is not announcing itself).

Common Fail: NetLogon (SYSVOL share is missing/broken).

4. Trust Relationship & Secure Channel
Symptom: "The trust relationship between this workstation and the primary domain failed." User cannot login.

Diagnostic Steps
Verify the Secure Channel: Run this on the affected workstation (locally):

PowerShell

Test-ComputerSecureChannel -Verbose
Repair the Channel: If the above returns False, repair it without unjoining/rejoining the domain (requires local admin & domain creds).

PowerShell

Test-ComputerSecureChannel -Repair -Credential (Get-Credential)
5. DNS: The Root of All Evil
Rule: 99% of AD issues are actually DNS issues.

Diagnostic Steps
Verify SRV Records: Ensure the DC is publishing its Service Records so clients can find it.

DOS

nslookup -type=SRV _ldap._tcp.dc._msdcs.yourdomain.com
Check DNS Scavenging: If you see hundreds of stale records, ensure DNS Scavenging is enabled on one DC only to prevent record deletion conflicts.

6. Disaster Recovery: FSMO Roles
If a DC dies permanently, you must know where the FSMO roles reside to seize them.

PowerShell

Get-ADDomain | Select-Object InfrastructureMaster, RIDMaster, PDCEmulator
Get-ADForest | Select-Object DomainNamingMaster, SchemaMaster

---

### Risk vs. Reward

* **Risk:** Medium. Running `repadmin /syncall` on a broken network can propagate corrupt data if not careful. The guide emphasizes checking status (`/showrepl`) *before* forcing action.
* **Reward:** Extreme. A consulting engineer charges $200+/hour to fix AD replication or lockouts. With these scripts, you can diagnose the issue in 60 seconds.

### Next Steps

You now have the "Holy Trinity" of troubleshooting: **Printers, VoIP, and Active Directory**.

There is **one final directory** mentioned in your initial prompt that we haven't touched: **`SysAdmin-Toolkit/reports`** (specifically the structure or logic for it, beyond just the folder). Or, if you are satisfied with the current file set, we can proceed to the **Initialization Script**.

**What is your preference?**
1.  Generate `init_repo.sh` to build everything now.
2.  Add one more specific troubleshooting guide (e.g., `vpn-connectivity.md` or `disk-space-cleanup
