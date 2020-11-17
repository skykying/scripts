#!/bin/bash

# https://www.cnblogs.com/saneri/p/9126207.html

install -Dm644 ./flannel.confd  /etc/conf.d/flanneld
install -Dm755 ./flanneld.initd /etc/init.d/flanneld

FLANNEL_ETCD_PREFIX='/kubernetes/network'

cat > flanneld-csr.json <<EOF
{
  "CN": "flanneld",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
cfssl gencert -ca=/k8s/kubernetes/ssl/ca.pem -ca-key=/k8s/kubernetes/ssl/ca-key.pem \
	-config=/k8s/kubernetes/ssl/ca-config.json -profile=kubernetes flanneld-csr.json | \
	cfssljson -bare flanneld    

# ls flanneld*
# flanneld.csr  flanneld-csr.json  flanneld-key.pem  flanneld.pem    


ETCDCTL_API=2 /k8s/etcd/bin/etcdctl  \
	--endpoints="https://192.168.0.3:2379,https://192.168.0.2:2379,https://192.168.0.1:2379" \
	--ca-file=/k8s/kubernetes/ssl/ca.pem \
	--cert-file=/k8s/flanneld/ssl/flanneld.pem \
	--key-file=/k8s/flanneld/ssl/flanneld-key.pem \
	set /kubernetes/network/config  '{ "Network": "100.100.0.0/16", "Backend": {"Type": "vxlan"}}'

# 输出信息：
# { "Network": "100.100.0.0/16", "Backend": {"Type": "vxlan"}}
# 该步骤只需在第一次部署Flannel 网络时执行，后续在其他节点上部署Flanneld 时无需再写入该信息
# 写入/kubernetes/network/config的 Pod 网段必须与kube-controller-manager 的 --cluster-cidr 选项值一致

# 检查flannel服务
# ifconfig flannel.1

etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/flannel/ssl/flannel.pem \
  --key-file=/etc/flannel/ssl/flannel-key.pem \
  get ${FLANNEL_ETCD_PREFIX}/config
# { "Network": "172.30.0.0/16", "SubnetLen": 24, "Backend": { "Type": "vxlan" } }


etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/flannel/ssl/flannel.pem \
  --key-file=/etc/flannel/ssl/flannel-key.pem \
  ls ${FLANNEL_ETCD_PREFIX}/subnets
# /kubernetes/network/subnets/172.30.39.0-24

etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/flannel/ssl/flannel.pem \
  --key-file=/etc/flannel/ssl/flannel-key.pem \
  get ${FLANNEL_ETCD_PREFIX}/subnets/172.30.39.0-24
# {"PublicIP":"10.211.55.14","BackendType":"vxlan","BackendData":{"VtepMAC":"16:de:b5:85:a7:3b"}}


etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  --ca-file=/etc/kubernetes/ssl/ca.pem \
  --cert-file=/etc/flannel/ssl/flannel.pem \
  --key-file=/etc/flannel/ssl/flannel-key.pem \
  ls ${FLANNEL_ETCD_PREFIX}/subnets

# /kubernetes/network/subnets/172.30.39.0-24
# /kubernetes/network/subnets/172.30.41.0-24
# /kubernetes/network/subnets/172.30.12.0-24

