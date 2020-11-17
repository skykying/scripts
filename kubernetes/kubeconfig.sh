#!/bin/bash


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
confiure_kube_components