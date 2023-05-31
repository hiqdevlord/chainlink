// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "./EVM2EVMOnRampSetup.t.sol";
import {EVM2EVMOnRamp} from "../../onRamp/EVM2EVMOnRamp.sol";
import {USDPriceWith18Decimals} from "../../libraries/USDPriceWith18Decimals.sol";

/// @notice #constructor
contract EVM2EVMOnRamp_constructor is EVM2EVMOnRampSetup {
  event ConfigSet(EVM2EVMOnRamp.StaticConfig staticConfig, EVM2EVMOnRamp.DynamicConfig dynamicConfig);
  event PoolAdded(address token, address pool);

  function testConstructorSuccess() public {
    EVM2EVMOnRamp.StaticConfig memory staticConfig = EVM2EVMOnRamp.StaticConfig({
      linkToken: s_sourceTokens[0],
      chainSelector: SOURCE_CHAIN_ID,
      destChainSelector: DEST_CHAIN_ID,
      defaultTxGasLimit: GAS_LIMIT,
      prevOnRamp: address(0)
    });
    EVM2EVMOnRamp.DynamicConfig memory dynamicConfig = generateDynamicOnRampConfig(
      address(s_sourceRouter),
      address(s_priceRegistry),
      address(s_mockARM)
    );
    EVM2EVMOnRamp.TokenAndPool[] memory tokensAndPools = getTokensAndPools(s_sourceTokens, getCastedSourcePools());

    vm.expectEmit();
    emit ConfigSet(staticConfig, dynamicConfig);
    vm.expectEmit();
    emit PoolAdded(tokensAndPools[0].token, tokensAndPools[0].pool);

    s_onRamp = new EVM2EVMOnRampHelper(
      staticConfig,
      dynamicConfig,
      tokensAndPools,
      new address[](0),
      rateLimiterConfig(),
      s_feeTokenConfigArgs,
      s_tokenTransferFeeConfigArgs,
      getNopsAndWeights()
    );

    EVM2EVMOnRamp.StaticConfig memory gotStaticConfig = s_onRamp.getStaticConfig();
    assertEq(staticConfig.linkToken, gotStaticConfig.linkToken);
    assertEq(staticConfig.chainSelector, gotStaticConfig.chainSelector);
    assertEq(staticConfig.destChainSelector, gotStaticConfig.destChainSelector);
    assertEq(staticConfig.defaultTxGasLimit, gotStaticConfig.defaultTxGasLimit);
    assertEq(staticConfig.prevOnRamp, gotStaticConfig.prevOnRamp);

    EVM2EVMOnRamp.DynamicConfig memory gotDynamicConfig = s_onRamp.getDynamicConfig();
    assertEq(dynamicConfig.router, gotDynamicConfig.router);
    assertEq(dynamicConfig.priceRegistry, gotDynamicConfig.priceRegistry);
    assertEq(dynamicConfig.maxDataSize, gotDynamicConfig.maxDataSize);
    assertEq(dynamicConfig.maxTokensLength, gotDynamicConfig.maxTokensLength);
    assertEq(dynamicConfig.maxGasLimit, gotDynamicConfig.maxGasLimit);
    assertEq(dynamicConfig.ARM, gotDynamicConfig.ARM);

    // Tokens
    assertEq(s_sourceTokens, s_onRamp.getSupportedTokens());

    // Initial values
    assertEq("EVM2EVMOnRamp 1.0.0", s_onRamp.typeAndVersion());
    assertEq(OWNER, s_onRamp.owner());
    assertEq(1, s_onRamp.getExpectedNextSequenceNumber());
  }
}

contract EVM2EVMOnRamp_payNops_fuzz is EVM2EVMOnRampSetup {
  function test_fuzz_NopPayNopsSuccess(uint96 nopFeesJuels) public {
    (EVM2EVMOnRamp.NopAndWeight[] memory nopsAndWeights, uint256 weightsTotal) = s_onRamp.getNops();
    // To avoid NoFeesToPay
    vm.assume(nopFeesJuels > weightsTotal);

    // Set Nop fee juels
    deal(s_sourceFeeToken, address(s_onRamp), nopFeesJuels);
    changePrank(address(s_sourceRouter));
    s_onRamp.forwardFromRouter(_generateEmptyMessage(), nopFeesJuels, OWNER);

    changePrank(OWNER);

    uint256 totalJuels = s_onRamp.getNopFeesJuels();
    s_onRamp.payNops();
    for (uint256 i = 0; i < nopsAndWeights.length; ++i) {
      uint256 expectedPayout = (totalJuels * nopsAndWeights[i].weight) / weightsTotal;
      assertEq(IERC20(s_sourceFeeToken).balanceOf(nopsAndWeights[i].nop), expectedPayout);
    }
  }
}

contract EVM2EVMOnRamp_payNops is EVM2EVMOnRampSetup {
  function setUp() public virtual override {
    EVM2EVMOnRampSetup.setUp();

    // Since we'll mostly be testing for valid calls from the router we'll
    // mock all calls to be originating from the router and re-mock in
    // tests that require failure.
    changePrank(address(s_sourceRouter));

    uint256 feeAmount = 1234567890;
    uint256 numberOfMessages = 5;

    // Send a bunch of messages, increasing the juels in the contract
    for (uint256 i = 0; i < numberOfMessages; ++i) {
      IERC20(s_sourceFeeToken).transferFrom(OWNER, address(s_onRamp), feeAmount);
      s_onRamp.forwardFromRouter(_generateEmptyMessage(), feeAmount, OWNER);
    }

    assertEq(s_onRamp.getNopFeesJuels(), feeAmount * numberOfMessages);
    assertEq(IERC20(s_sourceFeeToken).balanceOf(address(s_onRamp)), feeAmount * numberOfMessages);
  }

  function testOwnerPayNopsSuccess() public {
    changePrank(OWNER);

    uint256 totalJuels = s_onRamp.getNopFeesJuels();
    s_onRamp.payNops();
    (EVM2EVMOnRamp.NopAndWeight[] memory nopsAndWeights, uint256 weightsTotal) = s_onRamp.getNops();
    for (uint256 i = 0; i < nopsAndWeights.length; ++i) {
      uint256 expectedPayout = (nopsAndWeights[i].weight * totalJuels) / weightsTotal;
      assertEq(IERC20(s_sourceFeeToken).balanceOf(nopsAndWeights[i].nop), expectedPayout);
    }
  }

  function testFeeAdminPayNopsSuccess() public {
    changePrank(ADMIN);

    uint256 totalJuels = s_onRamp.getNopFeesJuels();
    s_onRamp.payNops();
    (EVM2EVMOnRamp.NopAndWeight[] memory nopsAndWeights, uint256 weightsTotal) = s_onRamp.getNops();
    for (uint256 i = 0; i < nopsAndWeights.length; ++i) {
      uint256 expectedPayout = (nopsAndWeights[i].weight * totalJuels) / weightsTotal;
      assertEq(IERC20(s_sourceFeeToken).balanceOf(nopsAndWeights[i].nop), expectedPayout);
    }
  }

  function testNopPayNopsSuccess() public {
    changePrank(getNopsAndWeights()[0].nop);

    uint256 totalJuels = s_onRamp.getNopFeesJuels();
    s_onRamp.payNops();
    (EVM2EVMOnRamp.NopAndWeight[] memory nopsAndWeights, uint256 weightsTotal) = s_onRamp.getNops();
    for (uint256 i = 0; i < nopsAndWeights.length; ++i) {
      uint256 expectedPayout = (nopsAndWeights[i].weight * totalJuels) / weightsTotal;
      assertEq(IERC20(s_sourceFeeToken).balanceOf(nopsAndWeights[i].nop), expectedPayout);
    }
  }

  // Reverts

  function testInsufficientBalanceReverts() public {
    changePrank(address(s_onRamp));
    IERC20(s_sourceFeeToken).transfer(OWNER, IERC20(s_sourceFeeToken).balanceOf(address(s_onRamp)));
    changePrank(OWNER);
    vm.expectRevert(EVM2EVMOnRamp.InsufficientBalance.selector);
    s_onRamp.payNops();
  }

  function testWrongPermissionsReverts() public {
    changePrank(STRANGER);

    vm.expectRevert(EVM2EVMOnRamp.OnlyCallableByOwnerOrFeeAdminOrNop.selector);
    s_onRamp.payNops();
  }

  function testNoFeesToPayReverts() public {
    changePrank(OWNER);
    s_onRamp.payNops();
    vm.expectRevert(EVM2EVMOnRamp.NoFeesToPay.selector);
    s_onRamp.payNops();
  }

  function testNoNopsToPayReverts() public {
    changePrank(OWNER);
    EVM2EVMOnRamp.NopAndWeight[] memory nopsAndWeights = new EVM2EVMOnRamp.NopAndWeight[](0);
    s_onRamp.setNops(nopsAndWeights);
    vm.expectRevert(EVM2EVMOnRamp.NoNopsToPay.selector);
    s_onRamp.payNops();
  }
}

