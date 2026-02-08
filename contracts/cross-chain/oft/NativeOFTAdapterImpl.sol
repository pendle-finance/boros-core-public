// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {NativeOFTAdapter} from "@layerzerolabs/oft-evm/contracts/NativeOFTAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract NativeOFTAdapterImpl is NativeOFTAdapter {
    constructor(
        uint8 _localDecimals,
        address _lzEndpoint,
        address _delegate,
        address _initialOwner
    ) NativeOFTAdapter(_localDecimals, _lzEndpoint, _delegate) Ownable(_initialOwner) {}
}
