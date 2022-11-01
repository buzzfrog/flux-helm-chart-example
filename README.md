# flux-helm-chart-example

Run `./tools/run.sh` to setup example.

# Introduction
Helm charts is often used to define a Kubernetes workload (application).
We want to support Helm charts in defining applications with gitops. 

# Solution
An example of the solution can be found [here](https://github.com/buzzfrog/flux-helm-chart-example).

## Apps
The apps structure look like this for an application, here with the name **app1**.

```
├── apps
│   └── app1
│       └── v1
│           ├── chart
│           │   ├── Chart.yaml
│           │   ├── templates
│           │   │   ├── config-configmap.yaml
│           │   │   └── deployment.yaml
│           │   └── values.yaml
│           ├── flux-helmrelease.yaml
│           └── kustomization.yaml
```
We describe different versions of the chart with the subfolder **v1**. In that folder we have a subfolder **chart** that contain the whole helm chart.

In **v1** we also have a Flux HelmRelease definition, `flux-helmrelease.yaml`. This definition connects the GitRepository and points where the helm chart can be found.
An important part of this definition is the **valuesFrom**. With this we can inject new values in the helm chart. These values are unique for each cluster.

```
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: app1-helmrelease
  namespace: app1-ns
spec:
  releaseName: app1-v1
  targetNamespace: app1-ns
  chart:
    spec:
      chart: ./apps/app1/v1/chart 
      sourceRef:
        kind: GitRepository
        name: source-repository
        namespace: flux-workspace
  interval: 30s
  upgrade:
    force: true
  install:
    createNamespace: true
    remediation:
      retries: 3
  values: 
    none: none
  valuesFrom:
    - kind: ConfigMap
      name: app1-config-values
    - kind: ConfigMap
      name: app1-line-config-values
    - kind: ConfigMap
      name: app1-cluster-config-values
```

# Cluster structure
This structure defines one cluster, **cluster1**. (I have not included *sets* here to make it a bit simpler.)
```
├── clusters
│   └── cluster1
│       ├── app1
│       │   ├── app1-config-values.yaml
│       │   ├── app1-line-config-values.yaml
│       │   ├── kustomization.yaml
│       │   ├── kustomizeconfig.yaml
│       │   ├── namespace-transformer.yaml
│       │   └── namespace.yaml
│       └── config
│           ├── app1-cluster-config-values.yaml
│           └── kustomization.yaml
```

# Values merging
How can we handle input values, especially if they are merged from different sources in the folder
structure.

Our example merge values from five places:
1. The default `values.yaml` in chart folder `apps/app1/v1/chart`
2. Values from `clusters/cluster1/app1/app1-config-values.yaml`
3. Values from `clusters/cluster1/app1/app1-line-config-values.yaml`
4. Values from `clusters/cluster1/config/app1-cluster-config-values.yaml`
5. Inline values in the HelmRelease manifest
```
    values: 
      none: none
```
   These can be patched in kustomization.yaml:
```
   patchesJson6902:
  - target:
      kind: HelmRelease
      name: app1-helmrelease
      version: v2beta1
    patch: |-
      - op: add
        path: /spec/values/replica
        value: 5
 ```

# Helm Sub-Charts
We envision that the "main" charts should be stored in the apps folder. All other charts should be stored in the
components folder. 

Example:
We have a sub-charts in the components folder, `components/component1`. This component is defined with a 
Component Manifest (instead of the usual Kustomization Manifest).

```
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component

resources:
  - flux-helmrelease.yaml
```
This component is referenced in the main charts kustomization.yaml file:
```
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - flux-helmrelease.yaml

components:
  - ../../../components/component1
```


# Chart dependencies
It is possible to define dependencies between charts in more than one way. We choose to use a feature in
Flux HelmRelease to do this. With the field **dependsOn** we can describe these dependencies.
The chart `component1-helmrelease` will be deployed first and will wait until it is deployed. 

```
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: app1-helmrelease
  namespace: app1-ns
spec:
  releaseName: app1-v1
  targetNamespace: app1-ns
  chart:
    spec:
      chart: ./apps/app1/v1/chart 
      sourceRef:
        kind: GitRepository
        name: source-repository
        namespace: flux-workspace
  interval: 30s
  upgrade:
    force: true
  install:
    createNamespace: true
    remediation:
      retries: 3
 <-shorten-for-abbreviation>
  dependsOn:
    - name: component1-helmrelease
  ```