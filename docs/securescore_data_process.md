### Secure Score Data Process

The second part of the script is the Secure Score Data Process.

In this function:

**1. A local environment configuration will run, installing 1 module:**  

- [Partner Center](https://learn.microsoft.com/en-us/partner-center/overview)
  - [Partner Center](https://partner.microsoft.com/dashboard/home) streamlines several business processes to make it easier for Microsoft partners to manage their relationship with Microsoft and their customers. Partner Center gives you access to the tools you need to get work done.

**2. Initializing process variables:**  

  It will ask your application details as configured in step one of the script. Make sure that you've consented the created API permissions for use.

**3. Partner Center connection:**

  An interactive window will pop up and you will be requested to log in. Do so with an account that has the required access on partner center as described in the requirements. The token retrieved from this process can now be used to authenticate to the Partner Center API and to fetch additional tokens for other Microsoft services like ARM. 

**4. Deploy SPN to partner customers:**

  Via the Partner Center app consent api, we can indicate that we want to deploy our SPN to a customer tenant with a specific set of permissions (Azure RM on behalf of the Partner Center user we used to get the tokens in the first place). So this is what happens, it will go through the list of customers and consent the SPN.

**5. Retrieving Azure information:**

  In this step it will retrieve all the Azure secure score information from every customer's subscription.

**6.  Output:**

  In this step the data that has been retrieved will be written to several JSON files ready for data upload and visualization.
