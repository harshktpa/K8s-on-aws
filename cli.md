aws configure
aws iam list-users | jq
aws ec2 create-security-group --group-name k8s-aws --description "to deploy k8s on aws" --vpc-id vpc-70b0bb19
aws ec2 describe-security-groups --group-ids sg-0bcc85db33ae3b786
aws ec2 authorize-security-group-ingress --group-id sg-0bcc85db33ae3b786 --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 run-instances --image-id ami-03ffa9b61e8d2cfda --count 1 --instance-type t2.micro --key-name k8sawskey --security-group-ids sg-0bcc85db33ae3b786 --subnet-id subnet-0cfad16cc1c3bb094

terminating ec2 instance
aws ec2 terminate-instances --instance-ids i-0891676bc46a3ad35


Ready to go 

- Creating a VPC for our cluster
```
VPCID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query "Vpc.VpcId" --output text)

```
- Enable DNS hostnames in the VPC
```
$ aws ec2 modify-vpc-attribute --enable-dns-support --vpc-id $VPCID
$ aws ec2 modify-vpc-attribute --enable-dns-hostnames --vpc-id $VPCID
```
- Tagging the VPC
```
aws ec2 create-tags --resources $VPCID --tags Key=Name,Value=k8s  Key=kubernetes.io/cluster/k8s,Value=shared
```
- show the route tables Id  for  VPC
```
$ PRIVATE_ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VPCID --query "RouteTables[0].RouteTableId" --output=text)
$ echo $PRIVATE_ROUTE_TABLE_ID
```
- creating new routetable 
```
$ PUBLIC_ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id $VPCID --query "RouteTable.RouteTableId" --output text)
$ echo $PUBLIC_ROUTE_TABLE_ID
```
- taging routetable
```
aws ec2 create-tags --resources $PUBLIC_ROUTE_TABLE_ID --tags Key=Name,Value=k8s-public
$ aws ec2 create-tags --resources $PRIVATE_ROUTE_TABLE_ID --tags Key=Name,Value=k8s-private
```
- creating subnets 
```
$ PRIVATE_SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPCID --availability-zone us-east-2a --cidr-block 10.0.0.0/20 --query "Subnet.SubnetId" --output text)
$ echo $PRIVATE_SUBNET_ID
$ PUBLIC_SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPCID --availability-zone us-east-2a --cidr-block 10.0.16.0/20 --query "Subnet.SubnetId" --output text)

- taging subnet
    $ aws ec2 create-tags --resources $PRIVATE_SUBNET_ID --tags Key=Name,Value=k8s-private-1a Key=kubernetes.io/cluster/k8s,Value=owned Key=kubernetes.io/role/internal-elb,Value=1
    $ aws ec2 create-tags --resources $PUBLIC_SUBNET_ID --tags Key=Name,Value=k8s-public-1a Key=kubernetes.io/cluster/k8s,Value=owned  Key=kubernetes.io/role/elb,Value=1

- asscosiating route table to subnet 
    $ aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_ID --route-table-id $PUBLIC_ROUTE_TABLE_ID

- Create an Internet Gateway and acquire its ID:
    INTERNET_GATEWAY_ID=$(aws ec2 create-internet-gateway --query "InternetGateway.InternetGatewayId" --output text)

- Attach this Internet Gateway to the VPC:
    $ aws ec2 attach-internet-gateway --internet-gateway-id $INTERNET_GATEWAY_ID --vpc-id $VPCID

- Create the necessary route rule in the public route table:
    $ aws ec2 create-route --route-table-id $PUBLIC_ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $INTERNET_GATEWAY_ID

- Create a NAT Gateway and configure the subnet to route
    - allocation
    $ NAT_GATEWAY_ALLOCATION_ID=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
    - creating nat gateway
    $ NAT_GATEWAY_ID=$(aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUBNET_ID --allocation-id $NAT_GATEWAY_ALLOCATION_ID --query NatGateway.NatGatewayId --output text)
    - nat gwy status
    $ aws ec2 describe-nat-gateways --query "NatGateways[].State" --filter "Name=nat-gateway-id,Values=$NAT_GATEWAY_ID" --output text
```
- creating the bastion server
```
$ BASTION_SG_ID=$(aws ec2 create-security-group --group-name ssh-bastion  --description "SSH Bastion Hosts"  --vpc-id $VPCID  --query GroupId --output text)

- enables traffic to port 22
    aws ec2 authorize-security-group-ingress --group-id $BASTION_SG_ID --protocol  tcp --port 22 --cidr 0.0.0.0/0

- create keypair from aws console

- creating instance aka bastion virtualmachine
    $ export UBUNTU_AMI_ID=ami-03ffa9b61e8d2cfda
    $ BASTION_ID=$(aws ec2 run-instances --image-id $UBUNTU_AMI_ID --instance-type t3.micro     --key-name k8s --security-group-ids  $BASTION_SG_ID --subnet-id $PUBLIC_SUBNET_ID   --associate-public-ip-address --query "Instances[0].InstanceId" --output text)

- add tga to bastion vm
    $ aws ec2 create-tags --resources $BASTION_ID --tags Key=Name,Value=ssh-bastion

- log in to bastion instance from local host
    BASTION_IP=$(aws ec2 describe-instances --instance-ids $BASTION_ID --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
    chmod 400 k8s.pem
    ssh -i k8s.pem ubuntu@$BASTION_IP
```
- Create the necessary IAM roles
```
- create master_policy.json ,see examples in manifest directory

- Create the policy 
    aws iam create-policy --policy-name k8s-cluster-iam-master --policy-document file://master_policy.json

    ** Make sure you copy the policy’s Arn string from the output because we’ll need it in the coming command.

- Create a role referencing 
    aws iam create-role --role-name k8s-cluster-iam-master --assume-role-policy-document file://manifest/trust_policy.json

- Create InstanceProfile
    $ aws iam create-instance-profile --instance-profile-name k8s-cluster-iam-master-Instance-Profile
- Create worker_policy.json ,see examples in manifest directory

- Create Policy 
    $ aws iam create-policy --policy-name k8s-cluster-iam-worker --policy-document file://manifest/worker_policy.json

- Create a role referencing 
    $ aws iam create-role --role-name k8s-cluster-iam-worker --assume-role-policy-document file://manifest/trust_policy.json

- Create InstanceProfile
    $ aws iam create-instance-profile --instance-profile-name k8s-cluster-iam-worker-Instance-Profile
```
- Create a base AMI
```
- Creating the EC2 instance
    $ K8S_AMI_SG_ID=$(aws ec2 create-security-group --group-name k8s-ami --description "Kubernetes AMI Instances" --vpc-id $VPCID --query GroupId --output text)
- authorize-security-group-ingress 
    $ aws ec2 authorize-security-group-ingress --group-id $K8S_AMI_SG_ID --protocol tcp --port 22 --source-group $BASTION_SG_ID
- create the instance 
    $K8S_AMI_INSTANCE_ID=$(aws ec2 run-instances --subnet-id $PRIVATE_SUBNET_ID --image-id $UBUNTU_AMI_ID --instance-type t3.micro --key-name k8s --security-group-ids $K8S_AMI_SG_ID --query "Instances[0].InstanceId" --output text)

- tag insatance
    $ aws ec2 create-tags --resources $K8S_AMI_INSTANCE_ID --tags Key=Name,Value=kubernetes-node-ami

- grab the private IP address
    $ K8S_AMI_IP=$(aws ec2 describe-instances --instance-ids $K8S_AMI_INSTANCE_ID --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)

- connecting to the instance through our bastion host
    ssh -J ubuntu@$BASTION_IP ubuntu@$K8S_AMI_IP
```
- Installing Kubernetes components
```
- Docker
    $ sudo mkdir -p /etc/systemd/system/docker.service.d/ && printf "[Service]\nExecStartPost=/sbin/iptables -P FORWARD ACCEPT" | sudo tee /etc/systemd/system/docker.service.d/10-iptables.conf
    ** command is just a shorthand for creating the docker.service.d directory, creating a 10-iptables.conf file inside it
-  Install Docker
    sudo apt-get update && sudo apt-get install -y docker.io

- Enbale Docker service
    sudo apt-get update && sudo apt-get install -y docker.io

- Installing kubeadm, kubelet, and kubectl
    (Add the repository key)
    $curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
    (Add the repository)
    $ sudo apt-add-repository 'deb http://apt.kubernetes.io/ kubernetes-xenial main'
    (Install the packages)
    sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl
```
- Generate the AMI
```
- Shutdown current instance 
    sudo shutdown -h now

-  create the AMI
    $ K8S_AMI_ID=$(aws ec2 create-image --name k8s --instance-id $K8S_AMI_INSTANCE_ID --description "Kubernetes" --query ImageId --output text)

-  AMI Image status
    $ aws ec2 describe-images --owners self --image-ids $K8S_AMI_ID  --query "Images[0].State"
```
- Launch the Master node instance
```
- Create secuirty group
    $ K8S_MASTER_SG_ID=$(aws ec2 create-security-group --group-name k8s-master --description "Kubernetes Master Hosts" --vpc-id $VPCID --query GroupId --output text)

- allow SSH traffic from the bastion 
    $ aws ec2 authorize-security-group-ingress --group-id $K8S_MASTER_SG_ID --protocol tcp --port 22 --source-group $BASTION_SG_ID

- create the instance
    $ K8S_MASTER_INSTANCE_ID=$(aws ec2 run-instances --private-ip-address 10.0.0.10 --subnet-id $PRIVATE_SUBNET_ID --image-id $K8S_AMI_ID --instance-type t3.medium --key-name k8s --security-group-ids $K8S_MASTER_SG_ID --iam-instance-profile Name=k8s-cluster-iam-master-Instance-Profile --query "Instances[0].InstanceId" --output text)

- Add tags
    $ aws ec2 create-tags --resources $K8S_MASTER_INSTANCE_ID --tags Key=Name,Value=k8s-k8s-master Key=kubernetes.io/cluster/k8s,Value=owned

- Grab the private IP 
    $ K8S_AMI_IP=$(aws ec2 describe-instances --instance-ids $K8S_AMI_INSTANCE_ID --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)

- set the hostname of the instance.
    $ sudo hostnamectl set-hostname $(curl -s http://169.254.169.254/latest/meta-data/hostname) && hostnamectl status

- configure the kubelet to work with the AWS cloud provider
    $ printf '[Service]\nEnvironment="KUBELET_EXTRA_ARGS=--cloud-provider=aws --node-ip=10.0.0.10"' | sudo tee /etc/systemd/system/kubelet.service.d/20-aws.conf

- bootstrap the cluster
    sudo kubeadm init --config=kubeadm.yaml

-apply kubernetes network plugin
    kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
````
- Enabling API access from your workstation
```
- configure the security group to allow access to the API server 
    $ aws ec2 authorize-security-group-ingress --group-id $K8S_MASTER_SG_ID --protocol tcp --port 6443 --source-group $BASTION_SG_ID

