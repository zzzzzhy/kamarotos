function configRouter() {
  EDGE="false"
  WLAN="false"
  WWAN="false"
  FORMAT_SD="false"
  GL_MODEL=""
  INIT_IP=192.168.5.1
  wifi_channel=3
  WORK_DIR=${OKD_LAB_PATH}/work-dir-router
  rm -rf ${WORK_DIR}
  mkdir -p ${WORK_DIR}/dns

  for i in "$@"; do
    case ${i} in
    -e | --edge)
      EDGE=true
      ;;
    -wl | --wireless-lan)
      WLAN="true"
      ;;
    -ww | --wireless-wan)
      WWAN="true"
      ;;
    -i | --init)
      INIT="true"
      ;;
    -s | --setup)
      SETUP="true"
      ;;
    -f | --format)
      FORMAT_SD="true"
      ;;
    -aw | --add-wireless)
      ADD_WIRELESS="true"
      ;;
    *)
      # catch all
      ;;
    esac
  done

  if [[ ! -d ${OKD_LAB_PATH}/boot-files ]]; then
    getBootFile
  fi
  if [[ ${INIT} == "true" ]]; then
    initRouter
  fi
  if [[ ${SETUP} == "true" ]]; then
    setupRouter
  fi
}

function initRouter() {
  initEdge
  # rm /etc/hotplug.d/block/10-mount
  echo "Generating SSH keys"
  ${SSH} root@${INIT_IP} "rm -rf /root/.ssh ; rm -rf /data/* ; mkdir -p /root/.ssh ; dropbearkey -t rsa -s 4096 -f /root/.ssh/id_dropbear"
  echo "Copying workstation SSH key to router"
  cat ${OKD_LAB_PATH}/ssh_key.pub | ${SSH} root@${INIT_IP} "cat >> /etc/dropbear/authorized_keys"
  echo "Applying UCI config"
  ${SCP} ${WORK_DIR}/uci.batch root@${INIT_IP}:/tmp/uci.batch
  ${SSH} root@${INIT_IP} "cat /tmp/uci.batch | uci batch ; \
  reboot"
}

function setupRouter() {
  ${SSH} root@${router_ip} "opkg update && opkg install haproxy curl ip-full procps-ng-ps bind-server bind-tools bash sfdisk rsync resize2fs wget block-mount wipefs coreutils-nohup"
  createDhcpConfig ${EDGE_ROUTER} ${LAB_DOMAIN}
  createIpxeHostConfig ${EDGE_ROUTER}
  createRouterDnsConfig  ${EDGE_ROUTER} ${LAB_DOMAIN} ${EDGE_ARPA} "edge"
  setupRouterCommon ${EDGE_ROUTER}
}

function setupHaProxy() {

  local router_ip=${1}

  ${SSH} root@${router_ip} "opkg install haproxy"
  ${SSH} root@${router_ip} "mv /etc/haproxy.cfg /etc/haproxy.cfg.orig ; \
    mkdir -p /data/haproxy ; \
    rm -f /etc/init.d/haproxy"
}

