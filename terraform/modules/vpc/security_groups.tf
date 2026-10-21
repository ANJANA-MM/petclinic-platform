# Four baseline security groups per environment (technical-spec.md#security-groups, PETPLAT-8).
# Rules are standalone resources because the groups reference each other
# (cluster <-> node, node <-> ALB), which inline rules cannot express without a cycle.

# --- EKS control plane ------------------------------------------------------

resource "aws_security_group" "eks_cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "EKS control plane - API access from worker nodes"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-eks-cluster-sg"
    Component = "security"
  })
}

resource "aws_vpc_security_group_ingress_rule" "eks_cluster_api_from_nodes" {
  security_group_id            = aws_security_group.eks_cluster.id
  referenced_security_group_id = aws_security_group.eks_node.id
  description                  = "API server access from worker nodes"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-eks-cluster-api-from-nodes", Component = "security" })
}

resource "aws_vpc_security_group_egress_rule" "eks_cluster_all" {
  security_group_id = aws_security_group.eks_cluster.id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # checkov:skip=CKV_AWS_382:Control plane needs outbound to AWS APIs (spec)

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-eks-cluster-all-out", Component = "security" })
}

# --- EKS worker nodes -------------------------------------------------------

resource "aws_security_group" "eks_node" {
  name        = "${local.name_prefix}-eks-node-sg"
  description = "EKS worker nodes - cluster, node-to-node, ALB traffic"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-eks-node-sg"
    Component = "security"
  })
}

resource "aws_vpc_security_group_ingress_rule" "eks_node_from_cluster" {
  security_group_id            = aws_security_group.eks_node.id
  referenced_security_group_id = aws_security_group.eks_cluster.id
  description                  = "All traffic from control plane"
  ip_protocol                  = "-1"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-eks-node-from-cluster", Component = "security" })
}

resource "aws_vpc_security_group_ingress_rule" "eks_node_self" {
  security_group_id            = aws_security_group.eks_node.id
  referenced_security_group_id = aws_security_group.eks_node.id
  description                  = "Inter-node communication"
  ip_protocol                  = "-1"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-eks-node-self", Component = "security" })
}

resource "aws_vpc_security_group_ingress_rule" "eks_node_kubelet_from_cluster" {
  security_group_id            = aws_security_group.eks_node.id
  referenced_security_group_id = aws_security_group.eks_cluster.id
  description                  = "Kubelet API from control plane"
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-eks-node-kubelet", Component = "security" })
}

resource "aws_vpc_security_group_ingress_rule" "eks_node_nodeport_from_alb" {
  security_group_id            = aws_security_group.eks_node.id
  referenced_security_group_id = aws_security_group.alb.id
  description                  = "NodePort services from ALB"
  ip_protocol                  = "tcp"
  from_port                    = 30000
  to_port                      = 32767

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-eks-node-nodeport", Component = "security" })
}

resource "aws_vpc_security_group_egress_rule" "eks_node_all" {
  security_group_id = aws_security_group.eks_node.id
  description       = "All outbound (ECR, Secrets Manager, S3 via IGW - no NAT)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # checkov:skip=CKV_AWS_382:All-public design, nodes pull images via IGW (ADR-0001)

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-eks-node-all-out", Component = "security" })
}

# --- RDS (MySQL) ------------------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS MySQL - 3306 from EKS nodes only"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-rds-sg"
    Component = "security"
  })
}

resource "aws_vpc_security_group_ingress_rule" "rds_mysql_from_nodes" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.eks_node.id
  description                  = "MySQL from EKS worker nodes"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-rds-mysql-from-nodes", Component = "security" })
}

# --- ALB --------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB - public HTTP/HTTPS, forwards to nodes"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-alb-sg"
    Component = "security"
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  # checkov:skip=CKV_AWS_260:Public ALB by design (PETPLAT-8); HTTP redirects to HTTPS at listener

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb-http-in", Component = "security" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb-https-in", Component = "security" })
}

resource "aws_vpc_security_group_egress_rule" "alb_nodeport_to_nodes" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.eks_node.id
  description                  = "Target group traffic to nodes (NodePort range)"
  ip_protocol                  = "tcp"
  from_port                    = 30000
  to_port                      = 32767

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb-nodeport-out", Component = "security" })
}

resource "aws_vpc_security_group_egress_rule" "alb_health_to_nodes" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.eks_node.id
  description                  = "Health checks to nodes"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb-health-out", Component = "security" })
}
