// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AMMId, MarketId, TokenId} from "./../types/MarketTypes.sol";

interface IMarkRatePusher {
    event MaxDeltaSet(uint256 newMaxDelta);

    function ROUTER() external view returns (address);

    function MARKET_HUB() external view returns (address);

    function maxDelta() external view returns (uint256);

    function forwarder1() external view returns (address);

    function forwarder2() external view returns (address);

    function setMaxDelta(uint256 newMaxDelta) external;

    function deposit(uint256 index, TokenId tokenId, uint256 amount) external;

    function withdraw(uint256 index, TokenId tokenId, uint256 amount, address receiver) external;

    function requestWithdrawal(uint256 index, TokenId tokenId, uint256 amount) external;

    function cashTransfer(uint256 index, MarketId marketId, int256 signedAmount) external;

    function enterMarket(uint256 index, MarketId marketId) external;

    function pushMarkRate(MarketId marketId, AMMId ammId) external returns (bool);
}
