// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {AuthStorage} from "./AuthStorage.sol";
import {SigningBase} from "./SigningBase.sol";
import {Err} from "./../../../lib/Errors.sol";

abstract contract AuthBase is AuthStorage, SigningBase {
    modifier onlyRelayer() {
        require(_isAllowedRelayer(msg.sender), Err.Unauthorized());
        _;
    }

    function _verifySignerSigAndIncreaseNonce(
        address signer,
        uint64 nonce,
        bytes32 messageHash,
        bytes memory signature
    ) internal {
        require(SignatureChecker.isValidSignatureNow(signer, messageHash, signature), Err.AuthInvalidMessage());
        _verifyAndIncreaseNonce(signer, nonce);
    }

    function _verifyAgentSigAndIncreaseNonce(
        address agent,
        PendleSignTx memory message,
        bytes memory signature,
        bytes32 onchainConnectedId
    ) internal {
        _verifyAgentSigSkipNonce(agent, message, signature, onchainConnectedId);
        _verifyAndIncreaseNonce(agent, message.nonce);
    }

    function _verifyAgentSigSkipNonce(
        address agent,
        PendleSignTx memory message,
        bytes memory signature,
        bytes32 onchainConnectedId
    ) internal view {
        require(
            SignatureChecker.isValidSignatureNow(agent, _hashPendleSignTx(message), signature),
            Err.AuthInvalidMessage()
        );

        require(_AMS().agentExpiry[message.account][agent] > block.timestamp, Err.AuthAgentExpired());
        require(onchainConnectedId == message.connectionId, Err.AuthInvalidConnectionId());
    }

    function _verifyAndIncreaseNonce(address signer, uint64 nonce) internal {
        require(_AMS().signerNonce[signer] < nonce, Err.AuthInvalidNonce());
        _AMS().signerNonce[signer] = nonce;
    }
}
