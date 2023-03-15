### App registration Process

Flow 1 of the script is an app registration process. With this app you can later retrieve the necessary data.

In this function:

**1. A local environment configuration will run**  

It will install 2 modules:

  - Microsoft.Graph.Authentication
    - To get an access token, your app must be registered with the Microsoft identity platform and be granted Microsoft Graph permissions by a user or administrator. ([More details](https://learn.microsoft.com/en-us/graph/auth/auth-concepts))
  - Microsoft.Graph.Application
    - Represents an application. Any application that outsources authentication to Azure Active Directory (Azure AD) must be registered in a directory. Application registration involves telling Azure AD about your application, including the URL where it's located, the URL to send replies after authentication, the URI to identify your application, and more. ([More details](https://learn.microsoft.com/en-us/graph/api/resources/application?view=graph-rest-1.0))

**2. An Azure graph connection will be set up**

- The connection that will be made is configured with Read & Write access on the applications in the tenant you provided in order to create the application.

**3. An application will be created**

- It will create an application called "DexMach CSP Secure Score dashboard", it also checks if it exists already, with access to Microsoft Azure Management and Microsoft Partner API's.

4. At the end of this part an app will be created that can be used in the data retrieval flow, in order to do so please create an application secret in the Azure Portal and consent to the API permissions. For more information on how to do this [see](https://learn.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal#option-2-create-a-new-application-secret).
