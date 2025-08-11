// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

// External
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Interfaces
import {IMarket} from "../../interfaces/IMarket.sol";

// Libraries
import {ArrayLib} from "../../lib/ArrayLib.sol";
import {Err} from "../../lib/Errors.sol";

// Types
import {MarketAcc} from "../../types/Account.sol";
import {MarketId, TokenId} from "../../types/MarketTypes.sol";

// Components
import {Storage} from "./Storage.sol";

abstract contract MarketHubSetAndView is Storage {
    using ArrayLib for MarketId[];
    using SafeERC20 for IERC20;

    function getEnteredMarkets(MarketAcc user) external view returns (MarketId[] memory) {
        return acc[user].enteredMarkets;
    }

    function getStrictMarkets() external view returns (MarketId[] memory) {
        return _strictMarkets;
    }

    function marketIdToAddress(MarketId marketId) external view returns (address) {
        return _marketIdToAddrChecked(marketId);
    }

    function tokenIdToAddress(TokenId tokenId) external view returns (address) {
        return _tokenDataChecked(tokenId).token;
    }

    function tokenData(TokenId tokenId) external view returns (TokenData memory) {
        return _tokenDataChecked(tokenId);
    }

    function getPersonalCooldown(address userAddr) external view returns (uint32) {
        return _getPersonalCooldown(userAddr);
    }

    function getUserWithdrawalStatus(address userAddr, TokenId tokenId) external view returns (Withdrawal memory) {
        require(_isValidTokenId(tokenId), Err.MHTokenNotExists());
        return _withdrawal[userAddr][tokenId];
    }

    function accCash(MarketAcc user) external view returns (int256) {
        return acc[user].cash;
    }

    function getCashFeeData(TokenId tokenId) external view returns (CashFeeData memory) {
        require(_isValidTokenId(tokenId), Err.MHTokenNotExists());
        return cashFeeData[tokenId];
    }

    function hasEnteredMarketBefore(MarketAcc user, MarketId marketId) external view returns (bool) {
        return acc[user].hasEnteredMarketBefore[marketId];
    }

    // --- ADMIN FUNCTIONS ---

    /// @dev in setting up this setMarketEntranceFees & setMinCashForAccounts must be called too
    function registerToken(address token) external onlyAuthorized returns (TokenId newTokenId) {
        uint256 len = _tokenData.length;
        for (uint256 i = 0; i < len; i++) {
            require(_tokenData[i].token != token, Err.MHTokenExists());
        }
        require(len < type(uint16).max, Err.MHTokenLimitExceeded());

        newTokenId = TokenId.wrap(uint16(_tokenData.length));

        // @dev safe cast scaling factor <= 10**18
        uint96 scalingFactor = uint96(10 ** (18 - IERC20Metadata(token).decimals()));
        _tokenData.push(TokenData(token, scalingFactor));

        emit TokenAdded(newTokenId, token);
    }

    function registerMarket(address[] memory markets) external onlyAuthorized {
        for (uint256 i = 0; i < markets.length; i++) {
            (, TokenId tokenId, MarketId marketId, , , , ) = IMarket(markets[i]).descriptor();
            require(markets[i] == _marketIdToAddrRaw(marketId), Err.MHMarketNotByFactory());
            require(_marketIdToAddress[marketId] == address(0), Err.MHMarketExists());
            require(_isValidTokenId(tokenId), Err.MHTokenNotExists());
            _marketIdToAddress[marketId] = markets[i];

            emit MarketAdded(marketId, markets[i]);
        }
    }

    function withdrawTreasury(TokenId[] memory tokenIds) external onlyAuthorized {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 scaledAmount = cashFeeData[tokenIds[i]].treasuryCash;
            cashFeeData[tokenIds[i]].treasuryCash = 0;

            TokenData memory data = _tokenDataChecked(tokenIds[i]);
            IERC20(data.token).safeTransfer(TREASURY, _toUnscaled(scaledAmount, data.scalingFactor));

            emit CollectFee(tokenIds[i], scaledAmount);
        }
    }

    function setCritHR(int128 newCritHR) external onlyAuthorized {
        require(newCritHR > 0, Err.MMInvalidCritHR());
        critHR = newCritHR;
        emit CritHRUpdated(newCritHR);
    }

    function setRiskyThresHR(int256 newRiskyThresHR) external onlyAuthorized {
        riskyThresHR = newRiskyThresHR;
        emit RiskyThresHRUpdated(newRiskyThresHR);
    }

    function setMinCashForAccounts(
        bool isCross,
        TokenId[] memory tokenIds,
        uint128[] memory newMinCash
    ) external onlyAuthorized {
        require(tokenIds.length == newMinCash.length, Err.InvalidLength());
        if (isCross) {
            for (uint256 i = 0; i < tokenIds.length; i++) {
                cashFeeData[tokenIds[i]].minCashCross = newMinCash[i];
            }
            emit MinCashCrossAccountsUpdated(tokenIds, newMinCash);
        } else {
            for (uint256 i = 0; i < tokenIds.length; i++) {
                cashFeeData[tokenIds[i]].minCashIsolated = newMinCash[i];
            }
            emit MinCashIsolatedAccountsUpdated(tokenIds, newMinCash);
        }
    }

    function setMarketEntranceFees(TokenId[] memory tokenIds, uint128[] memory entranceFees) external onlyAuthorized {
        require(tokenIds.length == entranceFees.length, Err.InvalidLength());
        for (uint256 i = 0; i < tokenIds.length; i++) {
            cashFeeData[tokenIds[i]].marketEntranceFee = entranceFees[i];
        }
        emit MarketEntranceFeesUpdated(tokenIds, entranceFees);
    }

    function enableStrictHealthCheck(MarketId marketId) external onlyAuthorized {
        if (_strictMarkets.include(marketId)) return;
        _strictMarkets.push(marketId);
        _isStrictMarket[marketId] = true;
        _strictMarketsFilter |= uint128(1 << _hashMarketId(marketId));
        emit StrictHealthCheckUpdated(marketId, true);
    }

    function disableStrictHealthCheck(MarketId marketId) external onlyAuthorized {
        MarketId[] memory markets = _strictMarkets;
        if (!markets.remove(marketId)) return;
        _strictMarkets = markets;
        _isStrictMarket[marketId] = false;
        emit StrictHealthCheckUpdated(marketId, false);

        uint8 b = _hashMarketId(marketId);
        for (uint256 i = 0; i < markets.length; i++) {
            if (_hashMarketId(markets[i]) == b) return;
        }
        _strictMarketsFilter ^= uint128((1 << b)); // b is mod 128
    }

    function setGlobalCooldown(uint32 newCooldown) external onlyAuthorized {
        globalCooldown = newCooldown;
        emit GlobalCooldownSet(newCooldown);
    }

    function setPersonalCooldown(address userAddr, uint32 cooldown) external onlyAuthorized {
        _personalCooldown[userAddr] = ~cooldown;
        emit PersonalCooldownSet(userAddr, cooldown);
    }
}
