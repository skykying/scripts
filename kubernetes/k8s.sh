#!/bin/bash

# set -x 
set -e 

# https://www.cnblogs.com/fanqisoft/p/10765038.html
# https://www.jianshu.com/p/214cfeb12ad3 手动部署kubernetes集群
# https://blog.csdn.net/iov_aaron/article/details/94389426
# https://www.yisu.com/zixun/9840.html (Extension apiserver)
# https://lingxiankong.github.io/2018-09-18-kubelet-bootstrap-process.html

[ -f common.sh ] && . common.sh

# insmod /lib/modules/4.9.56/br_netfilter.ko

# rc-service etcd restart 
# rc-service docker restart
# rc-service kube-apiserver restart
# rc-service kube-controller-manager restart
# rc-service kube-scheduler restart
# rc-service kubelet restart
# rc-service kube-proxy restart

export KUBE_CLUSTER_NAME=$(hostname -s)
export KUBE_MASTER_IP=$(ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d / -f 1)


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

function generate_docker_mirror {
	mk_k8s_bar "generate docker mirror"

	install -Dm755 -d /etc/docker
	cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://registry.docker-cn.com",
    "http://hub-mirror.c.163.com",
    "https://docker.mirrors.ustc.edu.cn"
  ]
}
EOF
}


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 系统配置初始化

function generate_net_conf {

	mk_k8s_bar "generate net conf"

	cat > /etc/conf.d/kubernetes <<EOF
net.ipv4.ip_forward = 1
net.ipv4.conf.all.route_localnet = 1

# in case that arp cache overflow in a latget cluster!
net.ipv4.neigh.default.gc_thresh1 = 70000
net.ipv4.neigh.default.gc_thresh2 = 80000
net.ipv4.neigh.default.gc_thresh3 = 90000
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
fs.file-max = 65535

# es requires vm.max_map_count to be at least 262144.
vm.max_map_count = 262144

# kubelet requires swap off.
# https://github.com/kubernetes/kubernetes/issues/53533
vm.swappiness = 0
EOF
 
	sysctl -p /etc/conf.d/kubernetes
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

function generate_system_conf {

	mk_k8s_bar "generate system conf"

	sed -i -r 's|^\S+\s+swap\s+swap.*|# &|' /etc/fstab
	 
	# modify the maxium number of files that can be opened by process
	# to avoid the nginx process of 'nginx-ingress-controller'
	# failed to set 'worker_rlimit_nofile' to '94520' in 0.12.0+
	# sed -i -r '/^\* (soft|hard) nofile/d' /etc/security/limits.conf
	# echo "* soft nofile 100000" >> /etc/security/limits.conf
	# echo "* hard nofile 200000" >> /etc/security/limits.conf
	 
	# rc-update del iptables
	# rc-service iptables stop
	 
	# clean up the existed iptables rules.
	iptables -F && iptables -F -t nat
	iptables -X && iptables -X -t nat
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# nginx配置（我们使用nginx作为反向代理）

function generate_nginx_configure {

	mk_k8s_bar "generate nginx configure"

	cat > /etc/conf.d/nginx <<-EOF
net.core.netdev_max_backlog = 262144
net.core.somaxconn = 262144
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_max_orphans = 262144
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_syn_retries = 1
EOF
 
	sysctl -p /etc/conf.d/nginx
}



# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
function generate_ca_aggregator {

	mk_k8s_bar "generate ca aggregator"

	if [ ! -d /etc/kubernetes/ssl ]; then
		mkdir -p /etc/kubernetes/ssl
	fi

	cd /etc/kubernetes/ssl
 
	# Generate CA Certificates
	cat > ca-agg-config.json <<-EOF
{
    "signing": {
        "default": {
            "expiry": "87600h"
        },
        "profiles": {
            "aggregator": {
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ],
                "expiry": "87600h"
            }
        }
    }
}
EOF
 
	cat > ca-agg-csr.json <<-EOF
{
    "CN": "aggregator",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "ST": "WuHan",
            "L": "WuHan",
            "O": "kubernetes",
            "OU": "CA"
        }
    ]
}
EOF
 
	cfssl gencert -initca ca-agg-csr.json |cfssljson -bare ca-agg
	# ca-agg.pem ca-agg.csr ca-agg-key.pem
}


