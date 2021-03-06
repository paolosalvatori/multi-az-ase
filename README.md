---
services: azure-resource-manager, application-gateway, app-service, dns, azure-monitor, virtual-network
author: paolosalvatori
---

# Multi Availabilty-Zone App Service Environment #
This article explains how to build a network topology with 3 zonal ILB App Service Environments, each hosting an instance of the same web app, to guarantee intra region resiliency. An Application Gateway V2 distributes incoming requests across the 3 web apps, each located in a different App Service Environment, App Service Plan and Availability Zone.

As mentioned above, this topology guarantees intra-region resiliency for App Services such as Web Apps and Azure Functions, while waiting for the product group to implement zone-redundant App Service Environments. This topology could easily be extended to Integration Service Environments, by replacing App Service Environments with Integration Service Environments and Web Apps with Logic Apps. 

# Scenario #
A customer wants to deploy internal or extenal Web Apps across multiple Availability Zones within a single Azure region to guarantee better resilence in case of failure of one or more datacenters. An Application Gateway V2 is used to distribute incoming requests across multiple copies of the same web app. Each web app is hosted by a separate zonal ILB App Service Environment and makes use of a separate Applications Insights resource for logging requests, events, errors and metrics. Log Analytics is used to monitor the health status of the Azure services, such as the Application Gateway, that compose the infrastructure.

# Architecture #
The following picture shows the architecture and network topology of the sample.
<br/>
<br/>
![Architecture](https://raw.githubusercontent.com/paolosalvatori/multi-az-ase/master/images/architecture.png)
<br/>

A few notes on the architecture:

- A Private DNS zone is used for name resolution in the virtual network by translating service names to their private IP address via A records. The **setup.sh** bash script automatically creates A record in the private DNS zone for the Web Apps, App Service Environments, and Application Gateway. Please refer to the script for more details.
- Visual Studio 2019 was used to develop and test the ASP.NET Core 3.0 application used to test the topology. 
- The **helloworld** folder contains the code of the ASP.NET Core 3.0 applications.
- I created a simple web application which UI displays info like the machine name and request headers. The application also exposes a REST API to collect the same information in JSON format.
- A self-hosted Azure DevOps agent is used to deploy the ASP.NET Core 3.0 to the Web Apps. A self-hosted agent is necessary in this case as the ILB App Service Environments and Web Apps do not expose public endpoints, hence Microsoft-hosted agent cannot be used to depoy the **Helloworld** test application to the Web Apps.
- Log Analytics is used to collect diagnostics logs and metrics from the Azure services (Application Gateway, App Service Environments, Key Vault, etc.)
- Application Insights is used to collect traces, metrics, requests and exceptions from the Web Apps. Each Web App uses a separate instance of Application Insights.
- Key Vault is used to store secrets such as the Application Insights instrumentation key and the self-signed certificate used by the Application Gateway to expose an HTTPS endpoint
- Bastion is used to connect to the Jumpbox VM and Agent VM
- The Jumpbox VM can be used to test the application by invoking the private endpoint exposed by the gateway
- The Application Gateway uses a Basic Rule to distribute requests across 3 web apps, each hosted in a separate zonal ILB App Service Environment.
- A rule in the Rewrite Set is used to set the location header of the response message to address the issue documented at [Rewrite HTTP headers with Azure Application Gateway](https://azure.microsoft.com/en-us/blog/rewrite-http-headers-with-azure-application-gateway/).
- Http Setting inherits host name from the backend. Likewise Health Probes, one for each web app, inherit host name from the Http Setting.
- Http Setting and Health probes are configured to use HTTPS on port 443.
- The Private Frontend is exposed via HTTPS and uses a certificate for SSL termination that is generated by the script.
- In the **kv-parameters.json** parameters file, make sure to substitute the placeholders with the objectId of the following user accounts: 
    - your user account on the Azure Active Directory tenant
    - the service principal used by your Azure DevOps organization to connect to your Azure subscription

# Deployment #
The deployment of the topology is fully automated via:

- ARM templates
- Bash script
- Azure DevOps CI/CD pipelines

Make sure to substitute the placeholders in the parameters files and in the **setup.bat** bash script, then run this script to deploy the sample in your Azure subscription.

# Testing #
VPN into the Jumpbox VM using Bastion or the public IP of the virtual machine, and use an internet browser to connect to the private endpoint exposed by the Application Gateway. If you refresh the page, you should see that requests are distributed across the 3 web Apps, each located in a separate zonal ILB App Service Environment.
<br/>
<br/>
![HelloWorld](https://raw.githubusercontent.com/paolosalvatori/multi-az-ase/master/images/helloworld.png)
<br/>
