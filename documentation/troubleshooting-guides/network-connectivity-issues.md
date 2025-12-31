# Troubleshooting Guide: General Network Connectivity

**Version:** 1.0
**Scope:** Diagnosis of LAN/WAN connectivity issues for servers and workstations.
**Methodology:** Bottom-Up (OSI Model Layer 1 to Layer 7).

---

## 1. Quick Triage (The "Is it just you?" Test)
Before diving deep, establish the scope.
* **Single Host:** Issue is likely local (cable, NIC, IP config).
* **Single Subnet:** Issue is likely the Switch or Gateway interface.
* **All Users:** Issue is the Core Router, Firewall, or ISP.

---

## 2. Layer 1 & 2: Physical & Data Link
**Symptom:** "Network Cable Unplugged" or no link lights.

### Diagnostic Steps
1.  **Check Link Status:**
    Linux: `ip link show dev eth0`
    Windows: `Get-NetAdapter | Select Name, Status, LinkSpeed`
    * *Look for state DOWN or LOWERLAYERDOWN.*

2.  **Check Interface Errors (CRC/Collisions):**
    High error counts indicate a bad cable or duplex mismatch.
    Linux: `ethtool -S eth0 | grep error`
    Windows: `netstat -e`

3.  **Verify MAC Address:**
    Ensure the device sees the gateway's MAC address in its ARP table.
    Command: `arp -a`
    * *If you can't see the Gateway MAC, Layer 2 is broken (VLAN mismatch or bad port).*

---

## 3. Layer 3: Network (IP & Routing)
**Symptom:** Link is up, but cannot reach the internet.

### Diagnostic Steps
1.  **Verify IP Configuration:**
    Ensure you have a valid IP, Subnet Mask, and Default Gateway.
    * *Warning:* If IP starts with `169.254.x.x` (APIPA), DHCP has failed.

2.  **Ping Test (The "Outward Spiral"):**
    Ping in this specific order to isolate the break:
    * 1. `ping 127.0.0.1` (Tests local TCP/IP stack)
    * 2. `ping <Local_IP>` (Tests NIC driver)
    * 3. `ping <Gateway_IP>` (Tests LAN connectivity)
    * 4. `ping 8.8.8.8` (Tests WAN/Routing)
    * 5. `ping google.com` (Tests DNS)

3.  **Trace the Route:**
    Find exactly where the packet dies.
    Linux: `mtr -rwc 10 8.8.8.8`
    Windows: `tracert -d 8.8.8.8` (The `-d` speeds it up by skipping DNS resolution)

---

## 4. Layer 4+: Transport & DNS
**Symptom:** "I can ping 8.8.8.8, but I can't browse to google.com."

### Diagnostic Steps
1.  **DNS Lookup Test:**
    Linux/Mac: `dig google.com` or `nslookup google.com`
    Windows: `nslookup google.com`
    * *Failure here means your DNS Server is down or unreachable.*

2.  **Port Connectivity (Firewall Check):**
    Can you actually reach the specific service port?
    * **Test Web (80/443):** `curl -I https://google.com`
    * **Test RDP (3389):** `Test-NetConnection -ComputerName <TargetIP> -Port 3389` (PowerShell)

---

## 5. Advanced: DHCP Troubleshooting
**Symptom:** User gets a 169.254.x.x address.

1.  **Release/Renew:**
    Windows: `ipconfig /release && ipconfig /renew`
    Linux: `sudo dhclient -r && sudo dhclient -v`
2.  **Check DHCP Server Availability:**
    If you have a static IP on the same subnet, try to ping the DHCP server.
3.  **DHCP Exhaustion:**
    Check the scope on the server. Are there available leases?

---

## 6. Cheat Sheet: Common Commands

| Action | Linux | Windows |
| :--- | :--- | :--- |
| **View IP** | `ip a` | `ipconfig /all` |
| **Show Route** | `ip route` | `route print` |
| **Show ARP** | `ip neigh` | `arp -a` |
| **Test Port** | `nc -vz <ip> <port>` | `Test-NetConnection <ip> -p <port>` |
| **Flush DNS** | `systemd-resolve --flush-caches` | `ipconfig /flushdns` |
Risk vs. Reward
Risk: Very Low. These are standard diagnostic commands.

Reward: High Efficiency. By following the "Outward Spiral" ping test (Local -> Gateway -> WAN -> DNS), you stop guessing and immediately pinpoint the broken link in the chain.

Next Steps
We have now generated the complete documentation suite:

Templates (Change Request, System Doc)

Configs (SSH, Bash)

Tools (Health Check, User Audit)

Troubleshooting (Printers, VoIP, AD, Network)

I am ready to generate the init_repo.sh script. This script will act as the "Installer," creating every single folder and file we have discussed, populating them with the content, and initializing the Git repository.
