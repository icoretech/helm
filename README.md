# iCoreTech Helm Charts Repository

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/icoretech)](https://artifacthub.io/packages/search?repo=icoretech)

Welcome to the iCoreTech Helm Charts repository! This repository hosts a collection of Helm charts for various applications and utilities to streamline your Kubernetes deployments.

## Available Charts

For detailed information on the individual charts and their usage, please navigate to the [charts](https://github.com/icoretech/helm/tree/main/charts) subdirectory.

- [Airbroke](https://icoretech.github.io/helm/charts/airbroke): A modern, React-based open-source error catcher web application.
- [PgBouncer](https://icoretech.github.io/helm/charts/pgbouncer): A lightweight connection pooler for PostgreSQL.
- [Next.js](https://icoretech.github.io/helm/charts/nextjs): Generic, no-database Helm chart for Next.js standalone apps.
- [MCP Server](https://icoretech.github.io/helm/charts/mcp-server): Generic runner for MCP servers (image, Node via npx, Python via uvx/pip).

## Deprecated Charts

- [ChatGPT Retrieval Plugin](https://icoretech.github.io/helm/charts/chatgpt-retrieval-plugin): DEPRECATED — This Helm chart is no longer maintained and will not be supported in the foreseeable future. Do not use it for new deployments.
- [Inngest Server](https://icoretech.github.io/helm/charts/inngest-server): DEPRECATED — This Helm chart is deprecated because an official Inngest Helm chart is available. Avoid new deployments and plan to migrate to the [official chart](https://github.com/inngest/inngest-helm.).

## Getting Started

To use the iCoreTech Helm charts, you can add the iCoreTech Helm repository to your local Helm setup:

```shell
helm repo add icoretech https://icoretech.github.io/helm
helm repo update
```

Once you have added the repository, you can browse and search for charts using the [Artifact Hub](https://artifacthub.io/packages/search?repo=icoretech) or the Helm CLI.

## Contributing

If you encounter any issues or have suggestions for improvements, please feel free to open an issue on the [GitHub repository](https://github.com/icoretech/helm). Contributions in the form of bug reports, feature requests, or pull requests are always welcome!

## License

The Helm charts in this repository are released under the MIT License. Please review the specific license for each chart in their respective subdirectories.

Happy Helm charting!
