#!/bin/bash

# Variables
prefixPlaceholder="{PREFIX-PLACEHOLDER}" 
resourceGroupName="${prefixPlaceholder}RG"
privateDnsZone="appserviceenvironment.net"
keyVaultName="${prefixPlaceholder}KeyVault"
serviceName="helloworld"
certificateFolder="./certificates"
deploy=1

# Certificate
certificateCn="www.contoso.com"
certificateCity="Milan"
certificateCountry="IT"
certificateOrganization="Contoso Ltd"
certificateOu="Cloud Departement"
certificatePassword="trustno1"

# Key Vault template
templateKv="../templates/kv-template.json"
parametersKv="../templates/kv-parameters.json"

# ASE template
templateAse="../templates/ase-template.json"
parametersAse="../templates/ase-parameters.json"

# Agent template
templateAgent="../templates/agent-template.json"
parametersAgent="../templates/agent-parameters.json"

# Application Gateway template
templateAppGw="../templates/appgw-template.json"
parametersAppGw="../templates/appgw-parameters.json"

location="WestEurope"

# SubscriptionId of the current subscription
subscriptionId=$(az account show --query id --output tsv)

# Check if the resource group already exists
createResourceGroup() {
    rg=$1

    echo "Checking if [$rg] resource group actually exists in the [$subscriptionId] subscription..."

    if ! az group show --name "$rg" &>/dev/null; then
        echo "No [$rg] resource group actually exists in the [$subscriptionId] subscription"
        echo "Creating [$rg] resource group in the [$subscriptionId] subscription..."

        # Create the resource group
        if az group create --name "$rg" --location "$location" 1>/dev/null; then
            echo "[$rg] resource group successfully created in the [$subscriptionId] subscription"
        else
            echo "Failed to create [$rg] resource group in the [$subscriptionId] subscription"
            exit 1
        fi
    else
        echo "[$rg] resource group already exists in the [$subscriptionId] subscription"
    fi
}

# Validate the ARM template
validateTemplate() {
    resourceGroup=$1
    template=$2
    parameters=$3
    arguments=$4

    echo "Validating [$template] ARM template..."

    if [[ -z $arguments ]]; then
        error=$(az group deployment validate \
            --resource-group "$resourceGroup" \
            --template-file "$template" \
            --parameters "$parameters" \
            --query error \
            --output json)
    else
        error=$(az group deployment validate \
            --resource-group "$resourceGroup" \
            --template-file "$template" \
            --parameters "$parameters" \
            --arguments $arguments \
            --query error \
            --output json)
    fi

    if [[ -z $error ]]; then
        echo "[$template] ARM template successfully validated"
    else
        echo "Failed to validate the [$template] ARM template"
        echo "$error"
        exit 1
    fi
}

# Deploy ARM template
deployTemplate() {
    resourceGroup=$1
    template=$2
    parameters=$3
    arguments=$4
    
    if [ $deploy != 1 ]; then
        return
    fi
    # Deploy the ARM template
    echo "Deploying ["$template"] ARM template..."

    if [[ -z $arguments ]]; then
        az group deployment create \
            --resource-group $resourceGroup \
            --template-file $template \
            --parameters $parameters  1>/dev/null
    else
        az group deployment create \
            --resource-group $resourceGroup \
            --template-file $template \
            --parameters $parameters \
            --parameters $arguments 1>/dev/null
    fi

    az group deployment create \
        --resource-group $resourceGroup \
        --template-file $template \
        --parameters $parameters  1>/dev/null

    if [[ $? == 0 ]]; then
        echo "["$template"] ARM template successfully provisioned"
    else
        echo "Failed to provision the ["$template"] ARM template"
        exit -1
    fi
}

# Create Resource Group
createResourceGroup "$resourceGroupName"

# Deploy Key Vault Template
deployTemplate \
    "$resourceGroupName" \
    "$templateKv" \
    "$parametersKv" \
    "keyVaultName=$keyVaultName location=$location"

# Deploy App Service Environment Template
deployTemplate \
    "$resourceGroupName" \
    "$templateAse" \
    "$parametersAse" \
    "privateDnsZoneName=$privateDnsZone location=$location"

