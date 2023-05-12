csi-config-map.yaml
```

---
apiVersion: v1
kind: ConfigMap
data:
  config.json: |-
    [
       {
        "clusterID": "f9373be0-c20b-11ed-8ffc-1d8857dcc8a4",  
        "monitors": [
          "43.229.28.25:6789",
          "43.229.28.32:6789",
          "43.229.28.33:6789"
        ]
      },
      {
        "clusterID": "89bc6b66-eaea-11ed-ad7d-e138c36c1e52",
        "monitors": [
          "43.229.28.58:6789",
          "43.229.28.59:6789",
          "43.229.28.60:6789"
        ]
      }
    ]
metadata:
  name: ceph-csi-config

```

新的sercret

ceph-sercret-ssd.yaml

```
---
apiVersion: v1
kind: Secret
metadata:
  name: csi-rbd-secret-ssd
  #namespace: default
stringData:
  # Key values correspond to a user name and its key, as defined in the
  # ceph cluster. User ID should have required access to the 'pool'
  # specified in the storage class
  userID: admin
  userKey: AQCbZlRkoHxiDBAAYc0EareoLE+sM91gjLW6HQ==

  # Encryption passphrase
  # encryptionPassphrase: test_passphrase
```

新的storageclass

storageclass-ssd.yaml
```
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: csi-ceph-rdb-ssd
provisioner: rbd.csi.ceph.com
parameters:
  clusterID: 89bc6b66-eaea-11ed-ad7d-e138c36c1e52 #新的ceph集群id
  pool: kubernetes  #创建的pool名
  imageFeatures: layering,fast-diff,object-map,deep-flatten,exclusive-lock
  csi.storage.k8s.io/provisioner-secret-name: csi-rbd-secret-ssd
  csi.storage.k8s.io/provisioner-secret-namespace: default
  csi.storage.k8s.io/controller-expand-secret-name: csi-rbd-secret-ssd
  csi.storage.k8s.io/controller-expand-secret-namespace: default
  csi.storage.k8s.io/node-stage-secret-name: csi-rbd-secret-ssd
  csi.storage.k8s.io/node-stage-secret-namespace: default
  csi.storage.k8s.io/fstype: ext4  #文件格式
reclaimPolicy: Delete
allowVolumeExpansion: true
mountOptions:
  - discard
```

pvc测试

```
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ceph-ssd-test  
spec:
  accessModes:
    - ReadWriteOnce
      #volumeMode: Block
  resources:
    requests:
      storage: 1Gi   
  storageClassName: csi-ceph-rdb-ssd 
```

pod 测试

```
---
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod1
  labels:
    name: nginx-pod1
spec:
  containers:
  - name: nginx-pod1
    image: nginx:alpine
    ports:
    - name: web
      containerPort: 80
    volumeMounts:
    - name: ceph-rdb
      mountPath: /usr/share/nginx/html
  volumes:
  - name: ceph-rdb
    persistentVolumeClaim:
      claimName: ceph-ssd-test

```

结果
```
Name:             nginx-pod1
Namespace:        default
Priority:         0
Service Account:  default
Node:             k8s-2/43.229.28.34
Start Time:       Thu, 11 May 2023 14:26:45 +0800
Labels:           name=nginx-pod1
Annotations:      k8s.v1.cni.cncf.io/network-status:
                    [{
                        "name": "cbr0",
                        "interface": "eth0",
                        "ips": [
                            "10.11.1.83"
                        ],
                        "mac": "42:d1:3e:1c:46:5c",
                        "default": true,
                        "dns": {}
                    }]
Status:           Running
IP:               10.11.1.83
IPs:
  IP:  10.11.1.83
Containers:
  nginx-pod1:
    Container ID:   containerd://7236869c177dbceefdf930f0ec8b9969209992a01daf2beeb48ba97cdb1acdfd
    Image:          nginx:alpine
    Image ID:       docker.io/library/nginx@sha256:6318314189b40e73145a48060bff4783a116c34cc7241532d0d94198fb2c9629
    Port:           80/TCP
    Host Port:      0/TCP
    State:          Running
      Started:      Thu, 11 May 2023 14:26:58 +0800
    Ready:          True
    Restart Count:  0
    Environment:    <none>
    Mounts:
      /usr/share/nginx/html from ceph-rdb (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-whtkl (ro)
Conditions:
  Type              Status
  Initialized       True 
  Ready             True 
  ContainersReady   True 
  PodScheduled      True 
Volumes:
  ceph-rdb:
    Type:       PersistentVolumeClaim (a reference to a PersistentVolumeClaim in the same namespace)
    ClaimName:  ceph-ssd-test
    ReadOnly:   false
  kube-api-access-whtkl:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  3607
    ConfigMapName:           kube-root-ca.crt
    ConfigMapOptional:       <nil>
    DownwardAPI:             true
QoS Class:                   BestEffort
Node-Selectors:              <none>
Tolerations:                 node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
                             node.kubernetes.io/unreachable:NoExecute op=Exists for 300s
Events:
  Type    Reason                  Age   From                     Message
  ----    ------                  ----  ----                     -------
  Normal  Scheduled               31s   default-scheduler        Successfully assigned default/nginx-pod1 to k8s-2
  Normal  SuccessfulAttachVolume  31s   attachdetach-controller  AttachVolume.Attach succeeded for volume "pvc-69e3f6c5-0823-486e-b7d5-9d3a9e8980a3"
  Normal  AddedInterface          21s   multus                   Add eth0 [10.11.1.83/24] from cbr0
  Normal  Pulled                  21s   kubelet                  Container image "nginx:alpine" already present on machine
  Normal  Created                 20s   kubelet                  Created container nginx-pod1
  Normal  Started                 19s   kubelet                  Started container nginx-pod1
```