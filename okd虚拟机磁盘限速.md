
# 打开KubeVirt HyperConverged Cluster Operator对Sidecar的支持

## 修改pod kubevirt-hyperconverged的yaml文件,可以直接页面上修改,也可终端执行如下命令
### 页面修改yaml
```
apiVersion: hco.kubevirt.io/v1beta1
kind: HyperConverged
metadata:
  annotations:
    deployOVS: 'false'
    kubevirt.kubevirt.io/jsonpatch: >-
      [{"op": "add", "path":
      "/spec/configuration/developerConfiguration/featureGates/-", "value":
      "Sidecar" }]
```
### 终端命令
```
kubectl annotate --overwrite -n kubevirt-hyperconverged hco kubevirt-hyperconverged kubevirt.kubevirt.io/jsonpatch='[{"op": "add", "path": "/spec/configuration/developerConfiguration/featureGates/-", "value": "Sidecar" }]'
```

## 钩子仓库
https://github.com/zzzzzhy/kubevirt-hook-virt-xml

## 使用方法
在VM的yaml文件中加入
```
...
  template:
    metadata:
      annotations:
        hooks.kubevirt.io/hookSidecars: >-
            [{"args": ["--args","all"], "image":
            "docker.io/rubyroes/virt-xml-hook:latest"}]
        virt.xml.hook/readBytesSec: '5120000'
        virt.xml.hook/writeBytesSec: '5120000'
        virt.xml.hook/readIopsSec: '1000'
        virt.xml.hook/writeIopsSec: '1000'
...
```
<details> <summary>完整例子</summary>
 <pre><code>
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  annotations:
    kubemacpool.io/transaction-timestamp: '2023-04-17T10:34:33.92456864Z'
    kubevirt.io/latest-observed-api-version: v1
    kubevirt.io/storage-observed-api-version: v1alpha3
    vm.kubevirt.io/validations: |
      [
        {
          "name": "minimal-required-memory",
          "path": "jsonpath::.spec.domain.resources.requests.memory",
          "rule": "integer",
          "message": "This VM requires more memory.",
          "min": 1073741824
        }
      ]
  resourceVersion: '15566208'
  name: '123'
  uid: ae2b5bc3-2348-420f-bb6b-251beda6beeb
  creationTimestamp: '2023-04-12T06:12:12Z'
  generation: 188
  managedFields:
    - apiVersion: kubevirt.io/v1
      fieldsType: FieldsV1
      fieldsV1:
        'f:metadata':
          'f:annotations':
            .: {}
            'f:kubemacpool.io/transaction-timestamp': {}
            'f:vm.kubevirt.io/validations': {}
          'f:labels':
            .: {}
            'f:app': {}
            'f:vm.kubevirt.io/template': {}
            'f:vm.kubevirt.io/template.namespace': {}
            'f:vm.kubevirt.io/template.revision': {}
            'f:vm.kubevirt.io/template.version': {}
        'f:spec':
          .: {}
          'f:dataVolumeTemplates': {}
          'f:template':
            .: {}
            'f:metadata':
              .: {}
              'f:annotations':
                .: {}
                'f:hooks.kubevirt.io/hookSidecars': {}
                'f:virt.xml.hook/readBytesSec': {}
                'f:vm.kubevirt.io/flavor': {}
                'f:vm.kubevirt.io/os': {}
                'f:vm.kubevirt.io/workload': {}
              'f:creationTimestamp': {}
              'f:labels':
                .: {}
                'f:kubevirt.io/domain': {}
                'f:kubevirt.io/size': {}
            'f:spec':
              .: {}
              'f:domain':
                .: {}
                'f:cpu':
                  .: {}
                  'f:cores': {}
                  'f:sockets': {}
                  'f:threads': {}
                'f:devices':
                  .: {}
                  'f:disks': {}
                  'f:interfaces': {}
                  'f:networkInterfaceMultiqueue': {}
                  'f:rng': {}
                'f:features':
                  .: {}
                  'f:acpi': {}
                  'f:smm':
                    .: {}
                    'f:enabled': {}
                'f:firmware':
                  .: {}
                  'f:bootloader':
                    .: {}
                    'f:efi': {}
                'f:machine':
                  .: {}
                  'f:type': {}
                'f:resources':
                  .: {}
                  'f:requests':
                    .: {}
                    'f:memory': {}
              'f:networks': {}
              'f:terminationGracePeriodSeconds': {}
              'f:volumes': {}
      manager: Mozilla
      operation: Update
      time: '2023-04-17T10:34:17Z'
    - apiVersion: kubevirt.io/v1alpha3
      fieldsType: FieldsV1
      fieldsV1:
        'f:metadata':
          'f:annotations':
            'f:kubevirt.io/latest-observed-api-version': {}
            'f:kubevirt.io/storage-observed-api-version': {}
        'f:spec':
          'f:running': {}
      manager: Go-http-client
      operation: Update
      time: '2023-04-17T10:34:33Z'
    - apiVersion: kubevirt.io/v1alpha3
      fieldsType: FieldsV1
      fieldsV1:
        'f:status':
          .: {}
          'f:conditions': {}
          'f:printableStatus': {}
          'f:volumeSnapshotStatuses': {}
      manager: Go-http-client
      operation: Update
      subresource: status
      time: '2023-04-17T10:34:39Z'
  namespace: default
  labels:
    app: '123'
    vm.kubevirt.io/template: fedora-server-small
    vm.kubevirt.io/template.namespace: openshift
    vm.kubevirt.io/template.revision: '1'
    vm.kubevirt.io/template.version: v0.24.1
