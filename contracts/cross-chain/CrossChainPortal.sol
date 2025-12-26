// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {
    IOFT,
    MessagingFee,
    MessagingReceipt,
    OFTReceipt,
    SendParam
} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import {PendleRolesPlugin} from "../core/roles/PendleRoles.sol";
import {IPCrossChainPortal} from "../interfaces/IPCrossChainPortal.sol";
import {ApprovedCall, IPDepositBox} from "../interfaces/IPDepositBox.sol";
import {IPDepositBoxFactory} from "../interfaces/IPDepositBoxFactory.sol";
import {Err} from "../lib/Errors.sol";

contract CrossChainPortal is IPCrossChainPortal, PendleRolesPlugin {
    uint32 public immutable BOROS_LZ_EID;
    IPDepositBoxFactory public immutable DEPOSIT_BOX_FACTORY;

    mapping(address token => address) public oftMessenger;

    constructor(
        address permissionController_,
        uint32 borosLzEid_,
        address depositBoxFactory_
    ) PendleRolesPlugin(permissionController_) {
        BOROS_LZ_EID = borosLzEid_;
        DEPOSIT_BOX_FACTORY = IPDepositBoxFactory(depositBoxFactory_);
    }

    function setOFTMessenger(address token, address messenger) external onlyAuthorized {
        if (messenger != address(0)) {
            require(IOFT(messenger).token() == token, Err.PortalInvalidMessenger());
        }
        oftMessenger[token] = messenger;
        emit SetOFTMessenger(token, messenger);
    }

    function bridgeOFT(address root, uint32 boxId, address token, uint256 amount) external payable onlyAuthorized {
        IPDepositBox box = DEPOSIT_BOX_FACTORY.deployDepositBox(root, boxId);

        address messenger = oftMessenger[token];
        require(messenger != address(0), Err.PortalMessengerNotSet());

        OFTReceipt memory receipt = _bridgeOFT(box, token, messenger, amount, msg.value, msg.sender);
        emit BridgeOFT(root, boxId, token, messenger, receipt.amountSentLD, receipt.amountReceivedLD);
    }

    function _bridgeOFT(
        IPDepositBox box,
        address token,
        address messenger,
        uint256 amount,
        uint256 nativeFee,
        address nativeRefund
    ) internal returns (OFTReceipt memory receipt) {
        SendParam memory sendParam = SendParam({
            dstEid: BOROS_LZ_EID,
            to: _addressToBytes32(address(box)),
            amountLD: amount,
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory sendFee = MessagingFee({nativeFee: nativeFee, lzTokenFee: 0});
        ApprovedCall memory call = ApprovedCall({
            token: token,
            amount: amount,
            approveTo: messenger,
            callTo: messenger,
            data: abi.encodeCall(IOFT.send, (sendParam, sendFee, nativeRefund))
        });
        (, receipt) = abi.decode(
            box.approveAndCall{value: nativeFee}(call, nativeRefund),
            (MessagingReceipt, OFTReceipt)
        );
    }

    function _addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }
}
