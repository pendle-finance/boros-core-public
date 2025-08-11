// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IMultiTokenMerkleDistributor {
    event Claimed(address indexed token, address indexed user, address indexed receiver, uint256 amount);
    event Verified(address indexed token, address indexed user, uint256 amountClaimable);
    event SetMerkleRoot(bytes32 indexed merkleRoot);

    error InvalidMerkleProof();

    function merkleRoot() external view returns (bytes32);

    function claimed(address token, address user) external view returns (uint256);

    function verified(address token, address user) external view returns (uint256);

    function setMerkleRoot(bytes32 newMerkleRoot) external;

    function claim(
        address receiver,
        address[] memory tokens,
        uint256[] memory totalAccrueds,
        bytes32[][] memory proofs
    ) external returns (uint256[] memory amountOuts);

    function claimVerified(address receiver, address[] memory tokens) external returns (uint256[] memory amountOuts);

    function verify(
        address user,
        address[] memory tokens,
        uint256[] memory totalAccrueds,
        bytes32[][] memory proofs
    ) external returns (uint256[] memory amountClaimable);
}
