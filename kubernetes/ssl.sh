#!/bin/bash

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

generate_kubes_certificates