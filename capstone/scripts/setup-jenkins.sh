#!/usr/bin/env bash
# One-time wiring of the local Jenkins service to Docker and minikube.
# Run as your normal user (it calls sudo where needed):
#
#   bash capstone/scripts/setup-jenkins.sh
set -Eeuo pipefail
JHOME=/var/lib/jenkins

sudo systemctl enable --now jenkins
sudo usermod -aG docker jenkins

# Give Jenkins its own kubeconfig for the minikube context, with certificates
# embedded (--flatten) so it does not need to read your ~/.minikube.
sudo mkdir -p "$JHOME/.kube"
kubectl config view --flatten --minify --context minikube | sudo tee "$JHOME/.kube/config" >/dev/null
sudo chown -R jenkins:jenkins "$JHOME/.kube"
sudo chmod 600 "$JHOME/.kube/config"

sudo systemctl restart jenkins   # picks up the docker group membership
echo "Checking what the jenkins user can reach:"
sudo -u jenkins kubectl get namespaces | grep -E 'NAME|kijani-staging|default|monitoring' || true
sudo -u jenkins docker ps --format '{{.Names}}' | head -3
sudo -u jenkins ansible --version | head -1
echo
echo "Jenkins: http://localhost:8080"
if sudo test -f "$JHOME/secrets/initialAdminPassword"; then
  echo "First-time unlock key: sudo cat $JHOME/secrets/initialAdminPassword"
fi