/// @notice #linkAvailableForPayment
contract EVM2EVMOnRamp_linkAvailableForPayment is EVM2EVMOnRamp_payNops {
  function testLinkAvailableForPaymentSuccess() public {
    uint256 totalJuels = s_onRamp.getNopFeesJuels();
    uint256 linkBalance = IERC20(s_sourceFeeToken).balanceOf(address(s_onRamp));

    assertEq(int256(linkBalance - totalJuels), s_onRamp.linkAvailableForPayment());

    changePrank(OWNER);
    s_onRamp.payNops();

    assertEq(int256(linkBalance - totalJuels), s_onRamp.linkAvailableForPayment());
  }

  function testInsufficientLinkBalanceSuccess() public {
    uint256 totalJuels = s_onRamp.getNopFeesJuels();
    uint256 linkBalance = IERC20(s_sourceFeeToken).balanceOf(address(s_onRamp));

    changePrank(address(s_onRamp));

    uint256 linkRemaining = 1;
    IERC20(s_sourceFeeToken).transfer(OWNER, linkBalance - linkRemaining);

    changePrank(STRANGER);
    assertEq(int256(linkRemaining) - int256(totalJuels), s_onRamp.linkAvailableForPayment());
  }
}

/// @notice #forwardFromRouter
contract EVM2EVMOnRamp_forwardFromRouter is EVM2EVMOnRampSetup {
  function setUp() public virtual override {
    EVM2EVMOnRampSetup.setUp();

    address[] memory feeTokens = new address[](1);
    feeTokens[0] = s_sourceTokens[1];
    s_priceRegistry.applyFeeTokensUpdates(feeTokens, new address[](0));

    // Since we'll mostly be testing for valid calls from the router we'll
    // mock all calls to be originating from the router and re-mock in
    // tests that require failure.
    changePrank(address(s_sourceRouter));
  }

  function testForwardFromRouterSuccessCustomExtraArgs() public {
    Client.EVM2AnyMessage memory message = _generateEmptyMessage();
    message.extraArgs = Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: GAS_LIMIT * 2, strict: true}));
    uint256 feeAmount = 1234567890;
    IERC20(s_sourceFeeToken).transferFrom(OWNER, address(s_onRamp), feeAmount);

    vm.expectEmit();
    emit CCIPSendRequested(_messageToEvent(message, 1, 1, feeAmount, OWNER));

    s_onRamp.forwardFromRouter(message, feeAmount, OWNER);
  }

  function testForwardFromRouterSuccess() public {
    Client.EVM2AnyMessage memory message = _generateEmptyMessage();

    uint256 feeAmount = 1234567890;
    IERC20(s_sourceFeeToken).transferFrom(OWNER, address(s_onRamp), feeAmount);

    vm.expectEmit();
    emit CCIPSendRequested(_messageToEvent(message, 1, 1, feeAmount, OWNER));

    s_onRamp.forwardFromRouter(message, feeAmount, OWNER);
  }

  function testShouldIncrementSeqNumAndNonceSuccess() public {
    Client.EVM2AnyMessage memory message = _generateEmptyMessage();

    for (uint64 i = 1; i < 4; ++i) {
      uint64 nonceBefore = s_onRamp.getSenderNonce(OWNER);

      vm.expectEmit();
      emit CCIPSendRequested(_messageToEvent(message, i, i, 0, OWNER));

      s_onRamp.forwardFromRouter(message, 0, OWNER);

      uint64 nonceAfter = s_onRamp.getSenderNonce(OWNER);
      assertEq(nonceAfter, nonceBefore + 1);
    }
  }

  event Transfer(address indexed from, address indexed to, uint256 value);

  function testShouldStoreLinkFees() public {
    Client.EVM2AnyMessage memory message = _generateEmptyMessage();

    uint256 feeAmount = 1234567890;
    IERC20(s_sourceFeeToken).transferFrom(OWNER, address(s_onRamp), feeAmount);

    s_onRamp.forwardFromRouter(message, feeAmount, OWNER);

    assertEq(IERC20(s_sourceFeeToken).balanceOf(address(s_onRamp)), feeAmount);
    assertEq(s_onRamp.getNopFeesJuels(), feeAmount);
  }

  function testShouldStoreNonLinkFees() public {
    Client.EVM2AnyMessage memory message = _generateEmptyMessage();
    message.feeToken = s_sourceTokens[1];

    uint256 feeAmount = 1234567890;
    IERC20(s_sourceTokens[1]).transferFrom(OWNER, address(s_onRamp), feeAmount);

    s_onRamp.forwardFromRouter(message, feeAmount, OWNER);

    assertEq(IERC20(s_sourceTokens[1]).balanceOf(address(s_onRamp)), feeAmount);

    // Calculate conversion done by prices contract
    uint256 feeTokenPrice = s_priceRegistry.getTokenPrice(s_sourceTokens[1]).value;
    uint256 linkTokenPrice = s_priceRegistry.getTokenPrice(s_sourceFeeToken).value;
    uint256 conversionRate = (feeTokenPrice * 1e18) / linkTokenPrice;
    uint256 expectedJuels = (feeAmount * conversionRate) / 1e18;

    assertEq(s_onRamp.getNopFeesJuels(), expectedJuels);
  }

  // Make sure any valid sender, receiver and feeAmount can be handled.
  function test_fuzz_ForwardFromRouterSuccess(address originalSender, address receiver, uint96 feeTokenAmount) public {
    // To avoid RouterMustSetOriginalSender
    vm.assume(originalSender != address(0));

    Client.EVM2AnyMessage memory message = _generateEmptyMessage();
    message.receiver = abi.encode(receiver);

    // Make sure the tokens are in the contract
    deal(s_sourceFeeToken, address(s_onRamp), feeTokenAmount);

    Internal.EVM2EVMMessage memory expectedEvent = _messageToEvent(message, 1, 1, feeTokenAmount, originalSender);

    vm.expectEmit(false, false, false, true);
    emit CCIPSendRequested(expectedEvent);

    // Assert the message Id is correct
    assertEq(expectedEvent.messageId, s_onRamp.forwardFromRouter(message, feeTokenAmount, originalSender));
    // Assert the fee token amount is correctly assigned to the nop fee pool
    assertEq(feeTokenAmount, s_onRamp.getNopFeesJuels());
  }

  // Reverts

  function testPausedReverts() public {
    changePrank(OWNER);
    s_onRamp.pause();
    vm.expectRevert(EVM2EVMOnRamp.PausedError.selector);
    s_onRamp.forwardFromRouter(_generateEmptyMessage(), 0, OWNER);
  }

  function testInvalidExtraArgsTagReverts() public {
    Client.EVM2AnyMessage memory message = _generateEmptyMessage();
    message.extraArgs = bytes("bad args");

    vm.expectRevert(EVM2EVMOnRamp.InvalidExtraArgsTag.selector);

    s_onRamp.forwardFromRouter(message, 0, OWNER);
  }

  function testUnhealthyReverts() public {
    s_mockARM.voteToCurse(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    vm.expectRevert(EVM2EVMOnRamp.BadARMSignal.selector);
    s_onRamp.forwardFromRouter(_generateEmptyMessage(), 0, OWNER);
  }

  function testPermissionsReverts() public {
    changePrank(OWNER);
    vm.expectRevert(EVM2EVMOnRamp.MustBeCalledByRouter.selector);
    s_onRamp.forwardFromRouter(_generateEmptyMessage(), 0, OWNER);
  }

  function testOriginalSenderReverts() public {
    vm.expectRevert(EVM2EVMOnRamp.RouterMustSetOriginalSender.selector);
    s_onRamp.forwardFromRouter(_generateEmptyMessage(), 0, address(0));
  }

  function testMessageTooLargeReverts() public {
    Client.EVM2AnyMessage memory message = _generateEmptyMessage();
    message.data = new bytes(MAX_DATA_SIZE + 1);
    vm.expectRevert(abi.encodeWithSelector(EVM2EVMOnRamp.MessageTooLarge.selector, MAX_DATA_SIZE, message.data.length));

    s_onRamp.forwardFromRouter(message, 0, STRANGER);
  }

  function testTooManyTokensReverts() public {
    Client.EVM2AnyMessage memory message = _generateEmptyMessage();
    uint256 tooMany = MAX_TOKENS_LENGTH + 1;
    message.tokenAmounts = new Client.EVMTokenAmount[](tooMany);
    vm.expectRevert(EVM2EVMOnRamp.UnsupportedNumberOfTokens.selector);
    s_onRamp.forwardFromRouter(message, 0, STRANGER);
  }

  function testSenderNotAllowedReverts() public {
    changePrank(OWNER);
    s_onRamp.setAllowListEnabled(true);

    vm.expectRevert(abi.encodeWithSelector(EVM2EVMOnRamp.SenderNotAllowed.selector, STRANGER));
    changePrank(address(s_sourceRouter));
    s_onRamp.forwardFromRouter(_generateEmptyMessage(), 0, STRANGER);
  }

  function testUnsupportedTokenReverts() public {
    address wrongToken = address(1);

    Client.EVM2AnyMessage memory message = _generateEmptyMessage();
    message.tokenAmounts = new Client.EVMTokenAmount[](1);
    message.tokenAmounts[0].token = wrongToken;
    message.tokenAmounts[0].amount = 1;

    // We need to set the price of this new token to be able to reach
    // the proper revert point. This must be called by the owner.
    changePrank(OWNER);

    Internal.PriceUpdates memory priceUpdates = getSinglePriceUpdateStruct(wrongToken, 1);
    s_priceRegistry.updatePrices(priceUpdates);

    // Change back to the router
    changePrank(address(s_sourceRouter));
    vm.expectRevert(abi.encodeWithSelector(EVM2EVMOnRamp.UnsupportedToken.selector, wrongToken));

    s_onRamp.forwardFromRouter(message, 0, OWNER);
  }

  function testConsumingMoreThanMaxCapacityReverts() public {
    Client.EVM2AnyMessage memory message = _generateEmptyMessage();
    message.tokenAmounts = new Client.EVMTokenAmount[](1);
    message.tokenAmounts[0].amount = 2 ** 128;
    message.tokenAmounts[0].token = s_sourceTokens[0];

    IERC20(s_sourceTokens[0]).approve(address(s_onRamp), 2 ** 128);

    vm.expectRevert(
      abi.encodeWithSelector(
        RateLimiter.ConsumingMoreThanMaxCapacity.selector,
        rateLimiterConfig().capacity,
        (message.tokenAmounts[0].amount * s_sourceTokenPrices[0]) / 1e18
      )
    );

    s_onRamp.forwardFromRouter(message, 0, OWNER);
  }

  function testPriceNotFoundForTokenReverts() public {
    Client.EVM2AnyMessage memory message = _generateEmptyMessage();

    address fakeToken = address(1);
    message.tokenAmounts = new Client.EVMTokenAmount[](1);
    message.tokenAmounts[0].token = fakeToken;

    vm.expectRevert(abi.encodeWithSelector(AggregateRateLimiter.PriceNotFoundForToken.selector, fakeToken));

    s_onRamp.forwardFromRouter(message, 0, OWNER);
  }

  // Asserts gasLimit must be <=maxGasLimit
  function testMessageGasLimitTooHighReverts() public {
    Client.EVM2AnyMessage memory message = _generateEmptyMessage();
    message.extraArgs = Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: MAX_GAS_LIMIT + 1, strict: false}));
    vm.expectRevert(abi.encodeWithSelector(EVM2EVMOnRamp.MessageGasLimitTooHigh.selector));
    s_onRamp.forwardFromRouter(message, 0, OWNER);
  }

  function testInvalidAddressEncodePackedReverts() public {
    Client.EVM2AnyMessage memory message = _generateEmptyMessage();
    message.receiver = abi.encodePacked(address(234));

    vm.expectRevert(abi.encodeWithSelector(EVM2EVMOnRamp.InvalidAddress.selector, message.receiver));

    s_onRamp.forwardFromRouter(message, 1, OWNER);
  }

  function testInvalidAddressReverts() public {
    Client.EVM2AnyMessage memory message = _generateEmptyMessage();
    message.receiver = abi.encode(type(uint208).max);

    vm.expectRevert(abi.encodeWithSelector(EVM2EVMOnRamp.InvalidAddress.selector, message.receiver));

    s_onRamp.forwardFromRouter(message, 1, OWNER);
  }
}

