kubectl delete -f pure-cns-vvols.yaml
rm pure-cns-vvols.yaml
kubectl delete -f csi-driver-deploy.yaml
rm csi-driver-deploy.yaml
kubectl delete -f csi-driver-rbac.yaml
rm csi-driver-rbac.yaml
kubectl delete secret vsphere-config-secret  --namespace=kube-system

# Remove the master taint
MASTERS=$(kubectl get node --selector='node-role.kubernetes.io/master' -o name)
for n in $MASTERS
do
    kubectl taint nodes $n node-role.kubernetes.io/master=:NoSchedule-
done

kubectl delete -f https://raw.githubusercontent.com/kubernetes/cloud-provider-vsphere/master/manifests/controller-manager/cloud-controller-manager-roles.yaml
kubectl delete -f https://raw.githubusercontent.com/kubernetes/cloud-provider-vsphere/master/manifests/controller-manager/cloud-controller-manager-role-bindings.yaml
kubectl delete -f https://github.com/kubernetes/cloud-provider-vsphere/raw/master/manifests/controller-manager/vsphere-cloud-controller-manager-ds.yaml

# 1. Remove the config-map
kubectl -n kube-system delete configmaps cloud-config
kubectl -n kube-system delete secret cloud-provider-secret

#De-taint

NODES=$(kubectl get nodes -o name)
for n in $NODES
do
    kubectl taint nodes $n node.cloudprovider.kubernetes.io/uninitialized=true:NoSchedule-
done
kubectl describe nodes | egrep "Taints:|Name:"

kubectl get all --all-namespaces