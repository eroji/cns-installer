# Quickly Intalling Cloud Native Storage for Pure Storage

Step 1.
clone this repo
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
Create a VMFS Datastore (Sorry vVols is not yet supported by VMWare)

Step 4.
VMware requires all the master to be tainted this way. 
```
MASTERS=$(kubectl get node --selector='node-role.kubernetes.io/master' -o name)
for n in $MASTERS
do
    kubectl taint nodes $n node-role.kubernetes.io/master=:NoSchedule
done
kubectl describe nodes | egrep "Taints:|Name:"
```

Step 5. 
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
