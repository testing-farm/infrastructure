output "localhost_public_ip" {
  value = data.external.localhost_public_ip.result.output
}
