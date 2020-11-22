#!/bin/bash

[ -f common.sh ] &&  source common.sh

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 安装配置flannel

function configure_flannel {

	mk_k8s_bar "configure flannel"


 # rc-service flanneld restart -v 

# etcdctlv3 put /k8s.com/network/config "${flannel_config}"
# etcdctlv3 get /k8s.com/network/config

# etcdctl get /awcloud.com/network/config
# {"Backend": {"Type": "vxlan"}, "Network": "172.17.0.0/16", "SubnetLen": 24}

cat > "/etc/conf.d/flanneld" <<-EOF
LOGPATH=/var/log/flanneld
FLANNELD_DIR=/var/lib/flanneld
command_args=" -etcd-cafile=/etc/kubernetes/ssl/ca.pem \
-etcd-certfile=/etc/kubernetes/ssl/etcd.pem \
-etcd-keyfile=/etc/kubernetes/ssl/etcd-key.pem \
-etcd-endpoints=https://$KUBE_MASTER_IP:2379 \
-etcd-prefix=/k8s.com/network \
-iface=eth0 \
-ip-masq"
EOF

}


function setup_flannel {

	mk_k8s_bar "setup flannel"

flannel_config=$(cat <<-EOF | python3
import json
conf = dict()
conf['Network'] = '172.17.0.0/16'
conf['SubnetLen'] = 24
conf['Backend'] = {'Type': 'vxlan'}
print(json.dumps(conf))
EOF
)

	export ETCDCTL_API=2

	etcdctl --endpoints=https://$KUBE_MASTER_IP:2379 \
   		--ca-file='/etc/kubernetes/ssl/ca.pem' \
        --cert-file='/etc/kubernetes/ssl/etcd.pem' \
        --key-file='/etc/kubernetes/ssl/etcd-key.pem' \
        set '/k8s.com/network/config' "${flannel_config}"
}


function boot_flanneld {
	rc-service flanneld restart -v 
}
