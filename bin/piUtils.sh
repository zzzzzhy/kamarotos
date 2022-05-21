
function configPi() {
  PI_WORK_DIR=${OKD_LAB_PATH}/work-dir-pi
  rm -rf ${PI_WORK_DIR}
  mkdir -p ${PI_WORK_DIR}/config
  for i in "$@"
  do
    case ${i} in
      -i)
        initPi
      ;;
      -s)
        piSetup
      ;;
      -n)
        instalNexus
      ;;
      -g)
        installGitea
      ;;
      *)
        # catch all
      ;;
    esac
  done
}

function initPi() {

  OPENWRT_VER=$(yq e ".openwrt-version" ${LAB_CONFIG_FILE})

read -r -d '' FILE << EOF
config interface 'loopback'\n
\toption device 'lo'\n
\toption proto 'static'\n
\toption ipaddr '127.0.0.1'\n
\toption netmask '255.0.0.0'\n
\n
config device\n
\toption name 'br-lan'\n
\toption type 'bridge'\n
\tlist ports 'eth0'\n
\n
config interface 'lan'\n
\toption device 'br-lan'\n
\toption proto 'static'\n
\toption ipaddr '${BASTION_HOST}'\n
\toption netmask '${EDGE_NETMASK}'\n
\toption gateway '${EDGE_ROUTER}'\n
\toption dns '${EDGE_ROUTER}'\n
EOF

echo -e ${FILE} > ${PI_WORK_DIR}/config/network

read -r -d '' FILE << EOF
config dropbear\n
\toption PasswordAuth off\n
\toption RootPasswordAuth off\n
\toption Port 22\n
EOF

echo -e ${FILE} > ${PI_WORK_DIR}/config/dropbear

read -r -d '' FILE << EOF
config system\n
\toption timezone 'UTC'\n
\toption ttylogin '0'\n
\toption log_size '64'\n
\toption urandom_seed '0'\n
\toption hostname 'bastion.${LAB_DOMAIN}'\n
\n
config timeserver 'ntp'\n
\toption enabled '1'\n
\toption enable_server '0'\n
\tlist server '0.openwrt.pool.ntp.org'\n
\tlist server '1.openwrt.pool.ntp.org'\n
\tlist server '2.openwrt.pool.ntp.org'\n
\tlist server '3.openwrt.pool.ntp.org'\n
EOF

echo -e ${FILE} > ${PI_WORK_DIR}/config/system
SD_DEV=mmcblk1
SD_PART=mmcblk1p

GL_MODEL=$(${SSH} root@${EDGE_ROUTER} "uci get glconfig.general.model" )
if [[ ${GL_MODEL} == "ar750s"  ]]
then
  SD_DEV=sda
  SD_PART=sda
fi

${SSH} root@${EDGE_ROUTER} "umount /dev/${SD_PART}1 ; \
  umount /dev/${SD_PART}2 ; \
  umount /dev/${SD_PART}3 ; \
  dd if=/dev/zero of=/dev/${SD_DEV} bs=4096 count=1 ; \
  wget https://downloads.openwrt.org/releases/${OPENWRT_VER}/targets/bcm27xx/bcm2711/openwrt-${OPENWRT_VER}-bcm27xx-bcm2711-rpi-4-ext4-factory.img.gz -O /data/openwrt.img.gz ; \
  gunzip /data/openwrt.img.gz ; \
  dd if=/data/openwrt.img of=/dev/${SD_DEV} bs=4M conv=fsync ; \
  PART_INFO=\$(sfdisk -l /dev/${SD_DEV} | grep ${SD_PART}2) ; \
  let ROOT_SIZE=20971520 ; \
  let P2_START=\$(echo \${PART_INFO} | cut -d\" \" -f2) ; \
  let P3_START=\$(( \${P2_START}+\${ROOT_SIZE}+8192 )) ; \
  sfdisk --no-reread -f --delete /dev/${SD_DEV} 2 ; \
  sfdisk --no-reread -f -d /dev/${SD_DEV} > /tmp/part.info ; \
  echo \"/dev/${SD_PART}2 : start= \${P2_START}, size= \${ROOT_SIZE}, type=83\" >> /tmp/part.info ; \
  echo \"/dev/${SD_PART}3 : start= \${P3_START}, type=83\" >> /tmp/part.info ; \
  sfdisk --no-reread -f /dev/${SD_DEV} < /tmp/part.info ; \
  rm /tmp/part.info ; \
  rm /data/openwrt.img ; \
  e2fsck -f /dev/${SD_PART}2 ; \
  resize2fs /dev/${SD_PART}2 ; \
  mkfs.ext4 /dev/${SD_PART}3 ; \
  mkdir -p /tmp/pi ; \
  mount -t ext4 /dev/${SD_PART}2 /tmp/pi/"

${SCP} -r ${PI_WORK_DIR}/config/* root@${EDGE_ROUTER}:/tmp/pi/etc/config
${SSH} root@${EDGE_ROUTER} "cat /etc/dropbear/authorized_keys >> /tmp/pi/etc/dropbear/authorized_keys ; \
  dropbearkey -y -f /root/.ssh/id_dropbear | grep \"^ssh-\" >> /tmp/pi/etc/dropbear/authorized_keys ; \
  rm -f /tmp/pi/etc/rc.d/*dnsmasq* ; \
  umount /dev/${SD_PART}1 ; \
  umount /dev/${SD_PART}2 ; \
  umount /dev/${SD_PART}3 ; \
  rm -rf /tmp/pi"
echo "bastion.${LAB_DOMAIN}.         IN      A      ${BASTION_HOST}" | ${SSH} root@${EDGE_ROUTER} "cat >> /etc/bind/db.${LAB_DOMAIN}"
echo "10    IN      PTR     bastion.${LAB_DOMAIN}."  | ${SSH} root@${EDGE_ROUTER} "cat >> /etc/bind/db.${EDGE_ARPA}"
${SSH} root@${EDGE_ROUTER} "/etc/init.d/named stop && /etc/init.d/named start"

}

function piSetup() {

CENTOS_MIRROR=$(yq e ".centos-mirror" ${LAB_CONFIG_FILE})

cat << EOF > ${PI_WORK_DIR}/MirrorSync.sh
#!/bin/bash

for i in BaseOS AppStream 
do 
  rsync  -avSHP --delete ${CENTOS_MIRROR}9-stream/\${i}/x86_64/os/ /usr/local/www/install/repos/\${i}/x86_64/os/ > /tmp/repo-mirror.\${i}.out 2>&1
done
EOF

cat << EOF > ${PI_WORK_DIR}/local-repos.repo
[local-appstream]
name=AppStream
baseurl=http://${BASTION_HOST}/install/repos/AppStream/x86_64/os/
gpgcheck=0
enabled=1

[local-baseos]
name=BaseOS
baseurl=http://${BASTION_HOST}/install/repos/BaseOS/x86_64/os/
gpgcheck=0
enabled=1

EOF

cat << EOF > ${PI_WORK_DIR}/chrony.conf
server ${BASTION_HOST} iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
EOF

cat << EOF > ${PI_WORK_DIR}/uci.batch
del_list uhttpd.main.listen_http="[::]:80"
del_list uhttpd.main.listen_http="0.0.0.0:80"
del_list uhttpd.main.listen_https="[::]:443"
del_list uhttpd.main.listen_https="0.0.0.0:443"
del uhttpd.defaults
del uhttpd.main.cert
del uhttpd.main.key
del uhttpd.main.cgi_prefix
del uhttpd.main.lua_prefix
add_list uhttpd.main.listen_http="${BASTION_HOST}:80"
add_list uhttpd.main.listen_http="127.0.0.1:80"
set uhttpd.main.home='/usr/local/www'
set system.ntp.enable_server="1"
commit
EOF

  echo "Installing packages"
  ${SSH} root@${BASTION_HOST} "opkg update && opkg install ip-full uhttpd shadow bash wget git-http ca-bundle procps-ng-ps rsync curl libstdcpp6 libjpeg libnss lftp block-mount ; \
    opkg list | grep \"^coreutils-\" | while read i ; \
    do opkg install \$(echo \${i} | cut -d\" \" -f1) ; \
    done
    echo \"Creating SSH keys\" ; \
    rm -rf /root/.ssh ; \
    mkdir -p /root/.ssh ; \
    dropbearkey -t rsa -s 4096 -f /root/.ssh/id_dropbear
    echo \"mounting /usr/local filesystem\" ; \
    let RC=0 ; \
    while [[ \${RC} -eq 0 ]] ; \
    do uci delete fstab.@mount[-1] ; \
    let RC=\$? ; \
    done; \
    PART_UUID=\$(block info /dev/mmcblk0p3 | cut -d\\\" -f2) ; \
    MOUNT=\$(uci add fstab mount) ; \
    uci set fstab.\${MOUNT}.target=/usr/local ; \
    uci set fstab.\${MOUNT}.uuid=\${PART_UUID} ; \
    uci set fstab.\${MOUNT}.enabled=1 ; \
    uci commit fstab ; \
    block mount ; \
    mkdir -p /usr/local/www/install/kickstart ; \
    mkdir /usr/local/www/install/postinstall ; \
    mkdir /usr/local/www/install/fcos ; \
    mkdir -p /root/bin ; \
    for i in BaseOS AppStream ; \
    do mkdir -p /usr/local/www/install/repos/\${i}/x86_64/os/ ; \
    done ;\
    dropbearkey -y -f /root/.ssh/id_dropbear | grep \"ssh-\" > /usr/local/www/install/postinstall/authorized_keys ;\
    mkdir -p /root/bin"

  ${SCP} ${PI_WORK_DIR}/local-repos.repo root@${BASTION_HOST}:/usr/local/www/install/postinstall/local-repos.repo
  ${SCP} ${PI_WORK_DIR}/chrony.conf root@${BASTION_HOST}:/usr/local/www/install/postinstall/chrony.conf
  ${SCP} ${PI_WORK_DIR}/MirrorSync.sh root@${BASTION_HOST}:/root/bin/MirrorSync.sh
  ${SSH} root@${BASTION_HOST} "chmod 750 /root/bin/MirrorSync.sh"
  echo "Apply UCI config, disable root password, and reboot"
  ${SCP} ${PI_WORK_DIR}/uci.batch root@${BASTION_HOST}:/tmp/uci.batch
  cat ${OKD_LAB_PATH}/ssh_key.pub | ${SSH} root@${BASTION_HOST} "cat >> /usr/local/www/install/postinstall/authorized_keys"
  ${SSH} root@${BASTION_HOST} "cat /tmp/uci.batch | uci batch ; passwd -l root ; reboot"
  echo "Setup complete."
  echo "After the Pi reboots, run ${SSH} root@${BASTION_HOST} \"nohup /root/bin/MirrorSync.sh &\""
}

function instalNexus() {

cat <<EOF > ${PI_WORK_DIR}/nexus
#!/bin/sh /etc/rc.common

START=99
STOP=80
SERVICE_USE_PID=0

start() {
   ulimit -Hn 65536
   ulimit -Sn 65536
    service_start /usr/local/nexus/nexus-3/bin/nexus start
}

stop() {
    service_stop /usr/local/nexus/nexus-3/bin/nexus stop
}
EOF

cat <<EOF > ${PI_WORK_DIR}/nexus.properties
nexus-args=\${jetty.etc}/jetty.xml,\${jetty.etc}/jetty-https.xml,\${jetty.etc}/jetty-requestlog.xml
application-port-ssl=8443
EOF

  ${SSH} root@${BASTION_HOST} "mkdir /tmp/work-dir ; \
    cd /tmp/work-dir; \
    PKG=\"openjdk8-8 openjdk8-jre-8 openjdk8-jre-lib-8 openjdk8-jre-base-8 java-cacerts\" ; \
    for package in \${PKG}; 
    do FILE=\$(lftp -e \"cls -1 alpine/edge/community/aarch64/\${package}*; quit\" http://dl-cdn.alpinelinux.org) ; \
      curl -LO http://dl-cdn.alpinelinux.org/\${FILE} ; \
    done ; \
    for i in \$(ls) ; \
    do tar xzf \${i} ; \
    done ; \
    mv ./usr/lib/jvm/java-1.8-openjdk /usr/local/java-1.8-openjdk ; \
    echo \"export PATH=\\\$PATH:/root/bin:/usr/local/java-1.8-openjdk/bin\" >> /root/.profile ; \
    opkg update  ; \
    opkg install ca-certificates  ; \
    rm -f /usr/local/java-1.8-openjdk/jre/lib/security/cacerts  ; \
    /usr/local/java-1.8-openjdk/bin/keytool -noprompt -importcert -file /etc/ssl/certs/ca-certificates.crt -keystore /usr/local/java-1.8-openjdk/jre/lib/security/cacerts -keypass changeit -storepass changeit ; \
    for i in \$(find /etc/ssl/certs -type f) ; \
    do ALIAS=\$(echo \${i} | cut -d\"/\" -f5) ; \
      /usr/local/java-1.8-openjdk/bin/keytool -noprompt -importcert -file \${i} -alias \${ALIAS}  -keystore /usr/local/java-1.8-openjdk/jre/lib/security/cacerts -keypass changeit -storepass changeit ; \
    done ; \
    cd ; \
    rm -rf /tmp/work-dir"

  ${SSH} root@${BASTION_HOST} "mkdir -p /usr/local/nexus/home ; \
    cd /usr/local/nexus ; \
    wget https://download.sonatype.com/nexus/3/latest-unix.tar.gz -O latest-unix.tar.gz ; \
    tar -xzf latest-unix.tar.gz ; \
    NEXUS=\$(ls -d nexus-*) ; \
    ln -s \${NEXUS} nexus-3 ; \
    rm -f latest-unix.tar.gz ; \
    groupadd nexus ; \
    useradd -g nexus -d /usr/local/nexus/home nexus ; \
    chown -R nexus:nexus /usr/local/nexus"
  ${SSH} root@${BASTION_HOST} 'sed -i "s|#run_as_user=\"\"|run_as_user=\"nexus\"|g" /usr/local/nexus/nexus-3/bin/nexus.rc'
  
  ${SCP} ${PI_WORK_DIR}/nexus root@${BASTION_HOST}:/etc/init.d/nexus
  ${SSH} root@${BASTION_HOST} "chmod 755 /etc/init.d/nexus"

  ${SSH} root@${BASTION_HOST} 'sed -i "s|# INSTALL4J_JAVA_HOME_OVERRIDE=|INSTALL4J_JAVA_HOME_OVERRIDE=/usr/local/java-1.8-openjdk|g" /usr/local/nexus/nexus-3/bin/nexus'

  ${SSH} root@${BASTION_HOST} "/usr/local/java-1.8-openjdk/bin/keytool -genkeypair -keystore /usr/local/nexus/nexus-3/etc/ssl/keystore.jks -deststoretype pkcs12 -storepass password -keypass password -alias jetty -keyalg RSA -keysize 4096 -validity 5000 -dname \"CN=nexus.${LAB_DOMAIN}, OU=okd4-lab, O=okd4-lab, L=City, ST=State, C=US\" -ext \"SAN=DNS:nexus.${LAB_DOMAIN},IP:${BASTION_HOST}\" -ext \"BC=ca:true\" ; \
    /usr/local/java-1.8-openjdk/bin/keytool -importkeystore -srckeystore /usr/local/nexus/nexus-3/etc/ssl/keystore.jks -destkeystore /usr/local/nexus/nexus-3/etc/ssl/keystore.jks -deststoretype pkcs12 -srcstorepass password  ; \
    rm -f /usr/local/nexus/nexus-3/etc/ssl/keystore.jks.old  ; \
    chown nexus:nexus /usr/local/nexus/nexus-3/etc/ssl/keystore.jks  ; \
    mkdir -p /usr/local/nexus/sonatype-work/nexus3/etc"
  cat ${PI_WORK_DIR}/nexus.properties | ${SSH} root@${BASTION_HOST} "cat >> /usr/local/nexus/sonatype-work/nexus3/etc/nexus.properties"
  ${SSH} root@${BASTION_HOST} "chown -R nexus:nexus /usr/local/nexus/sonatype-work/nexus3/etc ; /etc/init.d/nexus enable ; reboot"
  echo "nexus.${LAB_DOMAIN}.           IN      A      ${BASTION_HOST}" | ${SSH} root@${EDGE_ROUTER} "cat >> /etc/bind/db.${LAB_DOMAIN}"
  ${SSH} root@${EDGE_ROUTER} "/etc/init.d/named stop && /etc/init.d/named start"
}

function installGitea() {

  GITEA_VERSION=$(yq e ".gitea-version" ${LAB_CONFIG_FILE})
  ${SSH} root@${BASTION_HOST} "opkg update && opkg install sqlite3-cli openssh-keygen ; \
    mkdir -p /usr/local/gitea ; \
    for i in bin etc custom data db git ; \
    do mkdir /usr/local/gitea/\${i} ; \
    done ; \
    wget -O /usr/local/gitea/bin/gitea https://dl.gitea.io/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-arm64 ; \
    chmod 750 /usr/local/gitea/bin/gitea ; \
    cd /usr/local/gitea/custom ; \
    /usr/local/gitea/bin/gitea cert --host gitea.${LAB_DOMAIN} ; \
    groupadd gitea ; \
    useradd -g gitea -d /usr/local/gitea gitea ; \
    chown -R gitea:gitea /usr/local/gitea"
  INTERNAL_TOKEN=$(${SSH} root@${BASTION_HOST} "/usr/local/gitea/bin/gitea generate secret INTERNAL_TOKEN")
  SECRET_KEY=$(${SSH} root@${BASTION_HOST} "/usr/local/gitea/bin/gitea generate secret SECRET_KEY")
  JWT_SECRET=$(${SSH} root@${BASTION_HOST} "/usr/local/gitea/bin/gitea generate secret JWT_SECRET")

cat << EOF > ${PI_WORK_DIR}/app.ini
RUN_USER = gitea
RUN_MODE = prod

[repository]
ROOT = /usr/local/gitea/git
SCRIPT_TYPE = sh
DEFAULT_BRANCH = main
DEFAULT_PUSH_CREATE_PRIVATE = true
ENABLE_PUSH_CREATE_USER = true
ENABLE_PUSH_CREATE_ORG = true

[server]
PROTOCOL = https
ROOT_URL = https://gitea.${LAB_DOMAIN}:3000/
HTTP_PORT = 3000
CERT_FILE = cert.pem
KEY_FILE  = key.pem
STATIC_ROOT_PATH = /usr/local/gitea/web
APP_DATA_PATH    = /usr/local/gitea/data
LFS_START_SERVER = true

[service]
DISABLE_REGISTRATION = true

[database]
DB_TYPE = sqlite3
PATH = /usr/local/gitea/db/gitea.db

[security]
INSTALL_LOCK = true
SECRET_KEY = ${SECRET_KEY}
INTERNAL_TOKEN = ${INTERNAL_TOKEN}

[oauth2]
JWT_SECRET = ${JWT_SECRET}

[session]
PROVIDER = file

[log]
ROOT_PATH = /usr/local/gitea/log
MODE = file
LEVEL = Info
EOF

cat <<EOF > ${PI_WORK_DIR}/gitea
#!/bin/sh /etc/rc.common

START=99
STOP=80
SERVICE_USE_PID=0

start() {
   service_start /usr/bin/su - gitea -c 'GITEA_WORK_DIR=/usr/local/gitea /usr/bin/nohup /usr/local/gitea/bin/gitea --config /usr/local/gitea/etc/app.ini web > /dev/null 2>&1 &'
}

restart() {
   /usr/bin/su - gitea -c 'GITEA_WORK_DIR=/usr/local/gitea /usr/local/gitea/bin/gitea --config /usr/local/gitea/etc/app.ini manager restart'
}

stop() {
   /usr/bin/su - gitea -c 'GITEA_WORK_DIR=/usr/local/gitea /usr/local/gitea/bin/gitea --config /usr/local/gitea/etc/app.ini manager shutdown'
}
EOF

cat <<EOF > ${PI_WORK_DIR}/giteaInit.sh
su - gitea -c 'GITEA_WORK_DIR=/usr/local/gitea /usr/local/gitea/bin/gitea --config /usr/local/gitea/etc/app.ini migrate'
su - gitea -c "GITEA_WORK_DIR=/usr/local/gitea /usr/local/gitea/bin/gitea --config /usr/local/gitea/etc/app.ini admin user create --admin --username gitea --password password --email gitea@gitea.${LAB_DOMAIN} --must-change-password"
su - gitea -c "GITEA_WORK_DIR=/usr/local/gitea /usr/local/gitea/bin/gitea --config /usr/local/gitea/etc/app.ini admin user create --username devuser --password password --email devuser@gitea.${LAB_DOMAIN} --must-change-password"
EOF

  ${SCP} ${PI_WORK_DIR}/app.ini root@${BASTION_HOST}:/usr/local/gitea/etc/app.ini
  ${SCP} ${PI_WORK_DIR}/gitea root@${BASTION_HOST}:/etc/init.d/gitea
  ${SCP} ${PI_WORK_DIR}/giteaInit.sh root@${BASTION_HOST}:/tmp/giteaInit.sh
  ${SSH} root@${BASTION_HOST} "chown -R gitea:gitea /usr/local/gitea ; chmod 755 /etc/init.d/gitea ; chmod 755 /tmp/giteaInit.sh ; /tmp/giteaInit.sh ; /etc/init.d/gitea enable ; /etc/init.d/gitea start"
  echo "gitea.${LAB_DOMAIN}.           IN      A      ${BASTION_HOST}" | ${SSH} root@${EDGE_ROUTER} "cat >> /etc/bind/db.${LAB_DOMAIN}"
  ${SSH} root@${EDGE_ROUTER} "/etc/init.d/named stop && /etc/init.d/named start"
}