/// @notice #forwardFromRouter with ramp upgrade
contract EVM2EVMOnRamp_forwardFromRouter_upgrade is EVM2EVMOnRampSetup {
  uint256 internal constant FEE_AMOUNT = 1234567890;
  EVM2EVMOnRampHelper internal s_prevOnRamp;

  function setUp() public virtual override {
    EVM2EVMOnRampSetup.setUp();

    s_prevOnRamp = s_onRamp;

    s_onRamp = new EVM2EVMOnRampHelper(
      EVM2EVMOnRamp.StaticConfig({
        linkToken: s_sourceTokens[0],
        chainSelector: SOURCE_CHAIN_ID,
        destChainSelector: DEST_CHAIN_ID,
        defaultTxGasLimit: GAS_LIMIT,
        prevOnRamp: address(s_prevOnRamp)
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

    changePrank(address(s_sourceRouter));
  }

  function testV2Success() public {
    Client.EVM2AnyMessage memory message = _generateEmptyMessage();

    vm.expectEmit();
    emit CCIPSendRequested(_messageToEvent(message, 1, 1, FEE_AMOUNT, OWNER));
    s_onRamp.forwardFromRouter(message, FEE_AMOUNT, OWNER);
  }

  function testV2SenderNoncesReadsPreviousRampSucceess() public {
    Client.EVM2AnyMessage memory message = _generateEmptyMessage();
    uint64 startNonce = s_onRamp.getSenderNonce(OWNER);

    for (uint64 i = 1; i < 4; ++i) {
      s_prevOnRamp.forwardFromRouter(message, 0, OWNER);

      assertEq(startNonce + i, s_onRamp.getSenderNonce(OWNER));
    }
  }

  function testV2NonceStartsAtV1NonceSuccess() public {
    Client.EVM2AnyMessage memory message = _generateEmptyMessage();

    uint64 startNonce = s_onRamp.getSenderNonce(OWNER);

    // send 1 message from previous onramp
    s_prevOnRamp.forwardFromRouter(message, FEE_AMOUNT, OWNER);

    assertEq(startNonce + 1, s_onRamp.getSenderNonce(OWNER));

    // new onramp nonce should start from 2, while sequence number start from 1
    vm.expectEmit();
    emit CCIPSendRequested(_messageToEvent(message, 1, startNonce + 2, FEE_AMOUNT, OWNER));
    s_onRamp.forwardFromRouter(message, FEE_AMOUNT, OWNER);

    assertEq(startNonce + 2, s_onRamp.getSenderNonce(OWNER));

    // after another send, nonce should be 3, and sequence number be 2
    vm.expectEmit();
    emit CCIPSendRequested(_messageToEvent(message, 2, startNonce + 3, FEE_AMOUNT, OWNER));
    s_onRamp.forwardFromRouter(message, FEE_AMOUNT, OWNER);

    assertEq(startNonce + 3, s_onRamp.getSenderNonce(OWNER));
  }

  function testV2NonceNewSenderStartsAtZeroSuccess() public {
    Client.EVM2AnyMessage memory message = _generateEmptyMessage();

    // send 1 message from previous onramp from OWNER
    s_prevOnRamp.forwardFromRouter(message, FEE_AMOUNT, OWNER);

    address newSender = address(1234567);
    // new onramp nonce should start from 1 for new sender
    vm.expectEmit();
    emit CCIPSendRequested(_messageToEvent(message, 1, 1, FEE_AMOUNT, newSender));
    s_onRamp.forwardFromRouter(message, FEE_AMOUNT, newSender);
  }
}

contract EVM2EVMOnRamp_getFeeSetup is EVM2EVMOnRampSetup {
  uint192 internal s_feeTokenPrice;
  uint192 internal s_wrappedTokenPrice;
  uint192 internal s_customTokenPrice;

  function setUp() public virtual override {
    EVM2EVMOnRampSetup.setUp();

    s_feeTokenPrice = s_sourceTokenPrices[0];
    s_wrappedTokenPrice = s_sourceTokenPrices[2];
    s_customTokenPrice = CUSTON_TOKEN_PRICE;
  }

  function calcUSDValueFromTokenAmount(uint192 tokenPrice, uint256 tokenAmount) internal pure returns (uint256) {
    return (tokenPrice * tokenAmount) / 1e18;
  }

  function calcTokenAmountFromUSDValue(uint192 tokenPrice, uint256 usdValue) internal pure returns (uint256) {
    return (usdValue * 1e18) / tokenPrice;
  }

  function applyBpsRatio(uint256 tokenAmount, uint16 ratio) internal pure returns (uint256) {
    return (tokenAmount * ratio) / 1e5;
  }

  function centsToValue(uint32 cents) internal pure returns (uint256) {
    return uint256(cents) * 1e16;
  }
}

/// @notice #getTokenTransferFee
contract EVM2EVMOnRamp_getTokenTransferFee is EVM2EVMOnRamp_getFeeSetup {
  using USDPriceWith18Decimals for uint192;

  function testNoTokenTransferSuccess() public {
    Client.EVM2AnyMessage memory message = _generateEmptyMessage();
    uint256 feeAmount = s_onRamp.getTokenTransferFee(message.feeToken, s_feeTokenPrice, message.tokenAmounts);

    assertEq(0, feeAmount);
  }

  function testFeeTokenBpsFeeSuccess() public {
    uint256 tokenAmount = 10000e18;

    Client.EVM2AnyMessage memory message = _generateSingleTokenMessage(s_sourceFeeToken, tokenAmount);
    uint256 feeAmount = s_onRamp.getTokenTransferFee(message.feeToken, s_feeTokenPrice, message.tokenAmounts);

    uint256 usdValue = calcUSDValueFromTokenAmount(s_feeTokenPrice, tokenAmount);
    uint256 bpsUSDValue = applyBpsRatio(usdValue, s_tokenTransferFeeConfigArgs[0].ratio);
    uint256 expectedFeeTokenAmount = calcTokenAmountFromUSDValue(s_feeTokenPrice, bpsUSDValue);

    assertEq(expectedFeeTokenAmount, feeAmount);
  }

  function testFeeTokenMinFeeSuccess() public {
    Client.EVM2AnyMessage memory message = _generateSingleTokenMessage(s_sourceFeeToken, 1);
    uint256 feeAmount = s_onRamp.getTokenTransferFee(message.feeToken, s_feeTokenPrice, message.tokenAmounts);

    uint256 minFeeValue = centsToValue(s_tokenTransferFeeConfigArgs[0].minFee);
    uint256 expectedFeeTokenAmount = calcTokenAmountFromUSDValue(s_feeTokenPrice, minFeeValue);

    assertEq(expectedFeeTokenAmount, feeAmount);
  }

  function testFeeTokenZeroAmountMinFeeSuccess() public {
    Client.EVM2AnyMessage memory message = _generateSingleTokenMessage(s_sourceFeeToken, 0);
    uint256 feeAmount = s_onRamp.getTokenTransferFee(message.feeToken, s_feeTokenPrice, message.tokenAmounts);

    uint256 minFeeValue = centsToValue(s_tokenTransferFeeConfigArgs[0].minFee);
    uint256 expectedFeeTokenAmount = calcTokenAmountFromUSDValue(s_feeTokenPrice, minFeeValue);

    assertEq(expectedFeeTokenAmount, feeAmount);
  }

  function testFeeTokenMaxFeeSuccess() public {
    Client.EVM2AnyMessage memory message = _generateSingleTokenMessage(s_sourceFeeToken, 1e36);
    uint256 feeAmount = s_onRamp.getTokenTransferFee(message.feeToken, s_feeTokenPrice, message.tokenAmounts);

    uint256 maxFeeValue = centsToValue(s_tokenTransferFeeConfigArgs[0].maxFee);
    uint256 expectedFeeTokenAmount = calcTokenAmountFromUSDValue(s_feeTokenPrice, maxFeeValue);

    assertEq(expectedFeeTokenAmount, feeAmount);
  }

  function testWETHTokenBpsFeeSuccess() public {
    uint256 tokenAmount = 10000e18;

    Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
      receiver: abi.encode(OWNER),
      data: "",
      tokenAmounts: new Client.EVMTokenAmount[](1),
      feeToken: s_sourceRouter.getWrappedNative(),
      extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: GAS_LIMIT, strict: false}))
    });
    message.tokenAmounts[0] = Client.EVMTokenAmount({token: s_sourceRouter.getWrappedNative(), amount: tokenAmount});

    uint256 feeAmount = s_onRamp.getTokenTransferFee(message.feeToken, s_wrappedTokenPrice, message.tokenAmounts);

    uint256 usdValue = calcUSDValueFromTokenAmount(s_wrappedTokenPrice, tokenAmount);
    uint256 bpsUSDValue = applyBpsRatio(usdValue, s_tokenTransferFeeConfigArgs[1].ratio);
    uint256 expectedFeeTokenAmount = calcTokenAmountFromUSDValue(s_wrappedTokenPrice, bpsUSDValue);

    assertEq(expectedFeeTokenAmount, feeAmount);
  }

  function testCustomTokenBpsFeeSuccess() public {
    uint256 tokenAmount = 200000e18;

    Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
      receiver: abi.encode(OWNER),
      data: "",
      tokenAmounts: new Client.EVMTokenAmount[](1),
      feeToken: s_sourceFeeToken,
      extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: GAS_LIMIT, strict: false}))
    });
    message.tokenAmounts[0] = Client.EVMTokenAmount({token: CUSTOM_TOKEN, amount: tokenAmount});

    uint256 feeAmount = s_onRamp.getTokenTransferFee(message.feeToken, s_feeTokenPrice, message.tokenAmounts);

    uint256 usdValue = calcUSDValueFromTokenAmount(s_customTokenPrice, tokenAmount);
    uint256 bpsUSDValue = applyBpsRatio(usdValue, s_tokenTransferFeeConfigArgs[2].ratio);
    uint256 expectedFeeTokenAmount = calcTokenAmountFromUSDValue(s_feeTokenPrice, bpsUSDValue);

    assertEq(expectedFeeTokenAmount, feeAmount);
  }

  function testNoFeeConfigSuccess() public {
    Client.EVM2AnyMessage memory message = _generateSingleTokenMessage(s_sourceTokens[1], 1e36);
    uint256 feeAmount = s_onRamp.getTokenTransferFee(message.feeToken, s_feeTokenPrice, message.tokenAmounts);

    // if token does not have transfer fee config, it should cost 0 to transfer
    assertEq(0, feeAmount);
  }

  function testZeroFeeConfigSuccess() public {
    EVM2EVMOnRamp.TokenTransferFeeConfigArgs[]
      memory tokenTransferFeeConfigArgs = new EVM2EVMOnRamp.TokenTransferFeeConfigArgs[](1);
    tokenTransferFeeConfigArgs[0] = EVM2EVMOnRamp.TokenTransferFeeConfigArgs({
      token: s_sourceFeeToken,
      minFee: 0,
      maxFee: 0,
      ratio: 0
    });
    s_onRamp.setTokenTransferFeeConfig(tokenTransferFeeConfigArgs);

    Client.EVM2AnyMessage memory message = _generateSingleTokenMessage(s_sourceFeeToken, 1e36);
    uint256 feeAmount = s_onRamp.getTokenTransferFee(message.feeToken, s_feeTokenPrice, message.tokenAmounts);

    // if token transfer fee set to 0, it should cost 0 to transfer
    assertEq(0, feeAmount);
  }

  function testZeroFeeNotSupportedPriceSuccess() public {
    Client.EVM2AnyMessage memory message = _generateSingleTokenMessage(address(123), 200000e18);
    uint256 feeAmount = s_onRamp.getTokenTransferFee(message.feeToken, s_feeTokenPrice, message.tokenAmounts);

    // if token transfer fee is not set, it defaults to 0, price registry should not be called
    assertEq(0, feeAmount);
  }

  function testMixedTokenFeeSuccess() public {
    uint192[3] memory tokenPrices = [s_feeTokenPrice, s_wrappedTokenPrice, s_customTokenPrice];
    uint256[3] memory tokenTransferAmounts = [uint256(10000e18), uint256(10000e18), uint256(100000e18)];

    Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
      receiver: abi.encode(OWNER),
      data: "",
      tokenAmounts: new Client.EVMTokenAmount[](9),
      feeToken: s_sourceRouter.getWrappedNative(),
      extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: GAS_LIMIT, strict: false}))
    });
    // min fees = $6
    message.tokenAmounts[0] = Client.EVMTokenAmount({token: s_sourceFeeToken, amount: 1});
    message.tokenAmounts[1] = Client.EVMTokenAmount({token: s_sourceRouter.getWrappedNative(), amount: 1});
    message.tokenAmounts[2] = Client.EVMTokenAmount({token: CUSTOM_TOKEN, amount: 1});
    // max fees = $30,000
    message.tokenAmounts[3] = Client.EVMTokenAmount({token: s_sourceFeeToken, amount: 1e36});
    message.tokenAmounts[4] = Client.EVMTokenAmount({token: s_sourceRouter.getWrappedNative(), amount: 1e36});
    message.tokenAmounts[5] = Client.EVMTokenAmount({token: CUSTOM_TOKEN, amount: 1e36});
    // bps fees
    message.tokenAmounts[6] = Client.EVMTokenAmount({token: s_sourceFeeToken, amount: tokenTransferAmounts[0]});
    message.tokenAmounts[7] = Client.EVMTokenAmount({
      token: s_sourceRouter.getWrappedNative(),
      amount: tokenTransferAmounts[1]
    });
    message.tokenAmounts[8] = Client.EVMTokenAmount({token: CUSTOM_TOKEN, amount: tokenTransferAmounts[2]});

    uint256 feeAmount = s_onRamp.getTokenTransferFee(message.feeToken, s_wrappedTokenPrice, message.tokenAmounts);

    uint256 usdFeeValue;
    for (uint256 i = 0; i < tokenTransferAmounts.length; ++i) {
      usdFeeValue += centsToValue(s_tokenTransferFeeConfigArgs[i].minFee);
      usdFeeValue += centsToValue(s_tokenTransferFeeConfigArgs[i].maxFee);
      usdFeeValue += applyBpsRatio(
        calcUSDValueFromTokenAmount(tokenPrices[i], tokenTransferAmounts[i]),
        s_tokenTransferFeeConfigArgs[i].ratio
      );
    }

    uint256 expectedFeeTokenAmount = calcTokenAmountFromUSDValue(s_wrappedTokenPrice, usdFeeValue);
    assertEq(expectedFeeTokenAmount, feeAmount);
  }

  // reverts

  function testValidatedPriceNotSupportedReverts() public {
    address NOT_SUPPORTED_TOKEN = address(123);

    EVM2EVMOnRamp.TokenTransferFeeConfigArgs[]
      memory tokenTransferFeeConfigArgs = new EVM2EVMOnRamp.TokenTransferFeeConfigArgs[](1);
    tokenTransferFeeConfigArgs[0] = EVM2EVMOnRamp.TokenTransferFeeConfigArgs({
      token: NOT_SUPPORTED_TOKEN,
      minFee: 1,
      maxFee: 1,
      ratio: 1
    });
    s_onRamp.setTokenTransferFeeConfig(tokenTransferFeeConfigArgs);

    Client.EVM2AnyMessage memory message = _generateSingleTokenMessage(NOT_SUPPORTED_TOKEN, 200000e18);

    vm.expectRevert(abi.encodeWithSelector(PriceRegistry.TokenNotSupported.selector, NOT_SUPPORTED_TOKEN));

    s_onRamp.getTokenTransferFee(message.feeToken, s_feeTokenPrice, message.tokenAmounts);
  }

  function testValidatedPriceStalenessReverts() public {
    vm.warp(block.timestamp + TWELVE_HOURS + 1);

    Client.EVM2AnyMessage memory message = _generateSingleTokenMessage(s_sourceFeeToken, 1e36);
    message.tokenAmounts[0].token = s_sourceRouter.getWrappedNative();

    vm.expectRevert(
      abi.encodeWithSelector(
        PriceRegistry.StaleTokenPrice.selector,
        s_sourceRouter.getWrappedNative(),
        uint128(TWELVE_HOURS),
        uint128(TWELVE_HOURS + 1)
      )
    );

    s_onRamp.getTokenTransferFee(message.feeToken, s_feeTokenPrice, message.tokenAmounts);
  }
}

