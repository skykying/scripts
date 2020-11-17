#!/bin/bash

set -x 

# https://www.cnblogs.com/fanqisoft/p/10765038.html
# https://www.jianshu.com/p/214cfeb12ad3 手动部署kubernetes集群
# https://blog.csdn.net/iov_aaron/article/details/94389426

export KUBE_CLUSTER_NAME=$(hostname -s)
export KUBE_MASTER_IP=$(ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d / -f 1)


function install_packages {
	apk add docker docker-openrc
	apk add cfssl iptables iptables-openrc
	apk add kube-controller-manager-openrc kube-controller-manager
	apk add kube-scheduler-openrc kube-scheduler
	apk add kube-apiserver kube-apiserver-openrc

	rc-update add docker default
}


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

function generate_docker_mirror {
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
	sed -i -r 's|^\S+\s+swap\s+swap.*|# &|' /etc/fstab
	 
	# modify the maxium number of files that can be opened by process
	# to avoid the nginx process of 'nginx-ingress-controller'
	# failed to set 'worker_rlimit_nofile' to '94520' in 0.12.0+
	sed -i -r '/^\* (soft|hard) nofile/d' /etc/security/limits.conf
	echo "* soft nofile 100000" >> /etc/security/limits.conf
	echo "* hard nofile 200000" >> /etc/security/limits.conf
	 
	rc-service del iptables
	rc-service iptables stop
	 
	# clean up the existed iptables rules.
	iptables -F && iptables -F -t nat
	iptables -X && iptables -X -t nat
}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# nginx配置（我们使用nginx作为反向代理）

