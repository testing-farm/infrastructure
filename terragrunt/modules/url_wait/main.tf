terraform {
  required_providers {
    null = {
      source = "hashicorp/null"
      version = "3.2.3"
    }
  }
}

locals {
   url_map = { for url in var.urls : url => url }
}

resource "null_resource" "wait_for_urls" {
  for_each = local.url_map

  provisioner "local-exec" {
    command = <<EOT
url="${each.value}"
timeout=${var.timeout}
start_time=$(date +%s)
while ! curl -s --fail "$url" > /dev/null; do
  echo "Waiting for $url..."
  sleep 5
  current_time=$(date +%s)
  elapsed_time=$((current_time - start_time))
  if [ "$elapsed_time" -ge "$timeout" ]; then
    echo "Timeout reached while waiting for URL '$url' to be available."
    exit 1
  fi
done
echo "The URL '$url' is available."
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}
