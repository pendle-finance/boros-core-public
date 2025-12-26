// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IRouterEventsAndTypes} from "./IRouterEventsAndTypes.sol";
import {Account} from "./../types/Account.sol";

interface IAuthModule is IRouterEventsAndTypes {
    function vaultDeposit(VaultDepositMessage memory message, bytes memory signature) external;

    function vaultPayTreasury(VaultPayTreasuryMessage memory message, bytes memory signature) external;

    function requestVaultWithdrawal(RequestVaultWithdrawalMessage memory message, bytes memory signature) external;

    function cancelVaultWithdrawal(CancelVaultWithdrawalMessage memory message, bytes memory signature) external;

    function subaccountTransfer(SubaccountTransferMessage memory message, bytes memory signature) external;

    function setAccManager(SetAccManagerMessage memory data, bytes memory signature) external;

    function approveAgent(ApproveAgentMessage memory data, bytes memory signature) external;

    function revokeAgent(RevokeAgentsMessage memory data, bytes memory signature) external;

    function approveAgent(ApproveAgentReq memory req) external;

    function revokeAgent(RevokeAgentsReq memory req) external;

    function systemRevokeAgent(Account[] memory accounts, address[] memory agents) external;

    function agentExecute(
        address agent,
        PendleSignTx memory message,
        bytes memory signature,
        bytes memory callData
    ) external;

    function agentExpiry(Account acc, address agent) external view returns (uint256);

    function signerNonce(address signer) external view returns (uint64);

    function isIntentExecuted(bytes32 intentHash) external view returns (bool);

    function accountManager(Account acc) external view returns (address);
}
