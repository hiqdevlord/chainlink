// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IPriceRegistry} from "../../interfaces/IPriceRegistry.sol";

import {EVM2EVMOnRamp} from "../../onRamp/EVM2EVMOnRamp.sol";
import {Router} from "../../Router.sol";
import {PriceRegistry} from "../../PriceRegistry.sol";
import {RouterSetup} from "../router/RouterSetup.t.sol";
import {PriceRegistrySetup} from "../priceRegistry/PriceRegistry.t.sol";
import {Internal} from "../../libraries/Internal.sol";
import {Client} from "../../libraries/Client.sol";
import {EVM2EVMOnRampHelper} from "../helpers/EVM2EVMOnRampHelper.sol";
import "../../offRamp/EVM2EVMOffRamp.sol";
import "../TokenSetup.t.sol";

contract EVM2EVMOnRampSetup is TokenSetup, PriceRegistrySetup {
  // Duplicate event of the CCIPSendRequested in the IOnRamp
  event CCIPSendRequested(Internal.EVM2EVMMessage message);

  address internal constant CUSTOM_TOKEN = address(12345);
  uint192 internal constant CUSTON_TOKEN_PRICE = 1e17; // $0.1 CUSTOM

  uint256 internal immutable i_tokenAmount0 = 9;
  uint256 internal immutable i_tokenAmount1 = 7;

  bytes32 internal s_metadataHash;

  EVM2EVMOnRampHelper internal s_onRamp;
  address[] s_offRamps;

  EVM2EVMOnRamp.FeeTokenConfigArgs[] internal s_feeTokenConfigArgs;
  EVM2EVMOnRamp.TokenTransferFeeConfigArgs[] internal s_tokenTransferFeeConfigArgs;

  function setUp() public virtual override(TokenSetup, PriceRegistrySetup) {
    TokenSetup.setUp();
    PriceRegistrySetup.setUp();

    s_priceRegistry.updatePrices(getSinglePriceUpdateStruct(CUSTOM_TOKEN, CUSTON_TOKEN_PRICE));

    address WETH = s_sourceRouter.getWrappedNative();

    s_feeTokenConfigArgs.push(
      EVM2EVMOnRamp.FeeTokenConfigArgs({
        token: s_sourceFeeToken,
        networkFeeAmountUSD: 1e10,
        multiplier: 1e18,
        destGasOverhead: 100_000
      })
    );
    s_feeTokenConfigArgs.push(
      EVM2EVMOnRamp.FeeTokenConfigArgs({
        token: WETH,
        networkFeeAmountUSD: 5e8,
        multiplier: 2e18,
        destGasOverhead: 200_000
      })
    );

    s_tokenTransferFeeConfigArgs.push(
      EVM2EVMOnRamp.TokenTransferFeeConfigArgs({
        token: s_sourceFeeToken,
        minFee: 1_00, // $1
        maxFee: 5000_00, // $5,000
        ratio: 2_5 // 2.5 bps, or 0.025%
      })
    );
    s_tokenTransferFeeConfigArgs.push(
      EVM2EVMOnRamp.TokenTransferFeeConfigArgs({
        token: s_sourceRouter.getWrappedNative(),
        minFee: 2_00, // $2
        maxFee: 10_000_00, // $10,000
        ratio: 5_0 // 5 bps, or 0.05%
      })
    );
    s_tokenTransferFeeConfigArgs.push(
      EVM2EVMOnRamp.TokenTransferFeeConfigArgs({
        token: CUSTOM_TOKEN,
        minFee: 3_00, // $3
        maxFee: 15_000_00, // $15,000
        ratio: 10_0 // 10 bps, or 0.1%
      })
    );

    s_onRamp = new EVM2EVMOnRampHelper(
      EVM2EVMOnRamp.StaticConfig({
        linkToken: s_sourceTokens[0],
        chainSelector: SOURCE_CHAIN_ID,
        destChainSelector: DEST_CHAIN_ID,
        defaultTxGasLimit: GAS_LIMIT,
        prevOnRamp: address(0)
      }),
      generateDynamicOnRampConfig(address(s_sourceRouter), address(s_priceRegistry), address(s_mockARM)),
      getTokensAndPools(s_sourceTokens, getCastedSourcePools()),
      new address[](0),
      rateLimiterConfig(),
      s_feeTokenConfigArgs,
      s_tokenTransferFeeConfigArgs,
      getNopsAndWeights()
    );
    s_onRamp.setAdmin(ADMIN);

    s_metadataHash = keccak256(
      abi.encode(Internal.EVM_2_EVM_MESSAGE_HASH, SOURCE_CHAIN_ID, DEST_CHAIN_ID, address(s_onRamp))
    );

    TokenPool.RampUpdate[] memory onRamps = new TokenPool.RampUpdate[](1);
    onRamps[0] = TokenPool.RampUpdate({ramp: address(s_onRamp), allowed: true});

    LockReleaseTokenPool(address(s_sourcePools[0])).applyRampUpdates(onRamps, new TokenPool.RampUpdate[](0));
    LockReleaseTokenPool(address(s_sourcePools[1])).applyRampUpdates(onRamps, new TokenPool.RampUpdate[](0));

    s_offRamps = new address[](2);
    s_offRamps[0] = address(10);
    s_offRamps[1] = address(11);
    Router.OnRamp[] memory onRampUpdates = new Router.OnRamp[](1);
    Router.OffRamp[] memory offRampUpdates = new Router.OffRamp[](2);
    onRampUpdates[0] = Router.OnRamp({destChainSelector: DEST_CHAIN_ID, onRamp: address(s_onRamp)});
    offRampUpdates[0] = Router.OffRamp({sourceChainSelector: SOURCE_CHAIN_ID, offRamp: s_offRamps[0]});
    offRampUpdates[1] = Router.OffRamp({sourceChainSelector: SOURCE_CHAIN_ID, offRamp: s_offRamps[1]});
    s_sourceRouter.applyRampUpdates(onRampUpdates, new Router.OffRamp[](0), offRampUpdates);

    // Pre approve the first token so the gas estimates of the tests
    // only cover actual gas usage from the ramps
    IERC20(s_sourceTokens[0]).approve(address(s_sourceRouter), 2 ** 128);
    IERC20(s_sourceTokens[1]).approve(address(s_sourceRouter), 2 ** 128);
  }

  function _generateTokenMessage() public view returns (Client.EVM2AnyMessage memory) {
    Client.EVMTokenAmount[] memory tokenAmounts = getCastedSourceEVMTokenAmountsWithZeroAmounts();
    tokenAmounts[0].amount = i_tokenAmount0;
    tokenAmounts[1].amount = i_tokenAmount1;
    return
      Client.EVM2AnyMessage({
        receiver: abi.encode(OWNER),
        data: "",
        tokenAmounts: tokenAmounts,
        feeToken: s_sourceFeeToken,
        extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: GAS_LIMIT, strict: false}))
      });
  }

  function _generateSingleTokenMessage(
    address token,
    uint256 amount
  ) public view returns (Client.EVM2AnyMessage memory) {
    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
    tokenAmounts[0] = Client.EVMTokenAmount({token: token, amount: amount});

    return
      Client.EVM2AnyMessage({
        receiver: abi.encode(OWNER),
        data: "",
        tokenAmounts: tokenAmounts,
        feeToken: s_sourceFeeToken,
        extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: GAS_LIMIT, strict: false}))
      });
  }

  function _generateEmptyMessage() public view returns (Client.EVM2AnyMessage memory) {
    return
      Client.EVM2AnyMessage({
        receiver: abi.encode(OWNER),
        data: "",
        tokenAmounts: new Client.EVMTokenAmount[](0),
        feeToken: s_sourceFeeToken,
        extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: GAS_LIMIT, strict: false}))
      });
  }

  function _messageToEvent(
    Client.EVM2AnyMessage memory message,
    uint64 seqNum,
    uint64 nonce,
    uint256 feeTokenAmount,
    address originalSender
  ) public view returns (Internal.EVM2EVMMessage memory) {
    // Slicing is only available for calldata. So we have to build a new bytes array.
    bytes memory args = new bytes(message.extraArgs.length - 4);
    for (uint256 i = 4; i < message.extraArgs.length; ++i) {
      args[i - 4] = message.extraArgs[i];
    }
    Client.EVMExtraArgsV1 memory extraArgs = abi.decode(args, (Client.EVMExtraArgsV1));
    Internal.EVM2EVMMessage memory messageEvent = Internal.EVM2EVMMessage({
      sequenceNumber: seqNum,
      feeTokenAmount: feeTokenAmount,
      sender: originalSender,
      nonce: nonce,
      gasLimit: extraArgs.gasLimit,
      strict: extraArgs.strict,
      sourceChainSelector: SOURCE_CHAIN_ID,
      receiver: abi.decode(message.receiver, (address)),
      data: message.data,
      tokenAmounts: message.tokenAmounts,
      feeToken: message.feeToken,
      messageId: ""
    });

    messageEvent.messageId = Internal._hash(messageEvent, s_metadataHash);
    return messageEvent;
  }
}
