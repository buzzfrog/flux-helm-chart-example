#!/bin/bash
set -e

info()
{
    echo '[INFO] ' "$@"
}

warn()
{
    echo '[WARN] ' "$@" >&2
}

fatal()
{
    echo '[ERROR] ' "$@" >&2
    exit 1
}

SOURCE_REPO=https://github.com/buzzfrog/flux-helm-chart-example
SOURCE_BRANCH=main
KUSTOMIZE_FOLDER=./clusters/cluster1
while getopts u:p:b:i:a: flag
do
    case "${flag}" in
        r) SOURCE_BRANCH=${OPTARG};;
        b) SOURCE_BRANCH=${OPTARG};;
        f) KUSTOMIZE_FOLDER=${OPTARG};;
    esac
done

# create cluster
info "Create a new Kind cluster..."
kind delete cluster 
kind create cluster --config ./manifests/cluster-config.yaml

# add helm repos
info "Add Helm repository..."
helm repo add gitea-charts https://dl.gitea.io/charts/
helm repo update

# gitea
info "Installing Gitea..."
helm upgrade --install gitea gitea-charts/gitea \
        --namespace gitea \
        --create-namespace \
        --set gitea.admin.username=gitea-admin \
        --set gitea.admin.password=Happy12Morning \
        --set service.ssh.type=ClusterIP \
        --set service.http.type=NodePort \
        --set service.http.port=3000 \
        --set service.http.nodePort=30950 \
        --set service.ssh.port=23 \
        --set service.ssh.type=NodePort \
        --set service.ssh.nodePort=30951 \
        --set memcached.enabled=false \
        --set gitea.config.server.ROOT_URL=http://localhost:3000 \
        --wait > /dev/null

kubectl exec gitea-0 -n gitea -c gitea -it -- \
    su git bash -c "gitea dump-repo --git_service github \
    --clone_addr $SOURCE_REPO \
    --repo_dir /data/repository-backup"

kubectl exec gitea-0 -n gitea -c gitea -it -- \
    su git bash -c "gitea restore-repo --owner_name gitea-admin --repo_name source-repository --repo_dir /data/repository-backup"

# Create API token.
TOKEN=$(curl -XPOST -H "Content-Type: application/json" -s -k -d "{\"name\":\"key-for-test\"}" \
    -u gitea-admin:Happy12Morning "localhost:3000/api/v1/users/gitea-admin/tokens" | jq .sha1 | xargs)

DEPLOY_KEY=$(cat ~/.ssh/id_rsa.pub)
curl -X 'POST' \
    "localhost:3000/api/v1/repos/gitea-admin/source-repository/keys?token=$TOKEN" \
    -H 'accept: application/json' \
    -H 'Content-Type: application/json' \
    -d '{
    "key": "'"$DEPLOY_KEY"'",
    "read_only": true,
    "title": "'"deploykey"'"
}'

GITEA_IP_SSH=$(kubectl get endpoints gitea-ssh -n gitea -o jsonpath='{.subsets[].addresses[].ip}')
GITEA_IP_FULL_SSH=$(kubectl get endpoints gitea-ssh -n gitea -o jsonpath='{.subsets[].addresses[].ip}:{.subsets[].ports[].port}')

flux install

kubectl create namespace flux-workspace

flux create secret git repository-auth \
    --url=ssh://git@localhost:23/gitea-admin/source-repository \
    --private-key-file=$HOME/.ssh/id_rsa --export \
    --namespace flux-workspace \
    | sed 's/localhost/'${GITEA_IP_SSH}'/' \
    | kubectl apply -f -

flux create source git source-repository \
    --url="ssh://git@${GITEA_IP_FULL_SSH}/gitea-admin/source-repository" \
    --secret-ref repository-auth \
    --namespace flux-workspace \
    --branch=${SOURCE_BRANCH} \
    --interval=1m

flux create kustomization cluster \
    --path=${KUSTOMIZE_FOLDER} \
    --source=source-repository \
    --namespace flux-workspace \
    --prune=true \
    --interval=1m
