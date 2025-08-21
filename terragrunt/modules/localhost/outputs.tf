output "localhost_public_ips" {
  value = split("\n", trimspace(data.external.localhost_public_ips.result.output))
}