/// @notice #getFee
contract EVM2EVMOnRamp_getFee is EVM2EVMOnRamp_getFeeSetup {
  using USDPriceWith18Decimals for uint192;

  function getEmptyMessageExecutionFeeInLink() internal view returns (uint256) {
    EVM2EVMOnRamp.FeeTokenConfigArgs memory feeConfig = s_feeTokenConfigArgs[0];

    uint256 totalGasUsed = (GAS_LIMIT + feeConfig.destGasOverhead);
    uint256 totalGasIncMP = (totalGasUsed * feeConfig.multiplier) / 1 ether;
    uint256 totalUSDValue = totalGasIncMP * USD_PER_GAS + feeConfig.networkFeeAmountUSD;

    return calcTokenAmountFromUSDValue(s_feeTokenPrice, totalUSDValue);
  }

  function testEmptyMessageSuccess() public {
    uint192[2] memory feeTokenPrices = [s_feeTokenPrice, s_wrappedTokenPrice];
    for (uint256 i = 0; i < feeTokenPrices.length; ++i) {
      uint256 feeTokenIndex = i;
      EVM2EVMOnRamp.FeeTokenConfigArgs memory feeConfig = s_feeTokenConfigArgs[feeTokenIndex];

      Client.EVM2AnyMessage memory message = _generateEmptyMessage();
      message.feeToken = feeConfig.token;
      uint256 feeAmount = s_onRamp.getFee(message);

      uint256 totalGasUsed = (GAS_LIMIT + feeConfig.destGasOverhead);
      uint256 totalGasIncMP = (totalGasUsed * feeConfig.multiplier) / 1 ether;
      uint256 totalUSDPrice = totalGasIncMP * USD_PER_GAS + feeConfig.networkFeeAmountUSD;
      uint256 totalPriceInFeeToken = (totalUSDPrice * 1e18) / feeTokenPrices[feeTokenIndex];

      assertEq(totalPriceInFeeToken, feeAmount);
    }
  }

  function testLinkFeeTokenHighGasMessageSuccess() public {
    EVM2EVMOnRamp.FeeTokenConfigArgs memory feeConfig = s_feeTokenConfigArgs[0];

    uint256 customGasLimit = 1_000_000;
    Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
      receiver: abi.encode(OWNER),
      data: "",
      tokenAmounts: new Client.EVMTokenAmount[](0),
      feeToken: feeConfig.token,
      extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: customGasLimit, strict: false}))
    });
    uint256 feeAmount = s_onRamp.getFee(message);

    uint256 totalGasUsed = (customGasLimit + feeConfig.destGasOverhead);
    uint256 totalGasIncMP = (totalGasUsed * feeConfig.multiplier) / 1 ether;
    uint256 totalUSDPrice = totalGasIncMP * USD_PER_GAS + feeConfig.networkFeeAmountUSD;
    uint256 totalPriceInFeeToken = (totalUSDPrice * 1e18) / s_feeTokenPrice;

    assertEq(totalPriceInFeeToken, feeAmount);
  }

  function testMessageWithFeeTokenTransferSuccess() public {
    uint256 tokenAmount = 10000e18;

    Client.EVM2AnyMessage memory message = _generateSingleTokenMessage(s_sourceFeeToken, tokenAmount);
    uint256 feeAmount = s_onRamp.getFee(message);

    uint256 usdValue = calcUSDValueFromTokenAmount(s_feeTokenPrice, tokenAmount);
    uint256 bpsUSDValue = applyBpsRatio(usdValue, s_tokenTransferFeeConfigArgs[0].ratio);
    uint256 expectedTransferFeeAmountInLink = calcTokenAmountFromUSDValue(s_feeTokenPrice, bpsUSDValue);

    uint256 expectedTotalFeeAmount = getEmptyMessageExecutionFeeInLink() + expectedTransferFeeAmountInLink;
    assertEq(expectedTotalFeeAmount, feeAmount);
  }

  function testMessageWithTwoTokenTransferSuccess() public {
    uint256 feeTokenAmount = 10000e18;
    uint256 customTokenAmount = 200000e18;

    Client.EVM2AnyMessage memory message = _generateEmptyMessage();

    Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](2);
    tokenAmounts[0] = Client.EVMTokenAmount({token: s_sourceFeeToken, amount: feeTokenAmount});
    tokenAmounts[1] = Client.EVMTokenAmount({token: CUSTOM_TOKEN, amount: customTokenAmount});
    message.tokenAmounts = tokenAmounts;

    uint256 feeAmount = s_onRamp.getFee(message);

    uint256 usdFeeValue;
    usdFeeValue += applyBpsRatio(
      calcUSDValueFromTokenAmount(s_feeTokenPrice, feeTokenAmount),
      s_tokenTransferFeeConfigArgs[0].ratio
    );
    usdFeeValue += applyBpsRatio(
      calcUSDValueFromTokenAmount(s_customTokenPrice, customTokenAmount),
      s_tokenTransferFeeConfigArgs[2].ratio
    );
    uint256 expectedTransferFeeAmountInLink = calcTokenAmountFromUSDValue(s_feeTokenPrice, usdFeeValue);

    uint256 expectedTotalFeeAmount = getEmptyMessageExecutionFeeInLink() + expectedTransferFeeAmountInLink;
    assertEq(expectedTotalFeeAmount, feeAmount);
  }
}