spec:
  dataVolumeTemplates:
    - apiVersion: cdi.kubevirt.io/v1beta1
      kind: DataVolume
      metadata:
        creationTimestamp: null
        name: '123'
      spec:
        source:
          pvc:
            name: '123'
            namespace: default
        storage:
          resources:
            requests:
              storage: 30Gi
  running: false
  template:
    metadata:
      annotations:
        hooks.kubevirt.io/hookSidecars: >-
          [{"args": ["--args","all"], "image":
          "docker.io/rubyroes/virt-xml-hook:latest"}]
        virt.xml.hook/readBytesSec: '5120000'
        vm.kubevirt.io/flavor: small
        vm.kubevirt.io/os: fedora
        vm.kubevirt.io/workload: server
      creationTimestamp: null
      labels:
        kubevirt.io/domain: '123'
        kubevirt.io/size: small
    spec:
      domain:
        cpu:
          cores: 1
          sockets: 1
          threads: 1
        devices:
          disks:
            - disk:
                bus: virtio
              name: rootdisk
          interfaces:
            - macAddress: '02:71:74:00:00:17'
              masquerade: {}
              model: virtio
              name: default
          networkInterfaceMultiqueue: true
          rng: {}
        features:
          acpi: {}
          smm:
            enabled: true
        firmware:
          bootloader:
            efi: {}
        machine:
          type: q35
        resources:
          requests:
            memory: 2Gi
      networks:
        - name: default
          pod: {}
      terminationGracePeriodSeconds: 180
      volumes:
        - dataVolume:
            name: '123'
          name: rootdisk
status:
  conditions:
    - lastProbeTime: '2023-04-17T10:34:39Z'
      lastTransitionTime: '2023-04-17T10:34:39Z'
      message: VMI does not exist
      reason: VMINotExists
      status: 'False'
      type: Ready
    - lastProbeTime: null
      lastTransitionTime: null
      message: >-
        cannot migrate VMI: PVC 123 is not shared, live migration requires that
        all PVCs must be shared (using ReadWriteMany access mode)
      reason: DisksNotLiveMigratable
      status: 'False'
      type: LiveMigratable
  printableStatus: Stopped
  volumeSnapshotStatuses:
    - enabled: false
      name: rootdisk
      reason: >-
        No VolumeSnapshotClass: Volume snapshots are not configured for this
        StorageClass [rook-ceph-block] [rootdisk]
</code></pre>
</details>