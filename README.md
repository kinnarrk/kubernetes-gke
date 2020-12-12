# Google Kubernetes Engine (GKE)

## Team Members:
1. Kinnar Kansara
1. Rajashree Joshi

## Managing GKE Kubernetes clusters with Ansible Playbooks

This project is supported for Linux (Ubuntu 18.04). For other OS like MacOS or Windows, some system commands will need changes.

### Reuirements
- Python >= 2.7 (Generally available with recent linux distros)
- Ansible = 2.9.x

    ```    
    $ sudo apt update
    $ sudo apt install software-properties-common
    $ sudo apt-add-repository --yes --update ppa:ansible/ansible
    $ sudo apt install ansible
    ```
- GCloud-sdk

    ```    
    $ echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
    $ sudo apt-get install apt-transport-https ca-certificates gnupg
    $ curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
    $ sudo apt-get update && sudo apt-get install google-cloud-sdk 
    ```
- PIP packages for Ansible gcp modules

    ```
    $ pip install requests
    $ pip install google-auth
    ```

- Below APIs and Services should be enabled from GCP console to make everything work:
    1. Compute Engine API
    1. Cloud Monitoring API
    1. Cloud Logging API
    1. Kubernetes Engine API
    1. Cloud SQL Admin API
    1. Cloud DNS API
    1. Service Networking API
    1. Service Directory API
    1. Service Usage API


*This playbook installs `kubectl`, `boto` and `boto3` packages if they're not installed in the system. These packages are required to run all the tasks but they're installed within the playbook so not mentioned above.*

### Create Cluster

Create shell script preferably with file name `setup-k8s-cluster.sh` and keep the below content in the file:
```
#!/bin/bash

export CLUSTER_NAME=my-gke-cluster
export REGION_NAME=us-east4
export PROJECT_NAME=my-project-123456
export MACHINE_TYPE=e2-standard-4
export NUM_NODES=1
export MIN_NODES=1
export MAX_NODES=2
export EMAIL=me@example.com
export SUB_DOMAIN_NAME=webapp
export DNS_ZONE=gke.example.me

ANSIBLE_STDOUT_CALLBACK=debug ansible-playbook setup-k8s-cluster.yml --extra-vars "cluster_name=${CLUSTER_NAME} region_name=${REGION_NAME} project_name=${PROJECT_NAME} machine_type=${MACHINE_TYPE} num_nodes=${NUM_NODES} min_nodes=${MIN_NODES} max_nodes=${MAX_NODES} email=${EMAIL} sub_domain_name=${SUB_DOMAIN_NAME} dns_zone=${DNS_ZONE}"
```

**Important**: Make sure to execute the above script with elevated privileges i.e. with `sudo` because the playbook tries to install `boto` and `boto3` packages with `apt` which requires to be executed as root user. This is executable file so make sure that execute bit is set. Use `chmod +x setup-k8s-cluster.sh` to make it executable.

For above playbook to execute successfully, DNS zone mentioned in the env variable DNS_ZONE should be created beforehand.

During the execution, this will give public ip address for Bastion host. Use that to ssh into Bastion which in turn will be able to access Compute nodes and SQL instances.

For getting the internal IP addresses of Compute nodes and sql instances, access google cloud console

### Access Bastion Host
Use below command to access Bastion. Replace `bastion-ip-address` with the one got from above execution.
```
ssh -A ubuntu@bastion-ip-address
```

After getting into Bastion, use the same command as above with internal IP address of nodes to ssh into the each compute and sql instances.

### Delete Cluster
Create shell script preferably with file name `delete-k8s-cluster.sh` and keep the below content in the file:
```
#!/bin/bash

export CLUSTER_NAME=my-gke-cluster
export REGION_NAME=us-east4
export PROJECT_NAME=my-project-123456
export MACHINE_TYPE=e2-standard-4
export NUM_NODES=1
export MIN_NODES=1
export MAX_NODES=2
export EMAIL=me@example.com
export SUB_DOMAIN_NAME=webapp

ANSIBLE_STDOUT_CALLBACK=debug ansible-playbook delete-k8s-cluster.yml \
    --extra-vars "cluster_name=${CLUSTER_NAME} region_name=${REGION_NAME} project_name=${PROJECT_NAME} machine_type=${MACHINE_TYPE} num_nodes=${NUM_NODES} min_nodes=${MIN_NODES} max_nodes=${MAX_NODES} email=${EMAIL} sub_domain_name=${SUB_DOMAIN_NAME}"
```

This will delete the previously created kubernetes cluster

### References
https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-architecture
https://docs.ansible.com/ansible/latest/collections/google/cloud/
https://cloud.google.com/nat/docs/gke-example
https://github.com/GoogleCloudPlatform/gke-private-cluster-demo