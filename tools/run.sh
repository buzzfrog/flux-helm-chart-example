#!/bin/sh
set -o errexit

kind delete cluster --name flux-helm
kind create cluster --name flux-helm

flux install

kubectl apply -f ./manifests/flux-gitrepository.yaml
kubectl apply -f ./manifests/flux-kustomization.yaml