# Get the list of ILB App Service Environments in the resource group
ases=$(az resource list --resource-group $resourceGroupName \
                 --resource-type Microsoft.Web/hostingEnvironments \
                 --query [].name --output tsv)

for ase in ${ases[@]}
do
    if [[ -z $ase ]]; then
        echo "No app service environment exists in the [$resourceGroupName] resource group"
    else
        # Get the internal IP address of the of ILB App Service Environment
        internalIpAddress=$(az resource show --name $ase/capacities/virtualip \
                 --resource-group $resourceGroupName \
                 --resource-type Microsoft.Web/hostingEnvironments/capacities \
                 --api-version 2019-08-01 \
                 --query internalIpAddress --output tsv)
        
        if [[ -z $internalIpAddress ]]; then
            echo "The [$ase] app service environment in the [$resourceGroupName] resource group has no internal ip address"
        else
            echo "The [$ase] app service environment in the [$resourceGroupName] resource group has [$internalIpAddress] internal ip address"
        fi

        # Retrieve the list of server farms / App Service Plans in the current ILB App Service Environment
        appServicePlans=$(az appservice plan list --resource-group $resourceGroupName \
                --query "[?@.hostingEnvironmentProfile.name == '$ase'].name" \
                --output tsv)
        
        for appServicePlan in ${appServicePlans[@]}
        do
            if [[ -z $appServicePlan ]]; then
                echo "The [$ase] app service environment in the [$resourceGroupName] resource group has no app service plan"
            else
                echo "The [$ase] app service environment in the [$resourceGroupName] resource group contains [$appServicePlan] app service plan"
            fi
        done

        # Retrieve the list of web apps in the current ILB App Service Environment
        webApps=$(az webapp list --resource-group $resourceGroupName \
                --query "[?@.hostingEnvironmentProfile.name == '$ase'].name" \
                --output tsv)
        
        for webApp in ${webApps[@]}
        do
            if [[ -z $webApp ]]; then
                echo "The [$ase] app service environment in the [$resourceGroupName] resource group has no web app"
            else
                echo "The [$ase] app service environment in the [$resourceGroupName] resource group contains [$webApp] web app"

                records=("$ase" "$webApp.$ase" "$webApp.scm.$ase")
                for record in ${records[@]}
                do
                    record=${record,,}

                    
                    az network private-dns record-set a show --name $record \
                                        --resource-group $resourceGroupName \
                                        --zone-name $privateDnsZone &>/dev/null

                    if [[ $? != 0 ]]; then
                        az network private-dns record-set a add-record \
                                        --ipv4-address $internalIpAddress \
                                        --record-set-name $record \
                                        --resource-group $resourceGroupName \
                                        --zone-name $privateDnsZone 1> /dev/null

                        if [[ $? == 0 ]]; then
                            echo "The [$record] record for [$internalIpAddress] ip address has been successfully created in the [$privateDnsZone] private dns zone"
                        else
                            echo "Failed to create the [$record] record for [$internalIpAddress] ip address in the [$privateDnsZone] private dns zone"
                        fi   
                    else
                        echo "The [$record] record for [$internalIpAddress] ip address already exists in the [$privateDnsZone] private dns zone"
                    fi                  
                done
            fi
        done
    fi
done

# Deploy the Azure DevOps Agent + Jumpbox VM Template
deployTemplate \
    "$resourceGroupName" \
    "$templateAgent" \
    "$parametersAgent" \
    "location=$location baseResourceGroup=$resourceGroupName"

# Create certificates folder
mkdir -p $certificateFolder

# Create CN for the certificate
cn="$serviceName.$privateDnsZone"
filename="$certificateFolder/$cn"

if [ -f "$filename.pfx" ]; then
    # The certificate already exists
    echo "[$filename.pfx] file already exists"
else
    # Create a self-signed certificate for the application gateway
    echo "Creating [$filename.crt] certificate for [CN=$cn]..."

    # Create PEM certificate
    openssl req \
        -x509 \
        -sha256 \
        -nodes \
        -days 3650 \
        -newkey rsa:2048 \
        -keyout "$filename.key" \
        -out "$filename.crt" \
        -passout pass:$certificatePassword \
        -subj "/C=$certificateCountry/ST=$certificateCity/L=$certificateCity/O=$certificateOrganization/OU=$certificateOu/CN=$cn"

    # Convert PEM to PFX
    echo "Creating [$filename.pfx] certificate for [CN=$cn]..."
    openssl pkcs12 -export \
        -in "$filename.crt" \
        -inkey "$filename.key" \
        -passin pass:$certificatePassword \
        -out "$filename.pfx" \
        -passout pass:$certificatePassword