contract EVM2EVMOnRamp_setNops is EVM2EVMOnRampSetup {
  event NopPaid(address indexed nop, uint256 amount);

  // Used because EnumerableMap doesn't guarantee order
  mapping(address => uint256) internal s_nopsToWeights;

  function testSetNopsSuccess() public {
    EVM2EVMOnRamp.NopAndWeight[] memory nopsAndWeights = getNopsAndWeights();
    nopsAndWeights[1].nop = USER_4;
    nopsAndWeights[1].weight = 20;
    for (uint256 i = 0; i < nopsAndWeights.length; ++i) {
      s_nopsToWeights[nopsAndWeights[i].nop] = nopsAndWeights[i].weight;
    }

    s_onRamp.setNops(nopsAndWeights);

    (EVM2EVMOnRamp.NopAndWeight[] memory actual, ) = s_onRamp.getNops();
    for (uint256 i = 0; i < actual.length; ++i) {
      assertEq(actual[i].weight, s_nopsToWeights[actual[i].nop]);
    }
  }

  function testIncludesPaymentSuccess() public {
    EVM2EVMOnRamp.NopAndWeight[] memory nopsAndWeights = getNopsAndWeights();
    nopsAndWeights[1].nop = USER_4;
    nopsAndWeights[1].weight = 20;
    uint32 totalWeight;
    for (uint256 i = 0; i < nopsAndWeights.length; ++i) {
      totalWeight += nopsAndWeights[i].weight;
      s_nopsToWeights[nopsAndWeights[i].nop] = nopsAndWeights[i].weight;
    }

    // Make sure a payout happens regardless of what the weights are set to
    uint96 nopFeesJuels = totalWeight * 5;
    // Set Nop fee juels
    deal(s_sourceFeeToken, address(s_onRamp), nopFeesJuels);
    changePrank(address(s_sourceRouter));
    s_onRamp.forwardFromRouter(_generateEmptyMessage(), nopFeesJuels, OWNER);
    changePrank(OWNER);

    // We don't care about the fee calculation logic in this test
    // so we don't verify the amounts. We do verify the addresses to
    // make sure the existing nops get paid and not the new ones.
    EVM2EVMOnRamp.NopAndWeight[] memory existingNopsAndWeights = getNopsAndWeights();
    for (uint256 i = 0; i < existingNopsAndWeights.length; ++i) {
      vm.expectEmit(true, false, false, false);
      emit NopPaid(existingNopsAndWeights[i].nop, 0);
    }

    s_onRamp.setNops(nopsAndWeights);

    (EVM2EVMOnRamp.NopAndWeight[] memory actual, ) = s_onRamp.getNops();
    for (uint256 i = 0; i < actual.length; ++i) {
      assertEq(actual[i].weight, s_nopsToWeights[actual[i].nop]);
    }
  }

  function testSetNopsRemovesOldNopsCompletelySuccess() public {
    EVM2EVMOnRamp.NopAndWeight[] memory nopsAndWeights = new EVM2EVMOnRamp.NopAndWeight[](0);
    s_onRamp.setNops(nopsAndWeights);
    (EVM2EVMOnRamp.NopAndWeight[] memory actual, uint256 totalWeight) = s_onRamp.getNops();
    assertEq(actual.length, 0);
    assertEq(totalWeight, 0);
  }

  // Reverts

  function testNotEnoughFundsForPayoutReverts() public {
    uint96 nopFeesJuels = 2 ** 95;
    // Set Nop fee juels but don't transfer LINK. This can happen when users
    // pay in non-link tokens.
    changePrank(address(s_sourceRouter));
    s_onRamp.forwardFromRouter(_generateEmptyMessage(), nopFeesJuels, OWNER);
    changePrank(OWNER);

    vm.expectRevert(EVM2EVMOnRamp.InsufficientBalance.selector);

    s_onRamp.setNops(getNopsAndWeights());
  }

  function testNonOwnerReverts() public {
    EVM2EVMOnRamp.NopAndWeight[] memory nopsAndWeights = getNopsAndWeights();
    changePrank(STRANGER);

    vm.expectRevert("Only callable by owner");

    s_onRamp.setNops(nopsAndWeights);
  }

  function testTooManyNopsReverts() public {
    EVM2EVMOnRamp.NopAndWeight[] memory nopsAndWeights = new EVM2EVMOnRamp.NopAndWeight[](257);

    vm.expectRevert(EVM2EVMOnRamp.TooManyNops.selector);

    s_onRamp.setNops(nopsAndWeights);
  }
}

