# 创建rbd存储
oc apply -f csi/rbd/storageclass.yaml

# 创建cephfs存储
oc apply -f filesystem.yaml
oc apply -f csi/cephfs/storageclass.yaml

# 创建对象存储