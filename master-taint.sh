
MASTERS=$(kubectl get node --selector='node-role.kubernetes.io/master' -o name)
for n in $MASTERS
do
    kubectl taint nodes $n node-role.kubernetes.io/master=:NoSchedule
done
kubectl describe nodes | egrep "Taints:|Name:"