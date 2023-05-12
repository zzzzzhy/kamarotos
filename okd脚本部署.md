# 设备
1台bastion 2c4g
1台openwrt 1c1g 设置初始lanIP为192.168.5.1
1台bootstrap >8c8g
3台master >8g8c
2台worker

# TIPS:
虚拟机不同的引导启动方式使用不同的引导文件,bios使用undionly.kpxe, efi使用ipxe.efi
在openwrt的DHCP页面pxe/tftp页设置

# 步骤
## bastion执行
### 克隆脚本,配置环境
```
mkdir -p ${HOME}/okd-lab/bin
git clone https://github.com/zzzzzhy/kamarotos.git 
WORK_DIR=${HOME}/kamarotos
cp ${WORK_DIR}/bin/* ${HOME}/okd-lab/bin
chmod 700 ${HOME}/okd-lab/bin/*
mkdir -p ${HOME}/okd-lab/lab-config/cluster-configs
cp -r ${WORK_DIR}/examples ${HOME}/okd-lab/lab-config
cp ${HOME}/okd-lab/lab-config/examples/basic-lab-3-node.yaml ${HOME}/okd-lab/lab-config
cp ${HOME}/okd-lab/lab-config/examples/cluster-configs/3-node-no-pi.yaml ${HOME}/okd-lab/lab-config/cluster-configs
ln -s ${HOME}/okd-lab/lab-config/basic-lab-3-node.yaml ${HOME}/okd-lab/lab-config/lab.yaml
echo ". ${HOME}/okd-lab/bin/labEnv.sh" >> ~/.bashrc
source .bashrc
mkdir ${OKD_LAB_PATH}/yq-tmp
YQ_VER=$(basename $(curl -Ls -o /dev/null -w %{url_effective} https://github.com/mikefarah/yq/releases/latest))
wget -O ${OKD_LAB_PATH}/yq-tmp/yq.tar.gz https://github.com/mikefarah/yq/releases/download/${YQ_VER}/yq_linux_amd64.tar.gz
tar -xzf ${OKD_LAB_PATH}/yq-tmp/yq.tar.gz -C ${OKD_LAB_PATH}/yq-tmp
cp ${OKD_LAB_PATH}/yq-tmp/yq_linux_amd64 ${OKD_LAB_PATH}/bin/yq
chmod 700 ${OKD_LAB_PATH}/bin/yq
ssh-keygen -t rsa -b 4096 -N "" -f ${HOME}/.ssh/id_rsa
cp ~/.ssh/id_rsa.pub ${OKD_LAB_PATH}/ssh_key.pub
labctx dev
```

### 设置路由器网络
```
cat ${OKD_LAB_PATH}/ssh_key.pub | ssh root@192.168.5.1 "cat >> /etc/dropbear/authorized_keys"
labcli --router -i -e
```
等待路由器重启
### 设置路由器其他配置
```
labcli --router -s -e -f
```
### 获取oc等文件
```
labcli --latest
```
### 生成集群master部署文件
```
labcli --deploy -c
```
检查路由器下/www/install/fcos/4.12.0-0.okd-2023-03-18-084815/ 是否存在initrd rootfs.img vmlinuz三个文件,大小正常
以及/data/tftpboot/下的文件是否都有大小,之后开机bootstrap master
### 查看日志
```
labcli --monitor -b //bootstrap进度
labcli --monitor -j //引导节点journal log 
labcli --monitor -i //完成结果
```
# 等待安装完成...
## 添加worker节点
### 生成worker部署文件
```
labcli --deploy -w
```
### 通过csr
```
labcli --csr
```
### 全部部署完成后想新添加worker节点
编辑${HOME}/okd-lab/lab-config/cluster-configs/3-node-no-pi.yaml文件
在yaml文件中新增信息,登录openwrt页面设置静态绑定关系
```
compute-nodes:
  - metal: true
    mac-addr: "00:0c:29:10:8c:02"
    boot-dev: /dev/sda
    ip-addr: 10.11.12.234
```
### 删除worker节点
节点名称通过查看${HOME}/okd-lab/lab-config/cluster-configs/3-node-no-pi.yaml确定
labcli --destroy -w=节点名称
## 其他操作
### 卸载引导节点
```
labcli --destroy -b
```
### 卸载集群节点
```
labcli --destroy -c
```
### 取消master可调度
```
labcli --config-infra
```


### 部署ceph
```
labcli --ceph -i
labcli --ceph -c
or
$ git clone --single-branch --branch v1.11.2 https://github.com/rook/rook.git
cd rook/deploy/examples
oc create -f crds.yaml -f common.yaml -f operator.yaml
oc -n rook-ceph get pod
# 验证 rook-ceph-operator 是 Running
oc create -f cluster.yaml
```