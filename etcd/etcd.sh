#!/bin/bash

# https://blog.csdn.net/liuyuhui_gdtyj/article/details/84863925

mkdir -p /etc/etcd/ssl
cd /etc/etcd/ssl

cfssl print-defaults config > ca-config.json
cfssl print-defaults csr > ca-csr.json


#@@@@@@@@@@@@@@@@@
#CA配置文件
cat > ca-config.json <<EOF
{
    "signing": {
        "default": {
            "expiry": "43800h"
        },
        "profiles": {
            "server": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth"
                ]
            },
            "client": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "client auth"
                ]
            },
            "etcd": {
                "expiry": "43800h",
                "usages": [
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
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@2
#CA请求文件
cat > ca-csr.json <<EOF
{
    "CN": "etcd",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "ST": "Guangdong",
            "L": "Guangzhou",
            "O": "etcd",
            "OU": "System"
        }
    ]
}
EOF
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
#在当前目录下生成ca.csr、ca-key.pem、ca.pem三个文件

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
#etcd证书和私钥
#etcd证书签名请求
cat > etcd-csr.json <<EOF
{
    "CN": "etcd",
    "hosts": [
      "127.0.0.1",
      "10.3.8.101",
      "10.3.8.102",
      "10.3.8.103",
      "localhost",
      "core1",
      "core2",
      "core3"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "ST": "Guangdong",
            "L": "Guangzhou",
            "O": "etcd",
            "OU": "System"
        }
    ]
}
EOF

#hosts中三个ip即是三个ETCD节点，因为共用证书，所以写一起了
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=etcd etcd-csr.json | cfssljson -bare etcd

#生成etcd.pem etcd-key.pem，三个节点共用此证书
#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

#附：数字证书中主题(Subject)中字段的含义
#一般的数字证书产品的主题通常含有如下字段：
# 公用名称 (Common Name) 简称：CN 字段，对于 SSL 证书，一般为网站域名；而对于代码签名证书则为申请单位名称；而对于客户端证书则为证书申请者的姓名；
# 组织名称,公司名称(Organization Name) 简称：O 字段，对于 SSL 证书，一般为网站域名；而对于代码签名证书则为申请单位名称；而对于客户端单位证书则为证书申请者所在单位名称；
# 组织单位名称，公司部门(Organization Unit Name) 简称：OU字段

# 证书申请单位所在地
# 所在城市 (Locality) 简称：L 字段
# 所在省份 (State/Provice) 简称：S 字段，State：州，省
# 所在国家 (Country) 简称：C 字段，只能是国家字母缩写，如中国：CN


# install openrc of etcd

mkdir -p /var/lib/etcd
chown -R etcd:etcd /var/lib/etcd
chmod 700 /var/lib/etcd
install -Dm755 bin/etcd /usr/bin/etcd


install -Dm644 ./etcd.yaml-3.5  /etc/etcd/conf.yml
install -Dm644 ./etcd.confd /etc/conf.d/etcd
install -Dm755 ./etcd.initd /etc/init.d/etcd

install -Dm644 LICENSE /usr/share/licenses/etcd/LICENSE


# install etcdctl 
# install -Dm755 "$builddir"/bin/etcdctl "$subpkgdir"/usr/bin/etcdctl
