#!/usr/bin/env bash
VCENTER="<vcenter name or IP>"
VC_ADMIN="<vc admin>"
VC_PASS="<vc password>"
VC_DATACENTER="<vc datacentername>"
VC_NETWORK="<vc vm network name>"
#Unique to each K8s cluster of VM's must be unique within the vCenter
CLUSTER_UUID="dev-k8s-cluster-1874"

usage()
{
    echo "Usage : $0 edit the local install.sh file with your vcenter information."
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit
fi

# 1. Create config-map for Cloud Controller Manager

echo "
apiVersion: v1
kind: Secret
metadata:
  name: cloud-provider-secret
  namespace: kube-system
stringData:
  ${VCENTER}.user: \"${VC_ADMIN}\"
  ${VCENTER}.password: \"${VC_PASS}\"
" | kubectl apply -f -

echo "
[Global]
insecure-flag = \"true\"
secret-name = \"cloud-provider-secret\"
secret-namespace = \"kube-system\" 

[VirtualCenter \"${VCENTER}\"]
# user = \"${VC_ADMIN}\"
# password = \"${VC_PASS}\"
port = \"443\"
datacenters = \"${VC_DATACENTER}\"
  
[Network]
public-network = \"${VC_NETWORK}\"

" > vsphere.conf 
kubectl --namespace=kube-system create configmap cloud-config --from-file vsphere.conf
#clean up temp file
rm vsphere.conf

NODES=$(kubectl get nodes -o name)

for n in $NODES
do
    kubectl taint nodes $n node.cloudprovider.kubernetes.io/uninitialized=true:NoSchedule
done
#Verify Taints
#kubectl describe nodes | egrep "Taints:|Name:"

kubectl apply -f https://raw.githubusercontent.com/kubernetes/cloud-provider-vsphere/master/manifests/controller-manager/cloud-controller-manager-roles.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/cloud-provider-vsphere/master/manifests/controller-manager/cloud-controller-manager-role-bindings.yaml
kubectl apply -f https://github.com/kubernetes/cloud-provider-vsphere/raw/master/manifests/controller-manager/vsphere-cloud-controller-manager-ds.yaml

kubectl -n kube-system get pod

NODES=$(kubectl get nodes -o name)
for n in $NODES
do
    kubectl taint nodes $n node.cloudprovider.kubernetes.io/uninitialized=true:NoSchedule-
done

# 2. Install the vSphere Container Storage Interface Driver

MASTERS=$(kubectl get node --selector='node-role.kubernetes.io/master' -o name)
for n in $MASTERS
do
    kubectl taint nodes $n node-role.kubernetes.io/master=:NoSchedule
done
kubectl describe nodes | egrep "Taints:|Name:"

echo "
[Global]
cluster-id = \"${CLUSTER_UUID}\"


[VirtualCenter \"${VCENTER}\"]
insecure-flag = \"true\"
user = \"${VC_ADMIN}\"
password = \"${VC_PASS}\"
port = \"443\"
datacenters = \"${VC_DATACENTER}\"

" > csi-vsphere.conf 
#Create the CSI secret
kubectl create secret generic vsphere-config-secret --from-file=csi-vsphere.conf --namespace=kube-system
#Verify Creation
kubectl get secret vsphere-config-secret --namespace=kube-system
#Remove local temp file
rm csi-vsphere.conf

tee csi-driver-rbac.yaml >/dev/null <<EOF
kind: ServiceAccount
apiVersion: v1
metadata:
  name: vsphere-csi-controller
  namespace: kube-system
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: vsphere-csi-controller-role
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["csidrivers"]
    verbs: ["create", "delete"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "update", "create", "delete"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["csinodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["volumeattachments"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["list", "watch", "create", "update", "patch"]
  - apiGroups: ["snapshot.storage.k8s.io"]
    resources: ["volumesnapshots"]
    verbs: ["get", "list"]
  - apiGroups: ["snapshot.storage.k8s.io"]
    resources: ["volumesnapshotcontents"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: vsphere-csi-controller-binding
subjects:
  - kind: ServiceAccount
    name: vsphere-csi-controller
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: vsphere-csi-controller-role
  apiGroup: rbac.authorization.k8s.io
---
EOF
#Create the CSI RBAC
kubectl create -f csi-driver-rbac.yaml

#Instal the vSphere CSI Driver
tee csi-driver-deploy.yaml >/dev/null <<'EOF'
kind: StatefulSet
apiVersion: apps/v1
metadata:
  name: vsphere-csi-controller
  namespace: kube-system
spec:
  serviceName: vsphere-csi-controller
  replicas: 1
  updateStrategy:
    type: "RollingUpdate"
  selector:
    matchLabels:
      app: vsphere-csi-controller
  template:
    metadata:
      labels:
        app: vsphere-csi-controller
        role: vsphere-csi
    spec:
      serviceAccountName: vsphere-csi-controller
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: beta.kubernetes.io/os
                operator: NotIn
                values:
                - windows
              - key: node-role.kubernetes.io/controlplane
                operator: In
                values:
                - "true"
      tolerations:
        - operator: "Exists"
          key: node-role.kubernetes.io/master
          effect: "NoSchedule"
        - operator: "Exists"
          key: node-role.kubernetes.io/controlplane
          effect: "NoSchedule"
        - operator: "Exists"
          key : node-role.kubernetes.io/etcd
          effect: "NoExecute"
      hostNetwork: true
      containers:
        - name: csi-attacher
          image: quay.io/k8scsi/csi-attacher:v1.1.1
          args:
            - "--v=4"
            - "--timeout=60s"
            - "--csi-address=$(ADDRESS)"
          env:
            - name: ADDRESS
              value: /csi/csi.sock
          volumeMounts:
            - mountPath: /csi
              name: socket-dir
        - name: vsphere-csi-controller
          image: gcr.io/cloud-provider-vsphere/csi/release/driver:v1.0.2
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "rm -rf /var/lib/csi/sockets/pluginproxy/csi.vsphere.vmware.com"]
          args:
            - "--v=4"
          imagePullPolicy: "Always"
          env:
            - name: CSI_ENDPOINT
              value: unix:///var/lib/csi/sockets/pluginproxy/csi.sock
            - name: X_CSI_MODE
              value: "controller"
            - name: X_CSI_VSPHERE_CLOUD_CONFIG
              value: "/etc/cloud/csi-vsphere.conf"
          volumeMounts:
            - mountPath: /etc/cloud
              name: vsphere-config-volume
              readOnly: true
            - mountPath: /var/lib/csi/sockets/pluginproxy/
              name: socket-dir
        - name: liveness-probe
          image: quay.io/k8scsi/livenessprobe:v1.1.0
          args:
            - "--csi-address=$(ADDRESS)"
          env:
            - name: ADDRESS
              value: /var/lib/csi/sockets/pluginproxy/csi.sock
          volumeMounts:
            - mountPath: /var/lib/csi/sockets/pluginproxy/
              name: socket-dir
        - name: vsphere-syncer
          image: gcr.io/cloud-provider-vsphere/csi/release/syncer:v1.0.2
          args:
            - "--v=2"
          imagePullPolicy: "Always"
          env:
            - name: X_CSI_FULL_SYNC_INTERVAL_MINUTES
              value: "30"
            - name: X_CSI_VSPHERE_CLOUD_CONFIG
              value: "/etc/cloud/csi-vsphere.conf"
          volumeMounts:
            - mountPath: /etc/cloud
              name: vsphere-config-volume
              readOnly: true
        - name: csi-provisioner
          image: quay.io/k8scsi/csi-provisioner:v1.2.2
          args:
            - "--v=4"
            - "--timeout=60s"
            - "--csi-address=$(ADDRESS)"
            - "--feature-gates=Topology=true"
            - "--strict-topology"
          env:
            - name: ADDRESS
              value: /csi/csi.sock
          volumeMounts:
            - mountPath: /csi
              name: socket-dir
      volumes:
      - name: vsphere-config-volume
        secret:
          secretName: vsphere-config-secret
      - name: socket-dir
        hostPath:
          path: /var/lib/csi/sockets/pluginproxy/csi.vsphere.vmware.com
          type: DirectoryOrCreate
---
apiVersion: storage.k8s.io/v1beta1
kind: CSIDriver
metadata:
  name: csi.vsphere.vmware.com
spec:
  attachRequired: true
  podInfoOnMount: false
---
kind: DaemonSet
apiVersion: apps/v1
metadata:
  name: vsphere-csi-node
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: vsphere-csi-node
  updateStrategy:
    type: "RollingUpdate"
  template:
    metadata:
      labels:
        app: vsphere-csi-node
        role: vsphere-csi
    spec:
      hostNetwork: true
      containers:
        - name: node-driver-registrar
          image: quay.io/k8scsi/csi-node-driver-registrar:v1.1.0
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "rm -rf /registration/csi.vsphere.vmware.com /var/lib/kubelet/plugins_registry/csi.vsphere.vmware.com /var/lib/kubelet/plugins_registry/csi.vsphere.vmware.com-reg.sock"]
          args:
            - "--v=4"
            - "--csi-address=$(ADDRESS)"
            - "--kubelet-registration-path=$(DRIVER_REG_SOCK_PATH)"
          env:
            - name: ADDRESS
              value: /csi/csi.sock
            - name: DRIVER_REG_SOCK_PATH
              value: /var/lib/kubelet/plugins_registry/csi.vsphere.vmware.com/csi.sock
          securityContext:
            privileged: true
          volumeMounts:
            - name: plugin-dir
              mountPath: /csi
            - name: registration-dir
              mountPath: /registration
        - name: vsphere-csi-node
          image: vmware/vsphere-block-csi-driver:v1.0.0
          imagePullPolicy: "Always"
          env:
            - name: CSI_ENDPOINT
              value: unix:///csi/csi.sock
            - name: X_CSI_MODE
              value: "node"
            - name: X_CSI_SPEC_REQ_VALIDATION
              value: "false"
            - name: X_CSI_VSPHERE_CLOUD_CONFIG
              value: "/etc/cloud/csi-vsphere.conf"
          args:
            - "--v=4"
          securityContext:
            privileged: true
            capabilities:
              add: ["SYS_ADMIN"]
            allowPrivilegeEscalation: true
          volumeMounts:
            - name: vsphere-config-volume
              mountPath: /etc/cloud
            - name: plugin-dir
              mountPath: /csi
            - name: pods-mount-dir
              mountPath: /var/lib/kubelet
              # needed so that any mounts setup inside this container are
              # propagated back to the host machine.
              mountPropagation: "Bidirectional"
            - name: device-dir
              mountPath: /dev
        - name: liveness-probe
          image: quay.io/k8scsi/livenessprobe:v1.1.0
          args:
            - "--csi-address=$(ADDRESS)"
          env:
            - name: ADDRESS
              value: /csi/csi.sock
          volumeMounts:
            - name: plugin-dir
              mountPath: /csi
      volumes:
        - name: vsphere-config-volume
          secret:
            secretName: vsphere-config-secret
        - name: registration-dir
          hostPath:
            path: /var/lib/kubelet/plugins_registry
            type: DirectoryOrCreate
        - name: plugin-dir
          hostPath:
            path: /var/lib/kubelet/plugins_registry/csi.vsphere.vmware.com
            type: DirectoryOrCreate
        - name: pods-mount-dir
          hostPath:
            path: /var/lib/kubelet
            type: Directory
        - name: device-dir
          hostPath:
            path: /dev
---
EOF

kubectl create -f csi-driver-deploy.yaml

#Verify installation

kubectl get statefulset --namespace=kube-system
kubectl get daemonsets vsphere-csi-node --namespace=kube-system
kubectl get pods --namespace=kube-system

kubectl get CSINode

# echo "
# kind: StorageClass
# apiVersion: storage.k8s.io/v1
# metadata:
#   name: cns-vvols
#   annotations:
#     storageclass.kubernetes.io/is-default-class: \"false\"
# provisioner: csi.vsphere.vmware.com
# parameters:
#   # storagepolicyname: \"pure-vvols\"
#   DatastoreURL: \"ds:///vmfs/volumes/vvol:373bb977d8ca3de8-a41c2e2c4d1f43e6/\"
#   fstype: ext4
# " > pure-cns-vvols.yaml
# kubectl create -f pure-cns-vvols.yaml
