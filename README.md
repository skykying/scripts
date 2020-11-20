# scripts

setenv boot_normal 'sunxi_flash read 45000000 fit;bootm 45000000#config@2'
setenv boot_normal 'sunxi_flash read 0x45000000 fit;bootm 0x45000000#config@1'
setenv boot_normal boot

#######################################################################################################

echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 8.8.4.4" >> /etc/resolv.conf

cat > ip.sh <<EOF
#!/bin/bash
ip link set eth0 up
ip addr add 192.168.168.122/24 dev eth0
ip route add default via  192.168.168.1  dev eth0
EOF

echo "http://mirrors.tuna.tsinghua.edu.cn/alpine/edge/main" > /etc/apk/repositories
echo "http://mirrors.tuna.tsinghua.edu.cn/alpine/edge/community" >> /etc/apk/repositories
echo "http://mirrors.tuna.tsinghua.edu.cn/alpine/edge/testing" >> /etc/apk/repositories

rm arch/arm64/configs/sun50iw1p1smp_linux_vir_defconfig -rf; cp defconfig arch/arm64/configs/sun50iw1p1smp_linux_vir_defconfig

scp root@192.168.168.102:/mnt/sdb1/tulip-m64-2020-1-16/A81/tools/pack/sun50iw1p1_vir_vir_uart0.img .
#######################################################################################################
# 2020 11-09 17:19:10
date 112008062020.10
hwclock -w

ulimit -SHn 65535

sysctl -w user.max_user_namespaces=15000

#######################################################################################################
openstack 
monmaptool --create --add ceph0 192.168.168.122 --fsid 241da498-6c50-4a44-af7c-7ed3275b0393 /etc/ceph/monmap

apk add postgresql-bdr-dev py3-psycopg2

apk add py3-configobj libusb py3-pip python3-dev gcc linux-headers  py3-yaml
apk add musl-dev musl-utils libffi-dev openssl openssl-dev make m4
apk add liberasurecode-dev libxml2 libxslt libxml2-dev libxml2-utils libxslt-dev

pip3 install --upgrade pip -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com
pip3 install -U setuptools -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com
pip3 install pyyaml -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v


pip3 install pynacl -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install swift -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install cinder -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install horizon -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install neutron -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install keystone -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install numpy -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install nova -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install glance -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install trove -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install ironic -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install masakari -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install octavia -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v



pip3 install ceph-deploy -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v

pip3 install six -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install python-rbd -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v

pip3 install prettytable -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v
pip3 install shyaml -i http://mirrors.aliyun.com/pypi/simple  --trusted-host mirrors.aliyun.com -v

apk add device-mapper-udev udev  device-mapper-libs


cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://registry.docker-cn.com",
    "http://hub-mirror.c.163.com",
    "https://docker.mirrors.ustc.edu.cn"
  ]
}
EOF

kubeadm config print init-defaults > kubeadm-config.yaml
kubeadm init --config=kubeadm-config.yaml



kubeadm init phase certs all
kubeadm init phase kubeconfig all
kubeadm init phase etcd local


cat conf.yml | shyaml get-value peer-transport-security.key-file

$(ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d / -f 1)


9568256
 131072
9699328 


docker rm $(docker ps -a -q)

rc-service etcd restart 
rc-service docker restart
rc-service kube-apiserver restart
rc-service kube-controller-manager restart
rc-service kube-scheduler restart
rc-service kubelet restart
rc-service kube-proxy restart

rc-update add etcd default
rc-update add docker default
rc-update add kube-apiserver default
rc-update add kube-controller-manager default
rc-update add kube-scheduler default

Unable to get configmap/extension-apiserver-authentication in kube-system.  Usually fixed by 'kubectl create rolebinding -n kube-system ROLEBINDING_NAME --role=extension-apiserver-authentication-reader --serviceaccount=YOUR_NS:YOUR_SA'
unable to load configmap based request-header-client-ca-file: configmaps "extension-apiserver-authentication" is forbidden: User "CN" cannot get resource "configmaps" in API group "" in the namespace "kube-system"



Forbidden: "/api/v1/namespaces/kube-system/configmaps/extension-apiserver-authentication", Reason: ""

echo $(head -c 32 /dev/urandom |base64) > /etc/machine-id

kubectl describe clusterrole system:kube-scheduler
kubectl get apiservice

kubectl api-resources
kubectl api-resources -o wide

kubectl api-versions

kubectl get node
kubectl get csr

kubectl get clusterrole
kubectl get secret --all-namespaces

kubectl describe clusterrole system:kubelet-api-admin
kubectl describe events

kubectl get clusterrolebinding system:node

kubectl run crasher --image=alpine
kubectl logs crasher
kubectl describe crasher


kubectl create clusterrolebinding kubelet-role-binding --clusterrole=system:node --user=system:node:localhost
kubectl describe clusterrolebindings kubelet-role-binding