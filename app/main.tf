variable "region" {
  type = string
  default = "us-east4"
}

variable "project" {
  type = string
  default = "csye7125-297823"
}

provider "google" {
  region  = var.region
  project = var.project
}

resource "google_compute_network" "vpc_network" {
  name = "vpc-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "vpc_subnet" {
  name          = "vpc-subnetwork"
  ip_cidr_range = "10.2.0.0/16"
  region        = var.region
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_firewall" "vpc_firewall" {
  name    = "vpc-network-firewall"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "8080", "1000-2000", "3389", "3306", "443"]
  }

  source_tags = ["web"]
}

resource "google_container_cluster" "primary" {
  name     = "my-gke-cluster"
  location = var.region

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count = 1

  # cluster_autoscaling {
  #   enabled = true
  # }

  network = google_compute_network.vpc_network.name
  subnetwork = google_compute_subnetwork.vpc_subnet.name
  
  # networking_mode = VPC_NATIVE
  addons_config {
    network_policy_config {
      disabled = false
    }
  }

  master_auth {
    username = ""
    password = ""

    client_certificate_config {
      issue_client_certificate = false
    }
  }
  # lifecycle {
  #   ignore_changes = [
  #     addons_config,
  #     master_auth
  #   ]
  # }
}

resource "google_container_node_pool" "primary_preemptible_nodes" {
  name       = "my-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  # node_count = 1
  initial_node_count = 1

  node_config {
    preemptible  = true
    # machine_type = "e2-medium"
    machine_type = "e2-standard-4"

    disk_size_gb = 40
    
    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      # "https://www.googleapis.com/auth/devstorage.read_only",
      # "https://www.googleapis.com/auth/logging.write",
      # "https://www.googleapis.com/auth/monitoring",
      # "https://www.googleapis.com/auth/ndev.clouddns.readwrite",
      # "https://www.googleapis.com/auth/service.management.readonly",
      # "https://www.googleapis.com/auth/servicecontrol",
      # "https://www.googleapis.com/auth/trace.append",
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  autoscaling {
    min_node_count = 1
    max_node_count = 2
  }
}

resource "null_resource" "add_helm_repo" {
  provisioner "local-exec" {
    command = "helm repo add stable https://charts.helm.sh/stable"
  }
}

resource "null_resource" "helm_repo_update" {
  provisioner "local-exec" {
    command = "helm repo update"
    on_failure = continue
  }
}

resource "null_resource" "helm_install_nginx" {
  provisioner "local-exec" {
    command = "helm upgrade --install nginx-ingress stable/nginx-ingress --set controller.publishService.enabled=true"
    on_failure = continue
  }
}

resource "null_resource" "wait_for_nginx_pod_to_be_ready" {
  provisioner "local-exec" {
    command = "kubectl wait --for=condition=Ready pod -l app=nginx-ingress --timeout=180s"
  }
}

resource "null_resource" "nginx_load_balancer" {
  provisioner "local-exec" {
    command = "kubectl get svc nginx-ingress-controller -o json | jq -r .status.loadBalancer.ingress[0].ip"
  }
}

output "load_balancer_map" {
  value = "${null_resource.nginx_load_balancer}"
}

# Update subdomain with elb of nginx-ingress
# resource "google_dns_managed_zone" "my_zone" {
#   name     = "my-zone"
#   dns_name = "webapp.kinnarkansara.me."
# }

# resource "google_dns_record_set" "webapp_a_record" {
#   name = "webapp.${google_dns_managed_zone.my_zone.dns_name}"
#   type = "A"
#   ttl  = 60

#   managed_zone = google_dns_managed_zone.my_zone.name
#   managed_zone = csye7125-gke-zone

#   rrdatas = ["${null_resource.nginx_load_balancer}"]
# }

resource "null_resource" "nginx_ingress_without_ssl" {
  provisioner "local-exec" {
    command = <<EOD
      cat <<EOF | kubectl apply -f -
      apiVersion: networking.k8s.io/v1beta1
      kind: Ingress
      metadata:
        name: webapp-kubernetes-ingress
        annotations:
          kubernetes.io/ingress.class: nginx
      spec:
        rules:
        - host: webapp.kinnarkansara.me
          http:
            paths:
            - backend:
                serviceName: webapp-service
                servicePort: 80
      EOF
      EOD
  }
}

resource "null_resource" "cert_manager_crds" {
  provisioner "local-exec" {
    command = "kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.0.4/cert-manager.crds.yaml"
  }
}

resource "null_resource" "cert_manager_namespace" {
  provisioner "local-exec" {
    command = "kubectl create namespace cert-manager"
    on_failure = continue
  }
}

resource "null_resource" "add_jetstack_helm_repo" {
  provisioner "local-exec" {
    command = "helm repo add jetstack https://charts.jetstack.io"
  }
}

resource "null_resource" "cert_manager_helm_chart" {
  provisioner "local-exec" {
    command = "helm upgrade --install cert-manager --version v1.0.4 --namespace cert-manager jetstack/cert-manager"
  }
}

resource "null_resource" "apply_certificate" {
  provisioner "local-exec" {
    command = <<EOD
      cat <<EOF | kubectl apply -f -
      apiVersion: cert-manager.io/v1alpha2
      kind: ClusterIssuer
      metadata:
        name: letsencrypt-prod
      spec:
        acme:
          # Email address used for ACME registration
          email: kansara.k@northeastern.edu
          server: https://acme-v02.api.letsencrypt.org/directory
          privateKeySecretRef:
            # Name of a secret used to store the ACME account private key
            name: letsencrypt-prod-private-key
          # Add a single challenge solver, HTTP01 using nginx
          solvers:
          - http01:
              ingress:
                class: nginx
      EOF
      EOD
  }
}

resource "null_resource" "nginx_ingress_with_ssl" {
  provisioner "local-exec" {
    command = <<EOD
      cat <<EOF | kubectl apply -f -
      apiVersion: networking.k8s.io/v1beta1
      kind: Ingress
      metadata:
        name: webapp-kubernetes-ingress
        annotations:
          kubernetes.io/ingress.class: nginx
          cert-manager.io/cluster-issuer: letsencrypt-prod
      spec:
        tls:
        - hosts:
          - webapp.kinnarkansara.me
          secretName: webapp-kubernetes-tls
        rules:
        - host: webapp.kinnarkansara.me
          http:
            paths:
            - backend:
                serviceName: webapp-service
                servicePort: 80
      EOF
      EOD
  }
}