function generate_ssl_aggregator {

	mk_k8s_bar "generate ssl aggregator"
 
    local service_name="aggregator"
    local common_name="aggregator"
    local organization="aggregator"
    local csr_file="${service_name}-csr.json"
 
 	if [ ! -d /etc/kubernetes/ssl ]; then
		mkdir -p /etc/kubernetes/ssl
	fi
    cd /etc/kubernetes/ssl
 
	cat > "${csr_file}" <<-EOF
	{
	    "CN": "${common_name}",
	    "key": {
	        "algo": "rsa",
	        "size": 2048
	    },
	    "hosts": [
	    	"$KUBE_MASTER_IP",
	        "10.10.0.1",
	        "10.10.0.2",
	        "127.0.0.1",
    		"kubernetes",
    		"kubernetes.default",
    		"kubernetes.default.svc",
    		"kubernetes.default.svc.cluster",
    		"kubernetes.default.svc.cluster.local",
	        "$ALLOW_IPS"
	    ],
	    "names": [
	        {
	            "C": "CN",
	            "ST": "WuHan",
	            "L": "WuHan",
	            "O": "${organization}",
	            "OU": "kubernetes"
	        }
	    ]
	}
	EOF
 
    cfssl gencert 					\
          -ca=ca-agg.pem 				\
          -ca-key=ca-agg-key.pem 		\
          -config=ca-agg-config.json 	\
          -profile=aggregator 		\
          "${csr_file}" |cfssljson -bare "${service_name}"
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 初始化证书

function generate_ca_certificates {

	mk_k8s_bar "generate ca certificates"

	if [ ! -d /etc/kubernetes/ssl ]; then
		mkdir -p /etc/kubernetes/ssl
	fi

	cd /etc/kubernetes/ssl
 
	# Generate CA Certificates
	cat > ca-config.json <<-EOF
{
    "signing": {
        "default": {
            "expiry": "87600h"
        },
        "profiles": {
            "kubernetes": {
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ],
                "expiry": "87600h"
            }
        }
    }
}
EOF
 
	cat > ca-csr.json <<-EOF
{
    "CN": "kubernetes",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "ST": "WuHan",
            "L": "WuHan",
            "O": "kubernetes",
            "OU": "CA"
        }
    ]
}
EOF
 
	cfssl gencert -initca ca-csr.json |cfssljson -bare ca
	# ca.pem ca.csr ca-key.pem
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 
# 初始化SSL证书
# 需要生成证书的服务包括 
# etcd, docker, kube-apiserver, kube-controller-manager, kube-sheduler, kube-proxy, client
# 以下单独写一个函数用于生成各个证书
# 
# 定义通用函数, 生成ssl证书，其中hosts中的allow_ips表示所有允许访问的IP地址，
# 建议将集群所有的节点及允许访问的client节点的IP地址及主机名都加进去

# 需要上一步的配置
function generate_ssl_certificates {

	mk_k8s_bar "generate ssl certificates"

    if [[ "$#" -ne 3 ]]; then
        return 1
    fi
 
    local service_name="${1}"
    local common_name="${2}"
    local organization="${3}"
    local csr_file="${service_name}-csr.json"
 
 	if [ ! -d /etc/kubernetes/ssl ]; then
		mkdir -p /etc/kubernetes/ssl
	fi
    cd /etc/kubernetes/ssl
 
	cat > "${csr_file}" <<-EOF
	{
	    "CN": "${common_name}",
	    "key": {
	        "algo": "rsa",
	        "size": 2048
	    },
	    "hosts": [
	    	"$KUBE_MASTER_IP",
	        "10.10.0.1",
	        "10.10.0.2",
	        "127.0.0.1",
    		"kubernetes",
    		"kubernetes.default",
    		"kubernetes.default.svc",
    		"kubernetes.default.svc.cluster",
    		"kubernetes.default.svc.cluster.local",
	        "$ALLOW_IPS"
	    ],
	    "names": [
	        {
	            "C": "CN",
	            "ST": "WuHan",
	            "L": "WuHan",
	            "O": "${organization}",
	            "OU": "kubernetes"
	        }
	    ]
	}
	EOF
 
    cfssl gencert 					\
          -ca=ca.pem 				\
          -ca-key=ca-key.pem 		\
          -config=ca-config.json 	\
          -profile=kubernetes 		\
          "${csr_file}" |cfssljson -bare "${service_name}"
}

