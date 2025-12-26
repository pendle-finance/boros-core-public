// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IPDepositBoxFactory} from "./IPDepositBoxFactory.sol";

interface IPCrossChainPortal {
    event SetOFTMessenger(address indexed token, address indexed messenger);

    event BridgeOFT(
        address indexed root,
        uint32 boxId,
        address token,
        address messenger,
        uint256 amountSent,
        uint256 amountReceived
    );

    function oftMessenger(address token) external view returns (address);

    function setOFTMessenger(address token, address messenger) external;

    function bridgeOFT(address root, uint32 boxId, address token, uint256 amount) external payable;

    function BOROS_LZ_EID() external view returns (uint32);

    function DEPOSIT_BOX_FACTORY() external view returns (IPDepositBoxFactory);
}
