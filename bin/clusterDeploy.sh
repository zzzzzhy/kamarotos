function createInstallConfig() {

  if [[ ! -f  ${PULL_SECRET} ]]
  then
    pullSecret
  fi

  PULL_SECRET_TXT=$(cat ${PULL_SECRET})

cat << EOF > ${WORK_DIR}/install-config-upi.yaml
apiVersion: v1
baseDomain: ${DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
networking:
  networkType: OVNKubernetes
  clusterNetwork:
  - cidr: ${CLUSTER_CIDR}
    hostPrefix: 23 
  serviceNetwork: 
  - ${SERVICE_CIDR}
compute:
- name: worker
  replicas: 0
controlPlane:
  name: master
  replicas: ${CP_REPLICAS}
platform:
  none: {}
pullSecret: '${PULL_SECRET_TXT}'
sshKey: ${SSH_KEY}
EOF
}

function appendDisconnectedInstallConfig() {

NEXUS_CERT=$( openssl s_client -showcerts -connect ${PROXY_REGISTRY} </dev/null 2>/dev/null|openssl x509 -outform PEM | while read line ; do echo "  ${line}" ; done )

cat << EOF >> ${WORK_DIR}/install-config-upi.yaml
additionalTrustBundle: |
${NEXUS_CERT}
imageContentSources:
- mirrors:
  - ${PROXY_REGISTRY}/okd
  source: quay.io/openshift/okd
- mirrors:
  - ${PROXY_REGISTRY}/okd
  source: quay.io/openshift/okd-content
EOF
}

function createLbConfig() {

  local lb_ip=$(yq e ".cluster.ingress-ip-addr" ${CLUSTER_CONFIG})

  INTERFACE=$(echo "${CLUSTER_NAME//-/_}" | tr "[:upper:]" "[:lower:]")
  ${SSH} root@${DOMAIN_ROUTER} "uci set network.${INTERFACE}_lb=interface ; \
    uci set network.${INTERFACE}_lb.ifname=\"@lan\" ; \
    uci set network.${INTERFACE}_lb.proto=static ; \
    uci set network.${INTERFACE}_lb.hostname=${CLUSTER_NAME}-lb.${DOMAIN} ; \
    uci set network.${INTERFACE}_lb.ipaddr=${lb_ip}/${DOMAIN_NETMASK} ; \
    uci commit ; \
    /etc/init.d/network reload ; \
    sleep 10"

  configHaProxy ${lb_ip}
  ${SCP} ${WORK_DIR}/haproxy-${CLUSTER_NAME}.cfg root@${DOMAIN_ROUTER}:/etc/haproxy-${CLUSTER_NAME}.cfg
  ${SCP} ${WORK_DIR}/haproxy-${CLUSTER_NAME}.init root@${DOMAIN_ROUTER}:/etc/init.d/haproxy-${CLUSTER_NAME}
  ${SSH} root@${DOMAIN_ROUTER} "chmod 644 /etc/haproxy-${CLUSTER_NAME}.cfg ; \
    chmod 750 /etc/init.d/haproxy-${CLUSTER_NAME} ; \
    /etc/init.d/haproxy-${CLUSTER_NAME} enable ; \
    /etc/init.d/haproxy-${CLUSTER_NAME} start"
}

function createBootstrapNode() {
  host_name=${CLUSTER_NAME}-bootstrap
  metal=$(yq e ".control-plane.metal" ${CLUSTER_CONFIG})
  yq e ".bootstrap.name = \"${host_name}\"" -i ${CLUSTER_CONFIG}
  bs_ip_addr=$(yq e ".bootstrap.ip-addr" ${CLUSTER_CONFIG})
  boot_dev=/dev/sda
  if [[ "${metal}" == "true" ]]
  then
    platform=metal
  else
    platform=qemu
  fi
  if [[ $(yq e ".bootstrap.metal" ${CLUSTER_CONFIG}) == "false" ]]
  then
    kvm_host=$(yq e ".bootstrap.kvm-host" ${CLUSTER_CONFIG})
    memory=$(yq e ".bootstrap.node-spec.memory" ${CLUSTER_CONFIG})
    cpu=$(yq e ".bootstrap.node-spec.cpu" ${CLUSTER_CONFIG})
    root_vol=$(yq e ".bootstrap.node-spec.root-vol" ${CLUSTER_CONFIG})
    createOkdVmNode ${bs_ip_addr} ${host_name} ${kvm_host}.${BOOTSTRAP_KVM_DOMAIN} bootstrap ${memory} ${cpu} ${root_vol} 0 ".bootstrap.mac-addr"
  fi
  # Create the ignition and iPXE boot files
  mac_addr=$(yq e ".bootstrap.mac-addr" ${CLUSTER_CONFIG})
  createButaneConfig ${bs_ip_addr} ${host_name}.${DOMAIN} ${mac_addr} bootstrap ${platform} "false" ${boot_dev}
  createPxeFile ${mac_addr} ${platform} ${boot_dev} ${host_name} ${bs_ip_addr}
}

function configSno() {
  BIP=false
  metal=$(yq e ".control-plane.metal" ${CLUSTER_CONFIG})
  ip_addr=$(yq e ".control-plane.okd-hosts.[0].ip-addr" ${CLUSTER_CONFIG})
  host_name=${CLUSTER_NAME}-node
  yq e ".control-plane.okd-hosts.[0].name = \"${host_name}\"" -i ${CLUSTER_CONFIG}
  if [[ ${metal} == "false" ]]
  then
    memory=$(yq e ".control-plane.node-spec.memory" ${CLUSTER_CONFIG})
    cpu=$(yq e ".control-plane.node-spec.cpu" ${CLUSTER_CONFIG})
    root_vol=$(yq e ".control-plane.node-spec.root-vol" ${CLUSTER_CONFIG})
    kvm_host=$(yq e ".control-plane.okd-hosts.[0].kvm-host" ${CLUSTER_CONFIG})
    # Create the VM
    createOkdVmNode ${ip_addr} ${host_name} ${kvm_host}.${DOMAIN} sno ${memory} ${cpu} ${root_vol} 0 ".control-plane.okd-hosts.[0].mac-addr"
  fi
  # Create the ignition and iPXE boot files
  if [[ ${metal} == "true" ]]
  then
    platform=metal
    boot_dev=$(yq e ".control-plane.okd-hosts.[0].boot-dev" ${CLUSTER_CONFIG})
  else
    platform=qemu
    boot_dev=/dev/sda
  fi
  mac_addr=$(yq e ".control-plane.okd-hosts.[0].mac-addr" ${CLUSTER_CONFIG})
  if [[ ${BIP} == "true" ]]
  then
    install_dev=$(yq e ".control-plane.okd-hosts.[0].sno-install-dev" ${CLUSTER_CONFIG})
    createInstallConfig ${install_dev}
    cp ${WORK_DIR}/install-config-upi.yaml ${WORK_DIR}/okd-install-dir/install-config.yaml
    openshift-install --dir=${WORK_DIR}/okd-install-dir create single-node-ignition-config
    cp ${WORK_DIR}/okd-install-dir/bootstrap-in-place-for-live-iso.ign ${WORK_DIR}/ipxe-work-dir/sno.ign
    createButaneConfig ${ip_addr} ${host_name}.${DOMAIN} ${mac_addr} sno ${platform} "false" ${boot_dev}
    createSnoBipDNS ${host_name} ${ip_addr}
  else
    createButaneConfig ${ip_addr} ${host_name}.${DOMAIN} ${mac_addr} master ${platform} "false" ${boot_dev}
    createSnoDNS ${host_name} ${ip_addr} ${bs_ip_addr}
  fi
  createPxeFile ${mac_addr} ${platform} ${boot_dev} ${host_name} ${ip_addr}
}

function configControlPlane() {

  metal=$(yq e ".control-plane.metal" ${CLUSTER_CONFIG})
  ceph_node=$(yq ".control-plane | has(\"ceph\")" ${CLUSTER_CONFIG})
  config_ceph=false
  if [[ ${ceph_node} == "true" ]]
  then
    ceph_type=$(yq e ".control-plane.ceph.type" ${CLUSTER_CONFIG})
    if [[ ${ceph_type} == "part" ]]
    then
      config_ceph=true
    fi
  fi
  # Create DNS Entries:
  ingress_ip=$(yq e ".cluster.ingress-ip-addr" ${CLUSTER_CONFIG})
  echo "${CLUSTER_NAME}-bootstrap.${DOMAIN}.  IN      A      ${bs_ip_addr} ; ${CLUSTER_NAME}-${DOMAIN}-bs" >> ${WORK_DIR}/dns-work-dir/forward.zone
  echo "*.apps.${CLUSTER_NAME}.${DOMAIN}.     IN      A      ${ingress_ip} ; ${CLUSTER_NAME}-${DOMAIN}-cp" >> ${WORK_DIR}/dns-work-dir/forward.zone
  echo "api.${CLUSTER_NAME}.${DOMAIN}.        IN      A      ${ingress_ip} ; ${CLUSTER_NAME}-${DOMAIN}-cp" >> ${WORK_DIR}/dns-work-dir/forward.zone
  echo "api-int.${CLUSTER_NAME}.${DOMAIN}.    IN      A      ${ingress_ip} ; ${CLUSTER_NAME}-${DOMAIN}-cp" >> ${WORK_DIR}/dns-work-dir/forward.zone
  bs_o4=$(echo ${bs_ip_addr} | cut -d"." -f4)
  echo "${bs_o4}    IN      PTR     ${CLUSTER_NAME}-bootstrap.${DOMAIN}.   ; ${CLUSTER_NAME}-${DOMAIN}-bs" >> ${WORK_DIR}/dns-work-dir/reverse.zone
  let node_count=$(yq e ".control-plane.okd-hosts" ${CLUSTER_CONFIG} | yq e 'length' -)
  for((i=0;i<${node_count};i++))
  do
    ip_addr=$(yq e ".control-plane.okd-hosts.[${i}].ip-addr" ${CLUSTER_CONFIG})
    host_name=${CLUSTER_NAME}-master-${i}
    yq e ".control-plane.okd-hosts.[${i}].name = \"${host_name}\"" -i ${CLUSTER_CONFIG}
    if [[ ${metal} == "true" ]]
    then
      boot_dev=$(yq e ".control-plane.okd-hosts.[${i}].boot-dev" ${CLUSTER_CONFIG})
    else
      
      memory=$(yq e ".control-plane.node-spec.memory" ${CLUSTER_CONFIG})
      cpu=$(yq e ".control-plane.node-spec.cpu" ${CLUSTER_CONFIG})
      root_vol=$(yq e ".control-plane.node-spec.root-vol" ${CLUSTER_CONFIG})
      kvm_host=$(yq e ".control-plane.okd-hosts.[${i}].kvm-host" ${CLUSTER_CONFIG})
      boot_dev="/dev/sda"
      if [[ ${ceph_node} == "true" ]]
      then
        ceph_vol=$(yq e ".control-plane.ceph.ceph-vol" ${CLUSTER_CONFIG})
      else
        ceph_vol=0
      fi
      # Create the VM
      createOkdVmNode ${ip_addr} ${host_name} ${kvm_host}.${DOMAIN} master ${memory} ${cpu} ${root_vol} ${ceph_vol} ".control-plane.okd-hosts.[${i}].mac-addr"
    fi
    # Create the ignition and iPXE boot files
     platform=qemu
    if [[ ${metal} == "true" ]]
    then
      platform=metal
    fi
    mac_addr=$(yq e ".control-plane.okd-hosts.[${i}].mac-addr" ${CLUSTER_CONFIG})
    createButaneConfig ${ip_addr} ${host_name}.${DOMAIN} ${mac_addr} master ${platform} ${config_ceph} ${boot_dev}
    createPxeFile ${mac_addr} ${platform} ${boot_dev} ${host_name} ${ip_addr}
    # Create control plane node DNS Records:
    echo "${host_name}.${DOMAIN}.   IN      A      ${ip_addr} ; ${CLUSTER_NAME}-${DOMAIN}-cp" >> ${WORK_DIR}/dns-work-dir/forward.zone
    echo "etcd-${i}.${CLUSTER_NAME}.${DOMAIN}.          IN      A      ${ip_addr} ; ${CLUSTER_NAME}-${DOMAIN}-cp" >> ${WORK_DIR}/dns-work-dir/forward.zone
    o4=$(echo ${ip_addr} | cut -d"." -f4)
    echo "${o4}    IN      PTR     ${host_name}.${DOMAIN}.  ; ${CLUSTER_NAME}-${DOMAIN}-cp" >> ${WORK_DIR}/dns-work-dir/reverse.zone
  done
  # Create DNS SRV Records:
  for((i=0;i<${node_count};i++))
  do
    echo "_etcd-server-ssl._tcp.${CLUSTER_NAME}.${DOMAIN}    86400     IN    SRV     0    10    2380    etcd-${i}.${CLUSTER_NAME}.${DOMAIN}. ; ${CLUSTER_NAME}-${DOMAIN}-cp" >> ${WORK_DIR}/dns-work-dir/forward.zone
  done
  # Create The HA-Proxy Load Balancer
  createLbConfig
}

function deployCluster() {

  WORK_DIR=${OKD_LAB_PATH}/${CLUSTER_NAME}.${DOMAIN}
  rm -rf ${WORK_DIR}
  mkdir -p ${WORK_DIR}/ipxe-work-dir/ignition
  mkdir ${WORK_DIR}/dns-work-dir
  mkdir ${WORK_DIR}/okd-install-dir
  if [[ -d ${OKD_LAB_PATH}/lab-config/${CLUSTER_NAME}.${DOMAIN} ]]
  then
    rm -rf ${OKD_LAB_PATH}/lab-config/${CLUSTER_NAME}.${DOMAIN}
  fi
  mkdir -p ${OKD_LAB_PATH}/lab-config/${CLUSTER_NAME}.${DOMAIN}
  SSH_KEY=$(cat ${OKD_LAB_PATH}/ssh_key.pub)
  SNO="false"
  CP_REPLICAS=$(yq e ".control-plane.okd-hosts" ${CLUSTER_CONFIG} | yq e 'length' -)
  if [[ ${CP_REPLICAS} == "1" ]]
  then
    SNO="true"
  elif [[ ${CP_REPLICAS} != "3" ]]
  then
    echo "There must be 3 host entries for the control plane for a full cluster, or 1 entry for a Single Node cluster."
    exit 1
  fi
  createInstallConfig
  if [[ ${NO_LAB_PI} == "false" ]]
  then
    appendDisconnectedInstallConfig
  fi
  cp ${WORK_DIR}/install-config-upi.yaml ${WORK_DIR}/okd-install-dir/install-config.yaml
  openshift-install --dir=${WORK_DIR}/okd-install-dir create ignition-configs
  cp ${WORK_DIR}/okd-install-dir/*.ign ${WORK_DIR}/ipxe-work-dir/
  createBootstrapNode

  #Create Control Plane Nodes:
  if [[ ${SNO} == "true" ]]
  then
    configSno
  else
    configControlPlane
  fi
  cp ${WORK_DIR}/okd-install-dir/auth/kubeconfig ${OKD_LAB_PATH}/lab-config/${CLUSTER_NAME}.${DOMAIN}/
  chmod 400 ${OKD_LAB_PATH}/lab-config/${CLUSTER_NAME}.${DOMAIN}/kubeconfig
  prepNodeFiles
}

function deployWorkers() {
  WORK_DIR=${OKD_LAB_PATH}/${CLUSTER_NAME}.${DOMAIN}
  rm -rf ${WORK_DIR}
  mkdir -p ${WORK_DIR}/ipxe-work-dir/ignition
  mkdir -p ${WORK_DIR}/dns-work-dir
  
  ${OC} extract -n openshift-machine-api secret/worker-user-data --keys=userData --to=- > ${WORK_DIR}/ipxe-work-dir/worker.ign
  let node_count=$(yq e ".compute-nodes" ${CLUSTER_CONFIG} | yq e 'length' -)
  let node_index=0
  while [[ node_index -lt ${node_count} ]]
  do
    host_name=${CLUSTER_NAME}-worker-${node_index}
    yq e ".compute-nodes.[${node_index}].name = \"${host_name}\"" -i ${CLUSTER_CONFIG}
    ip_addr=$(yq e ".compute-nodes.[${node_index}].ip-addr" ${CLUSTER_CONFIG})
    ceph_node=$(yq ".compute-nodes.[${node_index}] | has(\"ceph\")" ${CLUSTER_CONFIG})
    if [[ $(yq e ".compute-nodes.[${node_index}].metal" ${CLUSTER_CONFIG}) == "true" ]]
    then
      platform=metal
      boot_dev=$(yq e ".compute-nodes.[${node_index}].boot-dev" ${CLUSTER_CONFIG})
    else
      platform=qemu
      boot_dev="/dev/sda"
      memory=$(yq e ".compute-nodes.[${node_index}].node-spec.memory" ${CLUSTER_CONFIG})
      cpu=$(yq e ".compute-nodes.[${node_index}].node-spec.cpu" ${CLUSTER_CONFIG})
      root_vol=$(yq e ".compute-nodes.[${node_index}].node-spec.root-vol" ${CLUSTER_CONFIG})
      kvm_host=$(yq e ".compute-nodes.[${node_index}].kvm-host" ${CLUSTER_CONFIG})
      # Create the VM
      if [[ ${ceph_node} == "true" ]]
      then
        ceph_vol=$(yq e ".compute-nodes.[${node_index}].ceph.ceph-vol" ${CLUSTER_CONFIG})
      else
        ceph_vol=0
      fi
      createOkdVmNode ${ip_addr} ${host_name} ${kvm_host}.${DOMAIN} worker ${memory} ${cpu} ${root_vol} ${ceph_vol} ".compute-nodes.[${node_index}].mac-addr"
    fi
    # Create the ignition and iPXE boot files
    mac_addr=$(yq e ".compute-nodes.[${node_index}].mac-addr" ${CLUSTER_CONFIG}) 
    config_ceph=false
    if [[ ${ceph_node} == "true" ]]
    then
      ceph_type=$(yq e ".compute-nodes.[${node_index}].ceph.type" ${CLUSTER_CONFIG})
      if [[ ${ceph_type} == "part" ]]
      then
        config_ceph=true
      fi
    fi
    createButaneConfig ${ip_addr} ${host_name}.${DOMAIN} ${mac_addr} worker ${platform} ${config_ceph} ${boot_dev}
    createPxeFile ${mac_addr} ${platform} ${boot_dev} ${host_name} ${ip_addr}
    # Create DNS entries
    echo "${host_name}.${DOMAIN}.   IN      A      ${ip_addr} ; ${host_name}-${DOMAIN}-wk" >> ${WORK_DIR}/dns-work-dir/forward.zone
    o4=$(echo ${ip_addr} | cut -d"." -f4)
    echo "${o4}    IN      PTR     ${host_name}.${DOMAIN}. ; ${host_name}-${DOMAIN}-wk" >> ${WORK_DIR}/dns-work-dir/reverse.zone
    node_index=$(( ${node_index} + 1 ))
  done
  prepNodeFiles
}

function deploy() {
  for i in "$@"
  do
    case $i in
      -c|--cluster)
        deployCluster
      ;;
      -w|--worker)
        deployWorkers
      ;;
      -k|--kvm-hosts)
        deployKvmHosts "$@"
      ;;
      *)
        # catch all
      ;;
    esac
  done
}

