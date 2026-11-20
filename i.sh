#!/bin/bash
store_recovery_password() {
    local new_password="$1" password_file_tmp
    password_file_tmp=$(mktemp /root/.shahanpanel-admin-password.XXXXXX) || return 1
    umask 077
    if ! printf '%s' "$new_password" > "$password_file_tmp" || ! chown root:root "$password_file_tmp" || ! chmod 600 "$password_file_tmp" || ! mv -f "$password_file_tmp" /root/.shahanpanel-admin-password; then
        rm -f "$password_file_tmp"
        return 1
    fi
}
INSTALL_URL=""
INSTALL_VERSION=""
if [[ $# -eq 1 && "$1" == "--help" ]]; then
    echo "Usage: bash install.sh [release-version]"
    echo "       bash install.sh --url https://host/path/archive.zip"
    echo "       sudo bash install.sh --set-admin-password"
    echo "       sudo bash install.sh --show-admin-password"
    exit 0
elif [[ $# -eq 1 && "$1" == "--set-admin-password" ]]; then
    if [[ "$EUID" -ne 0 ]]; then
        echo "Run this command as root: sudo bash install.sh --set-admin-password" >&2
        exit 1
    fi
    read -r -s -p "New admin password (8-128 characters): " new_admin_password
    printf '\n'
    if [[ ${#new_admin_password} -lt 8 || ${#new_admin_password} -gt 128 || "$new_admin_password" == *$'\n'* || "$new_admin_password" == *$'\r'* ]]; then
        echo "Password must be 8-128 characters on one line." >&2
        exit 2
    fi
    if ! printf '%s' "$new_admin_password" | php -r '
$newPassword = stream_get_contents(STDIN);
if (strlen($newPassword) < 8 || strlen($newPassword) > 128) exit(2);
require "/var/www/html/p/config.php";
$stmt = $conn->prepare("UPDATE setting SET adminpassword=? WHERE id=1");
if (!$stmt) exit(3);
$stmt->bind_param("s", $newPassword);
$ok = $stmt->execute() && $stmt->affected_rows === 1;
$stmt->close();
$conn->close();
exit($ok ? 0 : 4);
'; then
        echo "Could not update the admin password in the panel database." >&2
        exit 1
    fi
    if ! store_recovery_password "$new_admin_password"; then
        echo "Password changed, but secure recovery storage failed." >&2
        exit 1
    fi
    unset new_admin_password
    echo "Admin password changed and saved in root-only recovery storage."
    exit 0
elif [[ $# -eq 1 && "$1" == "--show-admin-password" ]]; then
    if [[ "$EUID" -ne 0 ]]; then
        echo "Run this command as root: sudo bash install.sh --show-admin-password" >&2
        exit 1
    fi
    password_file=/root/.shahanpanel-admin-password
    if [[ ! -f "$password_file" || ! -r "$password_file" || "$(stat -c '%u' "$password_file" 2>/dev/null)" != "0" ]]; then
        echo "No recoverable admin password is stored. Hashed passwords cannot be decoded." >&2
        exit 1
    fi
    password_mode=$(stat -c '%a' "$password_file") || exit 1
    if (( 8#$password_mode & 077 )); then
        echo "Stored password file permissions are unsafe; refusing to display it." >&2
        exit 1
    fi
    cat -- "$password_file"
    exit 0
elif [[ $# -eq 2 && "$1" == "--url" ]]; then
    INSTALL_URL=$2
    if [[ ! "$INSTALL_URL" =~ ^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?/.+\.zip([?#].*)?$ ]]; then
        echo "Usage: bash install.sh --url https://host/path/archive.zip" >&2
        exit 2
    fi
elif [[ $# -eq 1 && "$1" != "--url" ]]; then
    INSTALL_VERSION=$1
    if [[ ! "$INSTALL_VERSION" =~ ^[A-Za-z0-9._-]{1,64}$ ]]; then
        echo "Invalid release version." >&2
        exit 2
    fi
elif [[ $# -ne 0 ]]; then
    echo "Usage: bash install.sh [release-version] | bash install.sh --url https://host/path/archive.zip" >&2
    exit 2
fi

update_install_info() {
    local newtext="$1"
    touch "/tmp/last_text.txt"
    if [ -f "/tmp/last_text.txt" ]; then
        lasttext=$(cat /tmp/last_text.txt)
    else
        lasttext=""
    fi
    clear
    if [ -n "$lasttext" ]; then
        echo -e "$lasttext"
        echo "----------------"
    fi
    echo "$newtext" >> /tmp/last_text.txt
    tmpfile=$(mktemp)
    awk '!seen[$0]++' /tmp/last_text.txt > "$tmpfile" && mv "$tmpfile" /tmp/last_text.txt
}
red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'
###############################################
echo "#shahanDNS
nameserver 8.8.8.8" > /etc/resolv.conf
update_install_info "Load Startup Items"
update_install_info "ShaHaN Panel Installation :) By HamedAp"
update_install_info "Please Wait . . ."
printshahan() {
    text="$1"
    delay="$2"
    for ((i=0; i<${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep $delay
    done
    echo
}
function isRoot() {
	if [ "$EUID" -ne 0 ]; then
		return 1
	fi
}
if ! isRoot; then
	echo "Sorry, you need to run this as root"
	exit 1
fi
export PATH=$PATH:/usr/local/bin
panelporttmp=$(sudo lsof -i -P -n | grep -i LISTEN | grep apache2 | awk '{if(!seen[$9]++)print $9;exit}')
panelportt=$(echo $panelporttmp | sed 's/[^0-9]*//g' )
sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config
po=$(cat /etc/ssh/sshd_config | grep "^Port")
port=$(echo "$po" | sed "s/Port //g")
adminuser=$(mysql -N -e "use ShaHaN; select adminuser from setting where id='1';")
adminpass=$(mysql -N -e "use ShaHaN; select adminpassword from setting where id='1';")
previous_admin_password_display=$adminpass
previous_admin_password_available=1
stored_admin_password_is_hash=0
if [[ "$adminpass" =~ ^\$2[aby]\$ || "$adminpass" =~ ^\$argon2(id|i)\$ ]]; then
    # Password hashes cannot be converted back to the login password. Ask for
    # a new one so the installer never prints a hash as if it were usable.
    stored_admin_password_is_hash=1
    previous_admin_password_available=0
    previous_admin_password_display=""
    adminpass=""
fi
sudo wget -q -4 -O /usr/local/bin/shahan https://raw.githubusercontent.com/HamedAp/Ssh-User-management/main/screenshot/shahan &
wait
sudo chmod a+rx /usr/local/bin/shahan
clear
sudo wget -q -4 -O /usr/local/bin/shahancheck https://raw.githubusercontent.com/HamedAp/Ssh-User-management/main/screenshot/shahancheck &
wait
sudo chmod a+rx /usr/local/bin/shahancheck
clear
sudo wget -q -4 -O /root/wg.sh.x https://shahanpanel.com/wg.sh.x &
wait
sudo chmod a+rx /root/wg.sh.x
clear
sudo wget -q -4 -O /root/shadow.sh.x https://github.com/HamedAp/Ssh-User-management/raw/main/shadow.sh.x &
wait
sudo chmod a+rx /root/shadow.sh.x
clear
sudo wget -q -4 -O /root/signbox.sh.x https://github.com/HamedAp/Ssh-User-management/raw/main/signbox.sh.x &
wait
sudo chmod a+rx /root/signbox.sh.x
clear
sudo wget -q -4 -O /root/updatesignbox.sh.x https://github.com/HamedAp/Ssh-User-management/raw/main/updatesignbox.sh.x &
wait
sudo chmod a+rx /root/updatesignbox.sh.x
clear
if grep -q -E '^shahansources$' /etc/apt/sources.list; then
    echo "all good, do nothing";
else
sudo sed -i '/shahansources/d' /etc/apt/sources.list 
sudo sed -i '/ubuntu focal main restricted universe/d' /etc/apt/sources.list 
sudo sed -i '/ubuntu focal-updates main restricted universe/d' /etc/apt/sources.list 
sudo sed -i '/ubuntu focal-security main restricted universe multiverse/d' /etc/apt/sources.list 
sudo sed -i '/ubuntu focal partner/d' /etc/apt/sources.list 
echo "#shahansources
deb http://archive.ubuntu.com/ubuntu focal main restricted universe
deb http://archive.ubuntu.com/ubuntu focal-updates main restricted universe
deb http://security.ubuntu.com/ubuntu focal-security main restricted universe multiverse
deb http://archive.canonical.com/ubuntu focal partner" >> /etc/apt/sources.list
fi
sudo sed -i 's/^session.gc_maxlifetime = .*/session.gc_maxlifetime = 86400/' /etc/php/8.1/apache2/php.ini
clear
echo ""
printshahan "ShaHaN Panel Installation :) By HamedAp" 0.1
echo ""
echo ""
printshahan "Please Wait . . ." 0.1
echo ""
echo ""
if [ -n "$adminuser" ] && [ -n "$adminpass" ]; then
adminusername=$adminuser
adminpassword=$adminpass
else
adminusername=${adminuser:-admin}
if [[ -z "$adminuser" ]]; then
    echo -e "\nPlease input Panel admin user."
    printf "Default user name is \e[33m${adminusername}\e[0m, let it blank to use this user name: "
    read usernametmp
    if [[ -n "${usernametmp}" ]]; then
        adminusername=${usernametmp}
    fi
fi
if [[ "$stored_admin_password_is_hash" -eq 1 ]]; then
    echo -e "\nThe saved administrator password is hashed and cannot be recovered. Set a new login password."
fi
adminpassword=$(openssl rand -hex 16)
echo -e "\nPlease input Panel admin password."
printf "Default password is \e[33m${adminpassword}\e[0m, let it blank to use this password : "
read passwordtmp
if [[ -n "${passwordtmp}" ]]; then
    adminpassword=${passwordtmp}
fi
fi
if [[ ! "$adminusername" =~ ^[A-Za-z0-9_]{1,30}$ ]]; then
    echo "Invalid panel administrator username. Use 1-30 letters, digits, or underscores."
    exit 1
fi
if [[ ${#adminpassword} -lt 8 || ${#adminpassword} -gt 128 || "$adminpassword" == *$'\n'* || "$adminpassword" == *$'\r'* ]]; then
    echo "Invalid panel administrator password. Use 8-128 characters on one line."
    exit 1
fi
file=/etc/systemd/system/videocall.service
if [ -e "$file" ]; then
    echo ""
else
udpport=7300
fi
sql_escape() {
    local escaped=${1//\\/\\\\}
    escaped=${escaped//\'/\'\'}
    printf '%s' "$escaped"
}
adminusername_sql=$(sql_escape "$adminusername")
adminpassword_sql=$(sql_escape "$adminpassword")
ipv4=$(curl -s ipv4.icanhazip.com)
sudo sed -i '/www-data/d' /etc/sudoers &
wait
sudo sed -i '/apache/d' /etc/sudoers & 
wait
sed -i 's@#Banner none@Banner /var/www/html/p/banner.txt@' /etc/ssh/sshd_config
sed -i 's@#PrintMotd yes@PrintMotd yes@' /etc/ssh/sshd_config
sed -i 's@#PrintMotd no@PrintMotd yes@' /etc/ssh/sshd_config
if command -v apt-get >/dev/null; then
update_install_info "${green}Update And Upgrade Finished $plain"
apt update -y
rm -fr /etc/php/7.4/apache2/conf.d/00-ioncube.ini
sudo apt -y install software-properties-common
sudo apt install ca-certificates apt-transport-https qrencode -y
apt install shc gcc -y
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo add-apt-repository ppa:ondrej/php -y
apt install apache2 zip unzip net-tools curl mariadb-server iptables-persistent vnstat -y
apt install jq cpulimit -y
update_install_info "${green}Apache And Database Installed $plain"
apt  install php8.1-sqlite3 -y
string=$(php -v)
if [[ $string == *"8.1"* ]]; then
apt autoremove -y
  echo "PHP Is Installed :)"
else
apt remove php7* -y &
wait
apt remove php* -y
apt remove php -y
apt autoremove -y
apt install php8.1 php8.1-mysql php8.1-xml php8.1-curl cron -y
fi
sudo apt install  php8.1-mbstring -y
update_install_info "${green}PHP8.1 Installed $plain"
if [[ -n "$INSTALL_URL" ]]; then
    link=$INSTALL_URL
elif [[ -n "$INSTALL_VERSION" ]]; then
    lastzip=${INSTALL_VERSION//./}
    link="https://github.com/HamedAp/Ssh-User-management/releases/download/$INSTALL_VERSION/$lastzip.zip"
else
    release_json=$(curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --max-time 30 "https://api.github.com/repos/HamedAp/Ssh-User-management/releases/latest") || exit 1
    link=$(printf '%s' "$release_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); assets=[a.get("browser_download_url","") for a in d.get("assets",[]) if a.get("name","").lower().endswith(".zip")]; print(assets[0] if assets else "")')
    if [[ ! "$link" =~ ^https:// ]]; then
        echo "Could not find a HTTPS ZIP asset in the latest release." >&2
        exit 1
    fi
fi

archive_path=$(mktemp /var/tmp/shahan-panel-install.XXXXXX.zip) || exit 1
extract_dir=$(mktemp -d /var/tmp/shahan-panel-extract.XXXXXX) || { rm -f "$archive_path"; exit 1; }
if ! curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --max-time 300 --max-filesize 536870912 -o "$archive_path" "$link"; then
    rm -rf "$extract_dir" "$archive_path"
    echo "Could not download the panel ZIP." >&2
    exit 1
fi
archive_size=$(stat -c '%s' "$archive_path")
if [[ ! "$archive_size" =~ ^[0-9]+$ || "$archive_size" -gt 536870912 ]]; then
    rm -rf "$extract_dir" "$archive_path"
    echo "Downloaded ZIP exceeds the 512 MiB limit." >&2
    exit 1
fi
if ! python3 - "$archive_path" "$extract_dir" <<'PY'
import os, pathlib, stat, sys, zipfile

archive, destination = sys.argv[1:]
root = pathlib.Path(destination).resolve()
total = 0
with zipfile.ZipFile(archive) as bundle:
    entries = bundle.infolist()
    if not entries or len(entries) > 50000:
        raise SystemExit("Invalid ZIP: empty archive or too many entries")
    for entry in entries:
        name = entry.filename
        path = pathlib.PurePosixPath(name)
        mode = (entry.external_attr >> 16) & 0o170000
        if (not name or "\\" in name or name.startswith("/") or path.is_absolute()
                or ".." in path.parts or not path.parts
                or mode not in (0, stat.S_IFREG, stat.S_IFDIR)):
            raise SystemExit("Invalid ZIP entry path or file type")
        total += entry.file_size
        if total > 2 * 1024 * 1024 * 1024:
            raise SystemExit("ZIP expanded size exceeds 2 GiB")
        target = root.joinpath(*path.parts)
        if os.path.commonpath((str(root), str(target.resolve()))) != str(root):
            raise SystemExit("ZIP entry escapes extraction directory")
        if entry.is_dir():
            target.mkdir(parents=True, exist_ok=True, mode=0o755)
        else:
            target.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
            with bundle.open(entry) as source, open(target, "xb") as output:
                while True:
                    chunk = source.read(1024 * 1024)
                    if not chunk:
                        break
                    output.write(chunk)
    if bundle.testzip() is not None:
        raise SystemExit("ZIP integrity check failed")

if not (root / "p" / "config.php").is_file() or not (root / "p" / "restoretarikh.php").is_file():
    raise SystemExit("ZIP does not contain the expected panel files")
PY
then
    rm -rf "$extract_dir" "$archive_path"
    echo "The downloaded ZIP failed validation." >&2
    exit 1
fi
cp -a "$extract_dir"/. /var/www/html/ || { rm -rf "$extract_dir" "$archive_path"; exit 1; }
rm -rf "$extract_dir" "$archive_path"
# Apache must be able to traverse the web-root directories and read each
# .htaccess file. Keep code files root-owned; only set traversal/read modes.
chmod 755 /var/www /var/www/html /var/www/html/p || exit 1
find /var/www/html -maxdepth 2 -type f -name .htaccess -exec chmod 644 {} \; || exit 1
update_install_info "${green}Panel Source Downloaded And Validated $plain"
update_install_info "${green}Unzip Finished $plain"
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/bin/systemctl restart s-box.service' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/php-cgi' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/etc/init.d/shadowsocks' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/sbin/sshd' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/sbin/adduser' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/sbin/useradd' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/sbin/userdel' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/sed' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/cat' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/passwd' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/curl' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/kill' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/killall' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/pkill' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/lsof' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/sbin/lsof' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/sed' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/rm' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/crontab' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/mysqldump' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/pgrep' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/sbin/nethogs' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/nethogs' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/local/sbin/nethogs' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/netstat' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/bin/systemctl restart sshd' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/bin/systemctl restart videocall' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/bin/systemctl restart dropbear' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/bin/systemctl daemon-reload' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/bin/systemctl restart syslog' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/local/bin/ocpasswd' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/local/bin/occtl' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/sbin/iptables' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/sbin/nft' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/sbin/iptables-save' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/bin/systemctl restart tuic' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/uuidgen' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/who' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD: /usr/local/sbin/shahan-save-firewall' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/vnstat' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/bin/ovpm' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/bin/ovpm' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/bin/systemctl restart shahanguard' | sudo EDITOR='tee -a' visudo &
wait
echo 'www-data ALL=(ALL:ALL) NOPASSWD:/usr/local/bin/shahanguard' | sudo EDITOR='tee -a' visudo &
wait
sudo sed -i '/%sudo/s/^/#/' /etc/sudoers &
wait
echo "application/json      json" >> /etc/mime.types
update_install_info "${green}Permission Granted To Apache $plain"
sed -i 's/^memory_limit = .*/memory_limit = 512M/' /etc/php/8.1/apache2/php.ini
grep '^memory_limit' /etc/php/8.1/apache2/php.ini
sudo service apache2 restart
touch /var/www/html/p/banner.txt
chown -R www-data:www-data /var/www/html/* &
wait
mkdir /var/www/config/
chown www-data:www-data /var/www/config &
wait
systemctl restart mariadb &
wait
systemctl enable mariadb &
wait
sudo phpenmod curl
PHP_INI=$(php -i | grep /.+/php.ini -oE)
sed -i 's/extension=intl/;extension=intl/' ${PHP_INI}
IonCube=$(php -v)
if [[ $IonCube == *"PHP Loader v13"* ]]; then
  echo "IonCube Is Installed :)"
else
sed -i 's@zend_extension = /usr/local/ioncube/ioncube_loader_lin_8.1.so@@' /etc/php/8.1/cli/php.ini
bash <(curl -Ls https://raw.githubusercontent.com/HamedAp/ioncube-loader/main/install.sh --ipv4)
fi
update_install_info "${green}Php Ioncube Installed $plain"
Nethogs=$(nethogs -V)
if [[ $Nethogs == *"version 0.8.8"* ]]; then
  echo "Nethogs Is Installed :)"
else
bash <(curl -Ls https://raw.githubusercontent.com/HamedAp/Nethogs-Json/main/install.sh --ipv4)
fi
update_install_info "${green}Nethogs Installed $plain"
file=/etc/systemd/system/videocall.service
if [ -e "$file" ]; then
    echo "SSH-CALLS exists"
else
apt install git cmake -y
git clone https://github.com/ambrop72/badvpn.git /root/badvpn
mkdir /root/badvpn/badvpn-build
cd  /root/badvpn/badvpn-build
cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 &
wait
make &
wait
cp udpgw/badvpn-udpgw /usr/local/bin
cat >  /etc/systemd/system/videocall.service << ENDOFFILE
[Unit]
Description=UDP forwarding for badvpn-tun2socks
After=nss-lookup.target
[Service]
ExecStart=/usr/local/bin/badvpn-udpgw --loglevel none --listen-addr 127.0.0.1:$udpport --max-clients 999
User=videocall
[Install]
WantedBy=multi-user.target
ENDOFFILE
useradd -m videocall
systemctl enable videocall
systemctl start videocall
update_install_info "${green}SSH Calls Installed $plain"
fi
mysql -e "drop USER IF EXISTS '${adminusername_sql}'@'localhost'" &
wait
mysql -e "create database ShaHaN;" &
wait
mysql -e "CREATE USER '${adminusername_sql}'@'localhost' IDENTIFIED BY '${adminpassword_sql}';" &
wait
mysql -e "GRANT ALL ON *.* TO '${adminusername_sql}'@'localhost';" &
wait
sudo sed -i "s/22/$port/g" /var/www/html/p/config.php &
wait 
dbconfig_json=$(jq -n --arg username "$adminusername" --arg password "$adminpassword" --arg database "ShaHaN" '{host:"localhost",username:$username,password:$password,database:$database}') || exit 1
printf '%s' "$dbconfig_json" | php -r '
$settings = json_decode(stream_get_contents(STDIN), true);
if (!is_array($settings) || !isset($settings["username"], $settings["password"], $settings["database"])) exit(1);
$path = "/etc/shahanpanel/database.php";
$directory = dirname($path);
if (!is_dir($directory) && !mkdir($directory, 0750, true)) exit(1);
$temporary = tempnam($directory, ".database-");
if ($temporary === false) exit(1);
$contents = "<?php\nreturn " . var_export($settings, true) . ";\n";
if (file_put_contents($temporary, $contents, LOCK_EX) === false || !chmod($temporary, 0640) || !chown($temporary, 0) || !chgrp($temporary, "www-data") || !rename($temporary, $path)) {
    @unlink($temporary);
    exit(1);
}
' || { echo "Could not write protected database configuration."; exit 1; }
sed -i '/panelport/d' /var/www/html/p/config.php
cat >>  /var/www/html/p/config.php << ENDOFFILE
\$panelport = "$panelportt";
ENDOFFILE
mysql -e "use ShaHaN;update users set userport='' where userport like '39%';" &
wait
mysql -e "use ShaHaN;update users set userport='' where userport like '41%';" &
wait
php /var/www/html/p/restoretarikh.php
mysql --protocol=socket -uroot ShaHaN -e "UPDATE setting SET adminpassword='${adminpassword_sql}' WHERE adminuser='${adminusername_sql}' LIMIT 1;" || exit 1
store_recovery_password "$adminpassword" || exit 1
rm -fr /var/www/html/update.zip
update_install_info "${green}Database Created $plain"
nowdate=$(date +"%Y-%m-%d-%H-%M-%S")
mysqldump -u root ShaHaN > /var/www/html/p/backup/${nowdate}-update.sql
update_install_info "${green}Create Database Backup $plain"
rnd=$(shuf -i 1-59 -n 1)
crontab -l | grep -v '/p/expire.php'  | crontab  -
crontab -l | grep -v '/p/apptraffic.php'  | crontab  -
crontab -l | grep -v '/p/posttraffic.php'  | crontab  -
crontab -l | grep -v '/p/synctraffic.php'  | crontab  -
crontab -l | grep -v '/p/tgexpire.php'  | crontab  -
crontab -l | grep -v 'p/killusers.sh'  | crontab  -
crontab -l | grep -v '/p/log/log.sh'  | crontab  -
crontab -l | grep -v 'p/versioncheck.php'  | crontab  -
crontab -l | grep -v 'p/plugins/check.php'  | crontab  -
crontab -l | grep -v 'p/autoupdate.php'  | crontab  -
crontab -l | grep -v 'p/checkipauto.php'  | crontab  -
crontab -l | grep -v 'ocserv'  | crontab  -
crontab -l | grep -v 'tuic'  | crontab  -
crontab -l | grep -v 'HamedAp/Ssh-User-management/master/install.sh'  | crontab  -
crontab -l | grep -v '/p/checkipauto.php'  | crontab  -
crontab -l | grep -v '/p/log/clear.sh'  | crontab  -
(crontab -l ; echo "5 * * * * php /var/www/html/p/versioncheck.php >/dev/null 2>&1
* * * * * php /var/www/html/p/expire.php >/dev/null 2>&1
0 4 * * * php /var/www/html/p/apptraffic.php >/dev/null 2>&1
0 0 * * * php /var/www/html/p/tgexpire.php >/dev/null 2>&1
* * * * * php /var/www/html/p/posttraffic.php >/dev/null 2>&1
* * * * * bash /var/www/html/p/killusers.sh >/dev/null 2>&1
* * * * * bash /var/www/html/p/log/log.sh >/dev/null 2>&1
*/5 * * * * bash /var/www/html/p/log/clear.sh >/dev/null 2>&1" ) | crontab - &
wait
sudo timedatectl set-timezone Asia/Tehran
chmod 0646 /var/log/auth.log
update_install_info "${green}Cronjob Set $plain"
if  grep -q "Apache2 Ubuntu Default Page" "/var/www/html/index.html" ; then
cat >  /var/www/html/index.html << ENDOFFILE
<meta http-equiv="refresh" content="0;url=https://zula.ir/" />
ENDOFFILE
fi
rm -fr /var/www/html/h.apk
sudo sed -i 's/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf
systemctl restart apache2
elif command -v yum >/dev/null; then
echo "Only Ubuntu Supported"
fi
cat >  /usr/local/bin/listen << ENDOFFILE
sudo lsof -i -P -n | grep -E '(LISTEN|UDP.*:)'
ENDOFFILE
sudo chmod a+rx /usr/local/bin/listen

cat > /usr/local/sbin/shahan-save-firewall <<'EOF'
#!/bin/sh
set -eu
/usr/sbin/iptables-save > /etc/iptables/rules.v4
/usr/sbin/ip6tables-save > /etc/iptables/rules.v6
EOF
chown root:root /usr/local/sbin/shahan-save-firewall
chmod 0755 /usr/local/sbin/shahan-save-firewall
touch /var/www/shahanak.txt
touch /var/www/dropport.txt
touch /var/www/cisco.txt
touch /var/www/userlog.txt
sudo chmod 646 /var/www/shahanak.txt
sudo chmod 646 /var/www/dropport.txt
sudo chmod 646 /var/www/cisco.txt
sudo chmod 646 /var/www/userlog.txt
sudo chmod 646 /etc/default/dropbear
touch /etc/ocserv/ocpasswd
echo "
Include "/var/www/banner.conf"
" >> /etc/ssh/sshd_config
sed -i '/Match User/d' /etc/sshd/sshd_config
sed -i '/Banner /d' /etc/sshd/sshd_config
JAILPATH='/jailed'
mkdir -p $JAILPATH
if ! getent group jailed > /dev/null 2>&1
then
  echo "creating jailed group"
  groupadd -r jailed
fi
if ! grep -q "Match group jailed" /etc/ssh/sshd_config
then
  echo "Users Limited From SSH Login"
  echo "
Match group jailed
ForceCommand /bin/false
" >> /etc/ssh/sshd_config
fi
update_install_info "${green}Security Patched $plain"
sudo sed -i '/AllowTCPForwarding no/d' /etc/ssh/sshd_config &
wait
sudo sed -i 's@ChrootDirectory /jailed@ForceCommand /bin/false@' /etc/ssh/sshd_config &
wait
sudo sed -i '/X11Forwarding no/d' /etc/ssh/sshd_config &
wait
systemctl restart sshd
apt install php8.1-cgi -y
apt install php8.1-sqlite3 -y
rm -fr /var/log/shadowsocks.log
sudo /etc/init.d/shadowsocks restart
sudo tee /etc/sysctl.d/99-ssh-vpn-buffers.conf >/dev/null <<'EOF'
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOF
sudo sysctl --system


for sapi in apache2 cgi; do
    sapi_conf="/etc/php/8.1/${sapi}/conf.d"
    if [ -d "$sapi_conf" ]; then
        printf '%s\n' 'session.upload_progress.enabled=0' > "$sapi_conf/99-security-session-upload-progress.ini"
    fi
done
sudo service apache2 restart

clear
printf "%s" "$(</var/www/html/shahan.txt)"
Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Font_color_suffix="\033[0m"
IonCube=$(php -v)
if [[ $IonCube == *"PHP Loader v13"* ]]; then
  echo -e "\n${Green_font_prefix}IonCube Is Installed${Font_color_suffix}"
else
echo -e "\n${Red_font_prefix}IonCube Is NOT Installed${Font_color_suffix}"
fi
Nethogs=$(nethogs -V)
if [[ $Nethogs == *"version 0.8.8"* ]]; then
  echo -e "\n${Green_font_prefix}Nethogs Is Installed${Font_color_suffix}"
else
echo -e "\n${Red_font_prefix}Nethogs Is NOT Installed${Font_color_suffix}"
fi
string=$(php -v)
if [[ $string == *"8.1"* ]]; then
  echo -e "\n${Green_font_prefix}PHP8.1 Is Installed${Font_color_suffix}"
else
echo -e "\n${Red_font_prefix}PHP8.1 Is NOT Installed${Font_color_suffix}"
fi
if [ -e "$file" ]; then
echo -e "\n${Green_font_prefix}SSH-Calls Is Installed${Font_color_suffix}"
else
echo -e "\n${Red_font_prefix}SSH-Calls Is NOT Installed${Font_color_suffix}"
fi
printf "\n\n\nPanel Link : http://${ipv4}/p"
printf "\nUserName : \e[31m${adminusername}\e[0m "
if [[ "$previous_admin_password_available" -eq 1 && -n "$previous_admin_password_display" ]]; then
    printf "\nPrevious Password : \e[31m%s\e[0m " "$previous_admin_password_display"
elif [[ "$stored_admin_password_is_hash" -eq 1 ]]; then
    printf "\nPrevious Password : unavailable (the stored value is a one-way hash)"
else
    printf "\nPrevious Password : none (new installation)"
fi
printf "\nPassword : \e[31m${adminpassword}\e[0m "
printf "\nPort : \e[31m${port}\e[0m \n"
printf "\nNOW You Can Use ${Green_font_prefix}shahan${Font_color_suffix} and ${Green_font_prefix}shahancheck${Font_color_suffix} and ${Green_font_prefix}listen${Font_color_suffix} Command To See Menu Of Shahan Panel \n"

