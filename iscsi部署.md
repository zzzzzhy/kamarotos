### 前提条件
已部署k8s,并且是主节点查看下面步骤
# ubuntu部署
## 安装依赖
```
sudo apt install ceph-iscsi ceph-common rsync
```

## rook编排部署ceph
```
$ git clone --single-branch --branch v1.11.2 https://github.com/rook/rook.git
cd rook/deploy/examples
kubectl create -f crds.yaml -f common.yaml -f operator.yaml
kubectl -n rook-ceph get pod
# 验证 rook-ceph-operator 是 Running 状态后
kubectl create -f cluster.yaml
# 可选操作,配置dashboard面板,如果需要http,需要在创建cluster.yaml前修改cluster.yaml文件,将dashboard下的ssl关闭,执行dashboard-external-http.yaml
kubectl create -f dashboard-external-https.yaml
```

## 如果出现以下pod状态,说明已经部署成功ceph
```
$ kubectl -n rook-ceph get pod
NAME                                                 READY   STATUS      RESTARTS   AGE
csi-cephfsplugin-provisioner-d77bb49c6-n5tgs         5/5     Running     0          140s
csi-cephfsplugin-provisioner-d77bb49c6-v9rvn         5/5     Running     0          140s
csi-cephfsplugin-rthrp                               3/3     Running     0          140s
csi-rbdplugin-hbsm7                                  3/3     Running     0          140s
csi-rbdplugin-provisioner-5b5cd64fd-nvk6c            6/6     Running     0          140s
csi-rbdplugin-provisioner-5b5cd64fd-q7bxl            6/6     Running     0          140s
rook-ceph-crashcollector-minikube-5b57b7c5d4-hfldl   1/1     Running     0          105s
rook-ceph-mgr-a-64cd7cdf54-j8b5p                     1/1     Running     0          77s
rook-ceph-mon-a-694bb7987d-fp9w7                     1/1     Running     0          105s
rook-ceph-mon-b-856fdd5cb9-5h2qk                     1/1     Running     0          94s
rook-ceph-mon-c-57545897fc-j576h                     1/1     Running     0          85s
rook-ceph-operator-85f5b946bd-s8grz                  1/1     Running     0          92m
rook-ceph-osd-0-6bb747b6c5-lnvb6                     1/1     Running     0          23s
rook-ceph-osd-1-7f67f9646d-44p7v                     1/1     Running     0          24s
rook-ceph-osd-2-6cd4b776ff-v4d68                     1/1     Running     0          25s
rook-ceph-osd-prepare-node1-vx2rz                    0/2     Completed   0          60s
rook-ceph-osd-prepare-node2-ab3fd                    0/2     Completed   0          60s
rook-ceph-osd-prepare-node3-w4xyz                    0/2     Completed   0          60s
```


## 创建rbd存储池
```
kubectl create -f toolbox.yaml
kubectl -n rook-ceph rollout status deploy/rook-ceph-tools
#等待running状态后,进入pod
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- bash
#查看现有存储池
ceph osd lspools
#创建名为lvrbd的存储池
sudo ceph osd pool create lvrbd
sudo rbd pool init lvrbd
#完成后再次检查 ceph osd lspools 可以看到名为 lvrbd 的存储池
```

## 配置iscsi
```
#创建或编辑/etc/ceph/iscsi-gateway.cfg文件
cat > /etc/ceph/iscsi-gateway.cfg<<EOF
[config]
# Name of the Ceph storage cluster. A suitable Ceph configuration file allowing
# access to the Ceph storage cluster from the gateway node is required, if not
# colocated on an OSD node.
cluster_name = ceph

# Place a copy of the ceph cluster's admin keyring in the gateway's /etc/ceph
# directory and reference the filename here
gateway_keyring = ceph.client.admin.keyring


# API settings.
# The API supports a number of options that allow you to tailor it to your
# local environment. If you want to run the API under https, you will need to
# create cert/key files that are compatible for each iSCSI gateway node, that is
# not locked to a specific node. SSL cert and key files *must* be called
# 'iscsi-gateway.crt' and 'iscsi-gateway.key' and placed in the '/etc/ceph/' directory
# on *each* gateway node. With the SSL files in place, you can use 'api_secure = true'
# to switch to https mode.

# To support the API, the bare minimum settings are:
api_secure = false

# Additional API configuration options are as follows, defaults shown.
api_user = admin
api_password = admin
api_port = 5001
#是每个iSCSI网关上的IP地址列表
trusted_ip_list = 10.11.0.1,10.11.1.1
EOF
# 然后将/etc/ceph/目录下的所有文件复制出来,退出pod
exit
# 放入所有需要配置iscsi网关的服务器上 /etc/ceph/
rsync -a --exclude='rbdmap' /etc/ceph/ username@ipaddr:/etc/ceph/
```

## 启动服务
```
sudo systemctl daemon-reload 
sudo systemctl enable rbd-target-gw 
sudo systemctl start rbd-target-gw
sudo systemctl enable rbd-target-api
sudo systemctl start rbd-target-api
# 相关日志存放在/var/log/rbd-target-api 和 /var/log/rbd-target-gw
```