function setupRouterCommon() {

  local router_ip=${1}

  if [[ ${NO_LAB_PI} == "true" ]]; then
    initMicroSD ${router_ip} ${FORMAT_SD}
    ${SCP} ${WORK_DIR}/local-repos.repo root@${router_ip}:/usr/local/www/install/postinstall/local-repos.repo
    ${SCP} ${WORK_DIR}/chrony.conf root@${router_ip}:/usr/local/www/install/postinstall/chrony.conf
    ${SCP} ${WORK_DIR}/MirrorSync.sh root@${router_ip}:/root/bin/MirrorSync.sh
    ${SSH} root@${router_ip} "chmod 750 /root/bin/MirrorSync.sh"
    cat ~/.ssh/id_rsa.pub | ${SSH} root@${router_ip} "cat >> /usr/local/www/install/postinstall/authorized_keys"
  fi
  # if [[ ${GL_MODEL} == "GL-AXT1800" ]]; then
  # setupNginx ${router_ip}
  # else
  setupHaProxy ${router_ip}
  # fi
  ${SSH} root@${router_ip} "mkdir -p /data/var/named/data ; \
    cp -r /etc/bind /data/bind ; \
    mkdir -p /data/tftpboot/ipxe ; \
    mkdir /data/tftpboot/networkboot"
  ${SCP} ${OKD_LAB_PATH}/boot-files/* root@${router_ip}:/data/tftpboot/*
  ${SCP} ${WORK_DIR}/boot.ipxe root@${router_ip}:/data/tftpboot/boot.ipxe
  ${SCP} -r ${WORK_DIR}/dns/* root@${router_ip}:/data/bind/
  ${SSH} root@${router_ip} "mkdir -p /data/var/named/dynamic ; \
    chown -R bind:bind /data/var/named ; \
    chown -R bind:bind /data/bind ; \
    /etc/init.d/named disable ; \
    sed -i \"s|START=50|START=99|g\" /etc/init.d/named ; \
    sed -i \"s|config_file=/etc/bind/named.conf|config_file=/data/bind/named.conf|g\" /etc/init.d/named ; \
    /etc/init.d/named enable ; \
    uci set network.wan.dns=${router_ip} ; \
    uci set network.wan.peerdns=0 ; \
    uci show network.wwan ; \
    if [[ \$? -eq 0 ]] ; \
    then uci set network.wwan.dns=${router_ip} ; \
      uci set network.wwan.peerdns=0 ; \
    fi ; \
    uci commit"
  echo "commit" >> ${WORK_DIR}/uci.batch
  ${SCP} ${WORK_DIR}/uci.batch root@${router_ip}:/tmp/uci.batch
  ${SSH} root@${router_ip} "cat /tmp/uci.batch | uci batch ; /etc/init.d/network restart"
}
function initEdge() {

cat << EOF > ${WORK_DIR}/uci.batch
set dropbear.@dropbear[0].PasswordAuth="off"
set dropbear.@dropbear[0].RootPasswordAuth="off"
set network.lan.ipaddr="${EDGE_ROUTER}"
set network.lan.netmask=${EDGE_NETMASK}
set network.lan.hostname=router.${LAB_DOMAIN}
delete network.wan6
commit

EOF
}

function getBootFile() {
  mkdir -p ${OKD_LAB_PATH}/boot-files
  wget http://boot.ipxe.org/ipxe.efi -O ${OKD_LAB_PATH}/boot-files/ipxe.efi
  wget http://boot.ipxe.org/undionly.kpxe -O ${OKD_LAB_PATH}/boot-files/undionly.kpxe
  wget http://boot.ipxe.org/tinycore.ipxe -O ${OKD_LAB_PATH}/boot-files/tinycore.ipxe
  wget http://boot.ipxe.org/snponly.efi -O ${OKD_LAB_PATH}/boot-files/snponly.efi
}

function initMicroSD() {

  local router_ip=${1}
  local format=${2}
  ${SSH} root@${router_ip} "echo \"mounting /usr/local filesystem\" ; \
    let RC=0 ; \
    while [[ \${RC} -eq 0 ]] ; \
    do uci delete fstab.@mount[-1] ; \
    let RC=\$? ; \
    done; \
    PART_UUID=\$(block info /dev/sdb | cut -d\\\" -f2) ; \
    MOUNT=\$(uci add fstab mount) ; \
    uci set fstab.\${MOUNT}.target=/usr/local ; \
    uci set fstab.\${MOUNT}.uuid=\${PART_UUID} ; \
    uci set fstab.\${MOUNT}.enabled=1 ; \
    uci commit fstab ; \
    block mount ; \
    ln -s /usr/local /data ; \
    ln -s /usr/local/www/install /www/install ; \
    mkdir -p /root/bin"
  ${SSH} root@${router_ip} "mkfs.ext4 /dev/sdb ; \
      mkdir /usr/local;\
      mount /dev/sdb /usr/local ; \
      mkdir -p /usr/local/www/install/kickstart ; \
      mkdir /usr/local/www/install/postinstall ; \
      mkdir /usr/local/www/install/fcos ; \
      for i in BaseOS AppStream ; \
        do mkdir -p /usr/local/www/install/repos/\${i}/x86_64/os/ ; \
      done ;\
      dropbearkey -y -f /root/.ssh/id_dropbear | grep \"ssh-\" > /usr/local/www/install/postinstall/authorized_keys"
}
