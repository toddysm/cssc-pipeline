# KubeCon NA 2025 Copilot CLI Instructions
I am running a demo for KubeCon NA 2025 on using Azure Container Registry with Azure Kubernetes Service and Attribute-Based Access Control (ABAC). For this demo, I will ask you to use the Azure CLI and `oras` CLI tool to perform a series of tasks. Please follow the instructions and do not perform and tasks if I do not explicitly ask you to do so. More importantly, do not change any access permissions and do not use alternative methods. If you do not know how to perform a task, please let me know.

Use `az login` to authenticate me with Azure.

Create a resource group named `rg-kubecon-na-2025-demo` in the `westus2` region.

Create a premium Azure Container Registry named `acrkubeconna2025demo` in the resource group created earlier. Use the same region as the resource group.

Enable ABAC on the registry.

For the registry you created, assign `Container Registry Repository Catalog Lister` role to my user identity but don't set any conditions for this role.

For the registry you created, assign the `Container Registry Repository Writer` role to my user identity and create condition to read content and metadata and write content and metadata to the namespaces that start with `allowed/` and `blocked/`. When assigning the role, use environment variables to avoid issues with quotes. Also, export the environment variables to preserve them betwen bash calls. Use a single line for the command and properly escape the input for the condition. Here is the exact condition to use for the role assignment:

```
(
 (
  !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/content/read'})
  AND
  !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/content/write'})
  AND
  !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/metadata/read'})
  AND
  !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/metadata/write'})
 )
 OR 
 (
  @Request[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWithIgnoreCase 'allowed/'
  OR
  @Request[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWithIgnoreCase 'blocked/'
 )
)```

Use `oras` to copy `nginx:1.25-alpine` image from Docker Hub to the Azure Container Registry created earlier in reporitory `allowed/nginx`.

Use `oras` to copy `nginx:1.25-alpine` image from Docker Hub to the Azure Container Registry created earlier in reporitory `blocked/nginx`.

Create a single node AKS cluster named `aks-kubecon-na-2025-demo` in the resource group created earlier. Use the same region as the resource group. Enable Azure AD integration and enable the managed identity for the cluster. 

Provision the managed identity for the AKS cluster with `Container Registry Repository Reader` role scoped to the Azure Container Registry created earlier and add condition to read only from the `allowed/` namespace. When assigning the role, use environment variables to avoid issues with quotes. Also, export the environment variables to preserve them betwen bash calls. Use a single line for the command and properly escape the input for the condition. Here is the exact condition to use for the role assignment:

```
(
 (
  !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/content/read'})
  AND
  !(ActionMatches{'Microsoft.ContainerRegistry/registries/repositories/metadata/read'})
 )
 OR 
 (
  @Request[Microsoft.ContainerRegistry/registries/repositories:name] StringStartsWithIgnoreCase 'allowed/'
 )
)```

Assign `Azure Kubernetes Service Cluster Admin Role` to my user identity for the AKS cluster.

Deploy a sample nginx deployment to the AKS cluster using the image from the `allowed/nginx` repository in the Azure Container Registry. Observe and document what happens when trying to deploy this image.

Configure the AKS load balancer so I can access the NGINX application on my browser and load the browser with the NGINX page for the application.

Deploy another sample nginx deployment to the AKS cluster using the image from the `blocked/nginx` repository in the Azure Container Registry. Observe and document what happens when trying to deploy this image.

Summarize the results of the demo, including which image deployments succeeded and which failed, along with the reasons for each outcome.

List and export to a markdown file all the commands that you ran as part of this demo. Open the file in Visual Studio Code for review.
