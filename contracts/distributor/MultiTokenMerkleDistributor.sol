// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {PendleRolesPlugin} from "../core/roles/PendleRoles.sol";
import {IMultiTokenMerkleDistributor} from "../interfaces/IMultiTokenMerkleDistributor.sol";
import {Err} from "../lib/Errors.sol";

contract MultiTokenMerkleDistributor is IMultiTokenMerkleDistributor, PendleRolesPlugin {
    using SafeERC20 for IERC20;

    bytes32 public merkleRoot;

    /// (token, user) => amount
    mapping(address => mapping(address => uint256)) public claimed;
    mapping(address => mapping(address => uint256)) public verified;

    constructor(address permissionController_) PendleRolesPlugin(permissionController_) {}

    function setMerkleRoot(bytes32 newMerkleRoot) external onlyAuthorized {
        merkleRoot = newMerkleRoot;
        emit SetMerkleRoot(merkleRoot);
    }

    function claim(
        address receiver,
        address[] memory tokens,
        uint256[] memory totalAccrueds,
        bytes32[][] memory proofs
    ) external returns (uint256[] memory amountOuts) {
        require(tokens.length == totalAccrueds.length && tokens.length == proofs.length, Err.InvalidLength());

        address user = msg.sender;
        uint256 nToken = tokens.length;
        amountOuts = new uint256[](nToken);

        for (uint256 i = 0; i < nToken; ++i) {
            (address token, uint256 totalAccrued, bytes32[] memory proof) = (tokens[i], totalAccrueds[i], proofs[i]);
            require(_verifyMerkleData(token, user, totalAccrued, proof), InvalidMerkleProof());

            amountOuts[i] = totalAccrued - claimed[token][user];
            claimed[token][user] = totalAccrued;

            IERC20(token).safeTransfer(receiver, amountOuts[i]);
            emit Claimed(token, user, receiver, amountOuts[i]);
        }
    }

    function claimVerified(address receiver, address[] memory tokens) external returns (uint256[] memory amountOuts) {
        address user = msg.sender;
        uint256 nToken = tokens.length;
        amountOuts = new uint256[](nToken);

        for (uint256 i = 0; i < nToken; ++i) {
            address token = tokens[i];
            uint256 amountVerified = verified[token][user];
            uint256 amountClaimed = claimed[token][user];

            if (amountVerified > amountClaimed) {
                amountOuts[i] = amountVerified - amountClaimed;
                claimed[token][user] = amountVerified;

                IERC20(token).safeTransfer(receiver, amountOuts[i]);
                emit Claimed(token, user, receiver, amountOuts[i]);
            }
        }
    }

    function verify(
        address user,
        address[] memory tokens,
        uint256[] memory totalAccrueds,
        bytes32[][] memory proofs
    ) external returns (uint256[] memory amountClaimable) {
        require(tokens.length == totalAccrueds.length && tokens.length == proofs.length, Err.InvalidLength());

        uint256 nToken = tokens.length;
        amountClaimable = new uint256[](nToken);

        for (uint256 i = 0; i < nToken; ++i) {
            (address token, uint256 totalAccrued, bytes32[] memory proof) = (tokens[i], totalAccrueds[i], proofs[i]);
            require(_verifyMerkleData(token, user, totalAccrued, proof), InvalidMerkleProof());

            amountClaimable[i] = totalAccrued - claimed[token][user];
            verified[token][user] = totalAccrued;

            emit Verified(token, user, amountClaimable[i]);
        }
    }

    function _verifyMerkleData(
        address token,
        address user,
        uint256 amount,
        bytes32[] memory proof
    ) internal view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(token, user, amount));
        return MerkleProof.verify(proof, merkleRoot, leaf);
    }
}
