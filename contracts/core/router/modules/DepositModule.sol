// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IDepositModule} from "../../../interfaces/IDepositModule.sol";
import {IMarketHub} from "../../../interfaces/IMarketHub.sol";
import {ApprovedCall, IPDepositBox} from "../../../interfaces/IPDepositBox.sol";
import {IPDepositBoxFactory} from "../../../interfaces/IPDepositBoxFactory.sol";
import {Err} from "../../../lib/Errors.sol";
import {TokenHelper} from "../../../lib/TokenHelper.sol";
import {PMath} from "../../../lib/math/PMath.sol";
import {MarketAcc, AccountLib} from "../../../types/Account.sol";
import {AuthBase} from "../auth-base/AuthBase.sol";

contract DepositModule is IDepositModule, AuthBase, TokenHelper {
    IMarketHub internal immutable _MARKET_HUB;

    IPDepositBoxFactory public immutable DEPOSIT_BOX_FACTORY;

    constructor(address marketHub_, address depositBoxFactory_) {
        _MARKET_HUB = IMarketHub(marketHub_);
        DEPOSIT_BOX_FACTORY = IPDepositBoxFactory(depositBoxFactory_);
    }

    /// @dev must not use setAuth/setNonAuth because this function handles execution to user-specified swap router
    function depositFromBox(DepositFromBoxMessage memory message, bytes memory signature) external onlyRelayer {
        _verifyIntentSigAndMarkExecuted(message.root, message.expiry, _hashDepositFromBoxMessage(message), signature);

        (uint256 actualSpent, uint256 netTokenReceived) = _swapForDeposit(message);

        uint256 payTreasuryAmount = message.payTreasuryAmount;
        uint256 depositAmount = netTokenReceived - payTreasuryAmount;
        require(depositAmount >= message.minDepositAmount, Err.InsufficientDepositAmount());

        if (depositAmount > 0) {
            MarketAcc acc = AccountLib.from(message.root, message.accountId, message.tokenId, message.marketId);
            _MARKET_HUB.vaultDeposit(acc, depositAmount);
        }

        if (payTreasuryAmount > 0) {
            _MARKET_HUB.vaultPayTreasury(message.root, message.tokenId, payTreasuryAmount);
        }

        emit DepositFromBox(
            message.root,
            message.boxId,
            message.tokenSpent,
            actualSpent,
            message.accountId,
            message.tokenId,
            message.marketId,
            depositAmount,
            payTreasuryAmount
        );
    }

    /// @dev no setAuth because this function does not delegate call
    function withdrawFromBox(WithdrawFromBoxMessage memory message, bytes memory signature) external onlyRelayer {
        _verifyIntentSigAndMarkExecuted(message.root, message.expiry, _hashWithdrawFromBoxMessage(message), signature);

        IPDepositBox box = DEPOSIT_BOX_FACTORY.deployDepositBox(message.root, message.boxId);
        box.withdrawTo(message.root, message.token, message.amount);

        emit WithdrawFromBox(message.root, message.boxId, message.token, message.amount);
    }

    function _swapForDeposit(
        DepositFromBoxMessage memory message
    ) internal returns (uint256 actualSpent, uint256 netTokenReceived) {
        IPDepositBox box = DEPOSIT_BOX_FACTORY.deployDepositBox(message.root, message.boxId);
        address tokenReceived = _MARKET_HUB.tokenIdToAddress(message.tokenId);

        actualSpent = PMath.min(message.maxAmountSpent, _balanceOf(address(box), message.tokenSpent));

        if (tokenReceived == message.tokenSpent) {
            box.withdrawTo(address(this), message.tokenSpent, actualSpent);
            netTokenReceived = actualSpent;
        } else {
            ApprovedCall memory call = ApprovedCall({
                token: message.tokenSpent,
                amount: actualSpent,
                approveTo: message.swapApprove,
                callTo: message.swapExtRouter,
                data: message.swapCalldata
            });

            uint256 preBalance = _selfBalance(tokenReceived);
            box.approveAndCall(call, address(box));
            netTokenReceived = _selfBalance(tokenReceived) - preBalance;
        }
    }
}