- enable communication between workstation and Kubernetes master
    sshuttle -D --dns -r ubuntu@52.12.189.248 10.0.0.0/16

- Download the kubeconfig file from the master node
    scp -i k8s.pem ubuntu@10.0.0.10:~/.kube/config .

```
- Adding a worker node
```
- Create security group  for worker node
    K8S_NODES_SG_ID=$(aws ec2 create-security-group --group-name k8s-nodes --description "Kubernetes Nodes" --vpc-id $VPCID --query GroupId --output text)

- Enable SSH access from the bastion server
    aws ec2 authorize-security-group-ingress --group-id $K8S_NODES_SG_ID --protocol tcp --port 22 --source-group $BASTION_SG_ID

- Worker nodes will need access to the API server on the master node
    aws ec2 authorize-security-group-ingress --group-id $K8S_MASTER_SG_ID --protocol tcp --port 6443 --source-group $K8S_NODES_SG_ID

- Workers to be able to access the DNS addon on the master node:
    aws ec2 authorize-security-group-ingress --group-id $K8S_MASTER_SG_ID --protocol all --port 53 --source-group $K8S_NODES_SG_ID

- Enable kubelete access from worker nodes for master node 
    aws ec2 authorize-security-group-ingress --group-id $K8S_NODES_SG_ID --protocol tcp --port 10250 --source-group $K8S_MASTER_SG_ID 
    aws ec2 authorize-security-group-ingress --group-id $K8S_NODES_SG_ID --protocol tcp --port 10255 --source-group $K8S_MASTER_SG_ID

