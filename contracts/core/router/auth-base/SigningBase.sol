// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {EIP712Essential} from "./EIP712.sol";
import {IRouterEventsAndTypes} from "./../../../interfaces/IRouterEventsAndTypes.sol";
import {MarketId, TokenId} from "./../../../types/MarketTypes.sol";

abstract contract SigningBase is IRouterEventsAndTypes, EIP712Essential {
    // prettier-ignore
    bytes32 internal constant _VAULT_DEPOSIT_MESSAGE = keccak256(
        "VaultDepositMessage("
            "address root,"
            "uint8 accountId,"
            "uint16 tokenId,"
            "uint24 marketId,"
            "uint256 amount,"
            "uint64 nonce"
        ")"
    );

    // prettier-ignore
    bytes32 internal constant _VAULT_PAY_TREASURY_MESSAGE = keccak256(
        "VaultPayTreasuryMessage("
            "address root,"
            "uint16 tokenId,"
            "uint256 amount,"
            "uint64 nonce"
        ")"
    );

    // prettier-ignore
    bytes32 internal constant _REQUEST_VAULT_WITHDRAWAL_MESSAGE = keccak256(
        "RequestVaultWithdrawalMessage("
            "address root,"
            "uint16 tokenId,"
            "uint256 amount,"
            "uint64 nonce"
        ")"
    );

    // prettier-ignore
    bytes32 internal constant _CANCEL_VAULT_WITHDRAWAL_MESSAGE = keccak256(
        "CancelVaultWithdrawalMessage("
            "address root,"
            "uint16 tokenId,"
            "uint64 nonce"
        ")"
    );

    // prettier-ignore
    bytes32 internal constant _SUBACCOUNT_TRANSFER_MESSAGE = keccak256(
        "SubaccountTransferMessage("
            "address root,"
            "uint8 accountId,"
            "uint16 tokenId,"
            "uint24 marketId,"
            "uint256 amount,"
            "bool isDeposit,"
            "uint64 nonce"
        ")"
    );

    // prettier-ignore
    bytes32 internal constant _SET_ACC_MANAGER_MESSAGE = keccak256(
        "SetAccManagerMessage("
            "address root,"
            "uint8 accountId,"
            "address accManager,"
            "uint64 nonce"
        ")"
    );

    // prettier-ignore
    bytes32 internal constant _APPROVE_AGENT_MESSAGE = keccak256(
        "ApproveAgentMessage("
            "address root,"
            "uint8 accountId,"
            "address agent,"
            "uint64 expiry,"
            "uint64 nonce"
        ")"
    );

    // prettier-ignore
    bytes32 internal constant _REVOKE_AGENTS_MESSAGE = keccak256(
        "RevokeAgentsMessage("
            "address root,"
            "uint8 accountId,"
            "address[] agents,"
            "uint64 nonce"
        ")"
    );

    // prettier-ignore
    bytes32 internal constant _PENDLE_SIGN_TX = keccak256(
        "PendleSignTx("
            "bytes21 account,"
            "bytes32 connectionId,"
            "uint64 nonce"
        ")"
    );

    // prettier-ignore
    bytes32 internal constant _PLACE_CONDITIONAL_ACTION_MESSAGE = keccak256(
        "PlaceConditionalActionMessage("
            "bytes32 actionHash"
        ")"
    );

    // prettier-ignore
    bytes32 internal constant _EXECUTE_CONDITIONAL_ORDER_MESSAGE = keccak256(
        "ExecuteConditionalOrderMessage("
            "bytes32 orderHash,"
            "bytes execParams,"
            "uint64 expiry"
        ")"
    );

    // prettier-ignore
    bytes32 internal constant _DEPOSIT_FROM_BOX_MESSAGE = keccak256(
        "DepositFromBoxMessage("
            "address root,"
            "uint32 boxId,"
            "address tokenSpent,"
            "uint256 maxAmountSpent,"
            //
            "uint8 accountId,"
            "uint16 tokenId,"
            "uint24 marketId,"
            "uint256 minDepositAmount,"
            "uint256 payTreasuryAmount,"
            //
            "address swapExtRouter,"
            "address swapApprove,"
            "bytes swapCalldata,"
            //
            "uint64 expiry,"
            "uint256 salt"
        ")"
    );

    // prettier-ignore
    bytes32 internal constant _WITHDRAW_FROM_BOX_MESSAGE = keccak256(
        "WithdrawFromBoxMessage("
            "address root,"
            "uint32 boxId,"
            "address token,"
            "uint256 amount,"
            //
            "uint64 expiry,"
            "uint256 salt"
        ")"
    );

    function _hashVaultDepositMessage(VaultDepositMessage memory message) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _VAULT_DEPOSIT_MESSAGE,
                        message.root,
                        message.accountId,
                        message.tokenId,
                        message.marketId,
                        message.amount,
                        message.nonce
                    )
                )
            );
    }

    function _hashVaultPayTreasuryMessage(VaultPayTreasuryMessage memory message) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _VAULT_PAY_TREASURY_MESSAGE,
                        message.root,
                        message.tokenId,
                        message.amount,
                        message.nonce
                    )
                )
            );
    }

    function _hashRequestVaultWithdrawalMessage(
        RequestVaultWithdrawalMessage memory message
    ) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _REQUEST_VAULT_WITHDRAWAL_MESSAGE,
                        message.root,
                        message.tokenId,
                        message.amount,
                        message.nonce
                    )
                )
            );
    }

    function _hashCancelVaultWithdrawalMessage(
        CancelVaultWithdrawalMessage memory message
    ) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(abi.encode(_CANCEL_VAULT_WITHDRAWAL_MESSAGE, message.root, message.tokenId, message.nonce))
            );
    }

    function _hashSubaccountTransferMessage(SubaccountTransferMessage memory message) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _SUBACCOUNT_TRANSFER_MESSAGE,
                        message.root,
                        message.accountId,
                        message.tokenId,
                        message.marketId,
                        message.amount,
                        message.isDeposit,
                        message.nonce
                    )
                )
            );
    }

    function _hashSetAccManagerMessage(SetAccManagerMessage memory message) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _SET_ACC_MANAGER_MESSAGE,
                        message.root,
                        message.accountId,
                        message.accManager,
                        message.nonce
                    )
                )
            );
    }

    function _hashApproveAgentMessage(ApproveAgentMessage memory message) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _APPROVE_AGENT_MESSAGE,
                        message.root,
                        message.accountId,
                        message.agent,
                        message.expiry,
                        message.nonce
                    )
                )
            );
    }

    function _hashRevokeAgentsMessage(RevokeAgentsMessage memory message) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _REVOKE_AGENTS_MESSAGE,
                        message.root,
                        message.accountId,
                        keccak256(abi.encodePacked(message.agents)),
                        message.nonce
                    )
                )
            );
    }

    function _hashPendleSignTx(PendleSignTx memory message) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(abi.encode(_PENDLE_SIGN_TX, message.account, message.connectionId, message.nonce))
            );
    }

    function _hashPlaceConditionalActionMessage(
        PlaceConditionalActionMessage memory message
    ) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(_PLACE_CONDITIONAL_ACTION_MESSAGE, message.actionHash)));
    }

    function _hashExecuteConditionalOrderMessage(
        ExecuteConditionalOrderMessage memory message
    ) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _EXECUTE_CONDITIONAL_ORDER_MESSAGE,
                        message.orderHash,
                        keccak256(message.execParams),
                        message.expiry
                    )
                )
            );
    }

    // DepositFromBoxMessage without swapCalldata/expiry/salt, only containing fixed-size fields
    struct StaticDepositFromBoxMessage {
        address root;
        uint32 boxId;
        address tokenSpent;
        uint256 maxAmountSpent;
        //
        uint8 accountId;
        TokenId tokenId;
        MarketId marketId;
        uint256 minDepositAmount;
        uint256 payTreasuryAmount;
        //
        address swapExtRouter;
        address swapApprove;
    }

    function _hashDepositFromBoxMessage(DepositFromBoxMessage memory message) internal view returns (bytes32) {
        StaticDepositFromBoxMessage memory staticMessage;
        assembly ("memory-safe") {
            staticMessage := message
        }
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _DEPOSIT_FROM_BOX_MESSAGE,
                        staticMessage,
                        keccak256(message.swapCalldata),
                        //
                        message.expiry,
                        message.salt
                    )
                )
            );
    }

    function _hashWithdrawFromBoxMessage(WithdrawFromBoxMessage memory message) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _WITHDRAW_FROM_BOX_MESSAGE,
                        message.root,
                        message.boxId,
                        message.token,
                        message.amount,
                        //
                        message.expiry,
                        message.salt
                    )
                )
            );
    }
}
