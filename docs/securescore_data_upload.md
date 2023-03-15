## Secure Score Data Upload

The third part of the script is the Secure Score Data Process.

In this function:

1. A local environment configuration will run

    It will install 3 modules:

- Az.Accounts
  - Manages credentials and common configuration for all Azure modules.
  - More info [here](https://learn.microsoft.com/en-us/powershell/module/az.accounts/?view=azps-9.3.0)
- Az.Storage
  - Manage Azure Cloud Storage resources.
  - More info [here](https://learn.microsoft.com/en-us/cli/azure/storage?view=azure-cli-latest)
- Az.Resources
  - Manage Azure resources.
  - More info [here](https://learn.microsoft.com/en-us/cli/azure/resource?view=azure-cli-latest)

2. Azure connection

- In this step a connection will be made to your Azure tenant and subscription where you want to upload the files

3. Upload

- Here you will be able to choose if you want upload the data to an already existing storage account or if you want to make a complete new one. 
  - If you choose for a new one, a Resource Group, Storage Account and a Data Folder will be created. All the files uploaded to this Data Folder will be used for visualization.

4. Finish

- If everything went well all the data that was gathered will now be uploaded to the selected or new Storage Account and will be ready for visualization.
