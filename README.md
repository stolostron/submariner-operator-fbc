# File based catalog for the Submariner operator

This is based on/copied from gatekeeper-operator-fbc

# Managing the File Based Catalog

## Initializing the catalog from a current operator index

This step may not need to be re-done - was done with the oldest supported OCP at the time to generate
the catalog-template - then the next step (Adding or removing OCP versions) can prune the older unsupported
versions from older OCPs.

Use the [build/fetch-catalog.sh](../build/fetch-catalog.sh) script to pulling from the OCP vX.Y
index for the `submariner-product` operator package:

```bash
./build/fetch-catalog.sh X.Y submariner-product
```

## Adding or removing OCP versions

1. Update
   [konflux-release-data](https://gitlab.cee.redhat.com/releng/konflux-release-data/-/tree/main/tenants-config/cluster/kflux-prd-rh02/tenants/submariner-tenant),
   adding or removing OCP versions as needed.
2. If versions should be updated for an incoming or outgoing OCP version, update the
   [drop-versions.json](../drop-versions.json) map, which maps an OCP version to the version of the
   operator that should be dropped from the catalog.
3. Merge the PRs from Konflux corresponding to the addition or removal of the application. For
   additions, run the [pipeline-patch.sh](../.tekton/pipeline-patch.sh) script to patch the incoming
   pipeline with relevant updates.

## Updating the catalog entries

1. Run the [`add-bundle.sh`](../build/add-bundle.sh) script to add catalog entries into
   [`catalog-template.yaml`](../catalog-template.yaml) giving the Konflux bundle image as an
   argument. The image can be found on the Konflux console in the Application in the Components tab.
   For example:

   ```shell
   ./build/add-bundle.sh quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-X-Y@sha256:<sha>
   ```

2. Pruning previous catalogs without compelling reason is not allowed since it's already been
   deployed to customers. However, we can prune catalogs for unreleased versions of OCP.

   Update the OCP version <-> operator version map, [drop-versions.json](../drop-versions.json),
   with the version of the operator to drop for any unreleased OCP version.

3. Run the [build/generate-catalog-template.sh](../build/generate-catalog-template.sh) to regenerate
   the catalog template files:

   ```bash
   ./build/generate-catalog-template.sh
   ```

4. Run the [render-catalog.sh](../build/render-catalog.sh) script to re-render the catalog for the
   template files:

   ```bash
   ./build/render-catalog.sh
   ```

   **NOTE:** The catalog rendering replaces the Konflux image registry with the production Red Hat
   registry so the `opm` CLI can no longer reach it if you try to generate the catalog again before
   the image's release. In this case, you need to revert the bundle reference to the Konflux one for
   the script to complete.

## Testing an FBC image

A catalog source can be created pointing to the FBC image as follows:

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: fbc-test-catalogsource
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: quay.io/redhat-user-workloads/<tenant>-tenant/<fbc-image>@sha256:<digest>
  displayName: Konflux FBC test CatalogSource
  publisher: Red Hat
```
