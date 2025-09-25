// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IFundingRateVerifier {
    event ConfigUpdated(uint256 maxVerificationFee, uint32 period);

    function FINDEX_ORACLE() external view returns (address);

    function CHAIN_LINK_ORACLE() external view returns (address);

    function CHAIN_LINK_FEED_ID() external view returns (bytes32);

    function CHAOS_LABS_ORACLE() external view returns (address);

    function CHAOS_LABS_UPDATE_TYPE_HASH() external view returns (bytes32);

    function CHAOS_LABS_MARKET() external view returns (address);

    function PENDLE_ORACLE() external view returns (address);

    function maxVerificationFee() external view returns (uint256);

    function period() external view returns (uint32);

    function updateWithChainlink(bytes memory report) external;

    function updateWithChaosLabs(uint256 updateId) external;

    function updateWithPendle() external;

    function manualUpdate(int112 fundingRate, uint32 fundingTimestamp) external;

    function setConfig(uint256 newMaxVerificationFee, uint32 newPeriod) external;

    function withdraw(address receiver, uint256 amount) external;
}