/// @notice #withdrawNonLinkFees
contract EVM2EVMOnRamp_withdrawNonLinkFees is EVM2EVMOnRampSetup {
  IERC20 internal s_token;

  function setUp() public virtual override {
    EVM2EVMOnRampSetup.setUp();
    // Send some non-link tokens to the onRamp
    s_token = IERC20(s_sourceTokens[1]);
    deal(s_sourceTokens[1], address(s_onRamp), 100);
  }

  function testWithdrawNonLinkFeesSuccess() public {
    s_onRamp.withdrawNonLinkFees(address(s_token), address(this));

    assertEq(0, s_token.balanceOf(address(s_onRamp)));
    assertEq(100, s_token.balanceOf(address(this)));
  }

  function testSettlingBalanceSuccess() public {
    // Set Nop fee juels
    uint96 nopFeesJuels = 10000000;
    changePrank(address(s_sourceRouter));
    s_onRamp.forwardFromRouter(_generateEmptyMessage(), nopFeesJuels, OWNER);
    changePrank(OWNER);

    vm.expectRevert(EVM2EVMOnRamp.LinkBalanceNotSettled.selector);
    s_onRamp.withdrawNonLinkFees(address(s_token), address(this));

    // It doesnt matter how the link tokens get to the onRamp
    // In this case we simply deal them to the ramp to show
    // anyone can settle the balance
    deal(s_sourceTokens[0], address(s_onRamp), nopFeesJuels);

    s_onRamp.withdrawNonLinkFees(address(s_token), address(this));
  }

  // Reverts

  function testLinkBalanceNotSettledReverts() public {
    // Set Nop fee juels
    uint96 nopFeesJuels = 10000000;
    changePrank(address(s_sourceRouter));
    s_onRamp.forwardFromRouter(_generateEmptyMessage(), nopFeesJuels, OWNER);
    changePrank(OWNER);

    vm.expectRevert(EVM2EVMOnRamp.LinkBalanceNotSettled.selector);

    s_onRamp.withdrawNonLinkFees(address(s_token), address(this));
  }

  function testNonOwnerReverts() public {
    changePrank(STRANGER);

    vm.expectRevert("Only callable by owner");
    s_onRamp.withdrawNonLinkFees(address(s_token), address(this));
  }

  function testInvalidWithdrawalAddressReverts() public {
    vm.expectRevert(abi.encodeWithSelector(EVM2EVMOnRamp.InvalidWithdrawalAddress.selector, address(0)));
    s_onRamp.withdrawNonLinkFees(address(s_token), address(0));
  }

  function testInvalidTokenReverts() public {
    vm.expectRevert(abi.encodeWithSelector(EVM2EVMOnRamp.InvalidFeeToken.selector, s_sourceTokens[0]));
    s_onRamp.withdrawNonLinkFees(s_sourceTokens[0], address(this));
  }
}

/// @notice #setFeeTokenConfig
contract EVM2EVMOnRamp_setFeeTokenConfig is EVM2EVMOnRampSetup {
  event FeeConfigSet(EVM2EVMOnRamp.FeeTokenConfigArgs[] feeConfig);

  function testSetFeeTokenConfigSuccess() public {
    EVM2EVMOnRamp.FeeTokenConfigArgs[] memory feeConfig;

    vm.expectEmit();
    emit FeeConfigSet(feeConfig);

    s_onRamp.setFeeTokenConfig(feeConfig);
  }

  function testSetFeeTokenConfigByFeeAdminSuccess() public {
    EVM2EVMOnRamp.FeeTokenConfigArgs[] memory feeConfig;

    changePrank(ADMIN);

    vm.expectEmit();
    emit FeeConfigSet(feeConfig);

    s_onRamp.setFeeTokenConfig(feeConfig);
  }

  // Reverts

  function testOnlyCallableByOwnerOrFeeAdminReverts() public {
    EVM2EVMOnRamp.FeeTokenConfigArgs[] memory feeConfig;
    changePrank(STRANGER);

    vm.expectRevert(EVM2EVMOnRamp.OnlyCallableByOwnerOrFeeAdmin.selector);

    s_onRamp.setFeeTokenConfig(feeConfig);
  }
}

