## Configure vSphere Container Native Storage with Rancher Custom Clusters

**Prereqs**
- The host VMs must be hardware **version 15** or higher
- Install K8s on VM's must have **disk.EnableUUID=1** set.

Step 1.
Create the Rancher cluster with the follow `cloud_provider` configuration.
```
  cloud_provider:
    name: vsphere
    vsphereCloudProvider:
      global:
        insecure-flag: true # Or "false"
      virtual_center:
        vcenter.example.com:
          datacenters: datacenter
          port: '443'
          user: username
          password: password
      workspace:
        datacenter: /datacenter
        default-datastore: datastore
        folder: /datacenter/vm
        resourcepool-path: /datacenter/host/cluster/Resources/resourcepool
        server: vcenter.example.com
```

Step 2.
clone this repo
```
git clone https://github.com/eroji/cns-installer.git
```

Step 3. 
Get your vCenter information from your VI admin. Edit the install.sh file to contain the correct settings.
```
VCENTER="<vcenter name or IP>"
VC_ADMIN="<vc admin>"
VC_PASS="<vc password>"
VC_DATACENTER="<vc datacentername>"
VC_NETWORK="<vc vm network name>"
```

Step 4. 
```
# ./install.sh
```

Step 5.
Create StorageClass referencing DataStore.
```
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: cns-vsan
  annotations:
    storageclass.kubernetes.io/is-default-class: "true" # Or "false" if not default
provisioner: csi.vsphere.vmware.com
parameters:
  storagepolicyname: "vSAN Default Storage Policy" # Change this as needed
  DatastoreURL: ds:///vmfs/volumes/vsan:<uuid>/
  fstype: ext4
```

### To Remove
Remove all PVC's created with the Storage Class. 
```
kubectl delete pvc <pvcname>
```

Then run the cleanup script.
```
./uninstall.sh
```

You can run ```kubectl get all --all-namespaces``` to verify

### Note
If the CSI driver for vSphere does not start, the Cloud Controller may not have untainted the nodes when it initilized. I am have seen it work automatically and also had to run this:
```
NODES=$(kubectl get nodes -o name)
for n in $NODES
do
    kubectl taint nodes $n node.cloudprovider.kubernetes.io/uninitialized=true:NoSchedule-
done
kubectl describe nodes | egrep "Taints:|Name:"
```

### References
- https://docs.vmware.com/en/VMware-vSphere/6.7/Cloud-Native-Storage/GUID-3501C3F2-7D7C-45E9-B20A-F3F70D1E4679.html
- https://rancher.com/docs/rke/latest/en/config-options/cloud-providers/vsphere/config-reference/