# generate the certificate and private key of each services
function generate_kubes_certificates {
	
	mk_k8s_bar "generate kubes certificates"

	generate_ssl_certificates etcd etcd etcd
	generate_ssl_certificates docker docker docker
	generate_ssl_certificates kube-apiserver system:kube-apiserver system:kube-apiserver
	generate_ssl_certificates kube-controller-manager system:kube-controller-manager system:kube-controller-manager
	generate_ssl_certificates kube-scheduler system:kube-scheduler system:kube-scheduler
	 
	# notes: kube-proxy is different from other kubernetes components.
	generate_ssl_certificates kube-proxy system:kube-proxy system:node-proxier
	 
	# generate the admin client certificate and private key.
	generate_ssl_certificates admin admin system:masters
	 
	# the kube-controller-manager leverages a key pair to generate and sign service
	# account tokens as describe in the managing service accounts documentation.
	generate_ssl_certificates service-account service-accounts kubernetes

}

# 将生成的证书文件拷贝到集群其他节点
# scp /etc/kubernetes/ssl/* k8s-node2:/etc/kubernetes/
# scp /etc/kubernetes/ssl/* k8s-node3:/etc/kubernetes/

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 初始化kubelet的证书（所有的node节点执行）


function generate_kubelet_ssl {

	mk_k8s_bar "generate kubelet ssl"

	if [ ! -d /etc/kubernetes/ssl ]; then
		mkdir -p /etc/kubernetes/ssl
	fi

	cd /etc/kubernetes/ssl
 
	cat > kubelet-$(hostname).json <<-EOF
{
    "CN": "system:node:$(hostname)",
    "hosts": [
        "$(hostname)",
        "127.0.0.1",
        "${host}"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "ST": "WuHan",
            "L": "WuHan",
            "O": "system:nodes",
            "OU": "kubernetes"
        }
    ]
}
EOF
# kubelet-localhost.json
# kubectl create clusterrolebinding kubelet-role-binding --clusterrole=system:node --user=system:node:localhost
# kubectl describe clusterrolebindings kubelet-role-binding

	cfssl gencert 						\
      	-ca=ca.pem 						\
      	-ca-key=ca-key.pem 				\
      	-config=ca-config.json 			\
      	-profile=kubernetes				\
      	kubelet-$(hostname).json |cfssljson -bare kubelet-$(hostname)

}

