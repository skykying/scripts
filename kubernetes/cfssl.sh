#!/bin/bash

# https://www.cnblogs.com/fanqisoft/p/10765038.html

# https://www.jianshu.com/p/214cfeb12ad3 手动部署kubernetes集群
###########################################################################################

mkdir -p /etc/kubernetes/ssl
cd /etc/kubernetes/ssl

# 生成一个配置模板
cfssl print-defaults config > config.json
cfssl print-defaults csr > csr.json

# @@@@@@@@@@@@@@@@@@@@
# 生成配置模板及证书信息
cat > ca-config.json <<EOF
{
    "signing":{
        "default":{
            "expiry":"87600h"
        },
        "profiles":{
            "kubernetes":{
                "expiry":"87600h",
                "usages":[
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            }
        }
    }
}
EOF

cat > ca-csr.json <<EOF
{
    "CN":"kubernetes",
    "key":{
        "algo":"rsa",
        "size":2048
    },
    "names":[
        {
            "C":"CN",
            "L":"Hebei",
            "ST":"Zhangjiakou",
            "O":"k8s",
            "OU":"System"
        }
    ]
}
EOF
# 使用证书信息文件生成证书
cfssl gencert -initca ca-csr.json | cfssljson -bare ca -

# @@@@@@@@@@@@@@@@@@@@
# 生成服务端的配置模板及证书信息
cat > server-csr.json << EOF
{
    "CN":"kubernetes",
    "hosts":[
        "127.0.0.1",
        "192.168.0.211",
        "192.168.0.212",
        "192.168.0.213",
        "10.10.10.1",
        "kubernetes",
        "kubernetes.default",
        "kubernetes.default.svc",
        "kubernetes.default.svc.cluster",
        "kubernetes.default.svc.cluste.local"
    ],
    "key":{
        "algo":"rsa",
        "size":2048
    },
    "names":[
        {
            "C":"CN",
            "L":"Hebei",
            "ST":"Zhangjiakou",
            "O":"k8s",
            "OU":"System"
        }
    ]
}
EOF

cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes server-csr.json | cfssljson -bare server

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@
# 集群管理员通过该证书访问集群
cat > admin-csr.json <<EOF
{
    "CN":"admin",
    "hosts":[],
    "key":{
        "algo":"rsa",
        "size":2048
    },
    "names":[
        {
            "C":"CN",
            "L":"Hebei",
            "ST":"Zhangjiakou",
            "O":"system:masters",
            "OU":"System"
        }
    ]
}
EOF


cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes admin-csr.json | cfssljson -bare admin

# @@@@@@@@@@@@@@@@@@@@@@@@@@@@@
cat > kube-proxy-csr.json <<EOF
{
    "CN":"system:kube-proxy",
    "hosts":[],
    "key":{
        "algo":"rsa",
        "size":2048
    },
    "names":[
        {
            "C":"CN",
            "L":"Hebei",
            "ST":"Zhangjiakou",
            "O":"k8s",
            "OU":"System"
        }
    ]
}
EOF

cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-proxy-csr.json | cfssljson -bare kube-proxy

# 只保留证书文件，删除多余的文件
ls |grep -v pem |xargs -i rm {}
