// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// OpenZeppelin imports
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {PendleRolesPlugin} from "./../../../core/roles/PendleRoles.sol";
import {Err} from "./../../../lib/Errors.sol";
import {IAuthModule} from "./../../../interfaces/IAuthModule.sol";
import {IAMMModule} from "./../../../interfaces/IAMMModule.sol";
import {ITradeModule} from "./../../../interfaces/ITradeModule.sol";
import {Account, AccountLib} from "./../../../types/Account.sol";
import {RouterAccountBase} from "./../auth-base/RouterAccountBase.sol";
import {AuthBase} from "./../auth-base/AuthBase.sol";

// * Functions in here are callable only by Pendle's relayer, except for approveAgent and revokeAgent,
//   which have variants that can be called by accManager.
contract AuthModule is IAuthModule, AuthBase, RouterAccountBase, PendleRolesPlugin {
    using Address for address;
    using AccountLib for address;

    constructor(address permissionController_) PendleRolesPlugin(permissionController_) {}

    // * Reason why functions below have their dedicated structs is because those structs are meant to be signed directly by user,
    //      hence it needs to be readable
    // * SetAuth(message.root.toMain()) is so that the account is set correctly once authentication passed &
    //      function call is relayed to the AMMModule or TradeModule
    function vaultDeposit(
        VaultDepositMessage memory message,
        bytes memory signature
    ) external onlyRelayer setAuth(message.root.toMain()) {
        _verifySignerSigAndIncreaseNonce(message.root, message.nonce, _hashVaultDepositMessage(message), signature);

        address(this).functionDelegateCall(
            abi.encodeCall(
                ITradeModule.vaultDeposit,
                (message.accountId, message.tokenId, message.marketId, message.amount)
            )
        );
    }

    function vaultPayTreasury(
        VaultPayTreasuryMessage memory message,
        bytes memory signature
    ) external onlyRelayer setAuth(message.root.toMain()) {
        _verifySignerSigAndIncreaseNonce(message.root, message.nonce, _hashVaultPayTreasuryMessage(message), signature);

        address(this).functionDelegateCall(
            abi.encodeCall(ITradeModule.vaultPayTreasury, (message.tokenId, message.amount))
        );
    }

    function requestVaultWithdrawal(
        RequestVaultWithdrawalMessage memory message,
        bytes memory signature
    ) external onlyRelayer setAuth(message.root.toMain()) {
        _verifySignerSigAndIncreaseNonce(
            message.root,
            message.nonce,
            _hashRequestVaultWithdrawalMessage(message),
            signature
        );

        address(this).functionDelegateCall(
            abi.encodeCall(ITradeModule.requestVaultWithdrawal, (message.tokenId, message.amount))
        );
    }

    function cancelVaultWithdrawal(
        CancelVaultWithdrawalMessage memory message,
        bytes memory signature
    ) external onlyRelayer setAuth(message.root.toMain()) {
        _verifySignerSigAndIncreaseNonce(
            message.root,
            message.nonce,
            _hashCancelVaultWithdrawalMessage(message),
            signature
        );

        address(this).functionDelegateCall(abi.encodeCall(ITradeModule.cancelVaultWithdrawal, (message.tokenId)));
    }

    function subaccountTransfer(
        SubaccountTransferMessage memory message,
        bytes memory signature
    ) external onlyRelayer setAuth(message.root.toMain()) {
        _verifySignerSigAndIncreaseNonce(
            message.root,
            message.nonce,
            _hashSubaccountTransferMessage(message),
            signature
        );

        address(this).functionDelegateCall(
            abi.encodeCall(
                ITradeModule.subaccountTransfer,
                (message.accountId, message.tokenId, message.marketId, message.amount, message.isDeposit)
            )
        );
    }

    // * No setAuth is needed since this function doesn't delegate call
    function setAccManager(SetAccManagerMessage memory message, bytes memory signature) external onlyRelayer {
        _verifySignerSigAndIncreaseNonce(message.root, message.nonce, _hashSetAccManagerMessage(message), signature);

        Account account = AccountLib.from(message.root, message.accountId);
        _setAccManager(account, message.accManager);
    }

    // * No setAuth is needed since this function doesn't delegate call
    function approveAgent(ApproveAgentMessage memory message, bytes memory signature) external onlyRelayer {
        Account account = AccountLib.from(message.root, message.accountId);
        address accManager = accountManager(account);

        _verifySignerSigAndIncreaseNonce(accManager, message.nonce, _hashApproveAgentMessage(message), signature);

        _approveAgentAndSyncAMMAcc(account, message.agent, message.expiry);
    }

    // * No setAuth is needed since this function doesn't delegate call
    function revokeAgent(RevokeAgentsMessage memory message, bytes memory signature) external onlyRelayer {
        Account account = AccountLib.from(message.root, message.accountId);
        address accManager = accountManager(account);

        _verifySignerSigAndIncreaseNonce(accManager, message.nonce, _hashRevokeAgentsMessage(message), signature);

        for (uint256 i = 0; i < message.agents.length; i++) {
            _revokeAgentAndSyncAMMAcc(account, message.agents[i]);
        }
    }

    // ------------------------------------------------------------
    // ---------------- DIRECT CALL BY ACC MANAGER ----------------
    // ------------------------------------------------------------

    // * No setAuth is needed since this function doesn't delegate call
    function approveAgent(ApproveAgentReq memory req) external {
        Account account = AccountLib.from(req.root, req.accountId);
        address accManager = accountManager(account);

        require(msg.sender == accManager, Err.Unauthorized());

        _approveAgentAndSyncAMMAcc(account, req.agent, req.expiry);
    }

    // * No setAuth is needed since this function doesn't delegate call
    function revokeAgent(RevokeAgentsReq memory req) external {
        Account account = AccountLib.from(req.root, req.accountId);
        address accManager = accountManager(account);

        require(msg.sender == accManager, Err.Unauthorized());

        for (uint256 i = 0; i < req.agents.length; i++) {
            _revokeAgentAndSyncAMMAcc(account, req.agents[i]);
        }
    }

    function _setAccManager(Account acc, address accManager) internal {
        _AMS().accManager[acc] = accManager;
        emit NewAccManagerSet(acc, accManager);
    }

    function _approveAgent(Account acc, address agent, uint64 expiry) internal {
        require(expiry > block.timestamp, Err.AuthExpiryInPast());
        _AMS().agentExpiry[acc][agent] = expiry;
        emit AgentApproved(acc, agent, expiry);
    }

    function _revokeAgent(Account acc, address agent) internal {
        delete _AMS().agentExpiry[acc][agent];
        emit AgentRevoked(acc, agent);
    }

    function _approveAgentAndSyncAMMAcc(Account acc, address agent, uint64 expiry) internal {
        _approveAgent(acc, agent, expiry);
        if (acc.isMain()) {
            Account accAmm = acc.root().toAMM();
            _approveAgent(accAmm, agent, expiry);
        }
    }

    function _revokeAgentAndSyncAMMAcc(Account acc, address agent) internal {
        _revokeAgent(acc, agent);
        if (acc.isMain()) {
            Account accAmm = acc.root().toAMM();
            _revokeAgent(accAmm, agent);
        }
    }

    // ------------------------------------------------------------
    // ----------------------- AGENT EXECUTE ----------------------
    // ------------------------------------------------------------

    // * All agent-signed txs run through here. Agent will sign the message containing the message payload
    //      Of course we don't let agent sign everything, only the ones that is non-destructive (i.e no fund transfer)
    function agentExecute(
        address agent,
        PendleSignTx memory message,
        bytes memory signature,
        bytes memory callData
    ) external onlyRelayer setAuth(message.account) {
        _verifyAgentSigAndIncreaseNonce(agent, message, signature, keccak256(callData));

        _checkAgentAllowedToCall(callData);
        address(this).functionDelegateCall(callData);
    }

    function _checkAgentAllowedToCall(bytes memory callData) internal pure {
        bytes4 selector = bytes4(callData);
        require(
            selector == ITradeModule.cashTransfer.selector ||
                selector == ITradeModule.ammCashTransfer.selector ||
                selector == ITradeModule.payTreasury.selector ||
                selector == ITradeModule.placeSingleOrder.selector ||
                selector == ITradeModule.bulkOrders.selector ||
                selector == ITradeModule.bulkCancels.selector ||
                selector == ITradeModule.enterExitMarkets.selector ||
                //
                selector == IAMMModule.swapWithAmm.selector ||
                selector == IAMMModule.addLiquidityDualToAmm.selector ||
                selector == IAMMModule.addLiquiditySingleCashToAmm.selector ||
                selector == IAMMModule.removeLiquidityDualFromAmm.selector ||
                selector == IAMMModule.removeLiquiditySingleCashFromAmm.selector,
            Err.AuthSelectorNotAllowed()
        );
    }

    // ------------------------------------------------------------
    // ------------------------- MISC VIEW ------------------------
    // ------------------------------------------------------------

    function agentExpiry(Account acc, address agent) external view returns (uint256 expiry) {
        return _AMS().agentExpiry[acc][agent];
    }

    function signerNonce(address signer) external view returns (uint64) {
        return _AMS().signerNonce[signer];
    }

    function accountManager(Account acc) public view returns (address) {
        address accManager = _AMS().accManager[acc];
        if (accManager == address(0)) {
            accManager = acc.root();
        }
        return accManager;
    }

    // ------------------------------------------------------------
    // --------------------------- ADMIN --------------------------
    // ------------------------------------------------------------

    function systemRevokeAgent(Account[] memory accounts, address[] memory agents) external onlyAuthorized {
        require(accounts.length == agents.length, Err.InvalidLength());

        for (uint256 i = 0; i < accounts.length; i++) {
            _revokeAgent(accounts[i], agents[i]);
        }
    }
}
