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
