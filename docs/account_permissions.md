## Account Permissions

### Partner Center User

- The user running the extraction must be a member of the CSP partner tenant, and have the 'Admin Agent' role assigned in the Partner Center.
- CSP Customers must have an Azure subscription, and be enabled for 'Delegated Administration' by the CSP partner. If this is not the case for a specific customer, that customer will not have their secure score retrieved. ([More details](DelegatedAdmin.md))
- How to give the permissions to the user in Partner Center ([More details](CSP_User_Permissions.md))

### Mission 65 service principal

Used for brokering access between the user and the different interfaces, API permissions must be consented in the CSP partner tenant after creation.
- Providing consent can be done by an Azure AD Global admin or Application Administrator.
- Creation of the service principal is recommended to be done through choosing Flow 1 of the PowerShell script in this repository.

### Solution specifications

Both the CSP partner and the Customer tenant conditional access policies and/or token policies must allow the authentication by refresh_token from the location where the script is being run.

The device running the script must have PowerShell 7 or higher. For installation instructions see [the Microsoft documentation](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-7.3).

The device running the script must be able to access the following web locations
- [ ] https://login.microsoftonline.com
- [ ] https://managment.azure.com
- [ ] https://api.partnercenter.microsoft.com

### Power BI
For visualizing the solution, the following requirements have to be met:
 * The user must have PowerBI Environment
 * The user must have a Power BI Pro or Premium license.
