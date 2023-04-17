# 添加OSD
要添加更多 OSD，Rook 会自动监视添加到集群中的新节点和设备。 如果它们与集群 CR 的存储部分中的过滤器或其他设置匹配，则操作员将创建新的 OSD。

在更动态的环境中，可以使用原始块存储提供程序动态配置存储，OSD 可以由 PVC 支持。
要添加更多 OSD，您可以增加现有设备集中 OSD 的数量，也可以将更多设备集添加到集群 CR。 然后，Operator 会根据更新后的集群 CR 自动创建新的 OSD。

# 移除OSD
要因磁盘故障或其他重新配置而移除 OSD，请考虑以下事项以确保数据在移除过程中的健康：

1. 确认删除 OSD 后集群上有足够的空间来正确处理删除
2. 确认剩余的 OSD 及其归置组 (PG) 是健康的，以便处理数据的重新平衡
3. 不要一次删除太多 OSD
4. 等待移除多个 OSD 之间的重新平衡
5. 当node下只有一个osd时无法通过这种方式移除

更新您的 CephCluster CR。根据您的 CR 设置，您可能需要从列表中删除设备或更新设备过滤器。如果您使用 useAllDevices: true，则无需更改 CR。

## 基于主机的集群
> 在基于主机的集群上，您可能需要在执行 OSD 删除步骤时停止 Rook Operator，以防止 Rook 在擦除或删除磁盘之前检测到旧 OSD 并尝试重新创建它。
### 1.停止 Rook Operator

```
kubectl -n rook-ceph scale deployment rook-ceph-operator --replicas=0
```

### 2.确认关闭OSD

```
kubectl -n rook-ceph scale deployment rook-ceph-osd-<ID> --replicas=0 
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd down osd.<ID>
```

### 3.从 Ceph 集群中清除 OSD
> 在 osd-purge.yaml 中，将 <OSD-IDs> 更改为要删除的 OSD 的 ID。
```
kubectl create -f osd-purge.yaml
```

### 4.查看日志以确保成功

```
kubectl -n rook-ceph logs -l app=rook-ceph-purge-osd
```

### 5.开始删除

```
kubectl delete -f osd-purge.yaml
```

### 6.开启 Rook Operator

```
kubectl -n rook-ceph scale deployment rook-ceph-operator --replicas=1
```

## 基于 PVC 的集群

### 1.停止 Rook Operator

```
kubectl -n rook-ceph scale deployment rook-ceph-operator --replicas=0
```

### 2.缩减 CephCluster CR 中 storageClassDeviceSets 中的 OSD 数量。如果您有多个设备集，您可能需要在此示例路径中更改 0 的索引。
<desired number>:最终所需数量

```
kubectl -n rook-ceph patch CephCluster rook-ceph --type=json -p '[{"op": "replace", "path": "/spec/storage/storageClassDeviceSets/0/count", "value":2}]'
```

### 3.识别属于失败或被移除的 OSD 的 PVC。
```
kubectl -n rook-ceph get pvc -l ceph.rook.io/DeviceSet=<deviceSet>
```

### 4.确定您要删除的 OSD
分配给 PVC 的 OSD 可以在 PVC 上的标签中找到
```
kubectl -n rook-ceph get pod -l ceph.rook.io/pvc=<orphaned-pvc> -o yaml | grep ceph-osd-id
```

### 剩下步骤跟基于主机的集群第2步开始

>  如果在激活时出现 Error EINVAL: entity osd.0 exists but key does not match osd.0 does not exist. create it before updating the crush map RuntimeError: Failed to execute command: ceph-disk -v activate --mark-init sysvinit --mount /ceph/osd1 
> A：类似的错误，请在要激活的节点上使用ceph osd create命令后重新激活
