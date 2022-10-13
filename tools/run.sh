#!/bin/sh
set -o errexit

kind create cluster

flux install

kubectl apply -f ./manifests/flux-gitrepository.yaml
kubectl apply -f ./manifests/flux-kustomization.yaml