function generate_nginx_configure {

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
# 初始化证书

function generate_ca_certificates {
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
	    "CN": "CN",
	    "key": {
	        "algo": "rsa",
	        "size": 2048
	    },
	    "hosts": [
	    	"$KUBE_MASTER_IP",
	        "10.10.0.1",
	        "10.10.0.2",
	        "127.0.0.1",
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

# admin-csr.json
# admin-key.pem
# admin.csr
# admin.pem

# ca-config.json
# ca-csr.json
# ca-key.pem
# ca.csr
# ca.pem

# docker-csr.json
# docker-key.pem
# docker.csr
# docker.pem

# etcd-csr.json
# etcd-key.pem
# etcd.csr
# etcd.pem

# kube-apiserver-csr.json
# kube-apiserver-key.pem
# kube-apiserver.csr
# kube-apiserver.pem
# kube-controller-manager-csr.json
# kube-controller-manager-key.pem
# kube-controller-manager.csr
# kube-controller-manager.pem
# kube-proxy-csr.json
# kube-proxy-key.pem
# kube-proxy.csr
# kube-proxy.pem
# kube-scheduler-csr.json
# kube-scheduler-key.pem
# kube-scheduler.csr
# kube-scheduler.pem

# service-account-csr.json
# service-account-key.pem
# service-account.csr
# service-account.pem

# 将生成的证书文件拷贝到集群其他节点
# scp /etc/kubernetes/ssl/* k8s-node2:/etc/kubernetes/
# scp /etc/kubernetes/ssl/* k8s-node3:/etc/kubernetes/

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 初始化kubelet的证书（所有的node节点执行）


function generate_kubelet_ssl {
	if [ ! -d /etc/kubernetes/ssl ]; then
		mkdir -p /etc/kubernetes/ssl
	fi

	cd /etc/kubernetes/ssl
 
	cat > kubelet-$(hostname).json <<-EOF
{
    "CN": "system:node:$(hostname)",
    "hosts": [
        "$(hostname)",
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

	cfssl gencert 						\
      	-ca=ca.pem 						\
      	-ca-key=ca-key.pem 				\
      	-config=ca-config.json 			\
      	-profile=kubernetes				\
      	kubelet-$(hostname).json |cfssljson -bare kubelet-$(hostname)

}

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 配置etcd

function generate_etcd_conf {

	cat > /etc/conf.d/etcd << EOF
LOGPATH=/var/log/${RC_SVCNAME}
ETCD_CONFIG_FILE=/etc/etcd/conf.yml

ETCD_NAME=etcd0
ETCD_DATA_DIR="/var/lib/etcd/etcd0"
ETCD_LISTEN_PEER_URLS="https://$KUBE_MASTER_IP:2380"
ETCD_LISTEN_CLIENT_URLS="https://$KUBE_MASTER_IP:2379,https://127.0.0.1:2379"
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://$KUBE_MASTER_IP:2380"
ETCD_ADVERTISE_CLIENT_URLS="https://$KUBE_MASTER_IP:2379"
ETCD_INITIAL_CLUSTER="etcd0=https://$KUBE_MASTER_IP:2380"
ETCD_INITIAL_CLUSTER_TOKEN="k8s-etcd-cluster"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_AUTO_COMPACTION_RETENTION="1"

# 本次etcd是单机部署，如果是etcd集群的话则
ETCD_INITIAL_CLUSTER="etcd0=https://$KUBE_MASTER_IP:2380,etcd1=https://$KUBE_MASTER_IP:2380"
	 
ETCD_CERT_FILE="/etc/kubernetes/ssl/etcd.pem"
ETCD_KEY_FILE="/etc/kubernetes/ssl/etcd-key.pem"
ETCD_CLIENT_CERT_AUTH="true"
ETCD_TRUSTED_CA_FILE="/etc/kubernetes/ssl/ca.pem"
ETCD_PEER_CERT_FILE="/etc/kubernetes/ssl/etcd.pem"
ETCD_PEER_KEY_FILE="/etc/kubernetes/ssl/etcd-key.pem"
ETCD_PEER_CLIENT_CERT_AUTH="true"
ETCD_PEER_TRUSTED_CA_FILE="/etc/kubernetes/ssl/ca.pem"
EOF

	cat > /etc/etcd/conf.yml << EOF
name: '$KUBE_CLUSTER_NAME'
data-dir: /var/lib/etcd
wal-dir:
snapshot-count: 10000
heartbeat-interval: 100
election-timeout: 1000
quota-backend-bytes: 0
listen-peer-urls: https://$KUBE_MASTER_IP:2381
listen-client-urls: 'https://$KUBE_MASTER_IP:2379,https://127.0.0.1:2379'
max-snapshots: 5
max-wals: 5
cors:
initial-advertise-peer-urls: https://$KUBE_MASTER_IP:2381
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

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 配置etcdctl
#

function build_etcdctl_command {

alias etcdctlv2='ETCDCTL_API=2 etcdctl \
                   --endpoints=https://$KUBE_MASTER_IP:2380 \
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
cat > "/etc/conf.d/docker" <<-EOF	
DOCKER_OPTS= " \			
$DOCKER_NETWORK_OPTIONS \
--data-root=/var/lib/docker \
--host=tcp://$KUBE_MASTER_IP:2375 \
--host=unix:///var/run/docker.sock \
--insecure-registry=k8s.gcr.io \
--insecure-registry=quay.io \
--ip-forward=true \
--live-restore=true \
--log-driver=json-file \
--log-level=warn \
--registry-mirror=https://registry.docker-cn.com \
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

}

# 4. copy configfiles to all masters and nodes
# scp /etc/kubernetes/*.kubeconfig other_nodes:/etc/kubernetes/
# scp /etc/kubernetes/encryption-config.yaml other_nodes:/etc/kubernetes/


# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 安装配置master kube-apiserver

function configure_kube_apiserver {
	cat > "/etc/conf.d/kube-apiserver" <<-EOF
###
# kubernetes system config
#
# The following values are used to configure the kube-apiserver
#

command_args=" \
--address=$KUBE_MASTER_IP \
--advertise-address=$KUBE_MASTER_IP \
--allow-privileged=true \
--alsologtostderr=true \
--apiserver-count=1 \
--authorization-mode=Node,RBAC \
--bind-address=$KUBE_MASTER_IP \
--client-ca-file=/etc/kubernetes/ssl/ca.pem \
--enable-admission-plugins=Initializers,NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \
--enable-swagger-ui=true \
--etcd-cafile=/etc/kubernetes/ssl/ca.pem \
--etcd-certfile=/etc/kubernetes/ssl/etcd.pem \
--etcd-keyfile=/etc/kubernetes/ssl/etcd-key.pem \
--etcd-prefix=/kubernetes \
--etcd-servers=https://$KUBE_MASTER_IP:2379 \
--event-ttl=1h \
--experimental-encryption-provider-config=/etc/kubernetes/encryption-config.yaml \
--kubelet-certificate-authority=/etc/kubernetes/ssl/ca.pem \
--kubelet-client-certificate=/etc/kubernetes/ssl/kube-apiserver.pem \
--kubelet-client-key=/etc/kubernetes/ssl/kube-apiserver-key.pem \
--kubelet-https=true \
--insecure-bind-address=$KUBE_MASTER_IP \
--insecure-port=7070 \
--log-dir=/var/log/kubernetes \
--log-flush-frequency=10s \
--logtostderr=false \
--runtime-config=api/all \
--secure-port=5443 \
--service-account-key-file=/etc/kubernetes/ssl/service-account.pem \
--service-cluster-ip-range=10.10.0.0/16 \
--service-node-port-range=30000-32767 \
--tls-cert-file=/etc/kubernetes/ssl/kube-apiserver.pem \
--tls-private-key-file=/etc/kubernetes/ssl/kube-apiserver-key.pem \
--v=4"
EOF
}

function configure_kube_controller_manager {
cat > "/etc/conf.d/kube-controller-manager" <<-EOF
command_args= " \
--address=127.0.0.1 \
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
--port=10252 \
--root-ca-file=/etc/kubernetes/ssl/ca.pem \
--secure-port=10257 \
--service-account-private-key-file=/etc/kubernetes/ssl/service-account-key.pem \
--service-cluster-ip-range=10.10.0.0/16 \
--tls-cert-file=/etc/kubernetes/ssl/kube-controller-manager.pem \
--tls-private-key-file=/etc/kubernetes/ssl/kube-controller-manager-key.pem \
--use-service-account-credentials=true \
--v=4"
EOF
}

function configure_kube_scheduler {
cat > "/etc/conf.d/kube-scheduler" <<-EOF
command_args= "	\
--address=127.0.0.1 \
--alsologtostderr=true \
--bind-address=127.0.0.1 \
--kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
--leader-elect=true \
--leader-elect-lease-duration=15s \
--leader-elect-renew-deadline=10s \
--leader-elect-retry-period=2s \
--log-dir=/var/log/kubernetes \
--log-flush-frequency=10s \
--logtostderr=false \
--port=10251 \
--secure-port=10259 \
--tls-cert-file=/etc/kubernetes/ssl/kube-scheduler.pem \
--tls-private-key-file=/etc/kubernetes/ssl/kube-scheduler-key.pem \
--v=4"

EOF
}

function boot_kube_components {
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
cat > "/etc/conf.d/kubelet" <<-EOF
command_args= " \
--address=$KUBE_MASTER_IP \
--allow-privileged=true \
--alsologtostderr=true \
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
--kubeconfig=/etc/kubernetes/kubelet-$(hostname).kubeconfig \
--log-dir=/var/log/kubernetes \
--log-flush-frequency=5s \
--logtostderr=false \
--pod-infra-container-image=$KUBE_MASTER_IP:30050/kube-system/pause-amd64:3.1 \
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

cat > "/etc/conf.d/kube-proxy" <<-EOF
command_args= " \
--alsologtostderr=true \
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
	for svc in {kube-proxy,kubelet}; do
	    rc-update add ${svc} default
	    rc-service  ${svc} start
	done
}
# kubectl get node


install_packages
generate_docker_mirror
generate_net_conf
generate_system_conf
generate_nginx_configure
generate_ca_certificates
generate_ssl_certificates
generate_kubes_certificates
generate_kubelet_ssl
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
