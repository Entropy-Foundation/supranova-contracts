# SupraNova Smart Contracts

> [!IMPORTANT]
> **Note:** The smart contracts in this repository are **outdated** and do not represent the latest SupraNova smart contracts. The source code for the latest SupraNova smart contracts is currently not publicly available and will be released soon.
>
> Bug bounty submissions based on vulnerabilities in these outdated contracts will **not be considered valid**.

A cross-chain communication framework enabling secure asset and message transfer across blockchains.

## Overview

SupraNova is a cross-chain communication framework developed by Supra that enables the transfer of assets and messages across blockchains by integrating multiple bridging technologies under a unified architecture.

## Architecture

SupraNova supports two complementary bridging technologies:

### HyperNova
A trustless bridge protocol that uses the source chain's consensus layer for event verification using validator signatures. Ideal for trust-minimized bridging where security is paramount.

**Whitepaper:** [Supra HyperNova](https://supra.com/documents/Supra-HyperNova-Whitepaper.pdf)

### Hyperloop
A fast, multi-signature based game-theoretically secure bridge designed for source chains where HyperNova-style trustless bridging is not applicable, feasible, or results in high latency (particularly for Layer 2 chains).

**Whitepaper:** [Supra Hyperloop](https://supra.com/documents/Supra-Hyperloop-Whitepaper.pdf)

## Current Features

- Cross-chain asset transfer from Ethereum to Supra
- Multi-protocol bridging support (HyperNova)
- Unified architecture for different bridge technologies
- Trust-minimized and high-speed bridging capabilities

## Roadmap

Future versions of SupraNova will support:

- Reverse bridging from Supra to Ethereum
- Asset entry from other EVM chains
- Application-level services and integrations built on validated cross-chain messages

These expansions are made possible without changing the underlying message validation logic powered by HyperNova Core.

## Documentation

For detailed documentation, visit: [https://docs.supra.com/supranova](https://docs.supra.com/supranova)


## License

This project is licensed under the **Business Source License 1.1 (BUSL-1.1)**.

- **Non-production use** (evaluation, research, education, security auditing) is permitted under BUSL-1.1.
- **Production use** (including offering as a service) requires a commercial license from Supra Labs **until the Change Date**.
- **Change Date:** 2028-01-01 — on or after this date, this version of the code will be available under **MIT**.