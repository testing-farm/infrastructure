#!/bin/bash -eu

echo "[+] building container images"
OS=$OS VERSION=$VERSION ./container.sh

echo "[+] pulling built container images as root"
if [ "$OS" = "fedora" ]; then
  IMAGE="quay.io/testing-farm/fedora-bootc:${VERSION,,}"
  VM_IMAGE="Fedora-$VERSION"
elif [ "$OS" = "centos" ]; then
  IMAGE="quay.io/testing-farm/centos-bootc:stream$VERSION"
  VM_IMAGE="CentOS-Stream-$VERSION"
fi

sudo podman pull $IMAGE

echo "[+] image version built"
skopeo inspect --retry-times=5 --tls-verify=false docker://$IMAGE | jq -r '.Labels."org.opencontainers.image.version"'

echo "[+] running goss tests"
sudo CONTAINER_RUNTIME=podman dgoss run -e TARGET_IMAGE=$IMAGE --privileged --network=host --entrypoint sleep --stop-timeout=0 $IMAGE infinity

echo "[+] entering $HOME/images"
pushd $HOME/images

echo "[+] removing old qcow2 builds and images"
sudo rm -rf output/$OS-$VERSION-x86_64

echo "[+] building $VM_IMAGE"
mkdir -p output/$VM_IMAGE-x86_64; sudo podman run --network=host  --rm   -it   --privileged   --pull=newer   --security-opt label=type:unconfined_t -v $XDG_RUNTIME_DIR/containers/auth.json:/run/containers/0/auth.json:Z -v $(pwd)/output/$VM_IMAGE-x86_64:/output -v /var/lib/containers/storage:/var/lib/containers/storage quay.io/centos-bootc/bootc-image-builder:latest build --type qcow2 --rootfs xfs $IMAGE

echo "[+] copying qcow2s to artifacts.testing-farm.io"
sudo chown -Rf mvadkert:mvadkert ~/images
scp output/$VM_IMAGE-x86_64/qcow2/disk.qcow2 core@artifacts.dev.testing-farm.io:/archive/images/$VM_IMAGE-image-mode-x86_64.qcow2

echo "[+] syncing qcow2s to Testing Farm"
. /home/mvadkert/.cache/pypoetry/virtualenvs/tft-admin-gMwW6N3H-py3.12/bin/activate
cloud="fedora-aws"
tft-admin cloud set $cloud
tft-admin cloud compose delete $VM_IMAGE-image-mode-x86_64 || true
tft-admin cloud compose sync --cloud-compose $VM_IMAGE-image-mode-x86_64 --target-cloud-compose $VM_IMAGE-image-mode-x86_64 --arch x86_64 --from-file output/$VM_IMAGE-x86_64/qcow2/disk.qcow2  --force

popd
