resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.helm_chart_version
  namespace  = var.namespace

  create_namespace = true

  set = [
    # High Availability: Run 3 replicas of ArgoCD server for production resilience
    {
      name  = "server.replicas"
      value = "2"
    },
    # High Availability: Run 2 replicas of application controller
    {
      name  = "controller.replicas"
      value = "2"
    },
    # High Availability: Run 2 replicas of repo server for Git operations
    {
      name  = "repoServer.replicas"
      value = "2"
    },
    # High Availability: Run 2 replicas of ApplicationSet controller
    {
      name  = "applicationSet.replicas"
      value = "2"
    },
    # Security: Run ArgoCD in insecure mode (TLS terminated at ALB, not at pod)
    {
      name  = "server.extraArgs[0]"
      value = "--insecure"
    },
    # Service: Use ClusterIP since ALB handles external access
    {
      name  = "server.service.type"
      value = "ClusterIP"
    },
    # Redis HA: Enable Redis high availability for production (multiple Redis replicas)
    {
      name  = "redis-ha.enabled"
      value = "true"
    },
    # Config: Enable exec for debugging (allows kubectl exec into pods)
    {
      name  = "server.config.exec\\.enabled"
      value = "true"
    }
  ]
}