/// @notice #setTokenTransferFeeConfig
contract EVM2EVMOnRamp_setTokenTransferFeeConfig is EVM2EVMOnRampSetup {
  event TokenTransferFeeConfigSet(EVM2EVMOnRamp.TokenTransferFeeConfigArgs[] transferFeeConfig);

  function testSetFeeTokenConfigSuccess() public {
    EVM2EVMOnRamp.TokenTransferFeeConfigArgs[]
      memory tokenTransferFeeConfigArgs = new EVM2EVMOnRamp.TokenTransferFeeConfigArgs[](2);
    tokenTransferFeeConfigArgs[0] = EVM2EVMOnRamp.TokenTransferFeeConfigArgs({
      token: address(0),
      minFee: 0,
      maxFee: 0,
      ratio: 0
    });
    tokenTransferFeeConfigArgs[1] = EVM2EVMOnRamp.TokenTransferFeeConfigArgs({
      token: address(1),
      minFee: 1,
      maxFee: 1,
      ratio: 1
    });

    vm.expectEmit();
    emit TokenTransferFeeConfigSet(tokenTransferFeeConfigArgs);

    s_onRamp.setTokenTransferFeeConfig(tokenTransferFeeConfigArgs);

    EVM2EVMOnRamp.TokenTransferFeeConfig memory tokenTransferFeeConfig0 = s_onRamp.getTokenTransferFeeConfig(
      address(0)
    );
    assertEq(0, tokenTransferFeeConfig0.minFee);
    assertEq(0, tokenTransferFeeConfig0.maxFee);
    assertEq(0, tokenTransferFeeConfig0.ratio);

    EVM2EVMOnRamp.TokenTransferFeeConfig memory tokenTransferFeeConfig1 = s_onRamp.getTokenTransferFeeConfig(
      address(1)
    );
    assertEq(1, tokenTransferFeeConfig1.minFee);
    assertEq(1, tokenTransferFeeConfig1.maxFee);
    assertEq(1, tokenTransferFeeConfig1.ratio);
  }

  function testSetFeeTokenConfigByFeeAdminSuccess() public {
    EVM2EVMOnRamp.TokenTransferFeeConfigArgs[] memory transferFeeConfig;
    changePrank(ADMIN);

    vm.expectEmit();
    emit TokenTransferFeeConfigSet(transferFeeConfig);

    s_onRamp.setTokenTransferFeeConfig(transferFeeConfig);
  }

  // Reverts

  function testOnlyCallableByOwnerOrFeeAdminReverts() public {
    EVM2EVMOnRamp.TokenTransferFeeConfigArgs[] memory transferFeeConfig;
    changePrank(STRANGER);

    vm.expectRevert(EVM2EVMOnRamp.OnlyCallableByOwnerOrFeeAdmin.selector);

    s_onRamp.setTokenTransferFeeConfig(transferFeeConfig);
  }
}

// #getTokenPool
contract EVM2EVMOnRamp_getTokenPool is EVM2EVMOnRampSetup {
  function testGetTokenPoolSuccess() public {
    assertEq(s_sourcePools[0], address(s_onRamp.getPoolBySourceToken(IERC20(s_sourceTokens[0]))));
    assertEq(s_sourcePools[1], address(s_onRamp.getPoolBySourceToken(IERC20(s_sourceTokens[1]))));

    vm.expectRevert(abi.encodeWithSelector(EVM2EVMOnRamp.UnsupportedToken.selector, IERC20(s_destTokens[0])));
    s_onRamp.getPoolBySourceToken(IERC20(s_destTokens[0]));
  }
}

contract EVM2EVMOnRamp_applyPoolUpdates is EVM2EVMOnRampSetup {
  event PoolAdded(address token, address pool);
  event PoolRemoved(address token, address pool);

  function testApplyPoolUpdatesSuccess() public {
    Internal.PoolUpdate[] memory adds = new Internal.PoolUpdate[](1);
    adds[0] = Internal.PoolUpdate({token: address(1), pool: address(2)});

    vm.expectEmit();
    emit PoolAdded(adds[0].token, adds[0].pool);

    s_onRamp.applyPoolUpdates(new Internal.PoolUpdate[](0), adds);

    assertEq(adds[0].pool, address(s_onRamp.getPoolBySourceToken(IERC20(adds[0].token))));

    vm.expectEmit();
    emit PoolRemoved(adds[0].token, adds[0].pool);

    s_onRamp.applyPoolUpdates(adds, new Internal.PoolUpdate[](0));

    vm.expectRevert(abi.encodeWithSelector(EVM2EVMOnRamp.UnsupportedToken.selector, adds[0].token));
    s_onRamp.getPoolBySourceToken(IERC20(adds[0].token));
  }

  function testAtomicPoolReplacementSuccess() public {
    address token = address(1);

    Internal.PoolUpdate[] memory adds = new Internal.PoolUpdate[](1);
    adds[0] = Internal.PoolUpdate({token: token, pool: address(2)});

    vm.expectEmit();
    emit PoolAdded(token, adds[0].pool);

    s_onRamp.applyPoolUpdates(new Internal.PoolUpdate[](0), adds);

    assertEq(adds[0].pool, address(s_onRamp.getPoolBySourceToken(IERC20(token))));

    Internal.PoolUpdate[] memory updates = new Internal.PoolUpdate[](1);
    updates[0] = Internal.PoolUpdate({token: token, pool: address(3)});

    vm.expectEmit();
    emit PoolRemoved(token, adds[0].pool);
    vm.expectEmit();
    emit PoolAdded(token, updates[0].pool);

    s_onRamp.applyPoolUpdates(adds, updates);

    assertEq(updates[0].pool, address(s_onRamp.getPoolBySourceToken(IERC20(token))));
  }

  // Reverts
  function testOnlyCallableByOwnerReverts() public {
    changePrank(STRANGER);

    vm.expectRevert("Only callable by owner");

    s_onRamp.applyPoolUpdates(new Internal.PoolUpdate[](0), new Internal.PoolUpdate[](0));
  }

  function testPoolAlreadyExistsReverts() public {
    Internal.PoolUpdate[] memory adds = new Internal.PoolUpdate[](2);
    adds[0] = Internal.PoolUpdate({token: address(1), pool: address(2)});
    adds[1] = Internal.PoolUpdate({token: address(1), pool: address(2)});

    vm.expectRevert(EVM2EVMOnRamp.PoolAlreadyAdded.selector);

    s_onRamp.applyPoolUpdates(new Internal.PoolUpdate[](0), adds);
  }

  function testInvalidTokenPoolConfigReverts() public {
    Internal.PoolUpdate[] memory adds = new Internal.PoolUpdate[](1);
    adds[0] = Internal.PoolUpdate({token: address(0), pool: address(2)});

    vm.expectRevert(EVM2EVMOnRamp.InvalidTokenPoolConfig.selector);

    s_onRamp.applyPoolUpdates(new Internal.PoolUpdate[](0), adds);

    adds[0] = Internal.PoolUpdate({token: address(1), pool: address(0)});

    vm.expectRevert(EVM2EVMOnRamp.InvalidTokenPoolConfig.selector);

    s_onRamp.applyPoolUpdates(new Internal.PoolUpdate[](0), adds);
  }

  function testPoolDoesNotExistReverts() public {
    Internal.PoolUpdate[] memory removes = new Internal.PoolUpdate[](1);
    removes[0] = Internal.PoolUpdate({token: address(1), pool: address(2)});

    vm.expectRevert(abi.encodeWithSelector(EVM2EVMOnRamp.PoolDoesNotExist.selector, removes[0].token));

    s_onRamp.applyPoolUpdates(removes, new Internal.PoolUpdate[](0));
  }

  function testTokenPoolMismatchReverts() public {
    Internal.PoolUpdate[] memory adds = new Internal.PoolUpdate[](1);
    adds[0] = Internal.PoolUpdate({token: address(1), pool: address(2)});
    s_onRamp.applyPoolUpdates(new Internal.PoolUpdate[](0), adds);

    Internal.PoolUpdate[] memory removes = new Internal.PoolUpdate[](1);
    removes[0] = Internal.PoolUpdate({token: address(1), pool: address(20)});

    vm.expectRevert(EVM2EVMOnRamp.TokenPoolMismatch.selector);

    s_onRamp.applyPoolUpdates(removes, adds);
  }
}

