// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {EIP712Essential} from "./EIP712.sol";
import {IRouterEventsAndTypes} from "./../../../interfaces/IRouterEventsAndTypes.sol";

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
}
