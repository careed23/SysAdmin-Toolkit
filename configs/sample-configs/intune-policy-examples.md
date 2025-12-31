# Microsoft Intune (Endpoint Manager) Policy Standards

**Scope:** Cloud-Managed / Hybrid Joined Devices (Windows 10/11)
**Philosophy:** "Zero Trust" (Verify explicitly).

---

## 1. Compliance Policies
*If a device fails these, it is blocked from Email/Teams via Conditional Access.*

* **Require BitLocker:** `Required` (Data must be encrypted).
* **Require Secure Boot:** `Required`.
* **Minimum OS Version:** `Windows 10 22H2` (Force updates).
* **Firewall:** `Required`.
* **Antivirus:** `Required` (Must have Real-time protection enabled).

---

## 2. Endpoint Security Profiles (The "Antivirus")

### A. Attack Surface Reduction (ASR) Rules
*The most underrated security feature in Windows.*
* **Block executable content from email client and webmail:** `Block`
* **Block Office applications from creating child processes:** `Block` (Stops Word -> PowerShell malware).
* **Block credential stealing from the Windows local security authority subsystem (lsass.exe):** `Block`

### B. Disk Encryption (BitLocker)
* **Encryption Method:** `XTS-AES 256-bit`.
* **Removable Drives:** `Allow` but `Require Encryption` (No Write access unless encrypted).
* **Key Recovery:** Backup to Azure AD (Entra ID).

---

## 3. Configuration Profiles (The "Settings")

### A. Windows Updates for Business (WUfB)
* **Service Channel:** `General Availability Channel`.
* **Quality Update Deferral:** `7 Days` (Ring 1).
* **Feature Update Deferral:** `30 Days`.
* **User Experience:** `Auto install at maintenance time`, `Notify download`.

### B. WiFi & VPN
* **WiFi Profile:** Push SSID `Corp-Secure` and WPA2/3 Enterprise certs automatically.
* **VPN:** Always On VPN configuration.

---

## 4. Administrative Templates (Cloud GPO)
* **OneDrive Known Folder Move (KFM):** Silently move Desktop/Documents/Pictures to OneDrive. (Backup strategy).
* **Disable Fast User Switching:** Reduces resource load on shared kiosks.
Risk vs. Reward
Risk: GPO "Tattooing". Poorly written GPOs can leave settings permanently on a machine even after the policy is removed. Mitigation: Always use "Policies" (Registry keys that reset) rather than "Preferences" (Registry keys that stick) whenever possible.

Reward: Zero-Touch Onboarding. With the Intune policies above (Autopilot), you can hand a shrink-wrapped laptop to a user, they sign in with WiFi, and within 30 minutes, it is encrypted, patched, and secured without you touching it.

Quick Add Commands
Run these to create the files instantly:

Bash

# Create Group Policy Examples
cat << 'EOF' > SysAdmin-Toolkit/documentation/best-practices/group-policy-examples.md
# GPO Standards
## Security
* **Disable NTLMv1:** Send NTLMv2 response only.
* **LAPS:** Mandatory for local admins.
* **AppLocker:** Block .exe in AppData.

## UX
* **Drive Maps:** Use 'Replace' action.
* **Browser:** Force install Password Manager extension.
EOF

# Create Intune Examples
cat << 'EOF' > SysAdmin-Toolkit/documentation/best-practices/intune-policy-examples.md
# Intune Standards
## Compliance
* **BitLocker:** Required.
* **Antivirus:** Required.

## Attack Surface Reduction (ASR)
* Block Office child processes.
* Block credential stealing from LSASS.

## Windows Updates
* Quality Updates: Defer 7 days.
* Feature Updates: Defer 30 days.
EOF
