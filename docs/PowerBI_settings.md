# Power BI Tenant Settings
## Prequisites
* A PowerBI Environment
* User with Power BI admin privileges. ([Docs](https://learn.microsoft.com/en-us/power-bi/admin/service-admin-role))

Since the current version of the Dexmach Azure Secure Score app is still in preproduction, it is not live on the Appsource yet.  
By default this settings is enabled but from a security perspective it's not best practice to leave this enabled.  
To enable the installation of Apps not listed on Appsource the following setting needs to be enabled in your PowerBI environment:  
Install template apps not listed in AppSource.

To enable this setttings, go to the [Power BI Admin Portal](https://app.powerbi.com/admin-portal/tenantSettings) and scroll down to the Template App Settings section.  

![template_app_settings](img/template_app_settings.png)

You can pick if you want to enable it for the entire organization or specific security groups. After the installation of the app has been completed the setting can be disabled again.