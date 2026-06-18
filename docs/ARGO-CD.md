# Recommended approach for a multi-stage project via Argo CD

**TL;DR:** Use [this application manifest](../argo-app-manifest.yaml) as the starting point for your project.

## Short introduction to Argo CD

Argo CD is a declarative GitOps continuous delivery tool for Kubernetes. It automates the deployment and lifecycle management of applications by continuously monitoring a Git repository and ensuring that the desired state defined in Git matches the actual state running in a Kubernetes cluster.

Key Capabilities:
- **GitOps-based deployments** – Git serves as the single source of truth for application and infrastructure configuration.
- **Automated synchronization** – Detects configuration drift and can automatically reconcile cluster resources with the desired state in Git.
- **Multi-environment support** – Simplifies deployment management across development, test, and production environments.
- **Helm support** – Can deploy a properly written, self contained Helm chart.
- **Visual management interface** – Provides a web UI and CLI for monitoring application health, synchronization status, and deployment history.
- **Auditability and traceability** – Every deployment is tied to a Git commit, making it easy to track what was deployed and when.

In a nutshell: Argo CD monitors a Git repository containing a Helm chart, renders the chart using environment-specific configuration, and deploys the resulting Kubernetes resources into the target namespace. Any changes committed to the configured Git branch can then be automatically synchronized to the cluster according to the application's sync policy. All one needs to do is:
1. Create and populate your Git repository
2. Configure a repository connection, tell Argo CD where your Git repo is located and how to access it (preferably use HTTPS and API key based authentication)
3. Adjust the [application manifest](../argo-app-manifest.yaml) and import it to Argo CD

If unfamiliar but interested, feel free to [learn more about Argo CD](https://argo-cd.readthedocs.io/en/stable/).

## Helm Values configuration options with Argo CD

Values (configuration data) can be specified using a **default/override pattern**, where multiple sources of configuration are merged in a top-down order.

1. **Values Files**
   - Values are read from files listed under `source.helm.valueFiles`.
   - All files are merged in the order they are listed.

2. **Inline Values (`valuesObject`)**
   - The equivalent of a values file can be specified directly in the Application manifest using `source.helm.valuesObject`.
   - These values are merged with the values files and override conflicting values.

3. **Helm Parameters**
   - Individual parameters can be specified under `source.helm.parameters` using path-based notation.
   - Parameters have the highest precedence and override values defined in both values files and `valuesObject`.

## Recommended configuration strategy

Typically, a solution is deployed to multiple isolated environments representing stages such as DEV, TEST and PROD. It is considered good practice to separate common configuration (shared across all environments)
from environment-specific configuration that differs between stages.

### Option A

The following file contains environment-agnostic configuration common to all stages:
- `values.yaml`

The config files below merely captures the values which are to be overridden on a per-environment basis. This approach highly reduces redundancy.
- `values-override-DEV.yaml`
- `values-override-TEST.yaml`
- `values-override-PROD.yaml`

In addition, a full `values-config.yaml` variant for each environment is provided, the format of which most users of the product are familiar with. 
- `values-config-DEV.yaml`
- `values-config-TEST.yaml`
- `values-config-PROD.yaml`

**Benefits:**
- Reduces configuration duplication
- Promotes configuration reuse across deployment stages
- Improves maintainability and simplifies environment management
- Retrieves all non-sensitive configuration data from a single location, the Git repo
- Keeps `values-config-*.yaml` files easy to understand for people familiar with the original starterkit

### Option B

The previous approach may  yield high redundancy between the `values-config-*.yaml` files which can be eliminated by applying a **default/override approach** to these files as well resulting in the following files common to all stages:
- `values.yaml`
- `values-config.yaml`

The config files below merely captures environment specific overrides for both `values.yaml` and `values-config.yaml`.
- `values-override-DEV.yaml`
- `values-override-TEST.yaml`
- `values-override-PROD.yaml`

This approach reduces redundancy even further, but mixes the content of `values` and `values-config` in the override files. However, creating environment specific (thin) override files for both `values.yaml` and `values-config.yaml` separately for each environment would result in too many small files which is deemed a worse practice and therefore not proposed as 'option C'.

## Secrets Management

### Development / dummy setup

The `valuesObject` section can be used to provide sensitive data that must not be stored in a Git repository but one would feel comfortable storing it in plain text in Argo CD.

For development or dummy environments for a quick demo, one would insert the contents of `secrets.yaml` which can be conveniently generated by `secrets-setup.sh` and/or adjusted manually.

### Production-ready approach

Instead of storing secrets directly in the manifest, leave `valuesObject` empty and source secrets from a secure secret management solution such as Vault. To do so, toggle `general.install.externalSecret.*`. Describing Vault setup itself is out of the scope of this document.

## Further tips and tricks

### Deployment Revision Tracking

Annotating the Kubernetes namespace with the Git commit hash (or another revision identifier) allows teams to correlate deployments with source code revisions:
-  Track exactly what revision was last deployed
- Improve auditability
- Simplify troubleshooting

Argo CD exposes an environment variable `$ARGO_APP_REVISION_SHORT` which the manifest binds to Helm parameter `revision` to expose the currently deployed Git commit hash during template rendering. It will be stored in form of an annotation on the K8s namespace.

### Do not publicly disclose license keys 

While leaking license data and activation keys does not represent an inherent security risk and storing these in a private corporate Git repositor would be fine for many users, some might prefer to not store such information under version control at all (especially, when access to the repo is not restricted).

Instead of storing license keys in Git repositories (inside `values-config.yaml`), Argo CD can dynamically inject license values during Helm template rendering.  The [sample application manifest](../argo-app-manifest.yaml) demonstrates dynamic injection of the following licenses via Helm parameters:
- `general.install.license.activationKey`
- `general.install.license.ldapKey`
- `general.install.license.isvdiKey`

Keep in mind to replace the sample/dummy values in the manifest with your actual license keys before deployment.

**Benefits:**
- Provides an alternative to committing sensitive license information  to source control
- May simplify license management across environments

### PKI/x509 certificate management

Certificates (and their respective certificate signing requests and private keys) are stage-specific. The product originally requires one to store certificates (and private keys) under `config/certs` which then gets exposed to the containers (including a local CA private key as well).

This project fundamentally changes the approach to managing certificates.
- Only exposes the necessary certificate for each component
- Prepared certificates upfront, not within a container running in the target environment
- Provide an optional setting `general.install.certDir` in `values-config.yaml` to override the certificate directory

It is a good practice to specify a stage-specific certificate directory by setting `general.install.certDir` (to e.g `config/certs/DEV` in `values-config-DEV.yaml` or `values-override-DEV.yaml` depending on your choice of configuration strategy, 'Option A' or 'Option B' above) if you decide to store x509-related files in your Git repo.

However, the best practice is to not store any PKI/x509 related data (not even public keys/certificates) in Git, but source these from Vault (or a comparable alternative) dynamically by toggling `general.install.externalSecret.*certs` in `values-config.yaml`.