// #getSupportedTokens
contract EVM2EVMOnRamp_getSupportedTokens is EVM2EVMOnRampSetup {
  function testGetSupportedTokensSuccess() public {
    address[] memory supportedTokens = s_onRamp.getSupportedTokens();

    assertEq(s_sourceTokens, supportedTokens);

    Internal.PoolUpdate[] memory removes = new Internal.PoolUpdate[](1);
    removes[0] = Internal.PoolUpdate({token: s_sourceTokens[0], pool: s_sourcePools[0]});

    s_onRamp.applyPoolUpdates(removes, new Internal.PoolUpdate[](0));

    supportedTokens = s_onRamp.getSupportedTokens();

    assertEq(address(s_sourceTokens[1]), supportedTokens[0]);
    assertEq(s_sourceTokens.length - 1, supportedTokens.length);
  }
}

// #getExpectedNextSequenceNumber
contract EVM2EVMOnRamp_getExpectedNextSequenceNumber is EVM2EVMOnRampSetup {
  function testGetExpectedNextSequenceNumberSuccess() public {
    assertEq(1, s_onRamp.getExpectedNextSequenceNumber());
  }
}

// #setDynamicConfig
contract EVM2EVMOnRamp_setDynamicConfig is EVM2EVMOnRampSetup {
  event ConfigSet(EVM2EVMOnRamp.StaticConfig staticConfig, EVM2EVMOnRamp.DynamicConfig dynamicConfig);

  function testSetDynamicConfigSuccess() public {
    EVM2EVMOnRamp.StaticConfig memory staticConfig = s_onRamp.getStaticConfig();
    EVM2EVMOnRamp.DynamicConfig memory newConfig = EVM2EVMOnRamp.DynamicConfig({
      router: address(2134),
      priceRegistry: address(23423),
      maxDataSize: 400,
      maxTokensLength: 14,
      maxGasLimit: MAX_GAS_LIMIT / 2,
      ARM: address(11)
    });

    vm.expectEmit();
    emit ConfigSet(staticConfig, newConfig);

    s_onRamp.setDynamicConfig(newConfig);

    EVM2EVMOnRamp.DynamicConfig memory gotDynamicConfig = s_onRamp.getDynamicConfig();
    assertEq(newConfig.router, gotDynamicConfig.router);
    assertEq(newConfig.priceRegistry, gotDynamicConfig.priceRegistry);
    assertEq(newConfig.maxDataSize, gotDynamicConfig.maxDataSize);
    assertEq(newConfig.maxTokensLength, gotDynamicConfig.maxTokensLength);
    assertEq(newConfig.maxGasLimit, gotDynamicConfig.maxGasLimit);
  }

  // Reverts

  function testSetConfigInvalidConfigReverts() public {
    EVM2EVMOnRamp.DynamicConfig memory newConfig = EVM2EVMOnRamp.DynamicConfig({
      router: address(0),
      priceRegistry: address(23423),
      maxDataSize: 400,
      maxTokensLength: 14,
      maxGasLimit: MAX_GAS_LIMIT / 2,
      ARM: address(11)
    });

    vm.expectRevert(EVM2EVMOnRamp.InvalidConfig.selector);

    s_onRamp.setDynamicConfig(newConfig);

    newConfig.router = address(1);
    newConfig.priceRegistry = address(0);

    vm.expectRevert(EVM2EVMOnRamp.InvalidConfig.selector);

    s_onRamp.setDynamicConfig(newConfig);

    newConfig.priceRegistry = address(23423);
    newConfig.ARM = address(0);

    vm.expectRevert(EVM2EVMOnRamp.InvalidConfig.selector);

    s_onRamp.setDynamicConfig(newConfig);
  }

  function testSetConfigOnlyOwnerReverts() public {
    vm.stopPrank();
    vm.expectRevert("Only callable by owner");
    s_onRamp.setDynamicConfig(generateDynamicOnRampConfig(address(1), address(2), address(4)));
  }
}

contract EVM2EVMOnRampWithAllowListSetup is EVM2EVMOnRampSetup {
  function setUp() public virtual override(EVM2EVMOnRampSetup) {
    EVM2EVMOnRampSetup.setUp();
    address[] memory allowedAddresses = new address[](1);
    allowedAddresses[0] = OWNER;
    s_onRamp.applyAllowListUpdates(new address[](0), allowedAddresses);
    s_onRamp.setAllowListEnabled(true);
  }
}

contract EVM2EVMOnRamp_setAllowListEnabled is EVM2EVMOnRampWithAllowListSetup {
  function testSetAllowListEnabledSuccess() public {
    assertTrue(s_onRamp.getAllowListEnabled());
    s_onRamp.setAllowListEnabled(false);
    assertFalse(s_onRamp.getAllowListEnabled());
    s_onRamp.setAllowListEnabled(true);
    assertTrue(s_onRamp.getAllowListEnabled());
  }

  // Reverts

  function testOnlyOwnerReverts() public {
    vm.stopPrank();
    vm.expectRevert("Only callable by owner");
    s_onRamp.setAllowListEnabled(true);
  }
}

/// @notice #getAllowListEnabled
contract EVM2EVMOnRamp_getAllowListEnabled is EVM2EVMOnRampWithAllowListSetup {
  function testGetAllowListEnabledSuccess() public {
    assertTrue(s_onRamp.getAllowListEnabled());
    s_onRamp.setAllowListEnabled(false);
    assertFalse(s_onRamp.getAllowListEnabled());
    s_onRamp.setAllowListEnabled(true);
    assertTrue(s_onRamp.getAllowListEnabled());
  }
}

/// @notice #setAllowList
contract EVM2EVMOnRamp_applyAllowListUpdates is EVM2EVMOnRampWithAllowListSetup {
  event AllowListAdd(address sender);
  event AllowListRemove(address sender);

  function testSetAllowListSuccess() public {
    address[] memory newAddresses = new address[](2);
    newAddresses[0] = address(1);
    newAddresses[1] = address(2);

    for (uint256 i = 0; i < 2; ++i) {
      vm.expectEmit();
      emit AllowListAdd(newAddresses[i]);
    }

    s_onRamp.applyAllowListUpdates(new address[](0), newAddresses);
    address[] memory setAddresses = s_onRamp.getAllowList();

    // First address in allowList is owner, set in test setup.
    assertEq(address(1), setAddresses[1]);
    assertEq(address(2), setAddresses[2]);

    // Add address(3), remove address(1) from allow list
    newAddresses = new address[](2);
    newAddresses[0] = address(2);
    newAddresses[1] = address(3);

    address[] memory removeAddresses = new address[](1);
    removeAddresses[0] = address(1);

    vm.expectEmit();
    emit AllowListRemove(address(1));

    vm.expectEmit();
    emit AllowListAdd(address(3));

    s_onRamp.applyAllowListUpdates(removeAddresses, newAddresses);
    setAddresses = s_onRamp.getAllowList();

    assertEq(address(2), setAddresses[1]);
    assertEq(address(3), setAddresses[2]);
  }

  function testSetAllowListSkipsZeroSuccess() public {
    uint256 setAddressesLength = s_onRamp.getAllowList().length;

    address[] memory newAddresses = new address[](1);
    newAddresses[0] = address(0);

    s_onRamp.applyAllowListUpdates(new address[](0), newAddresses);
    address[] memory setAddresses = s_onRamp.getAllowList();

    assertEq(setAddresses.length, setAddressesLength);
  }

  // Reverts

  function testOnlyOwnerReverts() public {
    vm.stopPrank();
    vm.expectRevert("Only callable by owner");
    address[] memory newAddresses = new address[](2);
    s_onRamp.applyAllowListUpdates(new address[](0), newAddresses);
  }
}

/// @notice #getAllowList
contract EVM2EVMOnRamp_getAllowList is EVM2EVMOnRampWithAllowListSetup {
  function testGetAllowListSuccess() public {
    address[] memory setAddresses = s_onRamp.getAllowList();
    assertEq(OWNER, setAddresses[0]);
  }
}

contract EVM2EVMOnRamp_ARM is EVM2EVMOnRampSetup {
  function testARM() public {
    // Test pausing
    assertEq(s_onRamp.paused(), false);
    s_onRamp.pause();
    assertEq(s_onRamp.paused(), true);
    s_onRamp.unpause();
    assertEq(s_onRamp.paused(), false);

    // Test ARM
    assertEq(s_onRamp.isARMHealthy(), true);
    s_mockARM.voteToCurse(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    assertEq(s_onRamp.isARMHealthy(), false);
    ARM.UnvoteToCurseRecord[] memory records = new ARM.UnvoteToCurseRecord[](1);
    records[0] = ARM.UnvoteToCurseRecord({curseVoteAddr: OWNER, cursesHash: bytes32(uint256(0)), forceUnvote: true});
    s_mockARM.ownerUnvoteToCurse(records);
    assertEq(s_onRamp.isARMHealthy(), true);
  }
}