- Pod intercommunication:
    aws ec2 authorize-security-group-ingress --group-id $K8S_NODES_SG_ID --protocol all --port -1 --source-group $K8S_NODES_SG_ID
```

- user_data.sh 
```
#!/bin/bash
set -exuo pipefail
hostnamectl set-hostname $(curl http://169.254.169.254/latest/meta-data/hostname)
cat <<EOT > /etc/systemd/system/kubelet.service.d/20-aws.conf
[Service]
<!-- Environment="KUBELET_EXTRA_ARGS=--cloud-provider=aws --node-ip=$(curl http://169.254.169.254/latest/meta-data/local-ipv4) --node-labels=node-role.kubernetes.io/node" -->
EOT
systemctl daemon-reload
systemctl restart kubelet
kubeadm join 10.0.0.10:6443 --token hi56rz.95jbaj3x820lyrrz \
    --discovery-token-ca-cert-hash sha256:20ddd0cc5fe3e0e228af4082c140e07ce0af295b9a95e80cb7e27142adecf27d 
```
- Auto Scaling configuration template
```
$ aws autoscaling create-launch-configuration --launch-configuration-name k8s-node-1.16.2-t3-medium-001 --image-id $K8S_AMI_ID --key-name k8s --security-groups $K8S_NODES_SG_ID --user-data file://user_data.sh --instance-type t3.medium --iam-instance-profile k8s-cluster-iam-master-Instance-Profile --no-associate-public-ip-address
```

- Deploying a sample application
```
---
apiVersion: apps/v1
kind: Deployment
metadata:
 name: frontend
 labels:
   app: frontend
spec:
 replicas: 3
 selector:
   matchLabels:
     app: frontend
 template:
   metadata:
     labels:
       app: frontend
   spec:
     containers:
     - name: app
       image: nginx
---
apiVersion: v1
kind: Service
metadata:
 name: frontend-svc
spec:
 selector:
   app: frontend
 ports:
 - name: http
   port: 80
   targetPort: 80
   protocol: TCP
 type: LoadBalancer
 ```

- referenece
https://www.linuxschoolonline.com/how-to-set-up-kubernetes-1-16-on-aws-from-scratch/

