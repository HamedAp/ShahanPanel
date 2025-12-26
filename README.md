 [![GitHub release (latest by date)](https://img.shields.io/github/v/release/HamedAp/Ssh-User-management)](https://github.com/HamedAp/Ssh-User-management/releases/latest) 
[![GitHub all releases](https://img.shields.io/github/downloads/HamedAp/Ssh-User-management/total?label=Last%20Version%20Downloads)](https://github.com/HamedAp/Ssh-User-management/releases/latest)


# ShahanPanel

[Persian Readme (راهنمای فارسی)](README.fa.md)

This is a comprehensive panel for managing SSH users, monitoring traffic, and configuring server settings. 🚀

## ✨ Features

- **👤 User Management:** Add, remove, and edit users.
- **📊 Traffic Monitoring:** Monitor the traffic of each user.
- **⚙️ Server Settings:** Configure server settings, such as the SSH port.
- **💾 Backup and Restore:** Backup and restore the database.
- **🔌 API:** A simple API for interacting with the panel.

## 📈 Dashboard

The dashboard provides a real-time overview of your server and user activity. It includes the following key sections:

- **👥 User Statistics:**
    - **Total Users:** The total number of user accounts in the system.
    - **Online Users:** The number of users currently connected to the server.
    - **Active Users:** The number of enabled user accounts.
    - **Deactivated Users:** The number of disabled or expired user accounts.
- **🖥️ Server Health Monitoring:**
    - **RAM Usage:** Displays the percentage of memory currently in use.
    - **CPU Usage:** Shows the current processor load.
    - **HDD Usage:** Indicates the amount of disk space used.
    - **Server Traffic:** Total data transferred (upload and download) by the server.
    - **Users Traffic:** Total data consumed by all users combined.
- **📋 Users List:** A detailed table of all users with the following information:
    - **Username & Password:** User credentials.
    - **Start & Finish Date:** The activation and expiration dates for the user's account.
    - **Contact Info:** Mobile number and email address.
    - **Referral:** Information on who referred the user.
    - **Traffic:** The user's assigned data limit and their current usage.
    - **Connection Status:** Shows how many devices are currently connected for a user out of their allowed limit.
    - **Account Status:** Indicates whether the account is active, inactive, or expired.
    - **Operations:** A set of actions you can perform for each user, such as editing, activating/deactivating, resetting traffic, deleting, and viewing connection QR codes.

## 🛠️ Settings

The settings page provides a centralized location for configuring the server and panel. It is organized into the following tabs:

- **🔑 Change Admin Password:** Allows you to update the administrator's password and set a new subdomain for the server.
- **🔌 Change Port:** Configure the connection ports for various services:
    - **SSH Port:** The primary port for SSH connections.
    - **UDP Port:** For UDP-based protocols, such as gaming or streaming.
    - **DropBear Port:** An alternative lightweight SSH server.
    - **Tuic Port:** For the TUIC protocol, designed to bypass censorship.
- **📤 Telegram Message:** Send a custom message to all users who have linked their Telegram accounts.
- **💾 Backup and Restore:** Manage your panel's data:
    - **Bot Token & Admin ID:** Configure your bot's credentials to enable notifications and user interactions.
    - **User Messages:** Customize automated messages for account renewals, traffic limits, and other events.
    - **Actions:** Test your bot's connection, fix webhook issues, and submit your configuration.
- **Backup and Restore:** Manage your panel's data:
    - **Upload Backup:** Restore the panel from a SQL, JSON, or sqlite3 file.
    - **New Backup:** Create a new backup of the current database.
    - **User Management:**
        - **Delete All Backups:** Permanently remove all saved backups.
        - **Delete All Users:** A quick way to clear all user accounts.
        - **Import Server Users:** Add existing system users to the panel.
    - **Backups List:** View, restore, delete, or download existing backup files.
- **API Token:** Manage access for external applications:
    - **Create New Token:** Generate a new API token and specify the allowed IP address and a description.
    - **Tokens List:** View, renew, or delete existing tokens.
- **Daily Gift:** Reward your users:
    - **Add Gift Days:** Extend the subscription for all users by a specified number of days.
    - **Add Gift Traffic:** Grant additional traffic to all users.
- **Expired Users:** Automatically manage user accounts by setting a time frame (in days) to remove users after their subscription has expired.
- **Connection Message:** Set a custom message that is displayed to users upon connecting to the server.
- **Auto Backup:** Schedule automatic backups of your panel's database at regular intervals (e.g., every 6 or 12 hours).
- **OpenVPN:** Configure the OpenVPN server settings, including the port and protocol (UDP or TCP).

## How to Use

### Creating a Single User

1. From the main dashboard, click the green **plus** icon to open the **Add New User** dialog.
2. Fill in the user's details, including their username, password, traffic limit, and subscription duration.
3. Click **Submit** to create the account.

### Creating Bulk Users

1. From the main dashboard, click the **group** icon to open the **Add Bulk Users** dialog.
2. Specify the number of users to create, a starting username, and password preferences.
3. Set the traffic limit and subscription duration that will apply to all new accounts.
4. Click **Submit** to generate the accounts.

### Renewing a User's Subscription

1. In the **Users List** on the dashboard, find the user you want to renew and click the **bolt** icon in the **Operations** column.
2. A dialog will appear with options to extend their subscription by one, two, three, or six months, or for a full year.
3. Select the desired duration to instantly renew the user's account.

## API

The panel has a simple API that you can use to interact with it. To use the API, you need to create an API token in the settings page.

## System Requirements

To run the SSH Panel, your server must meet the following requirements:

- **Operating System:** A Linux-based OS (Ubuntu).


## Installation

1. **One Click Installation:**
````
bash <(curl -Ls https://raw.githubusercontent.com/HamedAp/Ssh-User-management/master/install.sh --ipv4)
````

## Free vs. Pro Version

This panel offers both a free and a paid (Pro) version. While the free version provides essential user management and monitoring features, the Pro version unlocks advanced capabilities for more demanding environments.

## This Table Will Update :)
Protocol | Add | Delete | Online | Limit | Traffic | MultiSe... | Backup | API | Qrcode 
--- | --- | --- | --- |--- |--- |--- |--- |--- |--- 
SSh | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ 
DropBear | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ 
TUIC⭐️ | ✅ | ✅ | ⏳ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ 
Cisco⭐️ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | 
Openvpn⭐️ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | 
Shadowsocks⭐️ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ 
Singbox⭐️ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ 
WireGuard⭐️ | ✅ | ✅ | ✅ | ⏳ | ✅ | ⏳ | ✅ | ✅ |  ✅
Xray |  |  |  |  |  |  |  |  |  


### Free Version Features:

- **User Management:** Create, modify, and delete SSH users.
- **Traffic Monitoring:** Track data usage for each user.
- **Server Health:** Monitor CPU, RAM, and disk usage.
- **Manual Backups:** Create and restore database backups.

### Pro⭐️ Version Features (Requires License):

- **Advanced Protocols:**
    - **TUIC:** Create and manage users for the TUIC protocol to bypass censorship.
    - **WireGuard:** Full support for WireGuard users, including QR code configuration.
    - **ShadowSocks:** Easily create and manage ShadowSocks users.
- **Enhanced Configuration:**
    - **SingBox & Shahanak Support:** Generate QR codes for specialized client apps.
    - **OpenVPN:** Download user-specific OpenVPN configuration files.
- **Automated Backups:**
    - **Protocol Backups:** Back up configurations for TUIC, ShadowSocks, WireGuard, and OpenVPN.
    - **Scheduled Backups:** Set up automatic database backups at regular intervals.


### ScreenShot :


![](screenshot/login.png)
![](screenshot/index.png)
![](screenshot/status.png)
![](screenshot/filter.png)
![](screenshot/setting.png)

