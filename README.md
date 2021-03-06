# Containerized Data Importer
This repo implements a fairly general file copier/importer. The importer, the controller which instantiates the importer, and the associated Persistent Volume Claims (PVC) reside within a single, dedicated namespace (or project) inside a Kubernetes or Openshift cluster.

1. [Purpose](#purpose)
1. [Design](#design)
1. [Running the CDI Controller](#running-the-data-importer)

Development: for devs who want to dig into the code, see our hacking [README](hack/README.md#getting-started-for-developers) (WIP)

## Purpose

This project eases the burden on cluster admins seeking to take advantage of Kubernetes/Openshift orchestration of their virtualized app platforms. For the purposes of running a VM inside a container, the imported file referred to above is a VM image and is considered to be an immutable _golden image_  source for subsequent cloning and instantiation. As a first step in migration to a Kubernetes cluster, virtual machine images must be imported into a location accessible to the kubelet. The Data Importer automates this by copying images from an external http repository and persisting them in in-cluster storage. The components of this process are detailed below.

## Design

The diagram below illustrates the architecture and control flow of this project.

![](doc/diagrams/cdi-controller.png)

### Work Flow
The agents responsible for each step are identified by corresponding colored shape.

#### Assumptions

- (Optional) A "golden" namespace  which is restricted such that ordinary users cannot create objects within it. This is to prevent a non-privileged user from trigger the import of a potentially large VM image.  In tire kicking setups, "default" is an acceptable namespace.

- (Required) A Kubernetes Storage Class which defines the storage provisioner. The "golden" pvc expects dynamic provisioning to be enabled in the cluster.

#### Event Sequence

1. The admin creates the Controller using a Deployment manifest provided in this repo. The Deployment launches the controller in the "golden" namespace and ensures only one instance of the controller is always running. This controller watches for PVCs containing special annotations which define the source file's endpoint path and secret name (if credentials are needed to access the endpoint).

1. (Optional) If the source repo requires authentication credentials to access the source endpoint, then the admin can create one or more secrets in the "golden" namespace, which contain the credentials in base64 encoding.

1. The admin creates the Golden PVC in the "golden" namespace.  This PVC should either reference a desired Storage Class or fall to the cluster default.  These PVCs, annotated per below, signal the controller to launch the ephemeral importer pod.  

1. When a PVC is created, the dynamic provisioner referenced by the Storage Class will create a Persistent Volume representing the backing storage volume.

1. (Parallel to 4) The dynamic provisioner creates the backing storage volume.

    >NOTE: for VM images there is a one-to-one mapping of a volume to a single image. Thus, each VM image has one PVC and one PV defining it.

1. The Data Import Pod, created by the controller, binds the Secret and mounts the backing storage volume via the Persistent Volume Claim.

1. The Data Importer Pod streams the file from the remote data store to the mounted backing storage volume. When the copy completes the importer pod terminates. The destination file name is always _disk.img_ but, since there is one volume per image file, the parent directory will (and must) differ.

### Components

**Data Import Controller:** Long-lived Controller pod in "golden" namespace.
The controller scans for "golden" PVCs in the same namespace looking for specific
annotations:
- kubevirt.io/storage.import.endpoint:  Defined by the admin: the full endpoint URI for the source file/image
- kubevirt.io/storage.import.secretName: Defined by the admin: the name of the existing Secret containing the credential to access the endpoint.
- kubevirt.io/storage.import.status: Added by the controller: the current status of the PVC with respect to the import/copy process. Values include:  ”In process”, “Success”, “ Failed”

On detecting a new PVC with the endpoint annotation (and lacking the status annotation), the controller creates the Data Importer pod "golden" namespace. The controller performs clean up operations after the data import process ends.

**Data Import Pod:** Short-lived pod in "golden" namespace. The pod is created by the controller and consumes the secret (if any) and the endpoint annotated in the PVC. It copies the object referenced by the PVC's endpoint annotation to the destination directory used by the storage class/provider. In all cases the target file **name** is _disk.img_.

**Dynamic Provisioner:** Existing storage provisoner(s) which create the Golden Persistent Volume that reference an empty cluster storage volume. Creation begins automatically when the Golden PVC is created by an admin.

**Endpoint Secret:** Long-lived secret in "golden" namespace that is defined and created by the admin. The Secret must contain the access key id and secret key required to make requests from the object store. The Secret is mounted by the Data Import pod.

**"Golden" Namespace:** Restricted/private Namespace for Golden PVCs and endpoint Secrets. Also the namespace where the CDI Controller and CDI Importer pods run.

**Golden PV:** Long-lived Persistent Volume created by the Dynamic Provisioner and written to by the Data Import Pod.  References the Golden Image volume in storage.

**Golden PVC:** Long-lived Persistent Volume Claim manually created by an admin in the "golden" namespace. Linked to the Dynamic Provisioner via a reference to the storage class and automatically bound to a dynamically created Golden PV. The "default" provisioner and storage class is used in the example; however, the importer pod supports any dynamic provisioner which supports mountable volumes.

**Object Store:** Arbitrary url-based storage location.  Currently we support http and S3 protocols.

**Storage Class:** Long-lived, default Storage Class which links Persistent Volume Claims to the desired Dynamic Provisioner(s). Referenced by the golden PVC. The example makes use of the "default" provisioner; however, any provisioner that manages mountable volumes is compatible.

## Running the Data Importer

Deploying the controller and importer pod fairly simple but requires several manual steps. An admin is expected to deploy the following object using `kubectl`. If the admin's current context is outside of the "golden" namespace then she is expected to use the `--namespace=<name>` kubectl flag:
1. "golden" namespace where the controller, importer, secret(s) and PVC(s) live.
1. secret(s) containing endpoint credentials. Not required if the endpoint(s) are public.
1. storage class(es) defining the backend storage provisioner(s).
1. controller pod via the Deployment template. Note that the controller pod spec needs to set an environment variable named OWN_NAMESPACE which can be done as:
```
...
   imagePullPolicy: Always
       env:
         - name: OWN_NAMESPACE
           valueFrom:
             fieldRef:
               fieldPath: metadata.namespace
```

### Assumptions
- A running Kubernetes cluster
- A reachable object store
- A file in the object store to be imported.

### Configuration

Make copies of the [example manifests](./manifests/importer) to some local directory for editing.  There are several values required by the data importer pod that are provided by the configMap and secret.

The files needed are:
- cdi-controller-pod.yaml
- endpoint-secret.yaml
- golden-pvc.yaml

#### cdi-controller-pod.yaml
(to be replaced by a Deployment manifest)

Defines the spec used by the controller. There should be nothing to edit in this file unless the "golden" namespace is desired to be hard-coded. Note: no namespace is supplied since the controller is excpected to be created from the "golden" namespace.

#### endpoint-secret.yaml

One or more endpoint secrets in the "golden" namespace are required for non-public endpoints. If the endpoint is public there is no need to an endpoint secret. No namespace is supplied since the secret is expected to be created from the "golden" namespace.

##### Edit:
- `metadata.name:` change this to a different secert name if desired. Remember to use this name in the PVC's secret annotation.
-  `accessKeyId:` to contain the endpoint's key and/or user name. This value must be **base64** encoded with no extraneous linefeeds. Use `echo -n "xyzzy" | base64` or `printf "xyzzy" | base64` to avoid a trailing linefeed.
-  `secretKey:`  the endpoint's secret or password, again base64 encoded.
The credentials provided here are consumed by the S3 client inside the pod.
> NOTE: the access key id and secret key **must** be base64 encoded without newlines (\n).

#### golden-pvc.yaml

This is the template PVC. No namespace is supplied since the PVC is excpected to be created from the "golden" namespace. A storage class is also not provided since there is excpected to be a default storage class per cluster. A storage class will need to be added if the default storage provider does not met the needs of golden images. For example, when copying VM image files, the backend storage should support fast-cloning, and thus a non-default storage class may be needed.

##### Edit:
-  `storageClassName:` change this to the desired storage class for high speed cloning.
-  `kubevirt.io/storage.import.endpoint:` change this to contain the source endpoint. Format: `(http||s3)://www.myUrl.com/path/of/data`
-  `kubevirt.io/storage.import.secretName:` (not needed for public endpoints). Edit the name of the secret containing credentials for the supplied endpoint.

### Deploy the API Objects

1. First, create the "golden" namespace:  (no manifests are provided)

1. Next, create one or more storage classes: (no manifests are provided).

1. Next, create the endpoint secrets:

        $ kubectl create -f endpoint-secret.yaml

1. Next, create the cdi controller:

        $ kubectl create -f cdi-controller-pod.yaml

1. Next, create the persistent volume claim to trigger the import process;

        $ kubectl create -f golden-pvc.yaml

1. Monitor the cdi-controller:

        $ kubectl logs cdi-controller

1. Monitor the importer pod:

        $ kubectl logs <unique-name-of-importer pod>  # shown in controller log above
