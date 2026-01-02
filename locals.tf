locals {
  # Compute a cluster name that appends the environment suffix when provided.
  # If `var.env_name` is empty, fall back to `var.cluster_name` as-is.
  cluster_name = var.env_name != "" ? format("%s-%s", var.cluster_name, var.env_name) : var.cluster_name
}
