# Quickly Intalling Cloud Native Storage and Rancher Custom Clusters

**Prereqs**
Install K8s on VM's and make sure **disk.EnableUUID=1** setting is set in the vms. [CNS Documentation](https://docs.vmware.com/en/VMware-vSphere/6.7/Cloud-Native-Storage/GUID-3501C3F2-7D7C-45E9-B20A-F3F70D1E4679.html)

Step 1.
clone this repo
```
git clone https://github.com/2vcps/cns-installer.git
```

Step 2. 
Get your vCenter information from your VI admin. Edit the install.sh file to contain the correct settings.
```
VCENTER="<vcenter name or IP>"
VC_ADMIN="<vc admin>"
VC_PASS="<vc password>"
VC_DATACENTER="<vc datacentername>"
VC_NETWORK="<vc vm network name>"
```

Step 3. 
Create a vSAN Datastore

Step 4. 
```
# ./install.sh
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