function kubelet_setup {

	mk_k8s_bar "kubelet setup"

		kubectl config set-cluster kubernetes \
				--embed-certs=true \
				--certificate-authority="/etc/kubernetes/ssl/ca.pem" \
				--server=https://$KUBE_MASTER_IP:5443 \
				--kubeconfig="/etc/kubernetes/kubelet.kubeconfig"
		
		kubectl config set-credentials "system:kubelet" \
				--embed-certs=true \
				--client-certificate=/etc/kubernetes/ssl/kubelet-$(hostname).pem \
				--client-key=/etc/kubernetes/ssl/kubelet-$(hostname)-key.pem \
				--kubeconfig="/etc/kubernetes/kubelet.kubeconfig"
		
		kubectl config set-context default \
				--cluster=kubernetes \
				--user="system:kubelet" \
				--kubeconfig="/etc/kubernetes/kubelet.kubeconfig"
		
		kubectl config use-context default \
				--kubeconfig="/etc/kubernetes/kubelet.kubeconfig"

		# kubectl create clusterrolebinding kubelet-admin --clusterrole=system:kubelet-api-admin --user="kubelet-client"
		# kubectl create clusterrolebinding kubelet-admin --clusterrole=system:kubelet-api-admin --user="system:kubelet"
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 配置etcd

function generate_etcd_conf {

	mk_k8s_bar "generate etcd conf"

	cat > /etc/etcd/conf.yml << EOF
name: '$KUBE_CLUSTER_NAME'
data-dir: /var/lib/etcd
wal-dir:
snapshot-count: 10000
heartbeat-interval: 100
election-timeout: 1000
quota-backend-bytes: 0
listen-peer-urls: https://$KUBE_MASTER_IP:2380
listen-client-urls: 'https://$KUBE_MASTER_IP:2379,https://127.0.0.1:2379'
max-snapshots: 5
max-wals: 5
cors:
initial-advertise-peer-urls: https://$KUBE_MASTER_IP:2380
advertise-client-urls: https://$KUBE_MASTER_IP:2379
discovery:
discovery-fallback: 'proxy'
discovery-proxy:
discovery-srv:
initial-cluster: 'etcd0=https://$KUBE_MASTER_IP:2380'
initial-cluster-token: 'etcd-cluster'
initial-cluster-state: 'new'
strict-reconfig-check: false
enable-v2: true
enable-pprof: true
proxy: 'off'
proxy-failure-wait: 5000
proxy-refresh-interval: 30000
proxy-dial-timeout: 1000
proxy-write-timeout: 5000
proxy-read-timeout: 0
client-transport-security:
  cert-file: '/etc/kubernetes/ssl/etcd.pem'
  key-file: '/etc/kubernetes/ssl/etcd-key.pem'
  client-cert-auth: true
  trusted-ca-file: '/etc/kubernetes/ssl/ca.pem'
  auto-tls: true

peer-transport-security:
  cert-file: '/etc/kubernetes/ssl/etcd.pem'
  key-file: '/etc/kubernetes/ssl/etcd-key.pem'
  client-cert-auth: true
  trusted-ca-file: '/etc/kubernetes/ssl/ca.pem'
  auto-tls: true
debug: true
logger: zap
log-outputs: [stderr]
force-new-cluster: false
auto-compaction-mode: periodic
auto-compaction-retention: "1"
EOF
}


function startup_etcd {
	rc-service etcd restart -v
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 配置etcdctl
#

function build_etcdctl_command {

	mk_k8s_bar "build etcdctl command"

alias etcdctlv2='ETCDCTL_API=2 etcdctl \
                   --endpoints=https://$KUBE_MASTER_IP:2381 \
                   --ca-file=/etc/kubernetes/ssl/ca.pem \
                   --cert-file=/etc/kubernetes/ssl/etcd.pem \
                   --key-file=/etc/kubernetes/ssl/etcd-key.pem'

alias etcdctlv3='ETCDCTL_API=3 etcdctl \
                   --endpoints=https://$KUBE_MASTER_IP:2379 \
                   --cacert=/etc/kubernetes/ssl/ca.pem \
                   --cert=/etc/kubernetes/ssl/etcd.pem \
                   --key=/etc/kubernetes/ssl/etcd-key.pem'
}

# etcdctlv2 cluster-health
# etcdctlv3 cluster-health

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Docker安装配置

function generate_docker_conf {

	mk_k8s_bar "generate docker conf"

cat > "/etc/conf.d/docker" <<-EOF	
DOCKER_OPTS=" $DOCKER_NETWORK_OPTIONS --data-root=/var/lib/docker \
--host=tcp://$KUBE_MASTER_IP:2375 \
--host=unix:///var/run/docker.sock \
--insecure-registry=k8s.gcr.io \
--insecure-registry=quay.io \
--ip-forward=true \
--live-restore=true \
--log-driver=json-file \
--log-level=warn \
--selinux-enabled=false \
--storage-driver=overlay2 \
--tlscacert=/etc/kubernetes/ssl/ca.pem \
--tlscert=/etc/kubernetes/ssl/docker.pem \
--tlskey=/etc/kubernetes/ssl/docker-key.pem \
--tlsverify"
EOF
}

# ifconfig docker0

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# Kubernetes 安装配置


# 初始化kubeconfig配置（master节点执行）
# 1.Generating the data encryption config and key

function confiure_kube_components {

	mk_k8s_bar "confiure kube components"

	encryption_key=$(head -c 32 /dev/urandom |base64)

	mkdir -p /etc/kubernetes/
	cat > "/etc/kubernetes/encryption-config.yaml" <<EOF
apiVersion: v1
kind: EncryptionConfig
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: ${encryption_key}
  - identity: {}
EOF

	# 2.Generating the kubeconfig file for k8s component
	for component in kube-controller-manager kube-scheduler kube-proxy; do
		kubectl config set-cluster kubernetes \
				--embed-certs=true \
				--certificate-authority="/etc/kubernetes/ssl/ca.pem" \
				--server=https://$KUBE_MASTER_IP:5443 \
				--kubeconfig="/etc/kubernetes/${component}.kubeconfig"
		
		kubectl config set-credentials "system:${component}" \
				--embed-certs=true \
				--client-certificate=/etc/kubernetes/ssl/${component}.pem \
				--client-key=/etc/kubernetes/ssl/${component}-key.pem \
				--kubeconfig="/etc/kubernetes/${component}.kubeconfig"
		
		kubectl config set-context default \
				--cluster=kubernetes \
				--user="system:${component}" \
				--kubeconfig="/etc/kubernetes/${component}.kubeconfig"
		
		kubectl config use-context default \
				--kubeconfig="/etc/kubernetes/${component}.kubeconfig"
	done
 
	# 3.Generating the kubeconfig file for user admin
	kubectl config set-cluster kubernetes \
	        --embed-certs=true \
	        --certificate-authority="/etc/kubernetes/ssl/ca.pem" \
	        --server=https://$KUBE_MASTER_IP:5443 \
	        --kubeconfig="/etc/kubernetes/admin.kubeconfig"
	 
	kubectl config set-credentials admin \
	        --embed-certs=true \
	        --client-certificate="/etc/kubernetes/ssl/admin.pem" \
	        --client-key="/etc/kubernetes/ssl/admin-key.pem" \
	        --kubeconfig="/etc/kubernetes/admin.kubeconfig"
	 
	kubectl config set-context default \
	        --cluster="${KUBE_CLUSTER_NAME}" \
	        --user=admin \
	        --kubeconfig="/etc/kubernetes/admin.kubeconfig"
	 
	kubectl config use-context default \
	        --kubeconfig="/etc/kubernetes/admin.kubeconfig"

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# kubelet

	# kubectl config set-cluster kubernetes \
	# 	--certificate-authority="/etc/kubernetes/ssl/ca.pem" \
	# 	--embed-certs=true \
	# 	--server=https://$KUBE_MASTER_IP:5443 \
	# 	--kubeconfig="/etc/kubernetes/kubelet-bootstrap.kubeconfig"

	# kubectl config set-credentials kubelet-bootstrap \
	# 		--token=${BOOTSTRAP_TOKEN} \
	# --kubeconfig="/etc/kubernetes/kubelet-bootstrap.kubeconfig"

	# kubectl config set-context default \
	#   		--cluster=kubernetes \
	#   		--user="kubelet-bootstrap" \
	#   		--kubeconfig="/etc/kubernetes/kubelet-bootstrap.kubeconfig"

	# kubectl config use-context default \
	# 		--kubeconfig="/etc/kubernetes/kubelet-bootstrap.kubeconfig"

	# # Bind kubelet-bootstrap user to system cluster roles.
	# kubectl create clusterrolebinding kubelet-bootstrap \
	#   		--clusterrole="system:node-bootstrapper" \
	#   		--user="kubelet-bootstrap"

	# kubectl create clusterrolebinding kube-apiserver:kubelet-apis \
	# 		--clusterrole=system:kubelet-api-admin \
	# 		--user kubernetes


	# kubectl create clusterrolebinding kubelet-admin \
	# 		--clusterrole=system:kubelet-api-admin \
	# 		--user="system:node:localhost"	
	
}

# 4. copy configfiles to all masters and nodes
# scp /etc/kubernetes/*.kubeconfig other_nodes:/etc/kubernetes/
# scp /etc/kubernetes/encryption-config.yaml other_nodes:/etc/kubernetes/

# kubectl describe clusterrole system:certificates.k8s.io:certificatesigningrequests:selfnodeclient
# kubectl create clusterrolebinding nodeclient-cert-renewal \
#   --clusterrole system:certificates.k8s.io:certificatesigningrequests:selfnodeclient \
#   --user system:node:test-node
# 
# kubectl get clusterrolebindings -o json | \
# jq -r '.items[] | select(.subjects // [] | .[] | [.kind,.name] == ["Group","system:nodes"]) | .metadata.name'

# kubectl create clusterrolebinding kubelet-admin --clusterrole=system:kubelet-api-admin --user=kubelet-client

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 安装配置master kube-apiserver

function configure_kube_apiserver {

	mk_k8s_bar "configure kube apiserver"

	cat > "/etc/conf.d/kube-apiserver" <<-EOF
###
# kubernetes system config
#
# The following values are used to configure the kube-apiserver
#

command_args=" \
--advertise-address=$KUBE_MASTER_IP \
--allow-privileged=true \
--alsologtostderr=true \
--apiserver-count=1 \
--authorization-mode=Node,RBAC \
--anonymous-auth=false \
--bind-address=$KUBE_MASTER_IP \
--client-ca-file=/etc/kubernetes/ssl/ca.pem \
--etcd-cafile=/etc/kubernetes/ssl/ca.pem \
--etcd-certfile=/etc/kubernetes/ssl/etcd.pem \
--etcd-keyfile=/etc/kubernetes/ssl/etcd-key.pem \
--etcd-prefix=/kubernetes \
--etcd-servers=https://$KUBE_MASTER_IP:2379 \
--event-ttl=1h \
--enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \
--encryption-provider-config=/etc/kubernetes/encryption-config.yaml \
--kubelet-certificate-authority=/etc/kubernetes/ssl/ca.pem \
--kubelet-client-certificate=/etc/kubernetes/ssl/kube-apiserver.pem \
--kubelet-client-key=/etc/kubernetes/ssl/kube-apiserver-key.pem \
--log-dir=/var/log/kubernetes \
--log-flush-frequency=10s \
--logtostderr=false \
--runtime-config=api/all=true \
--secure-port=5443 \
--service-account-key-file=/etc/kubernetes/ssl/service-account.pem \
--service-cluster-ip-range=10.10.0.0/16 \
--service-node-port-range=30000-32767 \
--tls-cert-file=/etc/kubernetes/ssl/kube-apiserver.pem \
--tls-private-key-file=/etc/kubernetes/ssl/kube-apiserver-key.pem \
--v=4 \
--enable-aggregator-routing=true
--requestheader-client-ca-file=/etc/kubernetes/ssl/ca-agg.pem \
--requestheader-allowed-names="" \
--requestheader-extra-headers-prefix=X-Remote-Extra- \
--requestheader-group-headers=X-Remote-Group \
--requestheader-username-headers=X-Remote-User \
--proxy-client-cert-file=/etc/kubernetes/ssl/aggregator.pem \
--proxy-client-key-file=/etc/kubernetes/ssl/aggregator-key.pem"
EOF
}

# kubectl get roles -n kube-system extension-apiserver-authentication-reader

function configure_kube_controller_manager {

	mk_k8s_bar "configure kube controller manager"

cat > "/etc/conf.d/kube-controller-manager" <<-EOF
command_args=" \
--allocate-node-cidrs=false \
--alsologtostderr=true \
--authentication-kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \
--authorization-kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \
--bind-address=127.0.0.1 \
--cluster-cidr=192.168.0.0/16 \
--cluster-name=kubernetes \
--cluster-signing-cert-file=/etc/kubernetes/ssl/ca.pem \
--cluster-signing-key-file=/etc/kubernetes/ssl/ca-key.pem \
--controller-start-interval=0 \
--kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \
--leader-elect=true \
--leader-elect-lease-duration=15s \
--leader-elect-renew-deadline=10s \
--leader-elect-retry-period=2s \
--log-dir=/var/log/kubernetes \
--log-flush-frequency=10s \
--logtostderr=false \
--node-cidr-mask-size=16 \
--node-monitor-grace-period=30s \
--node-monitor-period=3s \
--pod-eviction-timeout=30s \
--root-ca-file=/etc/kubernetes/ssl/ca.pem \
--service-account-private-key-file=/etc/kubernetes/ssl/service-account-key.pem \
--service-cluster-ip-range=10.10.0.0/16 \
--tls-cert-file=/etc/kubernetes/ssl/kube-controller-manager.pem \
--tls-private-key-file=/etc/kubernetes/ssl/kube-controller-manager-key.pem \
--use-service-account-credentials=true \
--v=4"
EOF
}

function configure_kube_scheduler {

	mk_k8s_bar "configure kube scheduler"

cat > "/etc/conf.d/kube-scheduler" <<-EOF
command_args=" --address=127.0.0.1 \
--alsologtostderr=true \
--bind-address=127.0.0.1 \
--authentication-kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
--authorization-kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
--kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
--leader-elect=true \
--leader-elect-lease-duration=15s \
--leader-elect-renew-deadline=10s \
--leader-elect-retry-period=2s \
--log-dir=/var/log/kubernetes \
--log-flush-frequency=10s \
--logtostderr=false \
--tls-cert-file=/etc/kubernetes/ssl/kube-scheduler.pem \
--tls-private-key-file=/etc/kubernetes/ssl/kube-scheduler-key.pem \
--v=4"
EOF
}
# kubectl create rolebinding -n kube-system ROLEBINDING_NAME --role=extension-apiserver-authentication-reader --serviceaccount=YOUR_NS:YOUR_SA

function boot_kube_components {

	mk_k8s_bar "boot kube components"

	for svc in kube-{apiserver,controller-manager,scheduler}; do
	    rc-update add ${svc} default
	    rc-service  ${svc} start
	done
}

export KUBECONFIG=/etc/kubernetes/admin.kubeconfig
# kubectl get node
# kubectl get cs


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

function configure_kubelet {

	mk_k8s_bar "configure kubelet"

cat > "/etc/conf.d/kubelet" <<-EOF
command_args=" --alsologtostderr=true \
--client-ca-file=/etc/kubernetes/ssl/ca.pem \
--cluster-dns=10.10.0.2 \
--cluster-domain=k8s.local \
--docker-tls \
--docker-tls-ca=/etc/kubernetes/ssl/ca.pem \
--docker-tls-cert=/etc/kubernetes/ssl/docker.pem \
--docker-tls-key=/etc/kubernetes/ssl/docker-key.pem \
--fail-swap-on=true \
--healthz-port=10248 \
--hostname-override= \
--image-pull-progress-deadline=30m \
--kubeconfig=/etc/kubernetes/kubelet.kubeconfig \
--log-dir=/var/log/kubernetes \
--log-flush-frequency=5s \
--logtostderr=false \
--pod-infra-container-image=alpine:latest \
--port=10250 \
--read-only-port=10255 \
--register-node=true \
--root-dir=/var/lib/kubelet \
--runtime-request-timeout=10m \
--serialize-image-pulls=false \
--tls-cert-file=/etc/kubernetes/ssl/kubelet-$(hostname).pem \
--tls-private-key-file=/etc/kubernetes/ssl/kubelet-$(hostname)-key.pem \
--v=4"
EOF

}

# kubectl get node

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 安装配置node kube-proxy

function configure_kube_proxy {

	mk_k8s_bar "configure kube proxy"

	cat > "/etc/conf.d/kube-proxy" <<-EOF
command_args=" --alsologtostderr=true \
--bind-address=$KUBE_MASTER_IP \
--cluster-cidr=172.17.0.0/16 \
--hostname-override= \
--kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig \
--log-dir=/var/log/kubernetes \
--log-flush-frequency=5s \
--logtostderr=false \
--proxy-mode=iptables \
--v=4"
EOF
}

function boot_kubelet_proxy {

	mk_k8s_bar "generate_ca_certificates"

	for svc in {kube-proxy,kubelet}; do
	    rc-update add ${svc} default
	    rc-service  ${svc} start
	done
}
# kubectl get node

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

	_etcdctlv2='ETCDCTL_API=2 etcdctl \
                   --endpoints=https://$KUBE_MASTER_IP:2379 \
                   --ca-file=/etc/kubernetes/ssl/ca.pem \
                   --cert-file=/etc/kubernetes/ssl/etcd.pem \
                   --key-file=/etc/kubernetes/ssl/etcd-key.pem'
	
	 _etcdctlv3='ETCDCTL_API=3 etcdctl \
                   --endpoints=https://$KUBE_MASTER_IP:2379 \
                   --cacert=/etc/kubernetes/ssl/ca.pem \
                   --cert=/etc/kubernetes/ssl/etcd.pem \
                   --key=/etc/kubernetes/ssl/etcd-key.pem'

	# etcdctlv3 put /k8s.com/network/config "${flannel_config}"
	${_etcdctlv2} set /k8s.com/network/config "${flannel_config}"
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

function main {
	mk_k8s_bar "setup begin "

	install_packages
	generate_docker_mirror
	generate_net_conf
	generate_system_conf
	generate_nginx_configure

	generate_ca_aggregator
	generate_ssl_aggregator

	generate_ca_certificates
	generate_kubes_certificates

	generate_kubelet_ssl
	kubelet_setup

	generate_etcd_conf
	generate_docker_conf

	confiure_kube_components
	configure_kube_apiserver
	configure_kube_controller_manager
	configure_kube_scheduler
	# boot_kube_components

	configure_kubelet
	configure_kube_proxy
	# boot_kubelet_proxy

	configure_flannel
	startup_etcd
	setup_flannel

	mk_k8s_bar "setup successful "
}

main 