fi

# Create secret name from cn using Camel format
certificateSecretName="${prefixPlaceholder}ApplicationGatewayCertificate"
passwordSecretName="${prefixPlaceholder}ApplicationGatewayPassword"

echo "Checking if [$certificateSecretName] secret already exists in [$keyVaultName] key vault..."

az keyvault secret show \
    --name $certificateSecretName \
    --vault-name $keyVaultName &>/dev/null

if [[ $? == 0 ]]; then
    echo "[$certificateSecretName] secret already exists in [$keyVaultName] key vault"
else
    echo "Creating [$certificateSecretName] secret in [$keyVaultName] key vault..."

    # Store the certificate as a secret into Key Vault
    az keyvault secret set \
        --vault-name $keyVaultName \
        --name $certificateSecretName \
        --encoding base64 \
        --description text/plain \
        --file "$filename.pfx"

    if [[ $? == 0 ]]; then
        echo "[$certificateSecretName] secret successfully created in [$keyVaultName] key vault"
    else
        echo "Failed to create [$certificateSecretName] secret in [$keyVaultName] key vault"
    fi
fi 

az keyvault secret show \
    --name $passwordSecretName \
    --vault-name $keyVaultName &>/dev/null

if [[ $? == 0 ]]; then
    echo "[$passwordSecretName] secret already exists in [$keyVaultName] key vault"
else
    echo "Creating [$passwordSecretName] secret in [$keyVaultName] key vault..."

    # Store the certificate as a secret into Key Vault
    az keyvault secret set \
        --vault-name $keyVaultName \
        --name $passwordSecretName \
        --value $certificatePassword

    if [[ $? == 0 ]]; then
        echo "[$passwordSecretName] secret successfully created in [$keyVaultName] key vault"
    else
        echo "Failed to create [$passwordSecretName] secret in [$keyVaultName] key vault"
    fi
fi 

# Deploy the Application Gateway Template
deployTemplate \
    "$resourceGroupName" \
    "$templateAppGw" \
    "$parametersAppGw" \
    "location=$location baseResourceGroup=$resourceGroupName"

# Get the list of Application Gateways in the resource group
appgws=$(az network application-gateway list --resource-group $resourceGroupName \
                                             --query [].name --output tsv)

for appgw in ${appgws[@]}
do
    if [[ -z $appgw ]]; then
        echo "No application gateway exists in the [$resourceGroupName] resource group"
    else
        echo "The [$appgw] application gateway exists in the [$resourceGroupName] resource group"

        # Get the internal IP address of the of ILB App Service Environment
        internalIpAddress=$(az network application-gateway show \
                                                --name $appgw \
                                                --resource-group $resourceGroupName \
                                                --query "@.frontendIpConfigurations[?privateIpAddress != null].privateIpAddress" \
                                                --output tsv)
        
        if [[ -z $internalIpAddress ]]; then
            echo "The [$appgw] application gateway in the [$resourceGroupName] resource group has no internal ip address"
        else
            echo "The [$appgw] application gateway in the [$resourceGroupName] resource group has [$internalIpAddress] internal ip address"
            
            record=$serviceName
            az network private-dns record-set a show --name $record \
                                            --resource-group $resourceGroupName \
                                            --zone-name $privateDnsZone &>/dev/null

            if [[ $? != 0 ]]; then
                az network private-dns record-set a add-record \
                                --ipv4-address $internalIpAddress \
                                --record-set-name $record \
                                --resource-group $resourceGroupName \
                                --zone-name $privateDnsZone 1> /dev/null

                if [[ $? == 0 ]]; then
                    echo "The [$record] record for [$internalIpAddress] ip address has been successfully created in the [$privateDnsZone] private dns zone"
                else
                    echo "Failed to create the [$record] record for [$internalIpAddress] ip address in the [$privateDnsZone] private dns zone"
                fi   
            fi
        fi
    fi
done