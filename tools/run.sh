#!/bin/sh
set -o errexit

kind create cluster

flux install

kubectl apply -f flux-gitrepository.yaml
kubectl apply -f flux-kustomization.yaml