### 添加iSCSI网关到Ceph管理Dashboard
```
echo "http://admin:admin@10.11.0.1:5001" > /tmp/iscsi-gw-1
echo "http://admin:admin@10.11.1.1:5001" > /tmp/iscsi-gw-2
ceph dashboard iscsi-gateway-add -i iscsi-gw /tmp/iscsi-gw-1
ceph dashboard iscsi-gateway-add -i iscsi-gw /tmp/iscsi-gw-2
```

## 配置target
```
gwcli
```

### 进入一个类似文件系统的层次结构，你可以简单执行 ls 命令，可以看到结合了底层 iSCSI target 和 rdb 的树状结构
```
/> ls /
o- / ................................................................... [...]
  o- cluster ................................................... [Clusters: 1]
  | o- ceph ...................................................... [HEALTH_OK]
  |   o- pools .................................................... [Pools: 3]
  |   | o- .mgr ............ [(x3), Commit: 0.00Y/46368320K (0%), Used: 1356K]
  |   | o- libvirt-pool ...... [(x3), Commit: 0.00Y/46368320K (0%), Used: 12K]
  |   | o- rbd ............... [(x3), Commit: 0.00Y/46368320K (0%), Used: 12K]
  |   o- topology .......................................... [OSDs: 3,MONs: 3]
  o- disks ................................................. [0.00Y, Disks: 0]
  o- iscsi-targets ......................... [DiscoveryAuth: None, Targets: 0]
```

### 进入 iscsi-targets,创建名为 iqn.2023-03.io.cloud.iscsi-gw:iscsi-igw 的iSCSI target
```
/> cd iscsi-targets
/iscsi-targets> ls
o- iscsi-targets ..................... [DiscoveryAuth: None, Targets: 0]
/iscsi-targets> create iqn.2023-03.io.cloud.iscsi-gw:iscsi-igw
ok
```

### 创建iSCSI网关，这里IP地址是用于读写命令的，可以和 trusted_ip_list 一致,ceph11 ceph12是本地域名
```
/iscsi-targets> cd iqn.2023-03.io.cloud.iscsi-gw:iscsi-igw/gateways/
/iscsi-target...-igw/gateways> create ceph11 10.11.0.1 skipchecks=true
OS version/package checks have been bypassed
Adding gateway, sync'ing 0 disk(s) and 0 client(s)
ok
/iscsi-target...-igw/gateways> create ceph12 10.11.0.1 skipchecks=true
OS version/package checks have been bypassed
Adding gateway, sync'ing 0 disk(s) and 0 client(s)
ok
```

### 创建一个 initator 名为 iqn.1989-06.io.cloud-atlas:libvirt-client 客户端，并且配置intiator的CHAP名字和密码，然后再把创建的RBD镜像磁盘添加给用
```
/disks> cd /iscsi-targets/iqn.2022-12.io.cloud-atlas.iscsi-gw:iscsi-igw/hosts
/iscsi-target...csi-igw/hosts> create iqn.1989-06.io.cloud-atlas:libvirt-client
ok
/iscsi-target...ibvirt-client> auth username=libvirtd password=mypassword12
ok
/iscsi-target...ibvirt-client> disk add libvirt-pool/vm_disk
ok
```

### 以上gwcli操作均可在Dashboard页面完成,具体步骤请自行摸索

-----------------------

# k8s使用 iscsi 存储
sc.yaml
```
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: manual
provisioner: manual
```
pv.yaml
```
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: iscsiplugin-pv
  labels:
    name: data-iscsiplugin
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteOnce
  capacity:
    storage: 1Gi
  iscsi:
    targetPortal: 10.11.1.1:3260
    iqn: iqn.2023-03.com.ceph:1679554531624
    initiatorName: iqn.2023-03.com.ceph:1679554531624-client
    lun: 0
    fsType: ext4
    chapAuthSession: true
    secretRef:
       name: chap-secret
```
pvc.yaml
```
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: iscsiplugin-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 512Mi
  storageClassName: manual
  selector:
    matchExpressions:
      - key: name
        operator: In
        values: ["data-iscsiplugin"]
```

chap-secret.yaml
```
---
apiVersion: v1
kind: Secret
metadata:
  name: chap-secret
type: "kubernetes.io/iscsi-chap"
data:
  node.session.auth.username: aGl0b3NlYTIK
  node.session.auth.password: MTIzMTIzMTIzMTIzCg==
```

pod.yaml
```
---
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
    - image: maersk/nginx
      imagePullPolicy: Always
      name: nginx
      ports:
        - containerPort: 80
          protocol: TCP
      volumeMounts:
        - mountPath: /var/www
          name: iscsi-volume
  volumes:
    - name: iscsi-volume
      persistentVolumeClaim:
        claimName: iscsiplugin-pvc
```

执行
```
kubectl create -f sc.yaml chap-secret.yaml pvc.yaml pv.yaml
# 等待pv,pvc绑定成功后
kubectl create -f pod.yaml
```