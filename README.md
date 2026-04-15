<p align="center">
  <img src="Images/bp_logo.png" alt="Bestillingsportalen logo" width="80" />
  <br />
  <strong style="font-size: 2em;">Bestillingsportalen</strong>
</p>

| [Deployment guide](/Deployment-guide.md) | [Upgrade Guide](/Upgrade.md) | [Architecture](/Architecture.md) | [Data Stores](/Data-stores.md) | [Cost Estimates](/Cost-estimates.md) | [Data Access & Security](/Data-access-security.md) | [Naming Conventions](/Naming-conventions.md) | [Business Units](/Business-units.md) | [Provisioning Types](/Provisioning-types.md) | [Site Templates](/Site-templates.md) | [Sensitivity Labels](/Sensitivity-labels.md) | [Teams Templates](/Teams-templates.md) | [PnP Templates](/PnP-templates.md) | [Retention Labels](/Retention-labels.md) | [Approval Flow](/Approval-flow.md) | [Regional Settings](/Regional-settings.md) | [Refreshing App Secret](/Refreshing-app-secret.md) | [Error Handling](/Error-handling.md) |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |

Bestillingsportalen is an Azure based solution that provides an alternative to self-service creation in Microsoft 365. It provides governance over this process through an SPFx Teams app allowing users to request Collaboration 'Spaces' (Teams, Groups, SharePoint Online Sites & Viva Engage Communities) and backend Azure components providing automated provisioning. Bestillingsportalen can be used as part of a Copilot for Microsoft 365 deployment in order to establish a layer of governance over self-service.

![Bestillingsportalen](/Images/bp_app.png)

## Capabilities

Bestillingsportalen provides the following capabilities:

- SPFx based Bestillingsportalen webdel and Teams app allowing users to request collaboration spaces.
- Configurable approval process using Power Automate to facilitate the approval of requests.
- SharePoint site and supporting lists which act as the backend for the solution.
- Requestor dashboard showing past and current requests with the approval status.
- Automated provisioning using Azure Logic Apps and Azure Automation.
  
## Architecture

The solution uses the Microsoft Graph and the SharePoint REST APIs for provisioning. Azure Runbooks are used with PnP PowerShell for tasks that cannot be completed using the Graph API. 

Application permissions are used through an Entra ID app registration, the secret for the Entra ID app is stored in a key vault.

Provisioning and other automation tasks in the solution is achieved through Azure Logic apps, ensuring a low runtime cost and the ability to secure access to all resources.

For more details on the architecture please read the [Architecture](Architecture.md) documentation.

## Getting Started

To get started with a new installation, please follow the [Deployment guide](Deployment-guide.md).

## Upgrading

If you have an existing Bestillingsportalen installation and want to upgrade to the latest version, see the [Upgrade Guide](Upgrade.md) for detailed instructions on how to upgrade without losing your data. 

## Issues

Please report any issues by raising an [issue](https://github.com/Puzzlepart/bestillingsportalen/issues/new/choose).

## Contributing

We 💖 to accept contributions.

Check out our [Contribution guidelines](/CONTRIBUTING.md) for guidance on how to contribute. 

If you want to get involved with helping us enhance Bestillingsportalen, whether that is suggesting or adding new functionality, updating our documentation or fixing bugs, we would love to hear from you.

## Special Thanks

Special thanks to those below who have helped build this awesome solution.

- [@alexc-MSFT](https://github.com/alexc-MSFT)
- [@OlgKis](https://www.github.com/OlgKis)
- [@PalinaSolik](https://www.github.com/PalinaSolik)

## Support

This solution is open-source and community provided with no active community providing support for it. This solution is maintained by both Microsoft employees and community contributors and is not a Microsoft provided solution so there is no SLA or direct support for this from Microsoft. Please report any issues by raising an [issue](https://github.com/Puzzlepart/bestillingsportalen/issues/new/choose).

## Microsoft 365 & Power Platform Community

Bestillingsportalen is a Microsoft 365 & Power Platform Community (PnP) project. Microsoft 365 & Power Platform Community is a virtual team consisting of Microsoft employees and community members focused on helping the community make the best use of Microsoft products. Bestillingsportalen is an open-source project not affiliated with Microsoft and not covered by Microsoft support. If you experience any issues using Bestillingsportalen, please submit an issue in the [issues list](https://github.com/Puzzlepart/bestillingsportalen/issues).

## "Sharing is Caring"

![Parker PnP](/Images/parker-pnp.png)

## Disclaimer

**THIS CODE IS PROVIDED AS IS WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING ANY IMPLIED WARRANTIES OF FITNESS FOR A PARTICULAR PURPOSE, MERCHANTABILITY, OR NON-INFRINGEMENT.**

## Code of Conduct

This repository has adopted the Microsoft Open Source Code of Conduct. For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact opencode@microsoft.com with any additional questions or comments.
